# SQLite-backed SMS relay.
#
# SMS content (message text and phone numbers) is held here ONLY while a message
# is in transit between an agent and the phone. It is encrypted at rest (see
# RelayOutbound / RelayRead), filtered from the logs, and pruned after a short
# TTL — a deliberate "transient, not a history" design. Nothing keeps a record
# once it has been delivered and aged out.
#
# Why SQLite instead of process memory: the relay is shared across all Puma
# workers on the host, so claims are coordinated through the database. Every
# operation is a handful of fast local queries — nothing blocks waiting on the
# phone; the phone reaches the server through its own (non-blocking) requests and
# the agent re-polls.
#
# Claims are race-free across workers without explicit locks: a claim flips rows
# with a single `UPDATE ... WHERE status = 'queued'` (atomic under SQLite's
# serialized writes) stamped with a unique token, then re-selects by that token.
# Two concurrent claimers can't grab the same row — the second UPDATE no longer
# matches it.
class SmsRelay
  TTL_SECONDS = 5 * 60
  # Safety cap so a phone that never drains can't grow the table without bound.
  MAX_ENTRIES_PER_SIM = 200

  class << self
    # ---- outbound: agent -> server -> phone ----------------------------------

    def enqueue_outbound(sim_card_id:, subscription_id:, to:, body:)
      prune!
      rec = RelayOutbound.create!(
        sim_card_id: sim_card_id, subscription_id: subscription_id,
        to: to, body: body, status: "queued"
      )
      cap!(RelayOutbound, sim_card_id)
      rec
    end

    # Atomically claim every queued outbound message for the given SIMs
    # (queued -> sending) and return them, oldest first.
    def claim_outbound(sim_card_ids)
      claim(RelayOutbound, sim_card_ids, from: "queued", to: "sending")
    end

    # Update an outbound entry's status. When `sim_card_ids` is given, the update
    # only applies if the entry belongs to one of those SIMs.
    def update_status(id, status:, error: nil, sim_card_ids: nil)
      scope = RelayOutbound.where(id: id)
      scope = scope.where(sim_card_id: Array(sim_card_ids)) if sim_card_ids
      rec = scope.first
      return nil unless rec
      rec.update!(status: status, error: error)
      rec
    end

    # ---- reads: agent -> server -> phone (read its SMS store) -> server -> agent

    def enqueue_read(sim_card_id:, subscription_id:, limit:, since: nil, address: nil, box: "all")
      prune!
      rec = RelayRead.create!(
        sim_card_id: sim_card_id, subscription_id: subscription_id,
        read_limit: limit, since: since, address: address, box: box, status: "pending"
      )
      cap!(RelayRead, sim_card_id)
      rec
    end

    # Atomically claim pending read-requests for the given SIMs (pending -> claimed).
    def claim_reads(sim_card_ids)
      claim(RelayRead, sim_card_ids, from: "pending", to: "claimed")
    end

    # Record the rows the phone read (or an error). Scoped to the device's SIMs.
    def fulfill_read(id, messages:, error: nil, sim_card_ids: nil)
      scope = RelayRead.where(id: id)
      scope = scope.where(sim_card_id: Array(sim_card_ids)) if sim_card_ids
      rec = scope.first
      return nil unless rec
      rec.update!(messages_json: JSON.generate(Array(messages)), error: error, status: "fulfilled")
      rec
    end

    # Look up a read-request for the agent that owns the SIM (nil if expired/foreign).
    def read_result(id, sim_card_id)
      RelayRead.where(id: id, sim_card_id: sim_card_id).where(fresh).first
    end

    # ---- shared --------------------------------------------------------------

    # Recent outbound messages for the given SIMs, newest first. This is all
    # `list_messages` / the web dashboard can show — there is no long-term history.
    def recent(sim_card_ids, since: nil, limit: 20)
      ids = Array(sim_card_ids)
      return [] if ids.empty?
      scope = RelayOutbound.where(sim_card_id: ids).where(fresh)
      scope = scope.where("updated_at > ?", since) if since
      scope.order(updated_at: :desc).limit(limit).to_a
    end

    def reset!
      RelayOutbound.delete_all
      RelayRead.delete_all
    end

    private

    def claim(model, sim_card_ids, from:, to:)
      ids = Array(sim_card_ids)
      return [] if ids.empty?
      prune!
      token = SecureRandom.hex(16)
      model.where(sim_card_id: ids, status: from).where(fresh)
           .update_all(status: to, claim_token: token, updated_at: Time.current)
      model.where(claim_token: token).order(:created_at).to_a
    end

    def cutoff
      Time.current - TTL_SECONDS
    end

    # Filter expired-but-not-yet-deleted rows out of reads (cheap; no write).
    def fresh
      [ "updated_at > ?", cutoff ]
    end

    # Delete aged-out rows. Called on writes (enqueue/claim), not on every poll.
    def prune!
      RelayOutbound.where("updated_at < ?", cutoff).delete_all
      RelayRead.where("updated_at < ?", cutoff).delete_all
    end

    def cap!(model, sim_card_id)
      excess = model.where(sim_card_id: sim_card_id).count - MAX_ENTRIES_PER_SIM
      return if excess <= 0
      old_ids = model.where(sim_card_id: sim_card_id).order(updated_at: :asc).limit(excess).pluck(:id)
      model.where(id: old_ids).delete_all
    end
  end
end
