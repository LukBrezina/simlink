module Mcp
  # Pure JSON-RPC 2.0 dispatch for the Model Context Protocol.
  #
  # Given a parsed JSON-RPC message (single object), #call returns a response
  # hash to send back, or nil for notifications (which get no response).
  # HTTP transport and auth live in McpController.
  #
  # Messages are relayed through SmsRelay — encrypted at rest, never logged, and
  # pruned within minutes. Every tool call is non-blocking: fetch_sms enqueues a read
  # for the phone and returns immediately, and the agent re-polls (passing the
  # returned request_id) until the phone has uploaded the rows.
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
        instructions: "Send and read SMS through the user's shared SIM card " \
                      "(#{sim_card.display_name}). Use `send_sms` to send a text, " \
                      "`list_messages` to see the status of recently sent messages, and " \
                      "`fetch_sms` to read messages already on the phone (inbox/sent). " \
                      "fetch_sms is a two-step, non-blocking call: start a read, then call " \
                      "again with the returned `request_id` to get the rows once the phone " \
                      "has uploaded them. Traffic is relayed transiently (encrypted, pruned " \
                      "within minutes); reads happen live on the device."
      }
    end

    def tools_call(params)
      name = params["name"]
      args = params["arguments"] || {}
      raise ArgumentError, "Missing tool name" if name.blank?

      case name
      when "send_sms"      then tool_send_sms(args)
      when "list_messages" then tool_list_messages(args)
      when "fetch_sms"     then tool_fetch_sms(args)
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
      Fcm.wake_async(sim_card.device)
      mcp_token.touch_used!

      tool_content(
        "Queued SMS to #{to} (message ##{entry.id}). The phone will send it shortly; " \
        "use list_messages to check its status.",
        message_json(entry)
      )
    end

    def tool_list_messages(args)
      limit = [ [ args.fetch("limit", DEFAULT_LIMIT).to_i, 1 ].max, 100 ].min
      entries = SmsRelay.recent(sim_card.id, since: parse_time(args["since"]), limit: limit)
      mcp_token.touch_used!

      tool_content(
        entries.empty? ? "No recent messages." : "#{entries.size} message(s).",
        { messages: entries.map { |e| message_json(e) } }
      )
    end

    # Read SMS already stored on the phone, on demand. Two-step and non-blocking:
    # the first call (no request_id) enqueues a read and wakes the phone; later
    # calls (with request_id) return the rows once the phone has uploaded them.
    def tool_fetch_sms(args)
      request_id = args["request_id"]
      return fetch_sms_result(request_id) if request_id.present?

      limit = [ [ args.fetch("limit", DEFAULT_LIMIT).to_i, 1 ].max, 100 ].min
      box = %w[inbox sent all].include?(args["box"]) ? args["box"] : "all"

      entry = SmsRelay.enqueue_read(
        sim_card_id: sim_card.id,
        subscription_id: sim_card.subscription_id,
        limit: limit,
        since: parse_time(args["since"])&.iso8601,
        address: args["address"].to_s.strip.presence,
        box: box
      )
      Fcm.wake_async(sim_card.device)
      mcp_token.touch_used!

      scope = box == "all" ? "" : "#{box} "
      tool_content(
        "Requested up to #{limit} #{scope}message(s) from the phone (request ##{entry.id}). " \
        "The phone reads them on-device and uploads them; call fetch_sms again with " \
        "request_id=#{entry.id} to retrieve the results.",
        { request_id: entry.id, pending: true, messages: [] }
      )
    end

    def fetch_sms_result(request_id)
      entry = SmsRelay.read_result(request_id.to_i, sim_card.id)
      mcp_token.touch_used!
      unless entry
        raise Mcp::ToolError, "Unknown or expired request_id #{request_id}. Reads are kept only " \
                              "briefly (a few minutes); start a new fetch_sms."
      end

      unless entry.status == "fulfilled"
        return tool_content(
          "The phone hasn't answered yet. Call fetch_sms again with request_id=#{entry.id} in a moment.",
          { request_id: entry.id, pending: true, messages: [] }
        )
      end

      raise Mcp::ToolError, "The phone couldn't read its messages: #{entry.error}" if entry.error.present?

      messages = Array(entry.messages).map { |m| read_message_json(m) }
      tool_content(
        messages.empty? ? "No matching messages on the device." : "#{messages.size} message(s) read from the device.",
        { request_id: entry.id, pending: false, messages: messages }
      )
    end

    # ---- resources -------------------------------------------------------

    def resource_definitions
      [
        {
          uri: "sms://recent",
          name: "Recent sent SMS",
          description: "Status of recently sent messages for #{sim_card.display_name} " \
                       "(transient, pruned within minutes). Use fetch_sms to read the phone's inbox.",
          mimeType: "application/json"
        }
      ]
    end

    def resources_read(params)
      uri = params["uri"]
      raise ArgumentError, "Unknown resource: #{uri}" unless uri == "sms://recent"

      messages = SmsRelay.recent(sim_card.id, limit: 50).map { |e| message_json(e) }
      {
        contents: [
          {
            uri: "sms://recent",
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
          description: "List recently sent SMS (and their send status/error) for the shared SIM, newest " \
                       "first. This is outbound traffic only — the last few minutes, then pruned. " \
                       "To read messages already on the phone (including received ones) use fetch_sms.",
          inputSchema: {
            type: "object",
            properties: {
              limit: { type: "integer", description: "Max messages to return (1-100). Default #{DEFAULT_LIMIT}." },
              since: { type: "string", description: "ISO8601 timestamp; only messages after this time." }
            }
          }
        },
        {
          name: "fetch_sms",
          description: "Read SMS already stored on the phone (inbox and/or sent), on demand. Two-step and " \
                       "non-blocking: call it with your filters to start a read (returns a `request_id` and " \
                       "pending:true), then call it again passing that `request_id` to get the messages once " \
                       "the phone has uploaded them. Nothing is stored on the server — the read runs live on " \
                       "the device. Use this to look up received texts, e.g. a one-time code.",
          inputSchema: {
            type: "object",
            properties: {
              request_id: { type: "integer", description: "Return the result of an earlier fetch_sms. Omit to start a new read." },
              box: { type: "string", enum: %w[inbox sent all], description: "Which mailbox to read. Default all." },
              limit: { type: "integer", description: "Max messages to return (1-100, newest first). Default #{DEFAULT_LIMIT}." },
              since: { type: "string", description: "ISO8601 timestamp; only messages newer than this." },
              address: { type: "string", description: "Only messages to/from this phone number (E.164 recommended)." }
            }
          }
        }
      ]
    end

    # ---- helpers ---------------------------------------------------------

    # The shape returned to MCP agents for an outbound (sent) message.
    def message_json(entry)
      {
        id: entry.id, direction: "outbound",
        from: sim_card.phone_number, to: entry.to,
        body: entry.body, status: entry.status,
        error: entry.error,
        timestamp: (entry.updated_at || entry.created_at).iso8601
      }.compact
    end

    # The shape returned to MCP agents for a message read off the device (fetch_sms).
    # `m` is a plain hash uploaded by the phone: { "from", "to", "body", "date", "type" }.
    def read_message_json(m)
      sent = m["type"] == "sent"
      {
        direction: sent ? "outbound" : "inbound",
        from: sent ? sim_card.phone_number : m["from"],
        to:   sent ? m["to"] : sim_card.phone_number,
        body: m["body"],
        timestamp: m["date"]
      }.compact
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
