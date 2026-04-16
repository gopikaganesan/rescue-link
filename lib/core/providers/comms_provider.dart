import 'package:flutter/foundation.dart';

enum CommsMode {
  auto,
  internet,
  meshSimulated,
  satelliteSimulated,
}

class CommsProvider extends ChangeNotifier {
  CommsMode _mode = CommsMode.auto;
  bool _simulateTowerFailure = false;
  bool _deviceSupportsSatellite = false;

  CommsMode get mode => _mode;
  bool get simulateTowerFailure => _simulateTowerFailure;
  bool get deviceSupportsSatellite => _deviceSupportsSatellite;

  // In simulated degraded-network scenarios, force local AI fallback.
  bool get forceOfflineAi {
    return _simulateTowerFailure ||
        _deviceSupportsSatellite ||
        _mode == CommsMode.meshSimulated ||
        _mode == CommsMode.satelliteSimulated;
  }

  void setMode(CommsMode value) {
    if (_mode == value) {
      return;
    }
    _mode = value;
    notifyListeners();
  }

  void setSimulateTowerFailure(bool value) {
    if (_simulateTowerFailure == value) {
      return;
    }
    _simulateTowerFailure = value;
    notifyListeners();
  }

  void setDeviceSupportsSatellite(bool value) {
    if (_deviceSupportsSatellite == value) {
      return;
    }
    _deviceSupportsSatellite = value;
    notifyListeners();
  }

  String resolveDeliveryRoute({
    required bool cloudWriteSucceeded,
    required bool hasNearbyResponders,
  }) {
    switch (_mode) {
      case CommsMode.internet:
        return 'Internet route';
      case CommsMode.meshSimulated:
        return 'Mesh relay (simulated)';
      case CommsMode.satelliteSimulated:
        return 'Satellite uplink (simulated)';
      case CommsMode.auto:
        if (_simulateTowerFailure || !cloudWriteSucceeded) {
          if (_deviceSupportsSatellite && !hasNearbyResponders) {
            return 'Satellite uplink (simulated)';
          }
          return 'Mesh relay (simulated)';
        }
        return 'Internet route';
    }
  }

  String modeLabel(CommsMode value) {
    switch (value) {
      case CommsMode.auto:
        return 'Auto';
      case CommsMode.internet:
        return 'Internet';
      case CommsMode.meshSimulated:
        return 'Mesh (Simulated)';
      case CommsMode.satelliteSimulated:
        return 'Satellite (Simulated)';
    }
  }
}