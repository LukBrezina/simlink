# Distributing SMS for Agents (prototype)

The plan: **host the server on your VPS with Kamal**, then ship the app via
**GitHub Releases + Obtainium** and **F-Droid**. No Google Play (its SMS
permission policy makes that a separate, larger effort — see the end).

```
 your VPS (Kamal) ── https://sms.example.com ──┐
                                               │  signed APK
 GitHub Releases ──▶ Obtainium (auto-update) ──┤──▶ users install
 F-Droid ──────────▶ F-Droid client ───────────┘
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
means you can never update the GitHub/Obtainium build):
```bash
cd android
keytool -genkey -v -keystore release.jks -keyalg RSA -keysize 2048 \
        -validity 10000 -alias smsforagents
cp keystore.properties.example keystore.properties   # fill in the passwords
```

**Commit the Gradle wrapper** (required by CI *and* F-Droid):
```bash
cd android && gradle wrapper        # or open once in Android Studio
git add android/gradlew android/gradlew.bat android/gradle/wrapper/gradle-wrapper.jar
```

**Build locally:**
```bash
cd android && ./gradlew assembleRelease
# -> app/build/outputs/apk/release/app-release.apk
```

---

## 4. Publish via GitHub Releases + Obtainium

CI (`.github/workflows/android-release.yml`) builds + signs + publishes on a tag.

1. Add repo secrets (Settings → Secrets → Actions):
   `KEYSTORE_BASE64` (`base64 -i android/release.jks`), `KEYSTORE_PASSWORD`,
   `KEY_ALIAS`, `KEY_PASSWORD`.
2. Release:
   ```bash
   git tag v0.1.0 && git push origin v0.1.0
   ```
   The APK appears on the GitHub Releases page.
3. **Users install** by adding your GitHub repo URL in
   [Obtainium](https://github.com/ImranR98/Obtainium) — it tracks releases and
   auto-updates. (Or they download the APK directly.)

---

## 5. Publish via F-Droid

The app is fully FOSS (no Google services), so it qualifies.

1. Make the repo public and MIT-licensed (already set: `LICENSE`).
2. Ensure the Gradle wrapper is committed (step 3) and a `v*` tag exists.
3. Submit `fdroid/com.smsforagents.app.yml` (edit `YOUR_GH_USER`) as a
   **Request For Packaging** merge request to
   [fdroiddata](https://gitlab.com/fdroid/fdroiddata). Listing text/screenshots
   come from `android/fastlane/metadata/`.

**Caveat:** F-Droid rebuilds from source and signs with **its own key**. So the
F-Droid APK and your GitHub/Obtainium APK have **different signatures** — a user
must pick one channel and can't cross-update between them. Pick one as the
"official" install path in your README to avoid confusion.

---

## Why not Google Play (yet)

`SEND_SMS` / `READ_SMS` are restricted permissions. Play approval requires
being the **default SMS handler** or fitting a narrow approved exception, plus a
permissions-declaration review — a poor fit for an early prototype. Validate
interest via sideload/F-Droid first. If it takes off, the Play path means
rebuilding the app as a full default-SMS handler.

See **[PRIVACY.md](PRIVACY.md)** for the data/risk disclosures to show users.
