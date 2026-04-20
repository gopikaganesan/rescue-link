# RescueLink 🛟

**Connecting help when it matters most**  
*AI-powered emergency synchronization for Rapid Crisis Response.*

Built for the **GDG Solution Challenge 2026**.

## 🚀 Mission
RescueLink instantly connects people in crisis to nearby responders and resources, even when traditional networks are compromised. By utilizing a "Universal SOS Bridge" and Gemini AI, we solve the fragmentation of communication between distressed individuals and emergency services.

## 🏆 GDG Solution Challenge 2026
- **Category**: Open Innovation
- **Problem Statement**: Accelerated Emergency Response and Crisis Coordination.
- **SDG Alignment**: 
    - **Goal 11**: Sustainable Cities and Communities (Target 11.5 - Disaster Resilience)
    - **Goal 3**: Good Health and Well-being (Target 3.d - Early Warning and Risk Management)

## ✨ Key Features
- **Universal SOS Access**: Trigger emergencies via high-visibility **Home Widgets**, **Native Voice Commands** (Google Assistant/Siri), or physical shake/tap.
- **Gemini AI Classification with Local Fallback**: Crisis category, severity, recommended skill, and suggested actions are derived from typed text and optional image evidence. If Gemini is unavailable, RescueLink falls back to a local emergency heuristic and still preserves a usable rescue workflow.
- **Synchronized Coordination**: Dynamic matching of victims to nearby verified responders based on proximity and required responder skill set.
- **Voice & Accessibility-First Interaction**: SOS creation supports on-device speech-to-text, voice clip attachment, TTS, screen-reader announcements, and multi-language translation in chat.
- **Context-Aware Assistance**: In-app AI guidance provides trusted survival videos, resource recommendations, and emergency suggestions tailored to the specific crisis.
- **Role-Aware Group Chat**: Secure real-time communication between victims and responders with granular action controls and accessible message presentation.
- **Simulated Resilience for Future Mesh**: The app includes degraded-network simulation modes for mesh/satellite fallback, with a design path to full hardware-based resilience later.

## ✅ GDG Challenge Readiness
- Designed for rapid response use cases and clear demonstration readiness.
- Supports one-tap emergency activation through **home widgets**, **native voice assistants**, and **deep links**.
- Built for operational resilience with **AI-assisted classification**, **real-time responder matching**, and **clean SOS lifecycle management**.
- Includes accessibility-first interaction patterns such as **high contrast**, **text scaling**, **voice transcription**, **screen-reader announcements**, and **language-aware chat translation**.
- Realistic resilience is demonstrated through **offline simulation**, while the architecture remains ready for future physical mesh hardware integration.

## 🛠️ Tech Stack
- **Flutter**: Cross-platform mobile front-end.
- **Google Gemini**: AI classification and context-aware guidance.
- **Firebase**: Real-time Firestore database, Auth, Cloud Messaging, and Storage.
- **App Links / WidgetBridge**: Universal bridge for voice assistant and widget integration.
- **Flutter Map**: Interactive resource mapping via OpenStreetMap.

## 📱 Developer Setup
- `GEMINI_API_KEY`: Required for Gemini crisis classification.
- `USE_CLOUD_TRANSCRIPTION`: Optional flag for future cloud transcription support; current runtime uses on-device speech-to-text for voice entry.
- `MEDIA_UPLOAD_PROVIDER`: Scalable storage for SOS evidence.

See [docs/SETUP_KEYS.md](docs/SETUP_KEYS.md) for full configuration details.

## 📚 Documentation
- [**Development Testing Guide**](docs/DEV_TEST_GUIDE.md): How to test Widgets and Voice SOS on a physical device.
- [**Voice Assistant Setup**](docs/voice_assistant_setup.md): Configuration for Alexa, Bixby, and more.
- [**GDG Alignment Detail**](docs/GDG_INDIA_2026_ALIGNMENT.md): Technical mapping to challenge requirements.
- [**Architecture & Process**](docs/PROCESS_FLOW_ARCHITECTURE.md): End-to-end system sequence diagrams.

## 📽️ Submission
- **Demo Video**: [Link coming soon]
- **Project Deck**: [Link coming soon]
- **APK Download**: [Link coming soon]
