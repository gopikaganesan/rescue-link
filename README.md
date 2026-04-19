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
- **Gemini AI Classification**: Instant analysis of crisis type, severity, and required skills from multimodal input (voice transcripts, photos, text).
- **Synchronized Coordination**: Dynamic matching of victims to nearby verified responders based on proximity and skill set.
- **Multimodal Evidence**: SOS requests include AI-summarized transcripts, original voice clips, and photo evidence.
- **Context-Aware Assistance**: In-app AI guidance provides trusted survival videos and resources tailored to the specific crisis.
- **Role-Aware Group Chat**: Secure real-time communication between victims and responders with granular action controls.
- **Offline Mesh Resilience**: Simulated fallback for peer-to-peer communication when internet/cellular towers are failing.

## 🛠️ Tech Stack
- **Flutter**: Cross-platform mobile front-end.
- **Google Gemini**: AI classification and context-aware guidance.
- **Firebase**: Real-time Firestore database, Auth, Cloud Messaging, and Storage.
- **App Links / WidgetBridge**: Universal bridge for voice assistant and widget integration.
- **Flutter Map**: Interactive resource mapping via OpenStreetMap.

## 📱 Developer Setup
- `GEMINI_API_KEY`: Required for crisis analysis.
- `USE_CLOUD_TRANSCRIPTION`: Toggle for cloud-assisted voice processing.
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
