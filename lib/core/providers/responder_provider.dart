import 'package:flutter/foundation.dart';
import '../models/responder_model.dart';

/// Manages nearby responders and matching logic
class ResponderProvider extends ChangeNotifier {
  List<ResponderModel> _responders = [];
  List<ResponderModel> _nearbyResponders = [];
  bool _isLoading = false;
  String? _error;

  // Getters
  List<ResponderModel> get responders => _responders;
  List<ResponderModel> get nearbyResponders => _nearbyResponders;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Fetch all responders (from Firestore in real implementation)
  Future<void> fetchResponders() async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      // TODO: Replace with actual Firestore fetch
      // For now, simulating with empty list
      _responders = [];
      _isLoading = false;
    } catch (e) {
      _error = 'Error fetching responders: ${e.toString()}';
      _isLoading = false;
    }
    notifyListeners();
  }

  /// Find nearby responders within radius (km)
  void findNearbyResponders(double userLat, double userLng, double radiusKm) {
    _nearbyResponders = _responders
        .where((responder) =>
            responder.isAvailable &&
            responder.distanceToLocation(userLat, userLng) <= radiusKm)
        .toList();

    // Sort by distance
    _nearbyResponders.sort((a, b) =>
        a.distanceToLocation(userLat, userLng)
            .compareTo(b.distanceToLocation(userLat, userLng)));

    notifyListeners();
  }

  /// Add responder (for registration)
  void addResponder(ResponderModel responder) {
    _responders.add(responder);
    notifyListeners();
  }

  /// Simulate adding responders for testing
  void addMockResponders(List<ResponderModel> mockResponders) {
    _responders = mockResponders;
    notifyListeners();
  }

  /// Clear responders
  void clearResponders() {
    _responders = [];
    _nearbyResponders = [];
    notifyListeners();
  }
}
