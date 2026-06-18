module Api
  module V1
    # Long-poll endpoint the phone calls in a loop. Returns queued outbound SMS
    # for this device's shared SIMs, atomically claiming them (queued -> sending)
    # so the phone can send them. Blocks up to `timeout_seconds` if none waiting.
    class OutboxController < Api::BaseController
      MAX_TIMEOUT = 60
      POLL_INTERVAL = 1.5

      def index
        timeout = [ [ params.fetch(:timeout_seconds, 25).to_i, 1 ].max, MAX_TIMEOUT ].min
        deadline = monotonic_now + timeout

        loop do
          claimed = claim_queued
          return render(json: { messages: claimed.map { |m| outbound_json(m) } }) if claimed.any?
          break if monotonic_now >= deadline
          sleep [ POLL_INTERVAL, deadline - monotonic_now ].min
        end

        render json: { messages: [] }
      end

      private

      def claim_queued
        Message.transaction do
          messages = Message.queued
                            .joins(:sim_card)
                            .where(sim_cards: { device_id: current_device.id, shared: true })
                            .order(:created_at)
                            .limit(20)
                            .lock
                            .to_a
          messages.each { |m| m.update_columns(status: "sending", updated_at: Time.current) }
          messages
        end
      end

      def outbound_json(message)
        {
          id: message.id,
          subscription_id: message.sim_card.subscription_id,
          to: message.address,
          body: message.body
        }
      end

      def monotonic_now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
