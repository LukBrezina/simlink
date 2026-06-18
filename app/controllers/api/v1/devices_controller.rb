module Api
  module V1
    class DevicesController < Api::BaseController
      # Lightweight keepalive so the dashboard can show "phone online".
      # touch_seen! already runs in the base controller's auth callback.
      def heartbeat
        render json: {
          ok: true,
          device: current_device.name,
          shared_sims: current_device.sim_cards.shared.count
        }
      end
    end
  end
end
