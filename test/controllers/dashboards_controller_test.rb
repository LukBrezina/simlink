require "test_helper"

class DashboardsControllerTest < ActionDispatch::IntegrationTest
  test "requires authentication" do
    get dashboard_path
    assert_redirected_to new_session_path
  end

  test "renders the setup steps for a signed-in user with an empty account" do
    sign_in_as(User.take)
    get dashboard_path
    assert_response :success
    assert_select "h1", /SMS hub/i
  end
end
