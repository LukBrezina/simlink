module ApplicationHelper
  # Third-party analytics loads only for anonymous visitors on the public web —
  # never for signed-in users, and never inside the native app's webviews.
  def public_web_visitor?
    !authenticated? && !hotwire_native_app?
  end
end
