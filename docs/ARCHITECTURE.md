# SimLink — architecture & internals

Give any AI agent the ability to **send SMS and read the messages on your own
Android phone**. You install one app on your phone, create an account, pick a SIM
to share, and the app hands you an **MCP URL + token** you paste into ChatGPT,
Claude, or any MCP-capable agent. Authentication ties every agent to *your*
account, so only you can use the SIM.

**Messages are relayed transiently — encrypted at rest, never logged, and pruned
within minutes.** Message text and numbers are encrypted (Active Record
encryption) while in flight and a short TTL deletes them; there's no plaintext
store and no browsable history.

```
┌─────────────┐   MCP (Streamable HTTP + Bearer token)   ┌──────────────┐
│ Agent /     │ ───── send_sms · list_messages ─────────▶│              │
│ ChatGPT /   │ ────────── fetch_sms (non-blocking) ─────▶│ Rails server │
│ Claude      │                                           │  (the hub)   │
└─────────────┘                                           │              │
                                                          │  accounts    │
┌─────────────────────────┐  device API (Bearer token)   │  SIMs        │
│ Android app             │  pull outbox + reads (woken) ▶│  MCP tokens  │
│ Hotwire Native UI shell │  upload read rows  ──────────▶│  (encrypted  │
│ + Kotlin SMS bridge     │◀─ outbound SMS + read reqs ───│   TTL relay) │
└─────────────────────────┘◀─ FCM wake (content-free) ────└──────────────┘
        SmsManager (send) · ContentResolver (read) · SubscriptionManager (SIMs)
```

## Does MCP support "push"?

**The protocol supports server→client notifications, but the big hosted agents
(ChatGPT, Claude) don't autonomously act on them** — they run a request/response
loop, so a push doesn't "wake the model." So the agent reads on demand:

1. **`fetch_sms(box:, since:, address:, request_id:)`** — reads the messages
   already on the phone (inbox/sent). Two-step and non-blocking: the first call
   starts a read and returns `request_id` + `pending:true`; call again with that
   id to get the rows once the phone has uploaded them. An agent loops on it to
   "wait" for, e.g., a one-time code. ✅
2. **`list_messages(since:)`** — recently *sent* messages and their delivery
   status (the relay only holds the last few minutes; there's no stored history). ✅

The **phone** side does get real push: the server sends a **content-free FCM
wake** the moment an agent queues an outbound text or a read, and the phone acts
over HTTPS (a slow fallback poll covers a missed push). Everything is
non-blocking — no request ever holds a server thread.

True autonomy ("an agent reacting to texts 24/7") needs a long-running agent
process you control — point it at the same MCP server and loop on `fetch_sms`.

## Tech

- **Backend:** Rails 8.1, SQLite, Hotwire/Turbo, Tailwind. Hand-rolled,
  spec-compliant MCP server (Streamable HTTP / JSON-RPC) — no fragile gem.
- **Phone app:** Android, Hotwire Native shell + native Kotlin SMS bridge.
  (iOS can't do this — no SMS API at the OS level — so Android only.)

## Repo layout

```
app/
  controllers/mcp_controller.rb       # MCP transport: POST JSON-RPC, auth
  services/mcp/handler.rb             # MCP tools: send_sms, list_messages, fetch_sms
  services/sms_relay.rb               # SQLite relay: encrypted at rest, TTL-pruned, shared across workers
  services/fcm.rb                     # content-free FCM wake pings
  controllers/api/v1/                 # device API: outbox, read_requests, sims, status, heartbeat, fcm_token
  controllers/{dashboards,sim_cards,mcp_tokens,messages,pairings}_controller.rb
  models/{user,device,sim_card,mcp_token}.rb
android/                              # the Android app (see android/README.md)
test/integration/relay_flow_test.rb  # full agent↔server↔phone loop
test/services/sms_relay_test.rb      # relay claim/TTL unit tests
```

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

## Security model

Three separate credentials, each scoped:

| Credential | Who holds it | Grants |
| --- | --- | --- |
| Account password | You | The web UI |
| **Device token** | Your phone (EncryptedSharedPreferences) | The device API |
| **MCP token** | Each agent you connect | `send_sms` / `list_messages` / `fetch_sms` on **one** shared SIM |

- MCP tokens are stored encrypted at rest (`ActiveRecord encrypts`) and matched by
  SHA-256 digest. Revoke any token from the UI.
- An MCP token is bound to a single SIM; agents never see other SIMs or accounts.
- **Message content is encrypted at rest and never logged** — text and numbers
  live in the relay tables (Active Record encryption) only while in transit, then
  a short TTL deletes them. SMS fields are also filtered from request logs.
- For production set real `AR_ENCRYPTION_*` keys (see
  `config/initializers/active_record_encryption.rb`) and serve over HTTPS.

## Tests

The full suite runs via `bin/ci` (see the [README](../README.md)). The headline
integration test:

```bash
bin/rails test test/integration/relay_flow_test.rb
```

Covers the whole loop: agent queues a send → phone claims it via the outbox →
phone confirms `sent`; agent calls `fetch_sms` → phone claims the read-request,
uploads rows → agent retrieves them; plus auth rejection and cross-device isolation.

## Status & next steps

Built & verified (server): SQLite relay (encrypted at rest, TTL-pruned, shared
across workers), MCP server (all 3 tools, non-blocking), device API, web UI, FCM
wake — full suite green. Natural follow-ups: delivery receipts and per-token
rate limits.
