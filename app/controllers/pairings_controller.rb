# Hands a device token to the native Android app. The web view is already
# signed in (shared cookies), so visiting this page authenticates the phone.
# A Hotwire Native "device" bridge component reads the token from the rendered
# page and stores it natively; there's also a copyable fallback for debugging.
class PairingsController < ApplicationController
  def show
    @device = current_user.devices.order(last_seen_at: :desc).first
    @connected_token = flash[:device_token]
  end

  def create
    device = current_user.devices.order(:created_at).first ||
             current_user.devices.new(platform: "android")
    device.name = params[:name].presence || device.name.presence || "My phone"
    device.app_version = params[:app_version] if params[:app_version].present?
    device.save! if device.new_record?

    token = device.regenerate_token!
    redirect_to pairing_path, flash: { device_token: token, notice: "Phone connected." }
  end
end
