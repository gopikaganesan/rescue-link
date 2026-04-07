import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Manages user location tracking and updates
class LocationProvider extends ChangeNotifier {
  double? _latitude;
  double? _longitude;
  bool _isLoading = false;
  String? _error;
  ServiceStatus? _serviceStatus;
  StreamSubscription<ServiceStatus>? _serviceStatusSubscription;

  // Getters
  double? get latitude => _latitude;
  double? get longitude => _longitude;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasLocation => _latitude != null && _longitude != null;
  bool get isServiceEnabled => _serviceStatus == ServiceStatus.enabled;

  Future<void> init() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    _serviceStatus =
      serviceEnabled ? ServiceStatus.enabled : ServiceStatus.disabled;
    _serviceStatusSubscription ??=
        Geolocator.getServiceStatusStream().listen((status) async {
      _serviceStatus = status;
      if (status == ServiceStatus.enabled) {
        await refreshLocationStatus(fetchLocation: true);
      } else {
        _error = 'Location services are disabled. Please turn on GPS.';
      }
      notifyListeners();
    });
    notifyListeners();
  }

  /// Request permission and get current location
  Future<bool> requestLocationPermission() async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      await init();

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      _serviceStatus =
          serviceEnabled ? ServiceStatus.enabled : ServiceStatus.disabled;
      if (!serviceEnabled) {
        _error = 'Location services are disabled. Please turn on GPS.';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      final permission = await Geolocator.checkPermission();
      LocationPermission finalPermission = permission;

      if (permission == LocationPermission.denied) {
        finalPermission = await Geolocator.requestPermission();
      }

      if (finalPermission == LocationPermission.deniedForever) {
        _error = 'Location permissions are permanently denied';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      if (finalPermission == LocationPermission.denied) {
        _error = 'Location permission denied. Please allow location access.';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      await getCurrentLocation();
      return hasLocation;
    } catch (e) {
      _error = 'Error: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> refreshLocationStatus({bool fetchLocation = false}) async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    _serviceStatus =
        serviceEnabled ? ServiceStatus.enabled : ServiceStatus.disabled;
    if (!serviceEnabled) {
      _error = 'Location services are disabled. Please turn on GPS.';
      notifyListeners();
      return false;
    }

    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      _error = 'Location permission denied. Please allow location access.';
      notifyListeners();
      return false;
    }
    if (permission == LocationPermission.deniedForever) {
      _error = 'Location permissions are permanently denied';
      notifyListeners();
      return false;
    }

    _error = null;
    notifyListeners();

    if (fetchLocation) {
      await getCurrentLocation();
    }
    return true;
  }

  Future<bool> openLocationSettings() async {
    final opened = await Geolocator.openLocationSettings();
    await refreshLocationStatus(fetchLocation: true);
    return opened;
  }

  Future<bool> openPermissionSettings() async {
    final opened = await Geolocator.openAppSettings();
    await refreshLocationStatus(fetchLocation: true);
    return opened;
  }

  /// Get current location
  Future<void> getCurrentLocation() async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        _latitude = lastKnown.latitude;
        _longitude = lastKnown.longitude;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 5),
        ),
      );

      _latitude = position.latitude;
      _longitude = position.longitude;
      _isLoading = false;
      _error = null;
    } catch (e) {
      _error = 'Could not get location: ${e.toString()}';
      _isLoading = false;
    }
    notifyListeners();
  }

  /// Simulate offline location (for testing)
  void setOfflineLocation(double lat, double lng) {
    _latitude = lat;
    _longitude = lng;
    _error = null;
    notifyListeners();
  }

  /// Clear location
  void clearLocation() {
    _latitude = null;
    _longitude = null;
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _serviceStatusSubscription?.cancel();
    super.dispose();
  }
}
