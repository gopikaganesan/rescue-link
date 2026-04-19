# RescueLink Use Cases, Process Flow, and Architecture

This document summarizes the current implementation flow for SOS activation, chat coordination, AI assistance, cancellation cleanup, and resilience behavior.

## 1) Use-Case Diagram

```mermaid
flowchart LR
  Victim((Victim User))
  VoiceAssistant((Voice Assistant / Routines))
  Widget((SOS Widget))
  Firebase[(Firebase Backend)]
  Responder((Responder))
  AI((RescueLink AI))
  Emergency[(Emergency Services)]

  Victim -->|Use widget| Widget
  Victim -->|Use voice assistant| VoiceAssistant
  Widget -->|Deep link trigger| Firebase
  VoiceAssistant -->|Deep link trigger| Firebase

  Firebase -->|Create SOS request| Victim
  Firebase -->|Notify nearby responders| Responder
  Victim -->|Send message/media| Firebase
  Responder -->|Join and chat| Firebase

  Victim -->|Ask AI in chat| AI
  AI -->|Context-aware guidance| Victim

  Victim -->|Cancel SOS / delete cancelled chat| Firebase
  Firebase -->|Cleanup linked SOS + chat artifacts| Victim

  Victim -->|Call emergency number| Emergency
```

## 2) Process Flow (End-to-End)

```mermaid
flowchart TD
  A[Voice or widget trigger received] --> B[Open app via rescue-link://sos]
  B --> C[Build emergency request payload]
  C --> D[Create or ensure chat by sosId]
  D --> E[Initialize participants: victim + AI assistant]
  E --> F[Responders discover and join]
  F --> G[Live group chat with text, media, and AI guidance]
  G --> H{AI assistance requested?}
  H -- No --> I[Continue human-assisted coordination]
  H -- Yes --> J[Create contextual AI prompt]
  J --> K[Gemini returns classification + guidance]
  K --> L[Sanitize and render response]
  L --> M[Display response cards and trusted media]
  M --> I

  I --> N{SOS cancelled?}
  N -- No --> O[Normal closure]
  N -- Yes --> P[Mark SOS as cancelled]
  P --> Q[Delete linked emergency docs and chat artifacts]
  Q --> R[Retain cancelled chat until user removes it]
```

## 3) Runtime Architecture Diagram

```mermaid
flowchart TB
  subgraph Client[Flutter Client]
    UI[Screens: Home, Victim/Responder Lists, Group Chat]
    ChatSvc[ChatService]
    AISvc[Gemini Integration]
    Media[Media Upload/Playback]
    VoiceBridge[Voice/Widget Bridge]
  end

  subgraph Firebase[Firebase]
    Auth[Firebase Auth]
    FS[(Cloud Firestore)]
    Storage[(Firebase Storage)]
    Msg[FCM / Notifications]
  end

  subgraph External[External Services]
    Gemini[Google Gemini API]
    Cloudinary[Cloudinary Optional]
    Tel[Phone Dialer / Emergency Call]
  end

  VoiceBridge --> UI
  UI --> ChatSvc
  UI --> Media
  ChatSvc --> FS
  ChatSvc --> Auth
  Media --> Storage
  Media --> Cloudinary
  ChatSvc --> AISvc
  AISvc --> Gemini
  UI --> Tel
  FS --> Msg
```

## 4) Performance and Reliability

```mermaid
flowchart TB
  A[Request received] --> B[Local validation + metadata enrichment]
  B --> C[Firestore write]
  C --> D[Realtime update to responders]
  D --> E[Chat and notification delivery]
  E --> F[AI classification request]
  F --> G[Gemini API response]
  G --> H[Client renders guidance]

  subgraph resilience[Resilience]
    H --> I[Offline simulation fallback]
    I --> D
  end
```

### Key reliability considerations
- The app uses Firestore for low-latency read/write and FCM notifications for responder alerts.
- Deep links support voice assistant and widget activation paths consistently.
- Local state is preserved during retry flows and cancellation cleanup is designed to remove orphaned SOS artifacts.

## Notes

- AI video suggestions are restricted to trusted IDs and filtered by prompt relevance.
- AI chat rendering removes raw YouTube URL lines when preview cards are shown.
- Cancelled SOS cleanup removes linked SOS records and supports cancelled chat deletion flow.
