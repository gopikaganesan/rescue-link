import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Manages user location tracking and updates
class LocationProvider extends ChangeNotifier {
  double? _latitude;
  double? _longitude;
  bool _isLoading = false;
  String? _error;

  // Getters
  double? get latitude => _latitude;
  double? get longitude => _longitude;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasLocation => _latitude != null && _longitude != null;

  /// Request permission and get current location
  Future<bool> requestLocationPermission() async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

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

      await getCurrentLocation();
      return hasLocation;
    } catch (e) {
      _error = 'Error: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Get current location
  Future<void> getCurrentLocation() async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
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
}
