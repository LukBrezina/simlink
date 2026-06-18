# Streamable HTTP transport for the MCP server.
#
#   POST /mcp            JSON-RPC request(s)  -> JSON-RPC response (or 202 for notifications)
#   GET  /mcp            -> text/event-stream of server notifications (push)
#   DELETE /mcp          -> end session (no-op, we are stateless)
#
# Auth: `Authorization: Bearer <mcp_token>` (preferred) or a `/mcp/:token` path
# / `?token=` for clients that can only store a URL.
class McpController < ActionController::Base
  include ActionController::Live

  skip_forgery_protection

  before_action :authenticate_mcp!

  # POST: handle one JSON-RPC message or a batch array.
  def handle
    payload = parse_json(request.raw_post)
    return render_error(nil, Mcp::Handler::PARSE_ERROR, "Parse error", status: :bad_request) if payload == :parse_error

    set_session_header
    handler = Mcp::Handler.new(@mcp_token)

    if payload.is_a?(Array)
      responses = payload.map { |m| handler.call(m) }.compact
      return head(:accepted) if responses.empty?
      render json: responses
    else
      response_body_hash = handler.call(payload)
      return head(:accepted) if response_body_hash.nil?
      render json: response_body_hash
    end
  end

  # GET: open an SSE stream and push notifications/resources/updated whenever a
  # new inbound SMS lands. Bonus channel — most agent hosts don't act on these.
  def stream
    response.headers["Content-Type"] = "text/event-stream"
    response.headers["Cache-Control"] = "no-cache"
    response.headers["X-Accel-Buffering"] = "no"
    set_session_header

    sim = @mcp_token.sim_card
    last_id = sim.messages.inbound.maximum(:id) || 0
    deadline = monotonic_now + 600
    write_comment("connected")

    loop do
      sim.messages.inbound.where("id > ?", last_id).order(:id).each do |m|
        last_id = m.id
        write_event(jsonrpc: "2.0", method: "notifications/resources/updated", params: { uri: "sms://inbox" })
      end
      break if monotonic_now >= deadline
      write_comment("keepalive")
      sleep 2
    end
  rescue ActionController::Live::ClientDisconnected, IOError, Errno::EPIPE
    # client disconnected; nothing to do
  ensure
    response.stream.close
  end

  # DELETE: clients may end a session. We are stateless, so just acknowledge.
  def terminate
    head :no_content
  end

  private

  def authenticate_mcp!
    @mcp_token = McpToken.authenticate(presented_token)
    return if @mcp_token

    response.set_header("WWW-Authenticate", 'Bearer realm="sms-for-agents"')
    render_error(nil, -32001, "Unauthorized: missing or invalid MCP token", status: :unauthorized)
  end

  def presented_token
    bearer = request.authorization.to_s[/\ABearer\s+(.+)\z/i, 1]
    bearer.presence || params[:token].presence
  end

  def parse_json(raw)
    return {} if raw.blank?
    JSON.parse(raw)
  rescue JSON::ParserError
    :parse_error
  end

  def set_session_header
    response.set_header("Mcp-Session-Id", request.headers["Mcp-Session-Id"].presence || SecureRandom.hex(16))
  end

  def render_error(id, code, message, status: :ok)
    render json: { jsonrpc: "2.0", id: id, error: { code: code, message: message } }, status: status
  end

  def write_event(obj)
    response.stream.write("data: #{obj.to_json}\n\n")
  end

  def write_comment(text)
    response.stream.write(": #{text}\n\n")
  end

  def monotonic_now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
