# Privacy & responsible use

A prototype that relays SMS deserves plain disclosure. Show users this before
they connect their phone, and adapt it into your privacy policy / terms.

## What the app accesses
- **SMS send/receive** — to send texts your agents request and forward texts you
  receive. The app does **not** read your existing SMS inbox; it only handles
  messages that arrive while it's running and ones agents send.
- **Phone/SIM info** — to list your SIM cards so you can choose which to share,
  and to send on the right SIM.
- **Notifications** — to run the relay as a foreground service.
- **Push (Firebase Cloud Messaging)** — to wake the app when an agent queues an
  outbound text. The push is **content-free** (just a "fetch now" signal); the
  message body and numbers are pulled from the server over HTTPS and never travel
  through Google.

The app sends message content **only** to the server you connect it to, and has
no analytics, ads, or trackers. It uses Google Play Services for the FCM wake
signal; on a Google-free device it simply falls back to a periodic poll.

## What the server stores
Message content is **not stored**. Texts are relayed **in memory only** while in
transit (a few minutes, then dropped) and are never written to disk or to the
logs. A server restart loses anything in flight. The database holds only:
- Account email + password (hashed).
- SIM details you report (label, number, carrier).
- Agent (MCP) tokens — encrypted at rest; matched by hash.
- Your phone's push (FCM) token, so the server can send wake signals.

Because message content is never persisted, there's no message history to leak or
to delete. If you run the public instance you remain the data controller for
account data; self-hosters keep even that on their own box.

## Risks users must understand
- **Carrier action (most important).** Sending automated/agent-driven SMS from a
  personal SIM can get the number rate-limited, flagged as spam, or suspended by
  the mobile carrier. Keep volumes low; this is not a bulk-SMS tool.
- **Your number is the sender.** Recipients see the user's real phone number.
- **Costs** are on the user's own mobile plan (per-SMS or bundle).
- **Trust the agent.** Any agent holding a valid MCP token can send on the shared
  SIM until the token is revoked. Issue one token per agent; revoke freely.

## Security notes for operators
- Serve over **HTTPS** only (Kamal proxy does this).
- Set strong, unique `AR_ENCRYPTION_*` keys and keep `RAILS_MASTER_KEY` secret.
- Consider per-token rate limits and a sending-volume cap before opening signups.
