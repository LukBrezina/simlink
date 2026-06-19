require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "downcases and strips nickname" do
    user = User.new(nickname: " Downcased ")
    assert_equal("downcased", user.nickname)
  end
end
