require "test_helper"

class DownloadsControllerTest < ActionDispatch::IntegrationTest
  test "get-the-app page is public and links to the APK download" do
    get get_app_path
    assert_response :success
    assert_select "a[href=?]", apk_download_path
  end

  test "APK is served with the Android package MIME type as an attachment" do
    get apk_download_path
    assert_response :success
    assert_equal "application/vnd.android.package-archive", @response.media_type
    assert_match "attachment", @response.headers["Content-Disposition"]
    assert_match "simlink.apk", @response.headers["Content-Disposition"]
  end
end
