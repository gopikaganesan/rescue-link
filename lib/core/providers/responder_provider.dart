import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/responder_model.dart';

/// Manages nearby responders and matching logic
class ResponderProvider extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

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

      final snapshot = await _firestore.collection('responders').get();
      _responders = snapshot.docs
          .map((doc) => ResponderModel.fromMap(<String, dynamic>{
                ...doc.data(),
                'id': doc.id,
              }))
          .toList();
      _isLoading = false;
    } catch (e) {
      _error = 'Error fetching responders: ${e.toString()}';
      _isLoading = false;
    }
    notifyListeners();
  }

  /// Find nearby responders within radius (km)
  void findNearbyResponders(
    double userLat,
    double userLng,
    double radiusKm, {
    String? requiredSkill,
  }) {
    final skillQuery = requiredSkill?.trim().toLowerCase();

    _nearbyResponders = _responders
        .where((responder) =>
            responder.isAvailable &&
            (skillQuery == null ||
                skillQuery.isEmpty ||
                responder.skillsArea.toLowerCase().contains(skillQuery)) &&
            responder.distanceToLocation(userLat, userLng) <= radiusKm)
        .toList();

    // Sort by distance
    _nearbyResponders.sort((a, b) =>
        a.distanceToLocation(userLat, userLng)
            .compareTo(b.distanceToLocation(userLat, userLng)));

    notifyListeners();
  }

  /// Add responder (for registration)
  Future<bool> addResponder(ResponderModel responder) async {
    try {
      await _firestore.collection('responders').doc(responder.id).set(responder.toMap());
    } catch (e) {
      _error = 'Firestore unavailable, saved locally: ${e.toString()}';
    }

    _responders.add(responder);
    notifyListeners();
    return true;
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
