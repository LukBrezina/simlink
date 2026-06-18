require "test_helper"

# Exercises the full loop: agent (MCP) -> server -> phone (device API) -> server
# -> agent. No running server needed.
class RelayFlowTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email_address: "loop@example.com", password: "password123")
    @device = @user.devices.create!(name: "Test Phone", platform: "android")
    @device_token = @device.token # plaintext available right after create
    @sim = @device.sim_cards.create!(
      subscription_id: 7, slot_index: 0, label: "Main",
      phone_number: "+420700000000", carrier_name: "Test", shared: true
    )
    @mcp = @user.mcp_tokens.create!(sim_card: @sim, name: "Agent")
    @mcp_token = @mcp.token
  end

  def mcp_call(method, params = {}, id: 1)
    body = { jsonrpc: "2.0", id: id, method: method, params: params }.to_json
    post "/mcp", params: body,
         headers: { "Authorization" => "Bearer #{@mcp_token}", "Content-Type" => "application/json" }
    JSON.parse(@response.body) unless @response.body.blank?
  end

  def tool(name, args = {})
    res = mcp_call("tools/call", { name: name, arguments: args })
    res.dig("result")
  end

  test "mcp initialize advertises tools and server info" do
    res = mcp_call("initialize", { protocolVersion: "2025-06-18" })
    assert_equal "simlink", res.dig("result", "serverInfo", "name")

    list = mcp_call("tools/list")
    names = list.dig("result", "tools").map { |t| t["name"] }
    assert_equal %w[send_sms list_messages wait_for_sms].sort, names.sort
  end

  test "unauthorized mcp request is rejected" do
    post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/list" }.to_json,
         headers: { "Content-Type" => "application/json" }
    assert_response :unauthorized
  end

  test "full send loop: agent queues, phone claims and confirms" do
    # 1. Agent sends
    result = tool("send_sms", { to: "+420123456789", body: "hello" })
    refute result["isError"], "send_sms should succeed"
    msg = Message.last
    assert_equal "queued", msg.status
    assert_equal "outbound", msg.direction
    assert_equal @mcp, msg.mcp_token

    # 2. Phone polls the outbox (claims it -> sending)
    get "/api/v1/outbox", params: { timeout_seconds: 1 },
        headers: { "Authorization" => "Bearer #{@device_token}" }
    assert_response :success
    claimed = JSON.parse(@response.body)["messages"]
    assert_equal 1, claimed.size
    assert_equal @sim.subscription_id, claimed.first["subscription_id"]
    assert_equal "sending", msg.reload.status

    # 3. Phone reports it sent
    post "/api/v1/messages/#{msg.id}/status", params: { status: "sent" },
         headers: { "Authorization" => "Bearer #{@device_token}" }
    assert_response :success
    assert_equal "sent", msg.reload.status
    assert msg.sent_at.present?
  end

  test "inbound: phone reports a received SMS, agent reads it" do
    post "/api/v1/inbound",
         params: { subscription_id: @sim.subscription_id, from: "+420999888777", body: "incoming!" },
         headers: { "Authorization" => "Bearer #{@device_token}" }
    assert_response :created

    result = tool("list_messages", { direction: "inbound", limit: 5 })
    messages = result.dig("structuredContent", "messages")
    assert_equal 1, messages.size
    assert_equal "incoming!", messages.first["body"]
    assert_equal "+420999888777", messages.first["from"]
  end

  test "wait_for_sms returns an inbound message that arrived after `since`" do
    travel_to Time.current do
      since = 1.minute.ago.iso8601
      @sim.messages.create!(direction: "inbound", address: "+420555", body: "ping",
                            status: "received", received_at: Time.current)
      result = tool("wait_for_sms", { since: since, timeout_seconds: 2 })
      messages = result.dig("structuredContent", "messages")
      assert_equal 1, messages.size
      assert_equal "ping", messages.first["body"]
    end
  end

  test "wait_for_sms times out cleanly when nothing arrives" do
    result = tool("wait_for_sms", { timeout_seconds: 1 })
    assert_equal true, result.dig("structuredContent", "timed_out")
    assert_empty result.dig("structuredContent", "messages")
  end

  test "device cannot claim another device's messages" do
    other_user = User.create!(email_address: "other@example.com", password: "password123")
    other_device = other_user.devices.create!(name: "Other", platform: "android")
    get "/api/v1/outbox", params: { timeout_seconds: 1 },
        headers: { "Authorization" => "Bearer #{other_device.token}" }
    assert_response :success
    assert_empty JSON.parse(@response.body)["messages"]
  end
end
