# SMS for Agents

Give any AI agent the ability to **send and receive SMS through your own Android
phone**. You install one app on your phone, create an account, pick a SIM to
share, and the app hands you an **MCP URL + token** you paste into ChatGPT,
Claude, or any MCP-capable agent. Authentication ties every agent to *your*
account, so only you can use the SIM.

```
┌─────────────┐   MCP (Streamable HTTP + Bearer token)   ┌──────────────┐
│ Agent /     │ ───── send_sms · list_messages ─────────▶│              │
│ ChatGPT /   │ ────────── wait_for_sms (long-poll) ─────▶│ Rails server │
│ Claude      │ ◀──── notifications/resources/updated ────│  (the hub)   │
└─────────────┘                  (SSE, bonus)             │              │
                                                          │  accounts    │
┌─────────────────────────┐  device API (Bearer token)   │  SIMs        │
│ Android app             │  long-poll outbox ───────────▶│  MCP tokens  │
│ Hotwire Native UI shell │  post inbound  ──────────────▶│  messages    │
│ + Kotlin SMS bridge     │◀─ queued outbound SMS ────────│              │
└─────────────────────────┘                              └──────────────┘
        SmsManager (send) · BroadcastReceiver (receive) · SubscriptionManager (SIMs)
```

## Does MCP support "push"?

You asked specifically about this. **The protocol supports server→client
notifications, but the big hosted agents (ChatGPT, Claude) don't autonomously act
on them** — they run a request/response loop, so a push doesn't "wake the model."
So this project gives you three ways to receive, in order of practicality:

1. **`wait_for_sms(timeout)`** — a tool that blocks server-side until a text
   arrives (or times out). The agent calls it and effectively "waits." This is
   the most compatible push-like behavior. ✅ built & tested
2. **`list_messages(since:)`** — plain polling whenever the agent wants. ✅
3. **`notifications/resources/updated`** over SSE — real push for the few clients
   that honor it; emitted the instant an SMS lands. ✅ (bonus)

True autonomy ("an agent reacting to texts 24/7") needs a long-running agent
process you control — point it at the same MCP server and loop on `wait_for_sms`.

## Tech

- **Backend:** Rails 8.1, SQLite, Hotwire/Turbo, Tailwind. Hand-rolled,
  spec-compliant MCP server (Streamable HTTP / JSON-RPC) — no fragile gem.
- **Phone app:** Android, Hotwire Native shell + native Kotlin SMS bridge.
  (iOS can't do this — no SMS API at the OS level — so Android only, as you said.)

## Repo layout

```
app/
  controllers/mcp_controller.rb       # MCP transport: POST JSON-RPC, GET SSE, auth
  services/mcp/handler.rb             # MCP tools: send_sms, list_messages, wait_for_sms
  controllers/api/v1/                 # device API: outbox, sims, inbound, status, heartbeat
  controllers/{dashboards,sim_cards,mcp_tokens,messages,pairings}_controller.rb
  models/{user,device,sim_card,mcp_token,message}.rb
android/                              # the Android app (see android/README.md)
test/integration/relay_flow_test.rb  # full agent↔server↔phone loop
```

## Run the server

```bash
bin/rails db:setup        # create + migrate + seed a demo account
bin/dev                   # or: bin/rails server -p 3001
```

> Port 3000 may be taken by another app — use `PORT=3001 bin/dev` or
> `bin/rails server -p 3001`.

The seed prints a demo login (`me@example.com` / `password123`) and a ready MCP
token. Open the printed URL, sign in, and you'll see the 3-step setup:
**Connect phone → Share a SIM → Connect an agent.**

## Connect an agent

The **Connect an agent** screen gives you copy-paste blocks. Examples:

**Claude Code (one command):**
```bash
claude mcp add --transport http sms "https://your-host/mcp/<MCP_TOKEN>"
```

**URL + header (any MCP client that allows headers):**
```
URL:    https://your-host/mcp
Header: Authorization: Bearer <MCP_TOKEN>
```

**JSON config (Claude Desktop / generic):**
```json
{ "mcpServers": { "sms": { "type": "http", "url": "https://your-host/mcp",
  "headers": { "Authorization": "Bearer <MCP_TOKEN>" } } } }
```

**ChatGPT connectors** typically only take a URL, so use the URL-with-token form:
`https://your-host/mcp/<MCP_TOKEN>`.

Quick manual check with curl:
```bash
curl -s https://your-host/mcp -H "Authorization: Bearer <MCP_TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call",
       "params":{"name":"send_sms","arguments":{"to":"+420...","body":"hi"}}}'
```

## The Android app

See **[android/README.md](android/README.md)** for build & install. In short:
open `android/` in Android Studio, set `BASE_URL` to your server, run it on a real
phone, sign in, tap **Connect phone**, grant SMS permissions, share a SIM.

## Security model

Three separate credentials, each scoped:

| Credential | Who holds it | Grants |
| --- | --- | --- |
| Account password | You | The web UI |
| **Device token** | Your phone (EncryptedSharedPreferences) | The device API |
| **MCP token** | Each agent you connect | `send_sms` / `list_messages` / `wait_for_sms` on **one** shared SIM |

- MCP tokens are stored encrypted at rest (`ActiveRecord encrypts`) and matched by
  SHA-256 digest. Revoke any token from the UI.
- An MCP token is bound to a single SIM; agents never see other SIMs or accounts.
- For production set real `AR_ENCRYPTION_*` keys (see
  `config/initializers/active_record_encryption.rb`) and serve over HTTPS.

## Tests

```bash
bin/rails test test/integration/relay_flow_test.rb
```

Covers the whole loop: agent queues a send → phone claims it via the outbox →
phone confirms `sent`; phone reports an inbound SMS → agent reads it via
`list_messages` / `wait_for_sms`; plus auth rejection and cross-device isolation.

## Distribute it (prototype)

Ship to the public without the Play Store: host the server on your own VPS with
**Kamal**, then distribute the app via **GitHub Releases + Obtainium** and
**F-Droid** (the app is fully FOSS — no Google services). Step-by-step in
**[DISTRIBUTION.md](DISTRIBUTION.md)**; data & responsible-use disclosures in
**[PRIVACY.md](PRIVACY.md)**.

Quick deploy:
```bash
# edit config/deploy.yml + .env, then:
bin/kamal setup     # first time
bin/kamal deploy    # updates
```

## Status & next steps

Built & verified: backend, MCP server (all 3 tools + SSE), device API, web UI,
the full Android project, and the deploy + distribution pipeline (Kamal, signed
release CI, F-Droid metadata). Natural follow-ups: FCM push (let the phone sleep
instead of long-polling), delivery receipts, and per-token rate limits.
