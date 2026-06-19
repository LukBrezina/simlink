require "test_helper"

# Exercises the full loop: agent (MCP) -> server -> phone (device API) -> server
# -> agent. Messages are relayed in memory (SmsRelay), never stored.
class RelayFlowTest < ActionDispatch::IntegrationTest
  setup do
    SmsRelay.reset!
    @user = User.create!(nickname: "loop", password: "password123")
    @device = @user.devices.create!(name: "Test Phone", platform: "android")
    @device_token = @device.token # plaintext available right after create
    @sim = @device.sim_cards.create!(
      subscription_id: 7, slot_index: 0, label: "Main",
      phone_number: "+420700000000", carrier_name: "Test", shared: true
    )
    @mcp = @user.mcp_tokens.create!(sim_card: @sim, name: "Agent")
    @mcp_token = @mcp.token
  end

  teardown { SmsRelay.reset! }

  def mcp_call(method, params = {}, id: 1)
    body = { jsonrpc: "2.0", id: id, method: method, params: params }.to_json
    post "/mcp", params: body,
         headers: { "Authorization" => "Bearer #{@mcp_token}", "Content-Type" => "application/json" }
    JSON.parse(@response.body) unless @response.body.blank?
  end

  def tool(name, args = {})
    mcp_call("tools/call", { name: name, arguments: args }).dig("result")
  end

  test "mcp initialize advertises tools and server info" do
    res = mcp_call("initialize", { protocolVersion: "2025-06-18" })
    assert_equal "simlink", res.dig("result", "serverInfo", "name")

    list = mcp_call("tools/list")
    names = list.dig("result", "tools").map { |t| t["name"] }
    assert_equal %w[send_sms list_messages fetch_sms].sort, names.sort
  end

  test "sms://status resource surfaces the phone's reported app version" do
    # The phone checks in carrying its version header, exactly as the real app does.
    post "/api/v1/heartbeat", params: {}.to_json,
         headers: {
           "Authorization" => "Bearer #{@device_token}",
           "Content-Type" => "application/json",
           "X-App-Version" => "0.4.0"
         }
    assert_response :success

    res = mcp_call("resources/read", { uri: "sms://status" })
    payload = JSON.parse(res.dig("result", "contents", 0, "text"))
    assert_equal "0.4.0", payload["app_version"]
    assert_equal true, payload["online"]
    assert_equal 1, payload["shared_sims"]
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
    sent = result.dig("structuredContent")
    assert_equal "outbound", sent["direction"]
    assert_equal "queued", sent["status"]
    msg_id = sent["id"]

    # 2. Phone pulls the outbox (claims it -> sending), non-blocking
    get "/api/v1/outbox", headers: { "Authorization" => "Bearer #{@device_token}" }
    assert_response :success
    claimed = JSON.parse(@response.body)["messages"]
    assert_equal 1, claimed.size
    assert_equal @sim.subscription_id, claimed.first["subscription_id"]
    assert_equal msg_id, claimed.first["id"]

    # A second pull gets nothing — already claimed.
    get "/api/v1/outbox", headers: { "Authorization" => "Bearer #{@device_token}" }
    assert_empty JSON.parse(@response.body)["messages"]

    # 3. Phone reports it sent
    post "/api/v1/messages/#{msg_id}/status", params: { status: "sent" },
         headers: { "Authorization" => "Bearer #{@device_token}" }
    assert_response :success
    assert_equal "sent", JSON.parse(@response.body)["status"]
  end

  test "fetch_sms loop: agent requests, phone reads and uploads, agent retrieves" do
    # 1. Agent starts a read (non-blocking, pending)
    start = tool("fetch_sms", { box: "inbox", limit: 10 })
    refute start["isError"], "fetch_sms should start a read"
    started = start.dig("structuredContent")
    assert_equal true, started["pending"]
    req_id = started["request_id"]

    # 2. Phone claims the pending read-request
    get "/api/v1/read_requests", headers: { "Authorization" => "Bearer #{@device_token}" }
    assert_response :success
    reqs = JSON.parse(@response.body)["requests"]
    assert_equal 1, reqs.size
    assert_equal req_id, reqs.first["id"]
    assert_equal @sim.subscription_id, reqs.first["subscription_id"]
    assert_equal "inbox", reqs.first["box"]

    # A second claim gets nothing — already claimed.
    get "/api/v1/read_requests", headers: { "Authorization" => "Bearer #{@device_token}" }
    assert_empty JSON.parse(@response.body)["requests"]

    # 3. Phone uploads what it read off the device
    post "/api/v1/read_requests/#{req_id}/results",
         params: { messages: [ { from: "+420999", body: "code 123", date: Time.current.iso8601, type: "inbox" } ] },
         headers: { "Authorization" => "Bearer #{@device_token}" }
    assert_response :success

    # 4. Agent retrieves the result by request_id
    done = tool("fetch_sms", { request_id: req_id })
    structured = done.dig("structuredContent")
    assert_equal false, structured["pending"]
    messages = structured["messages"]
    assert_equal 1, messages.size
    assert_equal "code 123", messages.first["body"]
    assert_equal "inbound", messages.first["direction"]
    assert_equal "+420999", messages.first["from"]
  end

  test "fetch_sms reports pending until the phone answers" do
    start = tool("fetch_sms", {})
    req_id = start.dig("structuredContent", "request_id")

    again = tool("fetch_sms", { request_id: req_id })
    assert_equal true, again.dig("structuredContent", "pending")
    assert_empty again.dig("structuredContent", "messages")
  end

  test "fetch_sms surfaces a read error from the phone" do
    start = tool("fetch_sms", {})
    req_id = start.dig("structuredContent", "request_id")

    post "/api/v1/read_requests/#{req_id}/results",
         params: { messages: [], error: "READ_SMS permission not granted on the phone." },
         headers: { "Authorization" => "Bearer #{@device_token}" }
    assert_response :success

    result = tool("fetch_sms", { request_id: req_id })
    assert result["isError"], "fetch_sms should surface the phone's read error"
  end

  test "device cannot claim another device's read requests" do
    tool("fetch_sms", {})

    other_user = User.create!(nickname: "other-read", password: "password123")
    other_device = other_user.devices.create!(name: "Other", platform: "android")
    get "/api/v1/read_requests", headers: { "Authorization" => "Bearer #{other_device.token}" }
    assert_response :success
    assert_empty JSON.parse(@response.body)["requests"]
  end

  test "device cannot claim another device's messages" do
    tool("send_sms", { to: "+420123456789", body: "for-owner" })

    other_user = User.create!(nickname: "other", password: "password123")
    other_device = other_user.devices.create!(name: "Other", platform: "android")
    get "/api/v1/outbox", headers: { "Authorization" => "Bearer #{other_device.token}" }
    assert_response :success
    assert_empty JSON.parse(@response.body)["messages"]
  end

  test "phone can register its FCM token" do
    post "/api/v1/fcm_token", params: { fcm_token: "fcm-abc-123" },
         headers: { "Authorization" => "Bearer #{@device_token}" }
    assert_response :success
    assert_equal "fcm-abc-123", @device.reload.fcm_token
  end
end
