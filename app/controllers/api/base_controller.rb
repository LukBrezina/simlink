module Api
  # Base for all device-facing JSON endpoints. Authenticates the Android app via
  # its device token (issued during web pairing) sent as `Authorization: Bearer`.
  class BaseController < ActionController::API
    before_action :authenticate_device!

    attr_reader :current_device

    private

    def authenticate_device!
      token = request.authorization.to_s[/\ABearer\s+(.+)\z/i, 1].presence || params[:device_token].presence
      @current_device = Device.find_by_token(token)
      unless @current_device
        render json: { error: "unauthorized" }, status: :unauthorized
        return
      end
      @current_device.touch_seen!(app_version: request.headers["X-App-Version"])
    end
  end
end
