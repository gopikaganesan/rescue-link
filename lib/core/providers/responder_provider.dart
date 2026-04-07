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

      final snapshot = await _firestore
          .collection('responders')
          .get()
          .timeout(const Duration(seconds: 5));
      final fetched = snapshot.docs
          .map((doc) => ResponderModel.fromMap(<String, dynamic>{
                ...doc.data(),
                'id': doc.id,
              }))
          .toList();

      // Keep only one responder per user (latest registration wins).
      final Map<String, ResponderModel> byUserId = <String, ResponderModel>{};
      for (final responder in fetched) {
        final existing = byUserId[responder.userId];
        if (existing == null ||
            responder.registeredAt.isAfter(existing.registeredAt)) {
          byUserId[responder.userId] = responder;
        }
      }

      _responders = byUserId.values.toList();
    } catch (e) {
      _error =
          'Could not refresh responders from cloud. Using local data if available.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
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
    final normalized = responder.copyWith(id: responder.userId);

    _responders = _responders
        .where((existing) => existing.userId != normalized.userId)
        .toList()
      ..add(normalized);
    notifyListeners();

    try {
      await _firestore
          .collection('responders')
          .doc(normalized.userId)
          .set(normalized.toMap())
          .timeout(const Duration(seconds: 4));

      if (normalized.verificationLevel.toLowerCase() != 'self-declared') {
        await _firestore
            .collection('responder_verification_requests')
            .doc(normalized.userId)
            .set(<String, dynamic>{
          'userId': normalized.userId,
          'name': normalized.name,
          'responderType': normalized.responderType,
          'verificationLevel': normalized.verificationLevel,
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true)).timeout(const Duration(seconds: 4));
      }
    } catch (e) {
      _error = 'Saved locally. Cloud sync pending: ${e.toString()}';
    }

    return true;
  }

  Future<void> removeResponderByUserId(String userId) async {
    _responders = _responders.where((responder) => responder.userId != userId).toList();
    _nearbyResponders =
        _nearbyResponders.where((responder) => responder.userId != userId).toList();
    notifyListeners();

    try {
      await _firestore
          .collection('responders')
          .doc(userId)
          .delete()
          .timeout(const Duration(seconds: 4));
    } catch (e) {
      _error = 'Removed locally. Cloud delete pending: ${e.toString()}';
      notifyListeners();
    }
  }

  Future<void> setResponderAvailability({
    required String userId,
    required bool isAvailable,
  }) async {
    _responders = _responders
        .map((responder) => responder.userId == userId
            ? responder.copyWith(isAvailable: isAvailable)
            : responder)
        .toList();
    notifyListeners();

    try {
      await _firestore
          .collection('responders')
          .doc(userId)
          .set(<String, dynamic>{'isAvailable': isAvailable}, SetOptions(merge: true))
          .timeout(const Duration(seconds: 4));
    } catch (e) {
      _error = 'Availability changed locally. Cloud sync pending: ${e.toString()}';
      notifyListeners();
    }
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
