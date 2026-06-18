# Privacy & responsible use

A prototype that relays SMS deserves plain disclosure. Show users this before
they connect their phone, and adapt it into your privacy policy / terms.

## What the app accesses
- **SMS send/receive** — to send texts your agents request and forward texts you
  receive. The app does **not** read your existing SMS inbox; it only handles
  messages that arrive while it's running and ones agents send.
- **Phone/SIM info** — to list your SIM cards so you can choose which to share,
  and to send on the right SIM.
- **Notifications** — to run the always-on relay as a foreground service.

The app talks **only** to the server you connect it to. It contains no
analytics, ads, trackers, or Google services.

## What the server stores
On the server you (or your provider) run:
- Account email + password (hashed).
- The **content and metadata** of messages sent/received through a shared SIM
  (numbers, body, timestamps, status).
- SIM details you report (label, number, carrier).
- Agent (MCP) tokens — encrypted at rest; matched by hash.

If you run the public instance, **you are the data controller** for your users'
message data. Have a real privacy policy and a deletion path before inviting
strangers. Privacy-conscious users can **self-host** the server (it's open
source) so their messages never touch your instance.

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
