module Mcp
  # Pure JSON-RPC 2.0 dispatch for the Model Context Protocol.
  #
  # Given a parsed JSON-RPC message (single object), #call returns a response
  # hash to send back, or nil for notifications (which get no response).
  # HTTP transport, auth and SSE streaming live in McpController.
  class Handler
    PROTOCOL_VERSION = "2025-06-18".freeze
    SERVER_INFO = { name: "simlink", version: "0.1.0" }.freeze
    DEFAULT_WAIT = 25
    MAX_WAIT = 280
    POLL_INTERVAL = 1.5

    # JSON-RPC error codes
    PARSE_ERROR = -32700
    INVALID_REQUEST = -32600
    METHOD_NOT_FOUND = -32601
    INVALID_PARAMS = -32602
    INTERNAL_ERROR = -32603

    attr_reader :mcp_token, :sim_card

    def initialize(mcp_token)
      @mcp_token = mcp_token
      @sim_card = mcp_token.sim_card
    end

    # message: a parsed JSON-RPC object. Returns a response hash or nil.
    def call(message)
      unless message.is_a?(Hash) && message["jsonrpc"] == "2.0" && message["method"].is_a?(String)
        return error_response(message.is_a?(Hash) ? message["id"] : nil, INVALID_REQUEST, "Invalid JSON-RPC request")
      end

      id = message["id"]
      method = message["method"]
      params = message["params"] || {}
      notification = !message.key?("id")

      result =
        case method
        when "initialize"                then initialize_result(params)
        when "ping"                      then {}
        when "notifications/initialized" then nil
        when "notifications/cancelled"   then nil
        when "tools/list"                then { tools: tool_definitions }
        when "tools/call"                then tools_call(params)
        when "resources/list"            then { resources: resource_definitions }
        when "resources/read"            then resources_read(params)
        when "resources/templates/list"  then { resourceTemplates: [] }
        else
          return notification ? nil : error_response(id, METHOD_NOT_FOUND, "Unknown method: #{method}")
        end

      return nil if notification
      success_response(id, result)
    rescue Mcp::ToolError => e
      success_response(id, tool_error_content(e.message))
    rescue ArgumentError => e
      error_response(id, INVALID_PARAMS, e.message)
    rescue => e
      Rails.logger.error("[MCP] #{e.class}: #{e.message}")
      error_response(id, INTERNAL_ERROR, "Internal error")
    end

    private

    # ---- method results --------------------------------------------------

    def initialize_result(params)
      requested = params["protocolVersion"]
      {
        protocolVersion: requested.is_a?(String) ? requested : PROTOCOL_VERSION,
        capabilities: {
          tools: {},
          resources: { subscribe: false, listChanged: false }
        },
        serverInfo: SERVER_INFO,
        instructions: "Send and receive SMS through the user's shared SIM card " \
                      "(#{sim_card.display_name}). Use `send_sms` to send a text, " \
                      "`list_messages` to read recent history, and `wait_for_sms` to " \
                      "block until a new inbound text arrives (push-style)."
      }
    end

    def tools_call(params)
      name = params["name"]
      args = params["arguments"] || {}
      raise ArgumentError, "Missing tool name" if name.blank?

      case name
      when "send_sms"      then tool_send_sms(args)
      when "list_messages" then tool_list_messages(args)
      when "wait_for_sms"  then tool_wait_for_sms(args)
      else
        raise Mcp::ToolError, "Unknown tool: #{name}"
      end
    end

    # ---- tools -----------------------------------------------------------

    def tool_send_sms(args)
      to = args["to"].to_s.strip
      body = args["body"].to_s
      raise Mcp::ToolError, "`to` (recipient phone number) is required" if to.blank?
      raise Mcp::ToolError, "`body` (message text) is required" if body.strip.blank?

      message = sim_card.messages.create!(
        mcp_token: mcp_token,
        direction: "outbound",
        address: to,
        body: body,
        status: "queued"
      )
      mcp_token.touch_used!

      tool_content(
        "Queued SMS to #{to} (message ##{message.id}). The phone will send it shortly; " \
        "use list_messages to check its status.",
        message.as_mcp_json
      )
    end

    def tool_list_messages(args)
      scope = sim_card.messages.recent_first
      case args["direction"]
      when "inbound"  then scope = scope.inbound
      when "outbound" then scope = scope.outbound
      end
      if (since = parse_time(args["since"]))
        scope = scope.where("messages.created_at > ?", since)
      end
      limit = [ [ args.fetch("limit", 20).to_i, 1 ].max, 100 ].min
      messages = scope.limit(limit).map(&:as_mcp_json)
      mcp_token.touch_used!

      tool_content(
        messages.empty? ? "No messages found." : "#{messages.size} message(s).",
        { messages: messages }
      )
    end

    def tool_wait_for_sms(args)
      timeout = [ [ args.fetch("timeout_seconds", DEFAULT_WAIT).to_i, 1 ].max, MAX_WAIT ].min
      since = parse_time(args["since"]) || Time.current
      deadline = monotonic_now + timeout

      loop do
        fresh = sim_card.messages.inbound.where("messages.created_at > ?", since).chronological.to_a
        if fresh.any?
          mcp_token.touch_used!
          return tool_content(
            "#{fresh.size} new inbound SMS.",
            { messages: fresh.map(&:as_mcp_json) }
          )
        end
        break if monotonic_now >= deadline
        sleep [ POLL_INTERVAL, deadline - monotonic_now ].min
      end

      mcp_token.touch_used!
      tool_content(
        "No new SMS within #{timeout}s. Call wait_for_sms again to keep waiting.",
        { messages: [], timed_out: true }
      )
    end

    # ---- resources -------------------------------------------------------

    def resource_definitions
      [
        {
          uri: "sms://inbox",
          name: "SMS inbox",
          description: "Recent received and sent messages for #{sim_card.display_name}",
          mimeType: "application/json"
        }
      ]
    end

    def resources_read(params)
      uri = params["uri"]
      raise ArgumentError, "Unknown resource: #{uri}" unless uri == "sms://inbox"

      messages = sim_card.messages.recent_first.limit(50).map(&:as_mcp_json)
      {
        contents: [
          {
            uri: "sms://inbox",
            mimeType: "application/json",
            text: JSON.pretty_generate(messages: messages)
          }
        ]
      }
    end

    def tool_definitions
      [
        {
          name: "send_sms",
          description: "Send an SMS text message from the user's shared SIM card.",
          inputSchema: {
            type: "object",
            properties: {
              to: { type: "string", description: "Recipient phone number, ideally E.164 (e.g. +420777123456)." },
              body: { type: "string", description: "The message text to send." }
            },
            required: %w[to body]
          }
        },
        {
          name: "list_messages",
          description: "List recent SMS messages (sent and received) for the shared SIM, newest first.",
          inputSchema: {
            type: "object",
            properties: {
              direction: { type: "string", enum: %w[inbound outbound all], description: "Filter by direction. Default all." },
              limit: { type: "integer", description: "Max messages to return (1-100). Default 20." },
              since: { type: "string", description: "ISO8601 timestamp; only messages created after this time." }
            }
          }
        },
        {
          name: "wait_for_sms",
          description: "Block until a new inbound SMS arrives, then return it. Push-style: " \
                       "the call holds until a text comes in or the timeout elapses.",
          inputSchema: {
            type: "object",
            properties: {
              timeout_seconds: { type: "integer", description: "How long to wait (1-#{MAX_WAIT}s). Default #{DEFAULT_WAIT}." },
              since: { type: "string", description: "ISO8601; return inbound messages after this time. Defaults to now (the call start)." }
            }
          }
        }
      ]
    end

    # ---- helpers ---------------------------------------------------------

    # MCP tool result with both a human-readable text block and machine-readable
    # structuredContent (for clients that support it).
    def tool_content(text, structured = nil)
      result = { content: [ { type: "text", text: structured ? "#{text}\n\n#{JSON.pretty_generate(structured)}" : text } ] }
      result[:structuredContent] = structured if structured
      result
    end

    def tool_error_content(message)
      { content: [ { type: "text", text: "Error: #{message}" } ], isError: true }
    end

    def success_response(id, result)
      { jsonrpc: "2.0", id: id, result: result }
    end

    def error_response(id, code, message)
      { jsonrpc: "2.0", id: id, error: { code: code, message: message } }
    end

    def parse_time(value)
      return nil if value.blank?
      Time.zone.parse(value.to_s)
    rescue ArgumentError
      nil
    end

    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end

  class ToolError < StandardError; end
end
