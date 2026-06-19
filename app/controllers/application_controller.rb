class ApplicationController < ActionController::Base
  include Authentication
  # No browser-version gate. The public landing page must render for every
  # visitor — `allow_browser versions: :modern` was returning 406 to mainstream
  # mobile browsers (Samsung Internet, older Safari/Chrome), so they never saw
  # the site. The UI is server-rendered HTML + Turbo, which works broadly.

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  helper_method :current_user, :hotwire_native_app?

  private

  def current_user
    Current.user
  end

  # True when the request comes from inside the SimLink Android app. We key off
  # the app's OWN User-Agent prefix — android/.../MainApplication.kt sets
  # `Hotwire.config.applicationUserAgentPrefix = "SimLink;"`, which is always
  # present in the native WebView and never in a real browser. That's stabler
  # than the Hotwire/Turbo library token (renamed "Turbo Native" → "Hotwire
  # Native" across versions); those are kept as a belt-and-suspenders fallback.
  def hotwire_native_app?
    ua = request.user_agent.to_s
    ua.include?("SimLink") || ua.include?("Hotwire Native") || ua.include?("Turbo Native")
  end
end
