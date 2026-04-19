# Voice Assistant Setup Guide

Rescue Link utilizes a **Universal Deep Linking** architecture, enabling it to synchronize with nearly any voice assistant or automation tool.

## 🤖 Google Assistant (Native Integration)
The app is pre-configured to handle Google Assistant voice intents via **App Actions**.
- **Standard Trigger**: *"Hey Google, start SOS on Rescue Link"*
- **Detailed Trigger**: *"Hey Google, tell Rescue Link I'm in an emergency"*

## 🍎 Siri (Shortcuts Integration)
Rescue Link integrates with Siri Shortcuts to allow hands-free SOS activation on iOS.
- **Command**: *"Siri, start SOS on Rescue Link"*

## 🌌 Bixby (Samsung Routines)
On Samsung Galaxy devices, you can create a custom voice trigger using **Bixby Routines**:
1. Open **Modes and Routines** (formerly Bixby Routines).
2. Tap the **+** icon to create a new routine.
3. **If**: Select **Voice Command** and enter a keyword (e.g., "Emergency").
4. **Then**: Select **Go to URL** or **Open Website**.
5. **URL**: Enter `rescue-link://sos`
6. Save the routine.

## 🗣️ Alexa (Alexa for Apps)
If you use the Alexa app on your mobile device, you can configure a routine:
1. Open the Alexa app and go to **Routines**.
2. Tap **+** to create a new routine.
3. **When this happens**: Set a voice trigger (e.g., "Alexa, SOS").
4. **Add action**: Select **Custom Action**.
5. **Action**: Type *"Open rescue-link://sos"*
6. Save and test.

## 🛠️ Universal Bridge Logic
Any tool or assistant capable of triggering a URL can control Rescue Link:
- **Universal URL**: `rescue-link://sos`
- **Dynamic Parameter**: `rescue-link://sos?message=UserSpecifiedMessage`

> [!TIP]
> **Optimizing Safety**: For the fastest response, we recommend ensuring the app's location permissions are set to "Allow all the time" in your device settings. This ensures the voice trigger can fetch your coordinates even if the screen is locked.
