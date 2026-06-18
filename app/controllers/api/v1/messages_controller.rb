module Api
  module V1
    class MessagesController < Api::BaseController
      # Phone reports the result of sending an outbound message.
      # POST /api/v1/messages/:id/status  { status: sent|failed, error? }
      def status
        new_status = params[:status].to_s
        unless %w[sent failed].include?(new_status)
          return render(json: { error: "invalid status" }, status: :unprocessable_entity)
        end

        entry = SmsRelay.update_status(
          params[:id].to_i,
          status: new_status,
          error: params[:error].presence,
          sim_card_ids: device_sim_ids
        )
        return render(json: { error: "not_found" }, status: :not_found) unless entry

        render json: { ok: true, id: entry.id, status: entry.status }
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

        entry = SmsRelay.add_inbound(
          sim_card_id: sim.id,
          from: from,
          body: body,
          received_at: parse_time(params[:received_at])
        )
        render json: { ok: true, id: entry.id }, status: :created
      end

      private

      def device_sim_ids
        current_device.sim_cards.pluck(:id)
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
