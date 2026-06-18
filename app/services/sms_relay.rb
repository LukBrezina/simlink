# Process-wide, in-memory SMS relay.
#
# SMS content (message text and phone numbers) lives here ONLY while a message is
# in transit between an agent and the phone. Nothing is ever written to disk or to
# the logs, and entries are pruned after a short TTL. This is the deliberate
# "don't store" design: a server restart, or a phone offline past the TTL, drops
# in-flight messages (send-and-forget). There is no durable queue.
#
# Single Puma process (no clustered workers) => one shared instance across all
# request threads, guarded by a mutex. If this ever runs multiple processes or
# servers, swap the backing store for Redis (same interface).
#
# In development, code reloading resets this between requests — consistent with
# the transient semantics. In production (eager load, no reload) it persists for
# the lifetime of the process.
class SmsRelay
  include Singleton

  TTL_SECONDS = 5 * 60
  # Safety cap so a phone that never drains can't grow memory without bound.
  MAX_ENTRIES_PER_SIM = 200

  Inbound  = Struct.new(:id, :sim_card_id, :from, :body, :received_at, keyword_init: true)
  Outbound = Struct.new(:id, :sim_card_id, :subscription_id, :to, :body, :status, :error,
                        :created_at, :updated_at, keyword_init: true)

  class << self
    delegate :enqueue_outbound, :claim_outbound, :update_status,
             :add_inbound, :inbound_since, :recent, :reset!, to: :instance
  end

  def initialize
    @mutex = Mutex.new
    @inbound = []
    @outbound = []
    @seq = 0
  end

  # ---- inbound: phone -> server -> agent -------------------------------------

  def add_inbound(sim_card_id:, from:, body:, received_at: nil)
    @mutex.synchronize do
      prune!
      entry = Inbound.new(id: next_id, sim_card_id: sim_card_id, from: from, body: body,
                          received_at: received_at || Time.current)
      @inbound << entry
      cap!(@inbound, sim_card_id)
      entry
    end
  end

  # Inbound messages for a SIM that arrived after `since` (nil => all buffered),
  # oldest first.
  def inbound_since(sim_card_id, since = nil)
    @mutex.synchronize do
      prune!
      @inbound.select { |e| e.sim_card_id == sim_card_id && (since.nil? || e.received_at > since) }
              .sort_by(&:received_at)
    end
  end

  # ---- outbound: agent -> server -> phone ------------------------------------

  def enqueue_outbound(sim_card_id:, subscription_id:, to:, body:)
    @mutex.synchronize do
      prune!
      now = Time.current
      entry = Outbound.new(id: next_id, sim_card_id: sim_card_id, subscription_id: subscription_id,
                           to: to, body: body, status: "queued", error: nil,
                           created_at: now, updated_at: now)
      @outbound << entry
      cap!(@outbound, sim_card_id)
      entry
    end
  end

  # Atomically claim every queued outbound message for the given SIMs
  # (queued -> sending) and return them. The phone calls this; claiming marks
  # them so a concurrent poll can't grab the same message twice.
  def claim_outbound(sim_card_ids)
    ids = Array(sim_card_ids)
    @mutex.synchronize do
      prune!
      now = Time.current
      claimed = @outbound.select { |e| ids.include?(e.sim_card_id) && e.status == "queued" }
      claimed.each { |e| e.status = "sending"; e.updated_at = now }
      claimed.sort_by(&:created_at)
    end
  end

  # Update an outbound entry's status. When `sim_card_ids` is given, the update
  # only applies if the entry belongs to one of those SIMs (so a device can't
  # touch another device's messages).
  def update_status(id, status:, error: nil, sim_card_ids: nil)
    @mutex.synchronize do
      prune!
      entry = @outbound.find { |e| e.id == id }
      return nil unless entry
      return nil if sim_card_ids && !Array(sim_card_ids).include?(entry.sim_card_id)
      entry.status = status
      entry.error = error
      entry.updated_at = Time.current
      entry
    end
  end

  # ---- shared ----------------------------------------------------------------

  # Recent in-flight messages (both directions) for the given SIMs, newest first.
  # This is all `list_messages` / the web dashboard can show — there is no history.
  def recent(sim_card_ids, direction: "all", since: nil, limit: 20)
    ids = Array(sim_card_ids)
    @mutex.synchronize do
      prune!
      items = []
      items.concat(@inbound.select  { |e| ids.include?(e.sim_card_id) }) unless direction == "outbound"
      items.concat(@outbound.select { |e| ids.include?(e.sim_card_id) }) unless direction == "inbound"
      items.select! { |e| since.nil? || timestamp(e) > since }
      items.sort_by { |e| timestamp(e) }.reverse.first(limit)
    end
  end

  def reset!
    @mutex.synchronize do
      @inbound = []
      @outbound = []
      @seq = 0
    end
  end

  private

  def next_id
    @seq += 1
  end

  def timestamp(entry)
    entry.is_a?(Inbound) ? entry.received_at : (entry.updated_at || entry.created_at)
  end

  def prune!
    cutoff = Time.current - TTL_SECONDS
    @inbound.reject!  { |e| e.received_at < cutoff }
    @outbound.reject! { |e| e.updated_at < cutoff }
  end

  def cap!(collection, sim_card_id)
    for_sim = collection.select { |e| e.sim_card_id == sim_card_id }
    excess = for_sim.size - MAX_ENTRIES_PER_SIM
    return if excess <= 0

    drop = for_sim.sort_by { |e| timestamp(e) }.first(excess)
    collection.reject! { |e| drop.include?(e) }
  end
end
