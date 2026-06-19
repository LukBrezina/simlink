# SimLink

**A phone number for your AI agent.** Drop a prepaid SIM into an old Android
phone, share it with SimLink, and any MCP agent (Claude, ChatGPT, Cursor, …) can
send & receive real SMS from your number. Messages are encrypted in transit,
never logged, and pruned within minutes.

Two ways to use it: **register on a hosted instance**, or **self-host the server
on your own VPS** (it's open source — instructions below).

---

## Run it locally (dev)

Requires Ruby 3.4 (`.ruby-version`).

```bash
bin/setup                 # installs gems, prepares the DB, seeds a demo account
bin/rails server -p 3001  # then open http://localhost:3001
```

The seed prints a demo login (`me@example.com` / `password123`) and a ready MCP
token. Sign in and you'll see the 3-step setup: **Connect phone → Share a SIM →
Connect an agent.** (Port 3000 is often taken; this uses 3001.)

## Self-host on your own VPS

Production runs on **[Kamal](https://kamal-deploy.org)** behind an
auto-provisioned Let's Encrypt cert. One-time setup:

```bash
cp .env.example .env          # set APP_HOST + keys (see the file's comments)
bin/kamal setup               # first deploy (boots the app + proxy + TLS)
bin/kamal deploy              # subsequent updates
```

Full step-by-step (encryption keys, backups, building the app): **[DISTRIBUTION.md](DISTRIBUTION.md)**.

## Install the phone app

The **only** install path is a direct download: open your SimLink site and tap
**Download the Android app (.apk)**, then sideload it. No app store — see
[DISTRIBUTION.md](DISTRIBUTION.md) for building & signing your own APK, and
[android/README.md](android/README.md) for the app itself.

## Connect an agent

After sharing a SIM, the **Connect an agent** screen gives copy-paste setup. The
short version for Claude Code:

```bash
claude mcp add --transport http sms "https://your-host/mcp/<MCP_TOKEN>"
```

## Checks before you push (CI signoff)

```bash
bin/ci   # RuboCop + bundler-audit + importmap audit + Brakeman + the full test suite
```

It stops at the first failure and prints a signoff line when everything's green.

---

- **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** — how it works, the MCP tools, repo layout, security model.
- **[DISTRIBUTION.md](DISTRIBUTION.md)** — deploy the server + ship the app.
- **[PRIVACY.md](PRIVACY.md)** — data handling & responsible-use disclosures.

MIT licensed. iOS can't send SMS at the OS level, so SimLink is Android-only.
