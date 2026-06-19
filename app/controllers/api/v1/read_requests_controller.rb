module Api
  module V1
    # The phone side of `fetch_sms`. The agent enqueues a read-request (via MCP),
    # the server wakes the phone, and the phone:
    #   1. GET  /api/v1/read_requests            -> claims pending requests for its shared SIMs
    #   2. reads its own SMS store on-device
    #   3. POST /api/v1/read_requests/:id/results -> uploads the rows (or an error)
    # Everything is relayed in memory and pruned after a short TTL — never stored.
    class ReadRequestsController < Api::BaseController
      # Hard cap so a misbehaving client can't push an unbounded batch into memory.
      MAX_MESSAGES = 100

      def index
        claimed = SmsRelay.claim_reads(shared_sim_ids)
        render json: { requests: claimed.map { |r| read_request_json(r) } }
      end

      def results
        messages = read_messages_param
        entry = SmsRelay.fulfill_read(
          params[:id].to_i,
          messages: messages,
          error: params[:error].presence,
          sim_card_ids: device_sim_ids
        )
        return render(json: { error: "not_found" }, status: :not_found) unless entry

        render json: { ok: true, id: entry.id, count: messages.size }
      end

      private

      # Tolerate an empty/missing/garbage array — only keep permittable rows.
      def read_messages_param
        raw = params[:messages]
        return [] unless raw.is_a?(Array)
        raw.first(MAX_MESSAGES).filter_map do |m|
          m.permit(:from, :to, :body, :date, :type).to_h if m.respond_to?(:permit)
        end
      end

      def shared_sim_ids
        current_device.sim_cards.shared.pluck(:id)
      end

      def device_sim_ids
        current_device.sim_cards.pluck(:id)
      end

      # Only non-null filters are sent so the phone can use optString(...).ifBlank.
      def read_request_json(entry)
        {
          id: entry.id,
          subscription_id: entry.subscription_id,
          limit: entry.read_limit,
          box: entry.box,
          since: entry.since,
          address: entry.address
        }.compact
      end
    end
  end
end
