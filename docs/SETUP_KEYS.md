# Setup and API Keys

## 1) Firebase Setup

1. Create a Firebase project.
2. Add Android and iOS apps with the exact package IDs used in this project.
3. Download config files:
    - Android: `android/app/google-services.json`
    - iOS: `ios/Runner/GoogleService-Info.plist`
4. Enable Authentication providers you need (Email/Password, Anonymous, Phone if required).
5. Enable Firestore and deploy security rules and indexes.

## 2) Gemini API Key

Gemini is implemented in the app via `lib/core/services/gemini_service.dart`.

To provide the key at runtime for Flutter (quick method):

- `flutter run --dart-define=GEMINI_API_KEY=YOUR_KEY`

Preferred local dev method (env file):

1. Copy `env/dev.json.example` to `env/dev.json`
2. Put your real key in `env/dev.json`
3. Run with:

- `flutter run -d chrome --dart-define-from-file=env/dev.json`

VS Code launch configs are included in `.vscode/launch.json`:

- `RescueLink (Chrome + Env)`
- `RescueLink (Windows + Env)`
- `RescueLink (Android + Env)`
- `RescueLink (iOS + Env)`

For release builds:

- Android/iOS CI or local release command should include the same `--dart-define`.

Optional model override (for trying alternative available Gemini models):

- `GEMINI_MODEL_CANDIDATES`: comma-separated model names in priority order.
- Alias also supported: `GEMINI_MODELS`.

Example:

- `GEMINI_MODEL_CANDIDATES=gemini-2.5-flash,gemini-2.5-flash-lite,gemini-2.0-flash,gemini-1.5-flash-latest`

If no key is provided, the app uses offline heuristic classification.

**Voice/audio note**: The current SOS flow supports on-device speech-to-text for typed context entry and uploads recorded voice clips as audio attachments, but it does not yet automatically transcribe uploaded voice clips with cloud speech recognition.

**Simulation Note**: When testing with simulation modes enabled (tower failure, satellite device, or mesh/satellite delivery modes), emergency classification automatically uses offline heuristic only, regardless of Gemini key availability. See [docs/SIMULATION_MODES.md](SIMULATION_MODES.md) for details.

## 3) Notifications

Current implementation uses local notifications for responder dispatch while app is active.

Chat message notifications are currently implemented in open-app mode:

- Human (non-AI) chat messages can trigger local notifications while the app is running.
- Tapping chat notifications navigates directly to the related group chat screen.
- Per-chat notifications are enabled by default and can be disabled from the group chat 3-dot menu.

SOS responder notifications support quick actions (where supported):

- Accept: accepts the request and opens the responder group chat.
- Navigate: opens map navigation for the SOS location when available.
- Fallback: opens the responder requests screen if location/action context is incomplete.

FCM client setup is now included in app code (token sync + topic subscription + foreground/background handler).

Android:

- Ensure notification permission is granted on Android 13+.

iOS:

- Ensure notification permission is granted in system settings.
- Configure APNs auth key/certificate in Firebase for iOS push delivery.

## 4) Media Upload Provider (Pluggable)

Emergency photo/audio uploads now use a provider abstraction in:

- `lib/core/services/media_upload_service.dart`

Runtime config via `--dart-define` (or `env/dev.json`):

- `MEDIA_UPLOAD_PROVIDER`: `firebase` (default) or `cloudinary`
- `CLOUDINARY_CLOUD_NAME` (required when provider is `cloudinary`)
- `CLOUDINARY_UPLOAD_PRESET` (required when provider is `cloudinary`)
- `USE_CLOUD_TRANSCRIPTION` (`false` by default for free mode; currently a future-mode flag while on-device speech-to-text handles voice entry)
- `MEDIA_IMAGE_MAX_DIMENSION` (`1280` by default)
- `MEDIA_IMAGE_JPEG_QUALITY` (`82` by default)

