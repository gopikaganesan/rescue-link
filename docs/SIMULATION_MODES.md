# Communication Simulation Modes

RescueLink includes simulation controls to test degraded networks without special hardware.

## Modes

- **Auto**: Uses internet when cloud write succeeds, otherwise simulates fallback.
- **Internet**: Force normal cloud route.
- **Mesh (Simulated)**: Simulate local relay behavior.
- **Satellite (Simulated)**: Simulate satellite path for supported-device scenarios.

## Toggles

- **Simulate tower failure**: Triggers fallback to simulated mesh/satellite, disables Gemini API calls.
- **Device supports satellite (simulated)**: Enables satellite uplink simulation, disables Gemini API calls.

## How It Works

- SOS is created through Firestore if network succeeds.
- If cloud write fails or tower failure is simulated, route switches to simulated mesh/satellite path.
- Route shown in SOS confirmation as `Comms Route`.

## Crisis AI Behavior in Simulation

**Important**: When any of the following are active, emergency classification uses **offline heuristic only** and does **not** call Gemini API:

- Simulate tower failure is enabled
- Device supports satellite (simulated) is enabled
- Delivery mode is set to "Mesh (Simulated)" or "Satellite (Simulated)"

This ensures testing of degraded-network scenarios doesn't depend on internet connectivity or consume API quota.

If no Gemini API key is provided, classification always uses offline heuristic regardless of simulation mode.

## Important

This is a software simulation for challenge demos. Real mesh/satellite requires platform and hardware-specific integration.
