# Distributing SimLink (prototype)

The plan: **host the server on your VPS with Kamal**, then build & sign the APK
and **serve it as a direct download from your own server**. No app store — no
Google Play, no F-Droid, no Obtainium. Users get the app one way: they tap
**Download** on your site and sideload the `.apk`.

```
 your VPS (Kamal) ── https://sms.example.com ──┐
                                               │  signed APK served at /get
 users ──────────▶ open the site ─────────────┴──▶ Download → sideload
```

---

## 1. Deploy the server (Kamal)

**Prerequisites**
- A VPS with Docker-capable Linux and SSH access.
- A domain with an **A record** pointing at the VPS (e.g. `sms.example.com`).
- A container registry account (Docker Hub or GHCR) + an access token.

**Configure**
1. Edit `config/deploy.yml` — set `image`, `servers.web` (VPS IP),
   `proxy.host` (domain), `registry.username`, and `builder.arch` (`amd64` or
   `arm64` to match the VPS).
2. `cp .env.example .env` and fill it in. Generate fresh encryption keys:
   ```bash
   bin/rails runner 'puts SecureRandom.alphanumeric(32)'   # x3
   cat config/master.key                                   # RAILS_MASTER_KEY
   ```
3. Deploy:
   ```bash
   bin/kamal setup     # first time: installs Docker bits, proxy, boots the app
   # later updates:
   bin/kamal deploy
   ```
   kamal-proxy auto-provisions a Let's Encrypt certificate for your domain.
   Migrations run automatically on boot (`db:prepare` in the entrypoint).

**After deploy**
- Visit `https://sms.example.com`, create your account.
- `bin/kamal app exec --interactive --reuse "bin/rails console"` for admin tasks.
- **Back up** the `sms_for_agents_storage` Docker volume — it holds the SQLite DB.

---

## 2. Point the app at your server

In `android/app/build.gradle.kts`, set the **release** `BASE_URL`:
```kotlin
release { buildConfigField("String", "BASE_URL", "\"https://sms.example.com\"") }
```
(Debug stays `http://10.0.2.2:3001` for the emulator.)

---

## 3. Build & sign the APK

**One-time keystore** (keep it and its passwords backed up forever — losing them
means you can never ship an update users can install over the top):
```bash
cd android
keytool -genkey -v -keystore release.jks -keyalg RSA -keysize 2048 \
        -validity 10000 -alias smsforagents
cp keystore.properties.example keystore.properties   # fill in the passwords
```

**Build the signed release APK:**
```bash
cd android && ./gradlew assembleRelease
# -> app/build/outputs/apk/release/app-release.apk
```
(If you don't have the Gradle wrapper yet, run `gradle wrapper` once or open the
project in Android Studio.)

---

## 4. Serve the APK as a direct download

The Rails app serves whatever APK lives at `downloads/simlink.apk` — the
**Download** button (`/get`) links to `/download/simlink.apk` with the right
Android MIME type, so it installs cleanly when sideloaded.

To publish a new version:
```bash
cp android/app/build/outputs/apk/release/app-release.apk downloads/simlink.apk
git add downloads/simlink.apk && git commit -m "Publish app vX.Y.Z"
bin/kamal deploy      # the APK is baked into the image and served from the VPS
```

Users install by visiting your site and tapping **Download** — that's the only
install path. They'll be prompted to allow installing from this source the first
time.

---

## Why no app store

`SEND_SMS` / `READ_SMS` are restricted permissions. **Google Play** approval
requires being the **default SMS handler** or fitting a narrow approved
exception, plus a permissions-declaration review — a poor fit for an early
prototype. **F-Droid** rebuilds from source and signs with its own key, so its
APK can't update over a directly-downloaded one (and vice-versa) — a confusing
two-channel split. Direct sideload keeps it to **one signature, one install
path**. Validate interest this way first; if it takes off, the Play path means
rebuilding the app as a full default-SMS handler.

See **[PRIVACY.md](PRIVACY.md)** for the data/risk disclosures to show users.
