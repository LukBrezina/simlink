class PagesController < ApplicationController
  allow_unauthenticated_access only: %i[home agent llms]

  # Per-agent connect guides. `method` picks how the connect snippet renders.
  AGENTS = {
    "claude"      => { name: "Claude Desktop", method: :json,
                       blurb: "Add SimLink as an HTTP MCP server in your Claude config." },
    "claude-code" => { name: "Claude Code", method: :command,
                       blurb: "One command in your terminal." },
    "chatgpt"     => { name: "ChatGPT", method: :url,
                       blurb: "Paste the URL into a custom connector." },
    "cursor"      => { name: "Cursor", method: :json,
                       blurb: "Add it to your mcp.json." },
    "hermes"      => { name: "Hermes", method: :json,
                       blurb: "Point your Hermes agent at the MCP endpoint." },
    "openclaw"    => { name: "OpenClaw", method: :json,
                       blurb: "Register SimLink as an MCP tool server." }
  }.freeze

  # Public landing page for anonymous browsers only. Signed-in users AND the
  # native app go to the dashboard — the dashboard enforces auth through the
  # normal flow (which sets return-to), so a post-login redirect lands back on
  # the dashboard instead of bouncing through here to /session/new.
  def home
    @agents = AGENTS
    redirect_to dashboard_path if authenticated? || hotwire_native_app?
  end

  # Per-agent connect guide, e.g. /for/claude.
  def agent
    @slug = params[:slug]
    @agent = AGENTS[@slug]
    redirect_to(root_path) unless @agent
  end

  # Machine-readable summary for LLMs/agents that read a site before using it.
  def llms
    host = request.base_url
    guides = AGENTS.map { |slug, a| "- #{a[:name]}: #{host}/for/#{slug}" }.join("\n")
    body = <<~TXT
      # SimLink

      > SMS for AI agents. Turn an old Android phone + a prepaid SIM into a
      > dedicated phone number your AI agent can send and receive texts from.

      SimLink is a hosted MCP (Model Context Protocol) server. It relays SMS
      through a real phone/SIM the user controls. Message content is encrypted at
      rest, never logged, and pruned within minutes — no browsable history.

      ## Connect
      - MCP endpoint: #{host}/mcp  (Streamable HTTP, `Authorization: Bearer <token>`)
      - URL-with-token form: #{host}/mcp/<token>  (for clients that only take a URL)
      - Get a token: #{host}/get  (install the app, sign in, share a SIM)

      ## Tools
      - send_sms(to, body) — send a text from the user's shared SIM
      - list_messages(since?, limit?) — recently sent messages (+ send status/error)
      - fetch_sms(box?, since?, address?, limit?, request_id?) — read SMS already on the
        phone (inbox/sent). Two-step: start a read, then call again with the returned
        request_id to get the rows. Non-blocking.

      ## Per-agent guides
      #{guides}
    TXT
    render plain: body, content_type: "text/plain"
  end
end
