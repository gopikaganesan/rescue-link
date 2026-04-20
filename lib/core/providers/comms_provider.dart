import 'package:flutter/foundation.dart';

import 'package:rescue_link/core/providers/app_settings_provider.dart';

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
    required AppSettingsProvider settings,
    required bool cloudWriteSucceeded,
    required bool hasNearbyResponders,
  }) {
    switch (_mode) {
      case CommsMode.internet:
        return settings.t('comms_route_internet');
      case CommsMode.meshSimulated:
        return settings.t('comms_route_mesh_simulated');
      case CommsMode.satelliteSimulated:
        return settings.t('comms_route_satellite_simulated');
      case CommsMode.auto:
        if (_simulateTowerFailure || !cloudWriteSucceeded) {
          if (_deviceSupportsSatellite && !hasNearbyResponders) {
            return settings.t('comms_route_satellite_simulated');
          }
          return settings.t('comms_route_mesh_simulated');
        }
        return settings.t('comms_route_internet');
    }
  }

  String modeLabel(CommsMode value, AppSettingsProvider settings) {
    switch (value) {
      case CommsMode.auto:
        return settings.t('comms_mode_auto');
      case CommsMode.internet:
        return settings.t('comms_mode_internet');
      case CommsMode.meshSimulated:
        return settings.t('comms_mode_mesh_simulated');
      case CommsMode.satelliteSimulated:
        return settings.t('comms_mode_satellite_simulated');
    }
  }
}