module Mcp
  # Pure JSON-RPC 2.0 dispatch for the Model Context Protocol.
  #
  # Given a parsed JSON-RPC message (single object), #call returns a response
  # hash to send back, or nil for notifications (which get no response).
  # HTTP transport and auth live in McpController.
  #
  # Messages are relayed through the in-memory SmsRelay — never stored on disk
  # and never logged. Every tool call is non-blocking: wait_for_sms peeks the
  # buffer and returns immediately, and the agent re-polls to keep waiting.
  class Handler
    PROTOCOL_VERSION = "2025-06-18".freeze
    SERVER_INFO = { name: "simlink", version: "0.1.0" }.freeze
    DEFAULT_LIMIT = 20

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
                      "`list_messages` to see recent in-flight messages, and " \
                      "`wait_for_sms` to check for newly arrived texts. Messages are " \
                      "relayed in memory and not stored, so only recent traffic is visible."
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

      entry = SmsRelay.enqueue_outbound(
        sim_card_id: sim_card.id,
        subscription_id: sim_card.subscription_id,
        to: to,
        body: body
      )
      Fcm.wake(sim_card.device)
      mcp_token.touch_used!

      tool_content(
        "Queued SMS to #{to} (message ##{entry.id}). The phone will send it shortly; " \
        "use list_messages to check its status.",
        message_json(entry)
      )
    end

    def tool_list_messages(args)
      direction = %w[inbound outbound].include?(args["direction"]) ? args["direction"] : "all"
      limit = [ [ args.fetch("limit", DEFAULT_LIMIT).to_i, 1 ].max, 100 ].min
      entries = SmsRelay.recent(sim_card.id, direction: direction, since: parse_time(args["since"]), limit: limit)
      mcp_token.touch_used!

      tool_content(
        entries.empty? ? "No recent messages." : "#{entries.size} message(s).",
        { messages: entries.map { |e| message_json(e) } }
      )
    end

    # Non-blocking: returns inbound SMS that arrived after `since` (defaults to
    # everything currently buffered). If none, replies pending:true with a
    # `checked_at` timestamp to pass back as `since` on the next call.
    def tool_wait_for_sms(args)
      since = parse_time(args["since"])
      checked_at = Time.current
      fresh = SmsRelay.inbound_since(sim_card.id, since)
      mcp_token.touch_used!

      if fresh.any?
        tool_content(
          "#{fresh.size} new inbound SMS.",
          { messages: fresh.map { |e| message_json(e) }, checked_at: checked_at.iso8601 }
        )
      else
        tool_content(
          "No new SMS yet. Call wait_for_sms again with since=#{checked_at.iso8601} to keep checking.",
          { messages: [], pending: true, checked_at: checked_at.iso8601 }
        )
      end
    end

    # ---- resources -------------------------------------------------------

    def resource_definitions
      [
        {
          uri: "sms://inbox",
          name: "SMS inbox",
          description: "Recent in-flight messages for #{sim_card.display_name} (not stored)",
          mimeType: "application/json"
        }
      ]
    end

    def resources_read(params)
      uri = params["uri"]
      raise ArgumentError, "Unknown resource: #{uri}" unless uri == "sms://inbox"

      messages = SmsRelay.recent(sim_card.id, limit: 50).map { |e| message_json(e) }
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
          description: "List recent in-flight SMS (sent and received) for the shared SIM, newest first. " \
                       "Messages are relayed in memory and not stored, so only the last few minutes are visible.",
          inputSchema: {
            type: "object",
            properties: {
              direction: { type: "string", enum: %w[inbound outbound all], description: "Filter by direction. Default all." },
              limit: { type: "integer", description: "Max messages to return (1-100). Default #{DEFAULT_LIMIT}." },
              since: { type: "string", description: "ISO8601 timestamp; only messages after this time." }
            }
          }
        },
        {
          name: "wait_for_sms",
          description: "Check for newly arrived inbound SMS and return immediately (non-blocking). " \
                       "If none have arrived it returns pending:true with a `checked_at` time — call " \
                       "again, passing that as `since`, to keep waiting for the next text.",
          inputSchema: {
            type: "object",
            properties: {
              since: { type: "string", description: "ISO8601; return inbound messages after this time. " \
                                                    "Pass the previous response's `checked_at` to get only newer ones." }
            }
          }
        }
      ]
    end

    # ---- helpers ---------------------------------------------------------

    # The shape returned to MCP agents. `entry` is an SmsRelay::Inbound/Outbound.
    def message_json(entry)
      if entry.is_a?(SmsRelay::Inbound)
        {
          id: entry.id, direction: "inbound",
          from: entry.from, to: sim_card.phone_number,
          body: entry.body, status: "received",
          timestamp: entry.received_at.iso8601
        }
      else
        {
          id: entry.id, direction: "outbound",
          from: sim_card.phone_number, to: entry.to,
          body: entry.body, status: entry.status,
          error: entry.error,
          timestamp: (entry.updated_at || entry.created_at).iso8601
        }
      end.compact
    end

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
  end

  class ToolError < StandardError; end
end
