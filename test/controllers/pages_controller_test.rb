require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  test "anonymous visitor sees the landing page" do
    get root_path
    assert_response :success
    assert_select "h1", /over MCP/i
  end

  test "landing page lets visitors register or self-host" do
    get root_path
    assert_response :success
    assert_select "a[href=?]", new_registration_path
    assert_select "a[href=?]", "https://github.com/LukBrezina/simlink"
  end

  test "authenticated user is redirected to the dashboard" do
    sign_in_as(User.take)
    get root_path
    assert_redirected_to dashboard_path
  end

  test "the native app is sent to the dashboard, not the marketing page" do
    # Regression: native app must not bounce to /session/new after sign-in.
    get root_path, headers: { "User-Agent" => "SimLink; Hotwire Native Android; Mozilla/5.0" }
    assert_redirected_to dashboard_path
  end

  test "the native app is detected by its own UA prefix, not the Hotwire token" do
    # The app sets applicationUserAgentPrefix = "SimLink;". Detection must not
    # depend on the Hotwire/Turbo library token (it gets renamed across versions).
    get root_path, headers: { "User-Agent" => "SimLink; Mozilla/5.0 (Linux; Android 14)" }
    assert_redirected_to dashboard_path
  end

  test "mainstream mobile browsers can load the landing page (no browser gate)" do
    # Samsung Internet used to get a 406 from `allow_browser versions: :modern`.
    get root_path, headers: { "User-Agent" =>
      "Mozilla/5.0 (Linux; Android 13; SAMSUNG SM-S918B) AppleWebKit/537.36 " \
      "(KHTML, like Gecko) SamsungBrowser/23.0 Chrome/115.0.0.0 Mobile Safari/537.36" }
    assert_response :success
    assert_select "h1", /over MCP/i
  end

  test "per-agent guide renders with the agent name" do
    get agent_guide_path("claude")
    assert_response :success
    assert_match "Claude Desktop", @response.body
  end

  test "unknown agent slug redirects home" do
    get agent_guide_path("not-an-agent")
    assert_redirected_to root_path
  end

  test "llms.txt is served as plain text and describes the MCP endpoint" do
    get "/llms.txt"
    assert_response :success
    assert_equal "text/plain", @response.media_type
    assert_match "/mcp", @response.body
    assert_match "send_sms", @response.body
  end

  test "robots.txt welcomes crawlers, hides private paths, and links the sitemap" do
    get "/robots.txt"
    assert_response :success
    assert_equal "text/plain", @response.media_type
    assert_match "User-agent: *", @response.body
    assert_match "Disallow: /mcp", @response.body
    assert_match %r{Sitemap: https?://[^/]+/sitemap\.xml}, @response.body
  end

  test "sitemap.xml lists the public marketing and agent-guide pages" do
    get "/sitemap.xml"
    assert_response :success
    assert_equal "application/xml", @response.media_type
    assert_match "/for/claude", @response.body
    assert_match "/llms.txt", @response.body
  end

  test "pwa manifest is served with brand name and theme color" do
    get pwa_manifest_path(format: :json)
    assert_response :success
    assert_match "SimLink", @response.body
    assert_match "#1a5f4a", @response.body
  end
end
