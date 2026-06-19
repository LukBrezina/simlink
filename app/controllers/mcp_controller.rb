# Streamable HTTP transport for the MCP server.
#
#   POST /mcp            JSON-RPC request(s)  -> JSON-RPC response (or 202 for notifications)
#   DELETE /mcp          -> end session (no-op, we are stateless)
#
# Auth: `Authorization: Bearer <mcp_token>` (preferred) or a `/mcp/:token` path
# / `?token=` for clients that can only store a URL.
#
# Every request returns immediately — no long-lived connections. Agents read the
# phone's messages by calling fetch_sms repeatedly (it's non-blocking: start a
# read, then re-poll with the returned request_id).
class McpController < ActionController::Base
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
end
