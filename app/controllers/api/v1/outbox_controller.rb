module Api
  module V1
    # Non-blocking endpoint the phone hits (FCM-woken, plus a slow fallback poll).
    # Returns and atomically claims (queued -> sending) any outbound SMS for this
    # device's shared SIMs. Returns immediately — it never holds the connection.
    class OutboxController < Api::BaseController
      def index
        claimed = SmsRelay.claim_outbound(shared_sim_ids)
        render json: { messages: claimed.map { |m| outbound_json(m) } }
      end

      private

      def shared_sim_ids
        current_device.sim_cards.shared.pluck(:id)
      end

      def outbound_json(entry)
        {
          id: entry.id,
          subscription_id: entry.subscription_id,
          to: entry.to,
          body: entry.body
        }
      end
    end
  end
end
