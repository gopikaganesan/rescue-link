# RescueLink

**Connecting help when it matters most**  
AI-powered emergency mesh network for Rapid Crisis Response.

## About
RescueLink connects people in crisis to nearby responders and resources — even when mobile towers or internet are down.  
Uses Bluetooth/WiFi-Direct mesh (simulated in prototype) + Gemini AI for crisis classification and smart matching.

Built with **Flutter + Firebase + Gemini** for GDG on Campus CIT Solution Challenge 2026 (Emergency Crisis track).

## Key Features (MVP)
- Universal accessible SOS (tap, shake, voice, icons)
- Gemini AI emergency classification & resource allocation
- Multimodal SOS evidence (typed context + voice transcript + voice clip + camera photo)
- Attachment-style SOS composer with in-app photo preview and voice clip playback
- Helper/Responder registration (anyone can register skills/capacity)
- Offline Mesh + Satellite Mode (simulated fallback)
- Nearby map of resources
- Role-aware responder notifications (skill + responder type + distance)
- Emergency fallback actions (call/SMS 112) when no nearby responders

## Runtime Config Highlights
- `GEMINI_API_KEY`: Gemini classification key
- `USE_CLOUD_TRANSCRIPTION`: Optional cloud assist for short/unclear voice clips (`false` by default)
- `MEDIA_UPLOAD_PROVIDER`: `firebase` (default) or `cloudinary`
- `CLOUDINARY_CLOUD_NAME` / `CLOUDINARY_UPLOAD_PRESET`: required only when using Cloudinary

See [docs/SETUP_KEYS.md](docs/SETUP_KEYS.md) for full setup details.

## Tech Stack
- Flutter
- Firebase (Auth, Firestore, Cloud Messaging)
- Gemini API
- Flutter Map (OpenStreetMap tiles)

## Docs
- [docs/START_HERE_CHECKLIST.md](docs/START_HERE_CHECKLIST.md)
- [docs/GDG_INDIA_2026_ALIGNMENT.md](docs/GDG_INDIA_2026_ALIGNMENT.md)
- [docs/SETUP_KEYS.md](docs/SETUP_KEYS.md)
- [docs/SIMULATION_MODES.md](docs/SIMULATION_MODES.md)
- [functions/README.md](functions/README.md)

## Submission
- Demo Video: [Paste link here]
- APK / Web demo: [Add here]
