require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  test "anonymous visitor sees the landing page" do
    get root_path
    assert_response :success
    assert_select "h1", /phone number/i
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
end
