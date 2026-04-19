# RescueLink Use Cases, Process Flow, and Architecture

This document summarizes the current implementation flow for SOS, chat, AI assist, and cancellation cleanup.

## 1) Use-Case Diagram

```mermaid
flowchart LR
  Victim((Victim User))
  Responder((Responder))
  AI((RescueLink AI))
  Firebase[(Firebase Backend)]
  Emergency[(Emergency Services)]

  Victim -->|Create SOS| Firebase
  Firebase -->|Create chat room| Victim
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
  A[Victim triggers SOS] --> B[Write emergency request]
  B --> C[Create or ensure chat by sosId]
  C --> D[Participants initialized victim + AI]
  D --> E[Responders discover and join]
  E --> F[Live group chat with text + media]
  F --> G{Ask AI triggered?}
  G -- No --> H[Continue human-assisted chat]
  G -- Yes --> I[Build AI prompt from SOS + recent context]
  I --> J[Gemini response]
  J --> K[Sanitize links to trusted, context-relevant videos]
  K --> L[Render formatted AI message]
  L --> M[Show video preview cards]
  M --> N[Hide duplicate raw YouTube links in text]
  N --> H

  H --> O{SOS cancelled?}
  O -- No --> P[Normal closure]
  O -- Yes --> Q[Mark chat cancelled]
  Q --> R[Delete linked sos docs: emergency_requests + sos_events]
  R --> S[Victim can delete cancelled chat]
  S --> T[Delete chat messages + chat doc]
```

## 3) Runtime Architecture Diagram

```mermaid
flowchart TB
  subgraph Client[Flutter Client]
    UI[Screens: Home, Victim/Responder Lists, Group Chat]
    ChatSvc[ChatService]
    AISvc[Gemini Integration]
    Media[Media Upload/Playback]
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

## Notes

- AI video suggestions are restricted to trusted IDs and filtered by prompt relevance.
- AI chat rendering removes raw YouTube URL lines when preview cards are shown.
- Cancelled SOS cleanup removes linked SOS records and supports cancelled chat deletion flow.
