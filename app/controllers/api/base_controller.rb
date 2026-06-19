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
      reported = request.headers["X-App-Version"]
      log_app_version(reported)
      @current_device.touch_seen!(app_version: reported)
    end

    # Log the phone's app version on first sight and whenever it changes — the
    # version itself isn't sensitive, and it's the cheapest way to confirm which
    # build a device is actually running (e.g. whether it has the fetch_sms path).
    def log_app_version(reported)
      return if reported.blank? || reported == current_device.app_version
      Rails.logger.info(
        "[device ##{current_device.id} #{current_device.name}] " \
        "app_version #{current_device.app_version.inspect} -> #{reported.inspect}"
      )
    end
  end
end
