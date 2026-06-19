# Distributing SimLink

Host the server on your VPS, then build the APK and serve it as a direct
download from that server. No app store — users tap **Download** on your site and
sideload the `.apk`.

## 1. Deploy the server

You need a VPS (Docker + SSH) and a domain with an A record pointing at it.

```bash
cp .env.example .env     # set APP_HOST + the keys (comments explain each)
bin/kamal setup          # first deploy: boots app + proxy + Let's Encrypt TLS
bin/kamal deploy         # later updates
```

Everything host-specific lives in `.env` — you don't edit `config/deploy.yml`.
Back up the `simlink_storage` Docker volume; it holds the SQLite DB.

## 2. Build the app pointed at your server

One-time keystore (back it up — losing it means no more updates users can install
over the top):

```bash
cd android
keytool -genkey -v -keystore release.jks -keyalg RSA -keysize 2048 \
        -validity 10000 -alias simlink
cp keystore.properties.example keystore.properties   # fill in the passwords
```

Build, pointing the release at your domain:

```bash
SIMLINK_BASE_URL="https://$APP_HOST" ./gradlew assembleRelease
# -> app/build/outputs/apk/release/app-release.apk
```

## 3. Publish the APK

The app serves whatever sits at `downloads/simlink.apk` (the **Download** button
links to `/download/simlink.apk`). It's gitignored — the deploy image picks it up
from disk, so it's never committed:

```bash
cp android/app/build/outputs/apk/release/app-release.apk downloads/simlink.apk
bin/kamal deploy
```

## Optional: FCM push

By default the phone polls for queued work. To wake it instantly instead, set up
**one Firebase project** for both halves:

1. Add an **Android app** with package name `cz.snaz.simlink` (the `applicationId`),
   download its `google-services.json`, drop it in `android/app/` (gitignored).
2. In the same project create a **service account** key and paste the JSON into
   `.env` as `FCM_SERVICE_ACCOUNT_JSON`, then redeploy.

Both must come from the same project. If either is missing, push is skipped and
the poll still delivers (`app/services/fcm.rb` is best-effort).

## Why no app store

`SEND_SMS` / `READ_SMS` are restricted permissions: Google Play needs you to be
the default SMS handler, and F-Droid's own signing key can't update a
directly-downloaded APK. Direct sideload keeps it to one signature, one install
path. See **[PRIVACY.md](PRIVACY.md)** for the user-facing disclosures.
