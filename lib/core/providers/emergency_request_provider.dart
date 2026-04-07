import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/emergency_request_model.dart';

class EmergencyRequestProvider extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  List<EmergencyRequestModel> _openRequests = <EmergencyRequestModel>[];
  final List<EmergencyRequestModel> _pendingSyncRequests =
      <EmergencyRequestModel>[];
  bool _isLoading = false;
  String? _error;

  List<EmergencyRequestModel> get openRequests => _openRequests;
  List<EmergencyRequestModel> get pendingSyncRequests =>
      List<EmergencyRequestModel>.unmodifiable(_pendingSyncRequests);
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> fetchOpenRequests({String? skillFilter}) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final snapshot = await _firestore
          .collection('emergency_requests')
          .where('status', isEqualTo: 'open')
          .orderBy('createdAt', descending: true)
          .get()
          .timeout(const Duration(seconds: 5));

      final all = snapshot.docs
          .map((doc) => EmergencyRequestModel.fromMap(<String, dynamic>{
                ...doc.data(),
                'id': doc.id,
              }))
          .toList();

      final normalizedSkill = skillFilter?.trim().toLowerCase();
      if (normalizedSkill == null || normalizedSkill.isEmpty) {
        _openRequests = all;
      } else {
        _openRequests = all
            .where((item) => item.recommendedSkill.toLowerCase().contains(normalizedSkill))
            .toList();
      }
    } catch (e) {
      _error = 'Failed to load help requests: ${e.toString()}';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<String?> createRequest({
    required String requesterUserId,
    required String requesterName,
    required double latitude,
    required double longitude,
    required String category,
    required String severity,
    required String summary,
    required String recommendedSkill,
  }) async {
    final doc = _firestore.collection('emergency_requests').doc();
    final payload = EmergencyRequestModel(
      id: doc.id,
      requesterUserId: requesterUserId,
      requesterName: requesterName,
      latitude: latitude,
      longitude: longitude,
      category: category,
      severity: severity,
      summary: summary,
      recommendedSkill: recommendedSkill,
      status: 'open',
      createdAt: DateTime.now(),
    );

    try {
      await doc.set(payload.toMap()).timeout(const Duration(seconds: 5));
      return doc.id; // Return the request ID
    } catch (e) {
      _error = 'SOS saved locally. Cloud sync pending.';
      _pendingSyncRequests.add(payload);
      notifyListeners();
      return payload.id; // Still need to track it even if offline
    }
  }

  Future<bool> cancelRequest(String requestId) async {
    try {
      await _firestore
          .collection('emergency_requests')
          .doc(requestId)
          .update(<String, dynamic>{
        'status': 'cancelled',
        'cancelledAt': FieldValue.serverTimestamp(),
      }).timeout(const Duration(seconds: 5));

      _openRequests = _openRequests.where((item) => item.id != requestId).toList();
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Failed to cancel SOS: ${e.toString()}';
      notifyListeners();
      return false;
    }
  }

  Future<void> retryPendingSync() async {
    if (_pendingSyncRequests.isEmpty) {
      return;
    }

    final pendingCopy = List<EmergencyRequestModel>.from(_pendingSyncRequests);
    for (final request in pendingCopy) {
      try {
        await _firestore
            .collection('emergency_requests')
            .doc(request.id)
            .set(request.toMap())
            .timeout(const Duration(seconds: 5));
        _pendingSyncRequests.removeWhere((item) => item.id == request.id);
      } catch (_) {
        break;
      }
    }
    notifyListeners();
  }

  Future<void> acceptRequest({
    required String requestId,
    required String responderUserId,
  }) async {
    try {
      await _firestore.collection('emergency_requests').doc(requestId).set(
        <String, dynamic>{
          'status': 'accepted',
          'acceptedByUserId': responderUserId,
          'acceptedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      ).timeout(const Duration(seconds: 5));

      _openRequests = _openRequests.where((item) => item.id != requestId).toList();
      notifyListeners();
    } catch (e) {
      _error = 'Request accepted locally. Cloud sync pending.';
      notifyListeners();
    }
  }
}
