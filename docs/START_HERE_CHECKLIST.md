# Start Here Checklist

## Recent Improvements (Latest Build)

✅ **SOS Cancel Feature**: Users can now accidentally trigger SOS and cancel it with a prominent "Cancel SOS" button in the confirmation dialog.

✅ **Improved SOS Button Design**: 
- Enhanced red gradient button with animated pulsing rings
- Clear "SOS TAP" labeling for better UX
- Smooth animations and haptic feedback built-in

✅ **Psychologically Safe UI Colors**:
- SOS confirmation dialog now uses green background (safe color) instead of red
- "✓ SOS Received" confirmation with green checkmark icon
- Color-coded action buttons (Cancel SOS: red, Map: blue, Emergency: orange)
- Safer visual feedback to reduce anxiety after SOS is triggered

✅ **Responder Profile Experience**:
- Added responder profile details for SOS flow: responder type, availability, verification status, rescue count, ratings, and review count
- Added profile entry points from nearby responder cards on map (`View profile`) and responder account sheet (`View my profile`)
- Added quick contact actions (call and temporary message fallback) from responder profile screen
- Added future-ready model fields for verification and ratings (`verifiedResponder`, `rescueCount`, `averageRating`, `ratingCount`)

✅ **Multimodal SOS Attachments**:
- SOS composer supports voice-to-text, recorded voice clips, and camera photos
- Media appears as compact attachment cards with quick actions
- Photo preview and voice clip playback are available before sending SOS

✅ **Pluggable Media Upload Setup**:
- Media upload provider abstraction added (`firebase` or `cloudinary`)
- Runtime flags support free-tier friendly Cloudinary integration without changing app flow

✅ **Cloud Transcription Toggle (Optional)**:
- Cloud assist transcription can be enabled/disabled with env flag
- On-device transcription remains default free mode

## Still To Do
1. Firebase Console
- Confirm Android and iOS app registrations
- Download the latest `google-services.json` and `GoogleService-Info.plist`
- Enable the Auth providers you want to demo

2. Firestore Deployment
- Deploy `firestore.rules`
- Deploy `firestore.indexes.json`

3. Gemini Key
- Create an API key in Google AI Studio
- Run the app with `--dart-define=GEMINI_API_KEY=YOUR_KEY`

4. Runtime Env Flags
- Copy `env/dev.json.example` to `env/dev.json`
- Configure:
	- `USE_CLOUD_TRANSCRIPTION`
	- `MEDIA_UPLOAD_PROVIDER`
	- Cloudinary keys if provider is `cloudinary`

5. Push Notifications
- Enable Firebase Cloud Messaging in the Firebase project
- Configure APNs key/certificate in Firebase for iOS
- Deploy the Cloud Functions starter in `functions/`

6. Test Plan
- Verify SOS creation from a low-connectivity device
- Verify responder topic notifications on Android first
- Verify responder registration and availability toggle
- Verify attachment flow:
	- capture photo -> preview -> send
	- record voice clip -> playback -> send
	- responder side media visibility and playback

## Suggested Start Order
1. Firebase project + config files
2. Firestore rules and indexes
3. Gemini key
4. Runtime env flags
5. Cloud Functions deploy
6. End-to-end notification + attachment flow test

## Submission Use
Use this doc in your submission pack as the implementation checklist for judges or teammates.