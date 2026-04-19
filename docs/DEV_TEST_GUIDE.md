# Developer Testing Guide (Physical Device)

This guide explains how to test the **Universal SOS** features (Widgets and Voice Triggers) on a physical Android device in **Developer Mode**.

## Prerequisites
1.  **Developer Options Enabled**: Ensure "USB Debugging" is on.
2.  **ADB Installed**: You should be able to run `adb` commands from your computer.
3.  **Physical Device Connected**: Connected via USB or Wireless ADB.

---

## 🏗️ 1. Home Screen Widget
Testing the widget on a physical device requires manual placement.

1.  **Build & Install**: Run `flutter run` to install the app on your device.
2.  **Add Widget**:
    - Long-press on an empty area of your phone's home screen.
    - Tap **Widgets**.
    - Scroll down to find **RescueLink**.
    - Drag the **SOS** button widget onto your home screen.
3.  **Test Trigger**:
    - Tap the widget button.
    - **Expected Result**: The app should launch and immediately trigger the SOS flow (Classification -> Notification -> Confirmation).

---

## 🎙️ 2. Voice Assistant (Simulated via ADB)
Testing native voice hooks like Google Assistant can be tricky without a full release. Use ADB to simulate the Assistant sending a deep link.

### Test A: Simple SOS Trigger
Run this command while your device is connected:
```bash
adb shell am start -a android.intent.action.VIEW -d "rescue-link://sos" com.gdg.rescue_link
```
**Expected Result**: The app opens and starts a generic SOS.

### Test B: SOS with Transcribed Message
Simulate the user saying *"Tell Rescue Link I have a medical emergency"*:
```bash
adb shell am start -a android.intent.action.VIEW -d "rescue-link://sos?message=Medical%20Emergency" com.gdg.rescue_link
```
**Expected Result**: The app opens, and the "Human Report" includes the text "Medical Emergency".

---

## 🧠 3. Verifying AI Synchronization
Since "Accelerated Emergency Response" is our problem statement, we must verify the AI's speed and accuracy.

1.  **Trigger an SOS** (via Widget or ADB).
2.  **Open Firestore**: Check the `emergency_requests` collection.
3.  **Verify Fields**:
    - `category`: Should be accurately classified (e.g., "Medical", "Fire").
    - `severity`: Should be correctly weighted.
    - `requesterUserId`: Matches your authenticated ID.
4.  **Notification Check**: Verify you received a system notification titled "SOS Triggered".

---

## 🛠️ Troubleshooting
- **Deep Link Fails**: Ensure `AndroidManifest.xml` has the `<intent-filter>` for `rescue-link://sos`.
- **Widget Doesn't Appear**: Ensure the app is correctly installed and you have restarted the launcher if necessary.
- **Permission Errors**: Ensure Location and Microphone permissions are granted in App Info.

> [!TIP]
> **Production Note**: For Bixby/Alexa, the deep link behavior is the same. To test them, set up a "Bixby Routine" on your phone that opens the URL `rescue-link://sos` when you say a specific keyword.
