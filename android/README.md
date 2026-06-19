# SMS for Agents — Android app

A thin [Hotwire Native](https://native.hotwired.dev/) shell around the Rails web
UI, plus the native pieces Android needs for SMS:

| Concern | Where |
| --- | --- |
| Account / SIM picker / MCP setup screens | Rendered by Rails, shown in the WebView |
| Capture the device token from the pairing page | `bridge/DeviceComponent.kt` (Hotwire bridge "device") |
| List SIM cards & report them | `sms/SimReporter.kt` (`SubscriptionManager`) |
| Send queued SMS | `sms/SmsSender.kt` (`SmsManager`, per-subscription) |
| Read SMS already on the device | `sms/SmsReader.kt` (on-demand SMS-provider query) |
| Always-on relay (sends + answers reads) | `service/OutboxService.kt` (foreground service) |
| Talk to the server | `net/ApiClient.kt` (device-token Bearer auth) |
| Secure token storage | `data/TokenStore.kt` (EncryptedSharedPreferences) |

## Prerequisites

- **Android Studio** (Ladybug or newer) with Android SDK 35.
- A **physical Android phone** with a SIM. SMS send/read does **not** work on
  most emulators (no real radio), though you can test the UI/pairing on one.

## Configure the server URL

`BASE_URL` is set per build type in `app/build.gradle.kts`:

```kotlin
debug   { buildConfigField("String", "BASE_URL", "\"http://10.0.2.2:3001\"") }
release { buildConfigField("String", "BASE_URL", "\"https://sms.example.com\"") }
```

- **debug** → `10.0.2.2:3001` is the emulator's alias for your host's
  `localhost:3001`. For a real phone in dev, use your LAN IP
  (`http://192.168.x.x:3001`) or an `ngrok` tunnel.
- **release** → your deployed HTTPS server. With HTTPS you can drop
  `android:usesCleartextTraffic="true"` from the manifest.

For building & signing a release and serving it as a direct download from your
server, see **[../DISTRIBUTION.md](../DISTRIBUTION.md)**.

## Build & install

1. Open the **`android/`** folder in Android Studio. On first sync it provisions
   Gradle and generates the wrapper. (CLI alternative if you have Gradle:
   `cd android && gradle wrapper` then `./gradlew installDebug`.)
2. Plug in your phone (USB debugging on) and **Run** the `app` configuration.
3. In the app:
   - Sign in / create your account (web view).
   - Open **Connect**, tap **Connect phone** — the bridge stores the device token.
   - Grant **SMS** and **Phone** permissions when prompted.
   - Your SIMs are reported automatically; pick one to **share**.
   - Create an **agent token** and paste the MCP URL into your agent.

## How the relay works

- **Outbound:** the foreground `OutboxService` keeps a 25s long-poll open against
  `GET /api/v1/outbox`. When the server hands back queued messages it sends each
  via `SmsManager` on the right SIM and reports `sent`/`failed`.
- **Reads (inbox/sent):** when an agent calls `fetch_sms`, the server enqueues a
  read-request and wakes the phone. `OutboxService` claims it from
  `GET /api/v1/read_requests`, `SmsReader` queries the device SMS provider with
  the requested filters (box / since / address / limit), and the rows are POSTed
  to `/api/v1/read_requests/:id/results`. There is no live receive — the phone
  only reads its own store on demand, never pushes.

## Important notes

- **Permissions & Play Store:** `SEND_SMS` / `READ_SMS` are restricted
  permissions. This app is designed to be **sideloaded onto your own phone**; it
  is not intended for Play Store distribution without Google's SMS-permission
  exception. It does **not** need to be the default SMS app.
- **Battery / Doze:** a foreground service is the Firebase-free way to stay
  responsive. Exclude the app from battery optimization for reliability. The
  production-grade alternative is **FCM push** (server wakes the phone instead of
  the phone polling) — a clean future upgrade that reuses the same endpoints.
- **Dual SIM:** reads are scoped to the token's SIM by the provider's `sub_id`
  column when the OEM populates it; rows with no `sub_id` are kept (never wrongly
  dropped). Single-SIM is unambiguous.

## Hotwire Native versions

Wiring targets `dev.hotwire:core` / `dev.hotwire:navigation-fragments` **1.2.8**.
If you bump versions and an API moved, regenerate the shell from the official
[demo](https://github.com/hotwired/hotwire-native-android/tree/main/demo) and drop
the `bridge/`, `sms/`, `service/`, `net/`, `data/` packages back in — they're
independent of the Hotwire API.