Recommended architecture for this app:

- Keep Firebase Auth + Firestore as your source of truth.
- Use Cloudinary only for file hosting/CDN (image/audio URLs).
- Store returned Cloudinary `secure_url` inside Firestore message docs.

Why this is better than MongoDB for your current app:

- Your app already depends on Firestore data models and rules.
- Migrating chat + presence + auth-linked access checks to MongoDB adds major backend work.
- Cloudinary solves only the media-hosting piece quickly, without replacing your current database.

### Cloudinary Free Setup (from your side)

1. Create account and product environment:
   - Open Cloudinary Console and create a free account.
   - Use the default product environment or create one dedicated for this app.

1. Create unsigned upload preset (required for direct client upload):
   - Go to Settings -> Upload.
   - Scroll to Upload presets -> Add upload preset.
   - Set Signing Mode to Unsigned.
   - Suggested restrictions:
      - Folder: `rescue_link`
      - Allowed formats: `jpg,jpeg,png,webp,wav,m4a,mp3`
      - Max file size: set a strict value that fits your use-case
      - Resource type: Auto
   - Save and copy the preset name.

1. Collect values you need in Flutter:
   - `cloud_name` from your Cloudinary dashboard.
   - `upload_preset` from step 2.

1. Add values to `env/dev.json`:

```json
{
   "GEMINI_API_KEY": "YOUR_KEY",
   "USE_CLOUD_TRANSCRIPTION": "false",
   "MEDIA_UPLOAD_PROVIDER": "cloudinary",
   "CLOUDINARY_CLOUD_NAME": "your-cloud-name",
   "CLOUDINARY_UPLOAD_PRESET": "your-unsigned-preset",
   "MEDIA_IMAGE_MAX_DIMENSION": "1280",
   "MEDIA_IMAGE_JPEG_QUALITY": "82"
}
```

1. Run app with env file:

- `flutter run -d chrome --dart-define-from-file=env/dev.json`

Security note:

- Do not put `api_secret` in Flutter app code.
- Unsigned presets must stay restricted (format/size/folder) because they can be abused if too open.
- If you later need stronger control, move uploads behind a signed backend endpoint.

Recommended local dev setup in `env/dev.json`:

```json
{
   "GEMINI_API_KEY": "YOUR_KEY",
   "USE_CLOUD_TRANSCRIPTION": "false",
   "MEDIA_UPLOAD_PROVIDER": "cloudinary",
   "CLOUDINARY_CLOUD_NAME": "your-cloud",
   "CLOUDINARY_UPLOAD_PRESET": "your_unsigned_preset",
   "MEDIA_IMAGE_MAX_DIMENSION": "1280",
   "MEDIA_IMAGE_JPEG_QUALITY": "82"
}
```

Notes:

- This keeps Firebase Auth/Firestore unchanged while allowing media uploads to use a free-tier provider.
- If `cloudinary` is selected but required values are missing, app now safely falls back to Firebase Storage upload.
- In-app SOS composer shows attachment-style media cards with preview/play/remove actions before send.
- Image uploads are automatically resized on-device before upload to keep media smaller and faster to deliver.
- Current optimization target: max 1280px on the longest edge, encoded as JPEG quality 82.

## 5) Optional Next Step for Background/Realtime Push

For true background immediate alerts, add Firebase Cloud Messaging server-side dispatch:

- Store responder FCM tokens
- Trigger topic or targeted push by category and geo filter
- Keep local fallback notifications for foreground mode

Note for this repository state:

- Cloud Function-based chat message push dispatch is prepared in `functions/index.js` but deployment is deferred.
- Reason: Firebase project plan/API prerequisites must be upgraded/configured before function deploy.
- Until deployment is completed, foreground/open-app local notifications are the active notification path.

Recommended topic strategy used by app:

- `responder_general`
- `responder_<normalized_skill>`
- `responder_<normalized_responder_type>`
