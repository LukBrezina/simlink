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

      private

      def device_sim_ids
        current_device.sim_cards.pluck(:id)
      end
    end
  end
end
