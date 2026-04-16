import 'package:cloud_firestore/cloud_firestore.dart';

class EmergencyRequestModel {
  final String id;
  final String requesterUserId;
  final String requesterName;
  final double latitude;
  final double longitude;
  final String category;
  final String severity;
  final String originalMessage;
  final String? voiceTranscript;
  final String? voiceAudioUrl;
  final String? voiceAudioType;
  final String? attachmentUrl;
  final String? attachmentType;
  final String summary;
  final String recommendedSkill;
  final List<String> suggestedActions;
  final double? aiConfidence;
  final bool humanReviewRecommended;
  final bool forcedCriticalByUser;
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
    required this.originalMessage,
    this.voiceTranscript,
    this.voiceAudioUrl,
    this.voiceAudioType,
    this.attachmentUrl,
    this.attachmentType,
    required this.summary,
    required this.recommendedSkill,
    required this.suggestedActions,
    this.aiConfidence,
    this.humanReviewRecommended = false,
    this.forcedCriticalByUser = false,
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
        originalMessage: (map['originalMessage'] as String?) ?? '',
        voiceTranscript: map['voiceTranscript'] as String?,
        voiceAudioUrl: map['voiceAudioUrl'] as String?,
        voiceAudioType: map['voiceAudioType'] as String?,
        attachmentUrl: map['attachmentUrl'] as String?,
        attachmentType: map['attachmentType'] as String?,
      summary: (map['summary'] as String?) ?? 'SOS requested',
      recommendedSkill: (map['recommendedSkill'] as String?) ?? 'General Support',
        suggestedActions: (map['suggestedActions'] as List?)
            ?.whereType<String>()
            .toList() ??
          const <String>[],
      aiConfidence: (map['aiConfidence'] as num?)?.toDouble(),
      humanReviewRecommended: map['humanReviewRecommended'] == true,
      forcedCriticalByUser: map['forcedCriticalByUser'] == true,
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
      'originalMessage': originalMessage,
      'voiceTranscript': voiceTranscript,
      'voiceAudioUrl': voiceAudioUrl,
      'voiceAudioType': voiceAudioType,
      'attachmentUrl': attachmentUrl,
      'attachmentType': attachmentType,
      'summary': summary,
      'recommendedSkill': recommendedSkill,
      'suggestedActions': suggestedActions,
      'aiConfidence': aiConfidence,
      'humanReviewRecommended': humanReviewRecommended,
      'forcedCriticalByUser': forcedCriticalByUser,
      'status': status,
      'acceptedByUserId': acceptedByUserId,
      'createdAt': createdAt,
    };
  }

  EmergencyRequestModel copyWith({
    String? status,
    String? acceptedByUserId,
    String? voiceAudioUrl,
    String? voiceAudioType,
    String? attachmentUrl,
    String? attachmentType,
  }) {
    return EmergencyRequestModel(
      id: id,
      requesterUserId: requesterUserId,
      requesterName: requesterName,
      latitude: latitude,
      longitude: longitude,
      category: category,
      severity: severity,
      originalMessage: originalMessage,
      voiceTranscript: voiceTranscript,
      voiceAudioUrl: voiceAudioUrl ?? this.voiceAudioUrl,
      voiceAudioType: voiceAudioType ?? this.voiceAudioType,
      attachmentUrl: attachmentUrl ?? this.attachmentUrl,
      attachmentType: attachmentType ?? this.attachmentType,
      summary: summary,
      recommendedSkill: recommendedSkill,
      suggestedActions: suggestedActions,
      aiConfidence: aiConfidence,
      humanReviewRecommended: humanReviewRecommended,
      forcedCriticalByUser: forcedCriticalByUser,
      status: status ?? this.status,
      acceptedByUserId: acceptedByUserId ?? this.acceptedByUserId,
      createdAt: createdAt,
    );
  }
}
