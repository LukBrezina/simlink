# Privacy & responsible use

A prototype that relays SMS deserves plain disclosure. Show users this before
they connect their phone, and adapt it into your privacy policy / terms.

## What the app accesses
- **SMS send & read** — to send texts your agents request, and to read messages
  already on your phone (inbox and sent) when an agent calls `fetch_sms`. Reads
  happen **on demand** on the device — the app does **not** listen in the
  background for incoming texts. Only the messages matching an agent's request
  (by mailbox, time, number, and a count limit) are uploaded to your server, and
  held only briefly — encrypted in transit, then pruned (see below).
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
Message content is held **only while in transit** (a few minutes), then
automatically pruned. While in transit it lives in the relay tables
(`relay_outbounds` / `relay_reads`), where the **message text and phone numbers
are encrypted at rest** (AES via Active Record encryption) and **filtered from
the logs** — the same scheme used for agent tokens. It is never kept as a
browsable history: once a message is delivered and ages past the short TTL, its
row is deleted. The rest of the database holds only:
- Account email + password (hashed).
- SIM details you report (label, number, carrier).
- Agent (MCP) tokens — encrypted at rest; matched by hash.
- Your phone's push (FCM) token, so the server can send wake signals.

Because in-transit content is encrypted and short-lived, there's no plaintext
message store and no long-term history to leak or to delete. If you run the
public instance you remain the data controller for account data; self-hosters
keep even that on their own box.

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
