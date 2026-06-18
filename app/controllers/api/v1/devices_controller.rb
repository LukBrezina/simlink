module Api
  module V1
    class DevicesController < Api::BaseController
      # Lightweight keepalive so the dashboard can show "phone online".
      # touch_seen! already runs in the base controller's auth callback.
      # Optionally carries the FCM token so the phone can refresh it cheaply.
      def heartbeat
        save_fcm_token
        render json: {
          ok: true,
          device: current_device.name,
          shared_sims: current_device.sim_cards.shared.count
        }
      end

      # POST /api/v1/fcm_token { fcm_token }
      # The phone registers/refreshes its FCM registration token here.
      def fcm_token
        token = params[:fcm_token].to_s
        return render(json: { error: "fcm_token required" }, status: :unprocessable_entity) if token.blank?

        current_device.update_columns(fcm_token: token, updated_at: Time.current)
        render json: { ok: true }
      end

      private

      def save_fcm_token
        token = params[:fcm_token].to_s
        return if token.blank? || token == current_device.fcm_token
        current_device.update_columns(fcm_token: token, updated_at: Time.current)
      end
    end
  end
end
