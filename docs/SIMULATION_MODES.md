# Communication Simulation Modes

RescueLink includes simulation controls to test degraded networks without special hardware.

## Modes
- Auto: Uses internet when cloud write succeeds, otherwise simulates fallback.
- Internet: Force normal cloud route.
- Mesh (Simulated): Simulate local relay behavior.
- Satellite (Simulated): Simulate satellite path for supported-device scenarios.

## Toggles
- Simulate tower failure
- Device supports satellite (simulated)

## How It Works
- SOS is created through Firestore if network succeeds.
- If cloud write fails or tower failure is simulated, route switches to simulated mesh/satellite path.
- Route shown in SOS confirmation as `Comms Route`.

## Important
This is a software simulation for challenge demos. Real mesh/satellite requires platform and hardware-specific integration.
