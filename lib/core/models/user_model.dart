import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String id;
  final String email;
  final String? phoneNumber;
  final String displayName;
  final bool isAnonymous;
  final double? latitude;
  final double? longitude;
  final bool isResponder;
  final DateTime createdAt;

  UserModel({
    required this.id,
    required this.email,
    this.phoneNumber,
    required this.displayName,
    this.isAnonymous = false,
    this.latitude,
    this.longitude,
    this.isResponder = false,
    required this.createdAt,
  });

  // Convert to JSON for Firestore
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'email': email,
      'phoneNumber': phoneNumber,
      'displayName': displayName,
      'isAnonymous': isAnonymous,
      'latitude': latitude,
      'longitude': longitude,
      'isResponder': isResponder,
      'createdAt': createdAt,
    };
  }

  // Create from JSON
  factory UserModel.fromMap(Map<String, dynamic> map) {
    final dynamic createdAtRaw = map['createdAt'];
    DateTime parsedCreatedAt = DateTime.now();
    if (createdAtRaw is Timestamp) {
      parsedCreatedAt = createdAtRaw.toDate();
    } else if (createdAtRaw is DateTime) {
      parsedCreatedAt = createdAtRaw;
    }

    return UserModel(
      id: (map['id'] as String?) ?? '',
      email: (map['email'] as String?) ?? '',
      phoneNumber: map['phoneNumber'] as String?,
      displayName: (map['displayName'] as String?) ?? '',
      isAnonymous: (map['isAnonymous'] as bool?) ?? false,
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      isResponder: (map['isResponder'] as bool?) ?? false,
      createdAt: parsedCreatedAt,
    );
  }

  // For updating location
  UserModel copyWith({
    String? id,
    String? email,
    String? phoneNumber,
    String? displayName,
    bool? isAnonymous,
    double? latitude,
    double? longitude,
    bool? isResponder,
    DateTime? createdAt,
  }) {
    return UserModel(
      id: id ?? this.id,
      email: email ?? this.email,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      displayName: displayName ?? this.displayName,
      isAnonymous: isAnonymous ?? this.isAnonymous,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      isResponder: isResponder ?? this.isResponder,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
