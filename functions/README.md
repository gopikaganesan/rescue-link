# RescueLink Cloud Functions

This folder contains the server-side dispatch starter for emergency alerts.

## What it does
- Listens for new documents in `emergency_requests`
- Maps incident text to responder topics
- Sends topic-based push notifications through Firebase Cloud Messaging

## Required setup
1. Install dependencies:
   - `cd functions`
   - `npm install`
2. Deploy the function after Firebase project setup:
   - `firebase deploy --only functions`
3. Configure Firebase Admin / Cloud Functions access in your Firebase project.

## Topic strategy
- `responder_general`
- `responder_off_duty_authority`
- `responder_<normalized_skill>`
- Specialty topics such as `responder_medical_emergency`, `responder_fire_and_rescue`, `responder_women_safety`, etc.
