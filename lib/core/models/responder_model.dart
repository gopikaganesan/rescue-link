import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';

class ResponderModel {
  final String id;
  final String userId;
  final String name;
  final String phoneNumber;
  final String skillsArea; // e.g., "Medical", "Fire", "Search & Rescue"
  final String responderType;
  final String verificationLevel;
  final bool verifiedResponder;
  final int rescueCount;
  final double averageRating;
  final int ratingCount;
  final double latitude;
  final double longitude;
  final bool isAvailable;
  final DateTime registeredAt;
  final String? idDocumentUrl; // URL to uploaded ID document in Firebase Storage
  final String? idDocumentFileName; // Original filename of uploaded document

  ResponderModel({
    required this.id,
    required this.userId,
    required this.name,
    required this.phoneNumber,
    required this.skillsArea,
    this.responderType = 'Volunteer',
    this.verificationLevel = 'Self-declared',
    this.verifiedResponder = false,
    this.rescueCount = 0,
    this.averageRating = 0,
    this.ratingCount = 0,
    required this.latitude,
    required this.longitude,
    this.isAvailable = true,
    required this.registeredAt,
    this.idDocumentUrl,
    this.idDocumentFileName,
  });

  // Distance calculation (simplified Haversine)
  double distanceToLocation(double lat, double lng) {
    const double earthRadiusKm = 6371.0;
    final double dLat = _toRad(lat - latitude);
    final double dLng = _toRad(lng - longitude);
    final double a = (math.sin(dLat / 2) * math.sin(dLat / 2)) +
        (math.cos(_toRad(latitude)) *
            math.cos(_toRad(lat)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2));
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusKm * c;
  }

  static double _toRad(double degree) {
    return degree * 3.14159265359 / 180.0;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'name': name,
      'phoneNumber': phoneNumber,
      'skillsArea': skillsArea,
      'responderType': responderType,
      'verificationLevel': verificationLevel,
      'verifiedResponder': verifiedResponder,
      'rescueCount': rescueCount,
      'averageRating': averageRating,
      'ratingCount': ratingCount,
      'latitude': latitude,
      'longitude': longitude,
      'isAvailable': isAvailable,
      'registeredAt': registeredAt,
      if (idDocumentUrl != null) 'idDocumentUrl': idDocumentUrl,
      if (idDocumentFileName != null) 'idDocumentFileName': idDocumentFileName,
    };
  }

  factory ResponderModel.fromMap(Map<String, dynamic> map) {
    final dynamic registeredAtRaw = map['registeredAt'];
    DateTime parsedRegisteredAt = DateTime.now();
    if (registeredAtRaw is Timestamp) {
      parsedRegisteredAt = registeredAtRaw.toDate();
    } else if (registeredAtRaw is DateTime) {
      parsedRegisteredAt = registeredAtRaw;
    }

    return ResponderModel(
      id: (map['id'] as String?) ?? '',
      userId: (map['userId'] as String?) ?? '',
      name: (map['name'] as String?) ?? '',
      phoneNumber: (map['phoneNumber'] as String?) ?? '',
      skillsArea: (map['skillsArea'] as String?) ?? '',
      responderType: (map['responderType'] as String?) ?? 'Volunteer',
      verificationLevel:
          (map['verificationLevel'] as String?) ?? 'Self-declared',
        verifiedResponder: (map['verifiedResponder'] as bool?) ?? false,
        rescueCount: (map['rescueCount'] as num?)?.toInt() ?? 0,
        averageRating: (map['averageRating'] as num?)?.toDouble() ?? 0,
        ratingCount: (map['ratingCount'] as num?)?.toInt() ?? 0,
      latitude: (map['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (map['longitude'] as num?)?.toDouble() ?? 0.0,
      isAvailable: (map['isAvailable'] as bool?) ?? true,
      registeredAt: parsedRegisteredAt,
      idDocumentUrl: (map['idDocumentUrl'] as String?),
      idDocumentFileName: (map['idDocumentFileName'] as String?),
    );
  }

  static ResponderModel ai() {
    return ResponderModel(
      id: 'rescuelink_ai',
      userId: 'rescuelink_ai',
      name: 'RescueLink AI',
      phoneNumber: '',
      skillsArea: 'Emergency Guidance, Logistics, Medical Dispatch',
      responderType: 'AI Assistant',
      verificationLevel: 'System Verified',
      verifiedResponder: true,
      rescueCount: 999,
      averageRating: 5.0,
      ratingCount: 0, // Will be replaced by live count in UI
      latitude: 0,
      longitude: 0,
      registeredAt: DateTime(2024),
    );
  }

  ResponderModel copyWith({
    String? id,
    String? userId,
    String? name,
    String? phoneNumber,
    String? skillsArea,
    String? responderType,
    String? verificationLevel,
    bool? verifiedResponder,
    int? rescueCount,
    double? averageRating,
    int? ratingCount,
    double? latitude,
    double? longitude,
    bool? isAvailable,
    DateTime? registeredAt,
    String? idDocumentUrl,
    String? idDocumentFileName,
  }) {
    return ResponderModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      skillsArea: skillsArea ?? this.skillsArea,
      responderType: responderType ?? this.responderType,
      verificationLevel: verificationLevel ?? this.verificationLevel,
      verifiedResponder: verifiedResponder ?? this.verifiedResponder,
      rescueCount: rescueCount ?? this.rescueCount,
      averageRating: averageRating ?? this.averageRating,
      ratingCount: ratingCount ?? this.ratingCount,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      isAvailable: isAvailable ?? this.isAvailable,
      registeredAt: registeredAt ?? this.registeredAt,
      idDocumentUrl: idDocumentUrl ?? this.idDocumentUrl,
      idDocumentFileName: idDocumentFileName ?? this.idDocumentFileName,
    );
  }
}
