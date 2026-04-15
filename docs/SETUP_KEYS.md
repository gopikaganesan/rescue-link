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

If no key is provided, the app uses offline heuristic classification.

**Simulation Note**: When testing with simulation modes enabled (tower failure, satellite device, or mesh/satellite delivery modes), emergency classification automatically uses offline heuristic only, regardless of Gemini key availability. See [docs/SIMULATION_MODES.md](SIMULATION_MODES.md) for details.

## 3) Notifications

Current implementation uses local notifications for responder dispatch while app is active.

FCM client setup is now included in app code (token sync + topic subscription + foreground/background handler).

Android:

- Ensure notification permission is granted on Android 13+.

iOS:

- Ensure notification permission is granted in system settings.
- Configure APNs auth key/certificate in Firebase for iOS push delivery.

## 4) Optional Next Step for Background/Realtime Push

For true background immediate alerts, add Firebase Cloud Messaging server-side dispatch:

- Store responder FCM tokens
- Trigger topic or targeted push by category and geo filter
- Keep local fallback notifications for foreground mode

Recommended topic strategy used by app:

- `responder_general`
- `responder_<normalized_skill>`
- `responder_<normalized_responder_type>`
