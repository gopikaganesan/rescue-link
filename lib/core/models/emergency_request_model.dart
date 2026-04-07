import 'package:cloud_firestore/cloud_firestore.dart';

class EmergencyRequestModel {
  final String id;
  final String requesterUserId;
  final String requesterName;
  final double latitude;
  final double longitude;
  final String category;
  final String severity;
  final String summary;
  final String recommendedSkill;
  final String status;
  final String? acceptedByUserId;
  final DateTime createdAt;

  const EmergencyRequestModel({
    required this.id,
    required this.requesterUserId,
    required this.requesterName,
    required this.latitude,
    required this.longitude,
    required this.category,
    required this.severity,
    required this.summary,
    required this.recommendedSkill,
    required this.status,
    this.acceptedByUserId,
    required this.createdAt,
  });

  factory EmergencyRequestModel.fromMap(Map<String, dynamic> map) {
    final rawCreatedAt = map['createdAt'];
    DateTime parsedCreatedAt = DateTime.now();
    if (rawCreatedAt is Timestamp) {
      parsedCreatedAt = rawCreatedAt.toDate();
    } else if (rawCreatedAt is DateTime) {
      parsedCreatedAt = rawCreatedAt;
    }

    return EmergencyRequestModel(
      id: (map['id'] as String?) ?? '',
      requesterUserId: (map['requesterUserId'] as String?) ?? '',
      requesterName: (map['requesterName'] as String?) ?? 'Unknown',
      latitude: (map['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (map['longitude'] as num?)?.toDouble() ?? 0,
      category: (map['category'] as String?) ?? 'General Emergency',
      severity: (map['severity'] as String?) ?? 'medium',
      summary: (map['summary'] as String?) ?? 'SOS requested',
      recommendedSkill: (map['recommendedSkill'] as String?) ?? 'General Support',
      status: (map['status'] as String?) ?? 'open',
      acceptedByUserId: map['acceptedByUserId'] as String?,
      createdAt: parsedCreatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'requesterUserId': requesterUserId,
      'requesterName': requesterName,
      'latitude': latitude,
      'longitude': longitude,
      'category': category,
      'severity': severity,
      'summary': summary,
      'recommendedSkill': recommendedSkill,
      'status': status,
      'acceptedByUserId': acceptedByUserId,
      'createdAt': createdAt,
    };
  }

  EmergencyRequestModel copyWith({
    String? status,
    String? acceptedByUserId,
  }) {
    return EmergencyRequestModel(
      id: id,
      requesterUserId: requesterUserId,
      requesterName: requesterName,
      latitude: latitude,
      longitude: longitude,
      category: category,
      severity: severity,
      summary: summary,
      recommendedSkill: recommendedSkill,
      status: status ?? this.status,
      acceptedByUserId: acceptedByUserId ?? this.acceptedByUserId,
      createdAt: createdAt,
    );
  }
}
