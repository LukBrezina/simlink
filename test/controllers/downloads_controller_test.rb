require "test_helper"

class DownloadsControllerTest < ActionDispatch::IntegrationTest
  APK_PATH = Rails.root.join("downloads/simlink.apk")

  test "get-the-app page is public and links to the APK download" do
    get get_app_path
    assert_response :success
    assert_select "a[href=?]", apk_download_path
  end

  test "APK is served with the Android package MIME type as an attachment" do
    # The published APK is gitignored (built + dropped in downloads/ at release
    # time), so synthesize one when it isn't present on this machine.
    created = ensure_apk_present
    get apk_download_path
    assert_response :success
    assert_equal "application/vnd.android.package-archive", @response.media_type
    assert_match "attachment", @response.headers["Content-Disposition"]
    assert_match "simlink.apk", @response.headers["Content-Disposition"]
  ensure
    File.delete(APK_PATH) if created
  end

  test "APK download 404s when none has been published" do
    skip "an APK is present on disk" if File.exist?(APK_PATH)
    get apk_download_path
    assert_response :not_found
  end

  private

  # Creates a throwaway APK only if one isn't already there; returns whether it
  # did, so the caller cleans up without clobbering a real published APK.
  def ensure_apk_present
    return false if File.exist?(APK_PATH)

    FileUtils.mkdir_p(APK_PATH.dirname)
    File.binwrite(APK_PATH, "PK\x03\x04 fake apk for test")
    true
  end
end
