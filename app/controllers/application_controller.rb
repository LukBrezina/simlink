class ApplicationController < ActionController::Base
  include Authentication
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  helper_method :current_user, :hotwire_native_app?

  private

  def current_user
    Current.user
  end

  # True when the request comes from inside the SimLink Android app (Hotwire
  # Native sets this in the user agent). Browser visitors get the download flow.
  def hotwire_native_app?
    request.user_agent.to_s.include?("Hotwire Native")
  end
end
