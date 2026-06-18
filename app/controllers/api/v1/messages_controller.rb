module Api
  module V1
    class MessagesController < Api::BaseController
      # Phone reports the result of sending an outbound message.
      # POST /api/v1/messages/:id/status  { status: sent|failed, error?, provider_message_id? }
      def status
        message = device_messages.find_by(id: params[:id])
        return render(json: { error: "not_found" }, status: :not_found) unless message

        new_status = params[:status].to_s
        unless %w[sent failed].include?(new_status)
          return render(json: { error: "invalid status" }, status: :unprocessable_entity)
        end

        message.update!(
          status: new_status,
          error: params[:error].presence,
          provider_message_id: params[:provider_message_id].presence,
          sent_at: (new_status == "sent" ? Time.current : message.sent_at)
        )
        render json: { ok: true, id: message.id, status: message.status }
      end

      # Phone reports an incoming SMS.
      # POST /api/v1/inbound  { subscription_id, from, body, received_at? }
      def inbound
        sim = current_device.sim_cards.find_by(subscription_id: params[:subscription_id])
        return render(json: { error: "unknown sim" }, status: :unprocessable_entity) unless sim

        from = params[:from].to_s
        body = params[:body].to_s
        if from.blank? || body.blank?
          return render(json: { error: "from and body required" }, status: :unprocessable_entity)
        end

        message = sim.messages.create!(
          direction: "inbound",
          address: from,
          body: body,
          status: "received",
          received_at: parse_time(params[:received_at]) || Time.current
        )
        render json: { ok: true, id: message.id }, status: :created
      end

      private

      def device_messages
        Message.joins(:sim_card).where(sim_cards: { device_id: current_device.id })
      end

      def parse_time(value)
        return nil if value.blank?
        Time.zone.parse(value.to_s)
      rescue ArgumentError
        nil
      end
    end
  end
end
