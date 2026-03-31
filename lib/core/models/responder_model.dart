import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';

class ResponderModel {
  final String id;
  final String userId;
  final String name;
  final String phoneNumber;
  final String skillsArea; // e.g., "Medical", "Fire", "Search & Rescue"
  final double latitude;
  final double longitude;
  final bool isAvailable;
  final DateTime registeredAt;

  ResponderModel({
    required this.id,
    required this.userId,
    required this.name,
    required this.phoneNumber,
    required this.skillsArea,
    required this.latitude,
    required this.longitude,
    this.isAvailable = true,
    required this.registeredAt,
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
      'latitude': latitude,
      'longitude': longitude,
      'isAvailable': isAvailable,
      'registeredAt': registeredAt,
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
      latitude: (map['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (map['longitude'] as num?)?.toDouble() ?? 0.0,
      isAvailable: (map['isAvailable'] as bool?) ?? true,
      registeredAt: parsedRegisteredAt,
    );
  }

  ResponderModel copyWith({
    String? id,
    String? userId,
    String? name,
    String? phoneNumber,
    String? skillsArea,
    double? latitude,
    double? longitude,
    bool? isAvailable,
    DateTime? registeredAt,
  }) {
    return ResponderModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      skillsArea: skillsArea ?? this.skillsArea,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      isAvailable: isAvailable ?? this.isAvailable,
      registeredAt: registeredAt ?? this.registeredAt,
    );
  }
}
