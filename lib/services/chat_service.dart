import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:http/http.dart' as http;

class ChatService {
  ChatService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _geminiApiKey = _resolveGeminiApiKey();

  static const int _maxMessageLength = 1000;
  static const int _maxAiMessageLength = 12000;
  static const int _maxDisplayNameLength = 80;
  static const String _aiUid = 'rescuelink_ai';
  static const String _aiDisplayName = 'RescueLink AI';
  static const List<String> _geminiModelCandidates = <String>[
    'gemini-2.5-flash',
    'gemini-2.5-flash-lite',
    'gemini-2.0-flash',
    'gemini-2.0-flash-001',
    'gemini-2.0-flash-lite-001',
    'gemini-2.0-flash-lite',
    'gemini-flash-latest',
  ];
  static const Duration _geminiTimeout = Duration(seconds: 12);
  static const String _aiSourceGemini = '[[AI_SOURCE:GEMINI]]';
  static const String _aiSourceBuiltIn = '[[AI_SOURCE:BUILTIN]]';
  static const String _aiStatusPrefix = '[[AI_STATUS:';
  static const String _systemSenderUid = 'rescuelink_system';
  static const String _systemSenderName = 'RescueLink';
  static const Map<String, String> _crisisTypeToYoutubeVideoId =
      <String, String>{
    'fire': 'Y107-A8Ny-4',
    'extinguisher': 'PQV71INDaqY',
    'smoke': 'Y107-A8Ny-4',
    'cpr': 'u0B-ea-_9rc',
    'cardiac arrest': 'u0B-ea-_9rc',
    'bleeding': 'BQNNOh8c8ks',
    'wound': 'BQNNOh8c8ks',
    'choking': '_zJQUUj2Oo8',
    'unresponsive': 'ea1RJUOiNfQ',
  };
  static const Map<String, List<String>> _quickFallbackByCrisisType =
      <String, List<String>>{
    'medical': <String>[
      'Check breathing and consciousness immediately.',
      'If unresponsive or breathing is abnormal, call emergency now and start CPR if trained.',
      'Control severe bleeding with direct pressure and keep the person still.',
    ],
    'fire': <String>[
      'Evacuate immediately; keep low under smoke and use nearest safe exit.',
      'If fire is small and contained, use PASS extinguisher method only if safe.',
      'Do not use water on electrical or oil fires.',
    ],
    'road': <String>[
      'Secure the scene first and prevent further traffic collisions.',
      'Call emergency and report number of injured people.',
      'Do not move seriously injured persons unless there is immediate danger.',
    ],
    'violence': <String>[
      'Move to a safer public place near trusted people.',
      'Call police/emergency immediately and share live location if possible.',
      'Preserve evidence such as messages, photos, and timeline details.',
    ],
    'flood': <String>[
      'Move to higher ground immediately and avoid flowing water.',
      'Switch off electricity at main source if safe to do so.',
      'Do not drive through flood water.',
    ],
    'earthquake': <String>[
      'Drop to the ground, cover your head, and hold onto a sturdy object.',
      'Stay indoors until shaking stops; avoid windows and loose fixtures.',
      'If outdoors, move away from buildings, trees, and streetlights.',
    ],
    'lost': <String>[
      'Stay exactly where you are to make finding you easier.',
      'Preserve phone battery and turn on location sharing.',
      'Make yourself visible or use a whistle. Do not walk at night.',
    ],
  };

  // Optional backend endpoint for secure Cloudinary deletion.
  static const String _cloudinaryDeleteEndpoint = String.fromEnvironment(
    'CLOUDINARY_DELETE_ENDPOINT',
    defaultValue: '',
  );
  static const String _cloudinaryDeleteToken = String.fromEnvironment(
    'CLOUDINARY_DELETE_TOKEN',
    defaultValue: '',
  );

  final FirebaseFirestore _firestore;
  final String _geminiApiKey;
  String? _lastAiFailure;
  static const List<Duration> _retryBackoff = <Duration>[
    Duration(milliseconds: 300),
    Duration(milliseconds: 700),
    Duration(milliseconds: 1200),
  ];

  Future<Map<String, dynamic>?> fetchEmergencyRequest(String sosId) async {
    try {
      final doc = await _firestore.collection('emergency_requests').doc(sosId).get();
      return doc.data();
    } catch (e) {
      debugPrint('ChatService: Error fetching emergency request $sosId: $e');
      return null;
    }
  }

  CollectionReference<Map<String, dynamic>> get _chats =>
      _firestore.collection('chats');

  DocumentReference<Map<String, dynamic>> chatRef(String sosId) =>
      _chats.doc(sosId);

  CollectionReference<Map<String, dynamic>> messagesRef(String sosId) =>
      chatRef(sosId).collection('messages');

  String? get lastAiFailure => _lastAiFailure;

  void _setLastAiFailure(String? message) {
    final normalized = message?.trim();
    _lastAiFailure =
        (normalized == null || normalized.isEmpty) ? null : normalized;
  }

  Future<void> createChatOnSos({
    required String sosId,
    required String victimUid,
    String? victimName,
    required String sosMessage,
    List<Map<String, dynamic>> media = const <Map<String, dynamic>>[],
    double? latitude,
    double? longitude,
    String? address,
  }) async {
    final now = FieldValue.serverTimestamp();
    final participantJoinedAt = Timestamp.now();
    final ref = chatRef(sosId);

    final victimParticipant = <String, dynamic>{
      'uid': victimUid,
      'displayName': _safeDisplayName(victimName, fallback: 'Victim'),
      'role': 'victim',
      'joinedAt': participantJoinedAt,
    };

    final aiParticipant = <String, dynamic>{
      'uid': 'rescuelink_ai',
      'displayName': 'RescueLink AI',
      'role': 'responder',
      'isAi': true,
      'joinedAt': participantJoinedAt,
    };

    await _withFirestoreRetry(() async {
      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(ref);
        if (snapshot.exists) {
          return;
        }

        transaction.set(
          ref,
          <String, dynamic>{
            'sosId': sosId,
            'createdAt': now,
            'status': 'active',
            'sosOverview': <String, dynamic>{
              'message': sosMessage,
              'media': media,
              if (latitude != null) 'latitude': latitude,
              if (longitude != null) 'longitude': longitude,
              if (address != null && address.isNotEmpty) 'address': address,
            },
            'participants': <Map<String, dynamic>>[
              victimParticipant,
              aiParticipant,
            ],
            'participantUids': <String>[
              victimUid,
              'rescuelink_ai',
            ],
            'onlineCount': 0,
          },
        );
      });
    });
  }

  Future<void> createChatFromSosPayload({
    required Map<String, dynamic> sosPayload,
  }) async {
    final sosId =
        (sosPayload['id'] as String?) ?? (sosPayload['sosId'] as String?) ?? '';
    final victimUid = (sosPayload['requesterUserId'] as String?) ??
        (sosPayload['victimUid'] as String?) ??
        '';
    final victimName = (sosPayload['requesterName'] as String?) ??
        (sosPayload['victimName'] as String?);

    if (sosId.isEmpty || victimUid.isEmpty) {
      return;
    }

    final sosMessage = (sosPayload['originalMessage'] as String?) ??
        (sosPayload['summary'] as String?) ??
        '';

    await createChatOnSos(
      sosId: sosId,
      victimUid: victimUid,
      victimName: victimName,
      sosMessage: sosMessage,
      media: _extractOverviewMedia(sosPayload),
      latitude: (sosPayload['latitude'] as num?)?.toDouble(),
      longitude: (sosPayload['longitude'] as num?)?.toDouble(),
      address: (sosPayload['address'] as String?) ??
          (sosPayload['location'] as String?),
    );
  }

  Future<void> cancelChatFromSosId({
    required String sosId,
    bool deleteDocument = false,
  }) async {
    await cancelChatOnSos(
      sosId: sosId,
      deleteDocument: deleteDocument,
    );
  }

  Future<bool> ensureChatFromEmergencyRequest({required String sosId}) async {
    final safeSosId = sosId.trim();
    if (safeSosId.isEmpty) {
      return false;
    }

    final chatSnapshot = await _withFirestoreRetry(
      () => chatRef(safeSosId).get(),
    );
    if (chatSnapshot.exists) {
      return true;
    }

    final requestSnapshot = await _withFirestoreRetry(
      () => _firestore.collection('emergency_requests').doc(safeSosId).get(),
    );
    final requestData = requestSnapshot.data();
    if (requestData == null) {
      return false;
    }

    final payload = <String, dynamic>{
      ...requestData,
      'id': safeSosId,
    };

    await createChatFromSosPayload(sosPayload: payload);

    final createdSnapshot = await _withFirestoreRetry(
      () => chatRef(safeSosId).get(),
    );
    return createdSnapshot.exists;
  }

  Future<bool> ensureVictimParticipant({
    required String sosId,
    required String victimUid,
    String? victimName,
  }) async {
    final safeSosId = sosId.trim();
    final safeVictimUid = victimUid.trim();
    if (safeSosId.isEmpty || safeVictimUid.isEmpty) {
      return false;
    }

    final ref = chatRef(safeSosId);

    return _withFirestoreRetry(() async {
      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(ref);
        final data = snapshot.data();
        if (data == null) {
          throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'not-found',
            message: 'Chat does not exist.',
          );
        }

        final status = (data['status'] as String?) ?? 'active';
        if (status == 'cancelled') {
          return;
        }

        final participants = _asMapList(data['participants']);
        final participantUids = _extractParticipantUids(data);
        if (participantUids.contains(safeVictimUid)) {
          return;
        }

        final updatedParticipants = participants.toList();
        final existingVictimIndex = updatedParticipants.indexWhere(
          (entry) => (entry['uid'] as String?) == safeVictimUid,
        );

        final victimEntry = <String, dynamic>{
          'uid': safeVictimUid,
          'displayName': _safeDisplayName(victimName, fallback: 'Victim'),
          'role': 'victim',
          'joinedAt': Timestamp.now(),
        };

        if (existingVictimIndex >= 0) {
          updatedParticipants[existingVictimIndex] = victimEntry;
        } else {
          updatedParticipants.add(victimEntry);
        }

        final updatedUids = participantUids.toSet()..add(safeVictimUid);

        transaction.set(
          ref,
          <String, dynamic>{
            'participants': updatedParticipants,
            'participantUids': updatedUids.toList(),
          },
          SetOptions(merge: true),
        );
      });

      final updated = await ref.get();
      final updatedData = updated.data() ?? <String, dynamic>{};
      final updatedUids = _extractParticipantUids(updatedData);
      return updatedUids.contains(safeVictimUid);
    });
  }

  Future<String?> findLatestVictimSosId({required String victimUid}) async {
    final safeVictimUid = victimUid.trim();
    if (safeVictimUid.isEmpty) {
      return null;
    }

    final snapshot = await _withFirestoreRetry(
      () => _firestore
          .collection('emergency_requests')
          .where('requesterUserId', isEqualTo: safeVictimUid)
          .orderBy('createdAt', descending: true)
          .limit(20)
          .get(),
    );

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final status = (data['status'] as String?)?.toLowerCase() ?? 'open';
      if (status == 'cancelled') {
        continue;
      }

      final sosId = doc.id;
      final existingChat =
          await _withFirestoreRetry(() => chatRef(sosId).get());
      if (existingChat.exists) {
        return sosId;
      }

      final payload = <String, dynamic>{
        ...data,
        'id': sosId,
      };

      try {
        await createChatFromSosPayload(sosPayload: payload);
      } catch (_) {
        continue;
      }

      final createdChat = await _withFirestoreRetry(() => chatRef(sosId).get());
      if (createdChat.exists) {
        return sosId;
      }
    }

    return null;
  }

  Future<void> cancelChatOnSos({
    required String sosId,
    bool deleteDocument = false,
  }) async {
    final safeSosId = sosId.trim();
    if (safeSosId.isEmpty) {
      return;
    }

    final ref = chatRef(sosId);
    if (deleteDocument) {
      await deleteEntireChat(
        sosId: safeSosId,
        deleteMediaFromCloudinary: true,
      );
      return;
    }

    await ref.set(
      <String, dynamic>{
        'status': 'cancelled',
        'cancelledAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    await _deleteLinkedSosRecords(safeSosId);
  }

  Future<void> deleteEntireChat({
    required String sosId,
    bool deleteMediaFromCloudinary = true,
  }) async {
    final safeSosId = sosId.trim();
    if (safeSosId.isEmpty) {
      return;
    }

    final ref = chatRef(safeSosId);

    await _withFirestoreRetry(() async {
      final processedMediaUrls = <String>{};

      if (deleteMediaFromCloudinary) {
        final chatSnapshot = await ref.get();
        final chatData = chatSnapshot.data();
        if (chatData != null) {
          await _deleteMediaForChatData(
            chatData,
            processedMediaUrls: processedMediaUrls,
          );
        }
      }

      while (true) {
        final batch = _firestore.batch();
        final messageSnapshot = await messagesRef(safeSosId).limit(150).get();
        if (messageSnapshot.docs.isEmpty) {
          break;
        }

        for (final doc in messageSnapshot.docs) {
          if (deleteMediaFromCloudinary) {
            final data = doc.data();
            await _deleteMediaForMessageData(
              data,
              processedMediaUrls: processedMediaUrls,
            );
          }
          batch.delete(doc.reference);
        }

        await batch.commit();
      }

      await ref.delete();
      await _deleteLinkedSosRecords(safeSosId);
    });
  }

  Future<void> _deleteLinkedSosRecords(String sosId) async {
    final safeSosId = sosId.trim();
    if (safeSosId.isEmpty) {
      return;
    }

    Future<void> safeDelete(String collection) async {
      try {
        await _firestore.collection(collection).doc(safeSosId).delete();
      } catch (_) {
        // Keep chat flow resilient; linked SOS cleanup is best-effort.
      }
    }

    await safeDelete('emergency_requests');
    await safeDelete('sos_events');
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchChat(String sosId) {
    return chatRef(sosId).snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchActiveChats() {
    return _chats.where('status', isEqualTo: 'active').snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchResponderChats(
    String responderUid,
  ) {
    final safeResponderUid = responderUid.trim();
    if (safeResponderUid.isEmpty) {
      return const Stream<QuerySnapshot<Map<String, dynamic>>>.empty();
    }

    return _chats
        .where('participantUids', arrayContains: safeResponderUid)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchVictimChats(
    String victimUid,
  ) {
    final safeVictimUid = victimUid.trim();
    if (safeVictimUid.isEmpty) {
      return const Stream<QuerySnapshot<Map<String, dynamic>>>.empty();
    }

    return _chats
        .where('participantUids', arrayContains: safeVictimUid)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchMessages(String sosId) {
    return messagesRef(sosId)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  bool shouldTriggerAiFromText(String text) {
    return RegExp(r'(^|\s)@ai(\b|$)', caseSensitive: false)
        .hasMatch(text.trim());
  }

  Future<bool> sendAutoAiInstructionsIfNeeded({
    required String sosId,
  }) async {
    final safeSosId = sosId.trim();
    if (safeSosId.isEmpty) {
      return false;
    }

    await _ensureAiParticipantPresent(safeSosId);

    final chatSnapshot =
        await _withFirestoreRetry(() => chatRef(safeSosId).get());
    final chatData = chatSnapshot.data();
    if (chatData == null) {
      return false;
    }

    final status = (chatData['status'] as String?) ?? 'active';
    if (status == 'cancelled') {
      return false;
    }

    if (_hasHumanResponder(chatData)) {
      return false;
    }

    if (await _hasAiAutoMessage(safeSosId)) {
      return false;
    }

    final recentMessages = await _fetchRecentMessages(safeSosId, limit: 12);
    final emergencyContext = await _loadEmergencyContext(safeSosId);
    final prompt = _buildAiPrompt(
      chatData: chatData,
      recentMessages: recentMessages,
      emergencyContext: emergencyContext,
      requesterName: 'Victim',
      requesterRole: 'victim',
      userPrompt:
          'No human responder has joined yet. Provide immediate, practical emergency guidance now.',
      imageDescription: null,
      voiceTranscript: null,
      askReason: 'auto_no_human_responder',
    );

    final sosOverview =
        (chatData['sosOverview'] as Map<String, dynamic>?) ?? {};
    final overviewMessage =
        (sosOverview['message'] as String?) ?? 'Emergency reported';

    final outcome = await _generateAiReply(prompt);
    var finalAiText = outcome.hasText
        ? outcome.text!
        : _buildApiFallbackMessage(
            reason: outcome.userMessage,
            userPrompt: 'No human responder has joined yet.',
            contextSummary: overviewMessage,
            emergencyContext: emergencyContext,
            recentMessages: recentMessages,
          );
    
    // Sanitize YouTube links in Gemini response to only include trusted videos.
    if (outcome.hasText) {
      finalAiText = _sanitizeYoutubeLinksInAiResponse(
        finalAiText,
        contextPrompt: '$overviewMessage\nNo human responder has joined yet.',
      );
    }
    
    final String sourceMarker =
        outcome.hasText ? _aiSourceGemini : _aiSourceBuiltIn;

    final fallbackRequesterUid = _resolveVictimUid(chatData);
    if (fallbackRequesterUid == null) {
      return false;
    }

    await _sendAiMessage(
      sosId: safeSosId,
      text: _composeAiMessageText(
        sourceMarker: sourceMarker,
        statusCode: outcome.code,
        body: finalAiText,
      ),
      requesterUid: fallbackRequesterUid,
    );
    return true;
  }

  Future<bool> sendMessageToAI({
    required String sosId,
    required String requesterUid,
    required String requesterName,
    required String requesterRole,
    required String userPrompt,
    String? preferredLanguageCode,
    String? imageDescription,
    String? voiceTranscript,
    String askReason = 'manual',
  }) async {
    final safeSosId = sosId.trim();
    final safeRequesterUid = requesterUid.trim();
    final safePrompt = _sanitizeAiPrompt(
      userPrompt,
      askReason: askReason,
    );
    _setLastAiFailure(null);

    if (safeSosId.isEmpty || safeRequesterUid.isEmpty || safePrompt.isEmpty) {
      _setLastAiFailure('AI request is invalid. Please try again.');
      return false;
    }

    try {
      await _ensureAiParticipantPresent(safeSosId);

      final chatSnapshot = await _withFirestoreRetry(
        () => chatRef(safeSosId).get(
          const GetOptions(source: Source.serverAndCache),
        ),
      );
      final chatData = chatSnapshot.data() ?? <String, dynamic>{};

      final status = (chatData['status'] as String?) ?? 'active';
      if (status == 'cancelled') {
        _setLastAiFailure(
          'This SOS chat is cancelled, so AI responses are disabled.',
        );
        return false;
      }

      final participantUids = _extractParticipantUids(chatData);
      if (participantUids.isNotEmpty &&
          (!participantUids.contains(safeRequesterUid) ||
              !_isActiveParticipant(chatData, safeRequesterUid))) {
        _setLastAiFailure(
          'You are not an active participant in this chat. Join first, then ask AI.',
        );
        return false;
      }

      final recentMessages = await _fetchRecentMessages(safeSosId, limit: 20);
      final emergencyContext = await _loadEmergencyContext(safeSosId);
      final normalizedLanguageCode = preferredLanguageCode?.trim().toLowerCase();
      final effectiveEmergencyContext =
          (normalizedLanguageCode != null && normalizedLanguageCode.isNotEmpty)
              ? <String, dynamic>{
                  ...emergencyContext,
                  'languageCode': normalizedLanguageCode,
                }
              : emergencyContext;
      final prompt = _buildAiPrompt(
        chatData: chatData,
        recentMessages: recentMessages,
        emergencyContext: effectiveEmergencyContext,
        requesterName: requesterName,
        requesterRole: requesterRole,
        userPrompt: safePrompt,
        imageDescription: imageDescription,
        voiceTranscript: voiceTranscript,
        askReason: askReason,
      );

      final sosOverview =
          (chatData['sosOverview'] as Map<String, dynamic>?) ?? {};
      final overviewMessage =
          (sosOverview['message'] as String?) ?? 'Emergency reported';

      final outcome = await _generateAiReply(prompt);
      final sourceMarker = outcome.hasText ? _aiSourceGemini : _aiSourceBuiltIn;
      var effectiveAiText = outcome.hasText
          ? _maybeAppendVisualGuidance(
              userPrompt: safePrompt,
              aiText: outcome.text!,
            )
          : _buildApiFallbackMessage(
              reason: outcome.userMessage,
              userPrompt: safePrompt,
              contextSummary: overviewMessage,
              emergencyContext: effectiveEmergencyContext,
              recentMessages: recentMessages,
            );

      // Sanitize YouTube links in Gemini response to only include trusted videos.
      if (outcome.hasText) {
        effectiveAiText = _sanitizeYoutubeLinksInAiResponse(
          effectiveAiText,
          contextPrompt: '$safePrompt\n$overviewMessage',
        );
      }

      final sent = await _sendAiMessage(
        sosId: safeSosId,
        text: _composeAiMessageText(
          sourceMarker: sourceMarker,
          statusCode: outcome.code,
          body: effectiveAiText,
        ),
        requesterUid: safeRequesterUid,
      );
      if (sent) {
        _setLastAiFailure(null);
        return true;
      }

      _setLastAiFailure(
        _lastAiFailure ??
            'AI reply could not be saved to chat. Check Firestore rules deployment.',
      );
    } catch (error) {
      if (error is FirebaseException) {
        _setLastAiFailure(
          'Firestore error (${error.code}): ${error.message ?? 'Unknown error'}',
        );
      }

      final fallbackText = _composeAiMessageText(
        sourceMarker: _aiSourceBuiltIn,
        statusCode: 'built_in_fallback',
        body: _buildApiFallbackMessage(
          reason: error.toString(),
          userPrompt: safePrompt,
          contextSummary: 'Emergency reported',
          emergencyContext: await _loadEmergencyContext(safeSosId),
          recentMessages: const <Map<String, dynamic>>[],
        ),
      );
      return _sendFallbackAiMessage(
        sosId: safeSosId,
        text: fallbackText,
        requesterUid: safeRequesterUid,
      );
    }

    return false;
  }

  String _composeAiMessageText({
    required String sourceMarker,
    required String statusCode,
    required String body,
  }) {
    return '$sourceMarker\n$_aiStatusPrefix$statusCode]]\n$body';
  }

  Future<void> sendMessage({
    required String sosId,
    required String senderUid,
    required String senderRole,
    required String senderName,
    required String text,
    String? attachmentUrl,
    String? attachmentType,
    String? voiceAudioUrl,
    String? voiceAudioType,
    String? voiceTranscript,
  }) async {
    final safeSenderUid = senderUid.trim();
    if (safeSenderUid.isEmpty) {
      return;
    }

    final trimmed = text.trim();
    final safeAttachmentUrl = attachmentUrl?.trim();
    final hasAttachment =
        safeAttachmentUrl != null && safeAttachmentUrl.isNotEmpty;
    final safeVoiceAudioUrl = voiceAudioUrl?.trim();
    final hasVoiceAudio =
        safeVoiceAudioUrl != null && safeVoiceAudioUrl.isNotEmpty;
    final safeVoiceTranscript = voiceTranscript?.trim();
    if (trimmed.isEmpty && !hasAttachment) {
      return;
    }

    final safeText = trimmed.isEmpty
        ? 'Attachment shared'
        : trimmed.length > _maxMessageLength
            ? trimmed.substring(0, _maxMessageLength)
            : trimmed;
    final safeRole = _normalizeRole(senderRole);

    final chat = chatRef(sosId);
    final messageDoc = messagesRef(sosId).doc();

    await _withFirestoreRetry(() async {
      await _firestore.runTransaction((transaction) async {
        final chatSnapshot = await transaction.get(chat);
        final chatData = chatSnapshot.data() ?? <String, dynamic>{};
        final status = (chatData['status'] as String?) ?? 'active';
        if (status == 'cancelled') {
          return;
        }

        final participantUids = _extractParticipantUids(chatData);
        if (!participantUids.contains(safeSenderUid) ||
            !_isActiveParticipant(chatData, safeSenderUid)) {
          return;
        }

        final hasDedicatedParticipantUids =
            (chatData['participantUids'] as List<dynamic>?) != null;
        if (!hasDedicatedParticipantUids) {
          transaction.set(
            chat,
            <String, dynamic>{
              'participantUids': participantUids.toList(),
            },
            SetOptions(merge: true),
          );
        }

        transaction.set(messageDoc, <String, dynamic>{
          'text': safeText,
          'senderUid': safeSenderUid,
          'senderRole': safeRole,
          'senderName': _safeDisplayName(senderName, fallback: 'Unknown'),
          'createdAt': FieldValue.serverTimestamp(),
          'type': 'text',
          if (hasAttachment) 'attachmentUrl': safeAttachmentUrl,
          if (hasAttachment)
            'attachmentType': (attachmentType ?? 'image').trim(),
          if (hasVoiceAudio) 'voiceAudioUrl': safeVoiceAudioUrl,
          if (hasVoiceAudio)
            'voiceAudioType': (voiceAudioType ?? 'audio/wav').trim(),
          if (safeVoiceTranscript != null && safeVoiceTranscript.isNotEmpty)
            'voiceTranscript': safeVoiceTranscript,
        });
      });
    });
  }

  Future<void> setChatNotificationPreference({
    required String sosId,
    required String userId,
    required bool enabled,
  }) async {
    final safeSosId = sosId.trim();
    final safeUserId = userId.trim();
    if (safeSosId.isEmpty || safeUserId.isEmpty) {
      return;
    }

    await _withFirestoreRetry(() {
      return chatRef(safeSosId).set(
        <String, dynamic>{
          'notificationPreferences.$safeUserId': enabled,
          'notificationPreferencesUpdatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }

  Future<void> joinResponder({
    required String sosId,
    required String responderUid,
    required String responderName,
  }) async {
    final safeResponderUid = responderUid.trim();
    if (safeResponderUid.isEmpty) {
      return;
    }

    final ref = chatRef(sosId);
    var didJoin = false;

    final participantEntry = <String, dynamic>{
      'uid': safeResponderUid,
      'displayName': _safeDisplayName(responderName, fallback: 'Responder'),
      'role': 'responder',
      'joinedAt': Timestamp.now(),
    };

    try {
      await _withFirestoreRetry(() async {
        await _firestore.runTransaction((transaction) async {
          // 1. Check if already joined or blocked
          final snapshot = await transaction.get(ref);
          final data = snapshot.data() ?? <String, dynamic>{};
          final blockedUids =
              (data['blockedUids'] as List<dynamic>?)?.cast<String>() ?? <String>[];

          if (blockedUids.contains(safeResponderUid)) {
            throw Exception('You have been removed from this conversation by the victim.');
          }

          final participants = _asMapList(data['participants']);
          final hasActiveResponderEntry = participants.any(
            (entry) =>
                (entry['uid'] as String?) == safeResponderUid &&
                (entry['role'] as String?) == 'responder' &&
                entry['isAi'] != true,
          );
          if (hasActiveResponderEntry) {
            return; // Already actively joined
          }

          final updatedParticipants = participants
              .where((entry) => !((entry['uid'] as String?) == safeResponderUid &&
                  (entry['role'] as String?) == 'responder' &&
                  entry['isAi'] != true))
              .toList()
            ..add(participantEntry);

          final updatedParticipantUids = _extractParticipantUids(data)
            ..add(safeResponderUid);

          // 2. Perform the join update
          transaction.set(
            ref,
            {
              'participants': updatedParticipants,
              'participantUids': updatedParticipantUids.toList(),
            },
            SetOptions(merge: true),
          );
          didJoin = true;
        });
      });
    } catch (e) {
      debugPrint('Error in joinResponder: $e');
      rethrow;
    }

    if (didJoin) {
      await addResponderJoinedSystemMessage(
        sosId: sosId,
        responderUid: safeResponderUid,
        responderName: responderName,
      );
    }
  }

  Future<void> removeResponder({
    required String sosId,
    required String responderUid,
    required String responderName,
    required String removedByUid,
  }) async {
    final ref = chatRef(sosId);
    final safeUid = responderUid.trim();

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      if (!snapshot.exists) return;

      final data = snapshot.data()!;
      final participants = _asMapList(data['participants']);
      final participantUids =
          List<String>.from((data['participantUids'] as List<dynamic>?) ?? <String>[]);
      final blockedUids =
          List<String>.from((data['blockedUids'] as List<dynamic>?) ?? <String>[]);
      final joinRequests = _asMapList(data['joinRequests']);

      // Filter out the responder
      final updatedParticipants = participants
          .where((p) => (p['uid'] as String?) != safeUid)
          .toList();
      final updatedUids = participantUids.where((u) => u != safeUid).toList();
      final updatedRequests =
          joinRequests.where((r) => (r['uid'] as String?) != safeUid).toList();

      final presence = data['responderPresence'] is Map
          ? Map<String, dynamic>.from(data['responderPresence'] as Map)
          : <String, dynamic>{};
      presence.remove(safeUid);
      final onlineCount =
          presence.values.where((value) => value == true).length;

      // Add to blocked if not already there
      if (!blockedUids.contains(safeUid)) {
        blockedUids.add(safeUid);
      }

      transaction.update(ref, {
        'participants': updatedParticipants,
        'participantUids': updatedUids,
        'blockedUids': blockedUids,
        'joinRequests': updatedRequests,
        'responderPresence': presence,
        'onlineCount': onlineCount,
      });
    });

    // Notify the chat
    await addResponderSystemMessage(
      sosId: sosId,
      text: 'Responder $responderName was removed from the conversation by the victim.',
    );
  }

  Future<void> requestJoinApproval({
    required String sosId,
    required String responderUid,
    required String responderName,
  }) async {
    final ref = chatRef(sosId);
    final safeResponderUid = responderUid.trim();
    if (safeResponderUid.isEmpty) {
      return;
    }

    await _withFirestoreRetry(() async {
      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(ref);
        final data = snapshot.data() ?? <String, dynamic>{};

        final joinRequests = _asMapList(data['joinRequests']);
        final blockedUids =
            List<String>.from((data['blockedUids'] as List<dynamic>?) ?? <String>[]);

        final previouslyRejected = joinRequests.any(
          (request) =>
              (request['uid'] as String?) == safeResponderUid &&
              (request['status'] as String?) == 'rejected',
        );
        if (previouslyRejected) {
          throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'permission-denied',
            message: 'This join request was rejected and cannot be re-requested.',
          );
        }

        if (!blockedUids.contains(safeResponderUid)) {
          throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'failed-precondition',
            message: 'Join request is only available after victim removal.',
          );
        }

        final updatedJoinRequests = joinRequests
            .where((request) => (request['uid'] as String?) != safeResponderUid)
            .toList();

        updatedJoinRequests.add(<String, dynamic>{
          'uid': safeResponderUid,
          'displayName': _safeDisplayName(responderName, fallback: 'Responder'),
          'requestedAt': Timestamp.now(),
          'status': 'pending',
        });

        transaction.update(ref, {
          'joinRequests': updatedJoinRequests,
        });
      });
    });
  }

  Future<void> resolveJoinRequest({
    required String sosId,
    required Map<String, dynamic> request,
    required bool approved,
  }) async {
    final ref = chatRef(sosId);
    final uid = request['uid'] as String;
    final resolvedName = _safeDisplayName(
      (request['displayName'] as String?) ?? (request['name'] as String?),
      fallback: 'Responder',
    );

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      if (!snapshot.exists) return;

      final data = snapshot.data()!;
      final joinRequests = _asMapList(data['joinRequests']);
      final blockedUids = List<String>.from((data['blockedUids'] as Iterable?) ?? []);

      final requestIndex = joinRequests.indexWhere(
        (entry) => (entry['uid'] as String?) == uid,
      );
      if (requestIndex < 0) {
        return;
      }

      final existing = Map<String, dynamic>.from(joinRequests[requestIndex]);
      existing['status'] = approved ? 'approved' : 'rejected';
      existing['resolvedAt'] = Timestamp.now();
      if ((existing['displayName'] as String?)?.trim().isEmpty ?? true) {
        existing['displayName'] = resolvedName;
      }
      joinRequests[requestIndex] = existing;

      var updateData = <String, dynamic>{
        'joinRequests': joinRequests,
      };

      if (approved) {
        // Remove from blocked list if approved
        blockedUids.remove(uid);
        updateData['blockedUids'] = blockedUids;
      } else {
        if (!blockedUids.contains(uid)) {
          blockedUids.add(uid);
        }
        updateData['blockedUids'] = blockedUids;
      }

      transaction.update(ref, updateData);
    });

    if (approved) {
      await addResponderSystemMessage(
        sosId: sosId,
        text: 'Victim approved re-join request for $resolvedName.',
      );
    }
  }

  Future<void> addResponderSystemMessage({
    required String sosId,
    required String text,
  }) async {
    final ref = chatRef(sosId).collection('messages');
    await ref.add({
      'text': text,
      'type': 'system',
      'isSystem': true,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> rejoinResponderConversation({
    required String sosId,
    required String responderUid,
    required String responderName,
  }) {
    return joinResponder(
      sosId: sosId,
      responderUid: responderUid,
      responderName: responderName,
    );
  }

  Future<void> setResponderPresence({
    required String sosId,
    required String responderUid,
    required bool isOnline,
  }) async {
    final ref = chatRef(sosId);
    final safeResponderUid = responderUid.trim();
    if (safeResponderUid.isEmpty) {
      return;
    }

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      final data = snapshot.data() ?? <String, dynamic>{};
      final status = (data['status'] as String?) ?? 'active';
      if (status == 'cancelled') {
        return;
      }

      final participantUids = _extractParticipantUids(data);
      if (!participantUids.contains(safeResponderUid)) {
        return;
      }

      final presence = data['responderPresence'] is Map
          ? Map<String, dynamic>.from(data['responderPresence'] as Map)
          : <String, dynamic>{};

      presence[safeResponderUid] = isOnline;

      final onlineCount =
          presence.values.where((value) => value == true).length;

      transaction.set(
        ref,
        <String, dynamic>{
          'responderPresence': presence,
          'onlineCount': onlineCount,
        },
        SetOptions(merge: true),
      );
    });
  }

  Future<void> clearResponderPresence({
    required String sosId,
    required String responderUid,
  }) async {
    final ref = chatRef(sosId);
    final safeResponderUid = responderUid.trim();
    if (safeResponderUid.isEmpty) {
      return;
    }

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      final data = snapshot.data() ?? <String, dynamic>{};

      final participantUids = _extractParticipantUids(data);
      if (!participantUids.contains(safeResponderUid)) {
        return;
      }

      final presence = data['responderPresence'] is Map
          ? Map<String, dynamic>.from(data['responderPresence'] as Map)
          : <String, dynamic>{};

      if (!presence.containsKey(safeResponderUid)) {
        return;
      }

      presence.remove(safeResponderUid);
      final onlineCount =
          presence.values.where((value) => value == true).length;

      transaction.set(
        ref,
        <String, dynamic>{
          'responderPresence': presence,
          'onlineCount': onlineCount,
        },
        SetOptions(merge: true),
      );
    });
  }

  Future<void> leaveResponder({
    required String sosId,
    required String responderUid,
  }) async {
    final ref = chatRef(sosId);
    final safeResponderUid = responderUid.trim();
    if (safeResponderUid.isEmpty) {
      return;
    }

    await _withFirestoreRetry(() async {
      String? removedResponderName;

      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(ref);
        final data = snapshot.data() ?? <String, dynamic>{};

        final participants = _asMapList(data['participants']);
        for (final entry in participants) {
          if ((entry['uid'] as String?) == safeResponderUid &&
              (entry['role'] as String?) == 'responder' &&
              entry['isAi'] != true) {
            removedResponderName = entry['displayName'] as String?;
            break;
          }
        }

        final updatedParticipants = participants
            .where((entry) => !((entry['uid'] as String?) == safeResponderUid &&
                (entry['role'] as String?) == 'responder' &&
                entry['isAi'] != true))
            .toList();

        if (updatedParticipants.length == participants.length) {
          return;
        }

        // Keep the responder uid discoverable in participantUids so they can
        // re-open and join again from chat lists after leaving.
        final updatedParticipantUids = _extractParticipantUids(data)
          ..add(safeResponderUid);

        final presence = data['responderPresence'] is Map
            ? Map<String, dynamic>.from(data['responderPresence'] as Map)
            : <String, dynamic>{};
        presence.remove(safeResponderUid);
        final onlineCount =
            presence.values.where((value) => value == true).length;

        transaction.set(
          ref,
          <String, dynamic>{
            'participants': updatedParticipants,
            'participantUids': updatedParticipantUids.toList(),
            'responderPresence': presence,
            'onlineCount': onlineCount,
          },
          SetOptions(merge: true),
        );
      });

      await addResponderLeftSystemMessage(
        sosId: sosId,
        responderUid: safeResponderUid,
        responderName: removedResponderName,
      );
    });
  }

  Future<void> removeResponderFromChatList({
    required String sosId,
    required String responderUid,
  }) async {
    final ref = chatRef(sosId);
    final safeResponderUid = responderUid.trim();
    if (safeResponderUid.isEmpty) {
      return;
    }

    await _withFirestoreRetry(() async {
      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(ref);
        final data = snapshot.data() ?? <String, dynamic>{};

        final participants = _asMapList(data['participants']);
        final updatedParticipants = participants
            .where((entry) => !((entry['uid'] as String?) == safeResponderUid &&
                (entry['role'] as String?) == 'responder' &&
                entry['isAi'] != true))
            .toList();

        final updatedParticipantUids = _extractParticipantUids(data)
          ..remove(safeResponderUid);

        final presence = data['responderPresence'] is Map
            ? Map<String, dynamic>.from(data['responderPresence'] as Map)
            : <String, dynamic>{};
        presence.remove(safeResponderUid);
        final onlineCount =
            presence.values.where((value) => value == true).length;

        transaction.set(
          ref,
          <String, dynamic>{
            'participants': updatedParticipants,
            'participantUids': updatedParticipantUids.toList(),
            'responderPresence': presence,
            'onlineCount': onlineCount,
          },
          SetOptions(merge: true),
        );
      });
    });
  }

  Future<bool> deleteMessageWithMedia({
    required String sosId,
    required String messageId,
    required String requestedByUid,
    bool deleteMediaFromCloudinary = true,
  }) async {
    final safeSosId = sosId.trim();
    final safeMessageId = messageId.trim();
    final safeRequestedByUid = requestedByUid.trim();
    if (safeSosId.isEmpty ||
        safeMessageId.isEmpty ||
        safeRequestedByUid.isEmpty) {
      return false;
    }

    final messageRef = messagesRef(safeSosId).doc(safeMessageId);
    final messageSnapshot = await _withFirestoreRetry(() => messageRef.get());
    final messageData = messageSnapshot.data();
    if (messageData == null) {
      return false;
    }

    final senderUid = (messageData['senderUid'] as String?)?.trim() ?? '';
    final requesterIsSender = senderUid == safeRequestedByUid;

    if (!requesterIsSender) {
      return false;
    }

    if (deleteMediaFromCloudinary) {
      await _deleteMediaForMessageData(messageData);
    }

    await _withFirestoreRetry(() => messageRef.delete());
    return true;
  }

  Future<void> addSystemStatusMessage({
    required String sosId,
    required String text,
    required String statusType,
    String? actorUid,
    String? actorName,
  }) async {
    final safeSosId = sosId.trim();
    final safeText = text.trim();
    final safeStatusType = statusType.trim();
    if (safeSosId.isEmpty || safeText.isEmpty || safeStatusType.isEmpty) {
      return;
    }

    final messageDoc = messagesRef(safeSosId).doc();
    await _withFirestoreRetry(() async {
      await messageDoc.set(<String, dynamic>{
        'text': safeText,
        'type': 'system',
        'statusType': safeStatusType,
        'senderUid': _systemSenderUid,
        'senderRole': 'system',
        'senderName': _systemSenderName,
        'isSystem': true,
        'actorUid': actorUid?.trim(),
        'actorName': actorName?.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> addResponderJoinedSystemMessage({
    required String sosId,
    required String responderUid,
    required String responderName,
  }) {
    final safeName =
        _safeDisplayName(responderName, fallback: responderUid.trim());
    return addSystemStatusMessage(
      sosId: sosId,
      text: 'Responder $safeName joined the conversation',
      statusType: 'responder_joined',
      actorUid: responderUid,
      actorName: safeName,
    );
  }

  Future<void> addResponderLeftSystemMessage({
    required String sosId,
    required String responderUid,
    String? responderName,
  }) async {
    final safeName =
        _safeDisplayName(responderName, fallback: responderUid.trim());

    await addSystemStatusMessage(
      sosId: sosId,
      text: 'Responder $safeName left the conversation',
      statusType: 'responder_left',
      actorUid: responderUid,
      actorName: safeName,
    );
  }

  Future<void> addAiAssistingSystemMessage({
    required String sosId,
  }) {
    return addSystemStatusMessage(
      sosId: sosId,
      text: 'AI is now assisting',
      statusType: 'ai_assisting',
      actorUid: _aiUid,
      actorName: _aiDisplayName,
    );
  }

  Future<bool> _sendAiMessage({
    required String sosId,
    required String text,
    required String requesterUid,
    bool allowNonParticipantRequester = false,
  }) async {
    final safeText = text.length > _maxAiMessageLength
      ? text.substring(0, _maxAiMessageLength)
        : text;
    if (safeText.trim().isEmpty) {
      return false;
    }

    final chat = chatRef(sosId);
    final messageDoc = messagesRef(sosId).doc();
    var wroteMessage = false;

    try {
      await _withFirestoreRetry(() async {
        await _firestore.runTransaction((transaction) async {
          final chatSnapshot = await transaction.get(chat);
          final chatData = chatSnapshot.data() ?? <String, dynamic>{};
          final status = (chatData['status'] as String?) ?? 'active';
          if (status == 'cancelled') {
            return;
          }

          final participantUids = _extractParticipantUids(chatData);
          if (!participantUids.contains(requesterUid) &&
              !allowNonParticipantRequester) {
            return;
          }

          transaction.set(messageDoc, <String, dynamic>{
            'text': safeText,
            'senderUid': _aiUid,
            'senderRole': 'responder',
            'senderName': _aiDisplayName,
            'isAi': true,
            'requestedByUid': requesterUid,
            'createdAt': FieldValue.serverTimestamp(),
            'type': 'text',
          });

          // Stamp the AI source on the parent chat doc for AppBar badge
          final sourceMatch = RegExp(r'\[\[AI_SOURCE:(GEMINI|BUILTIN)\]\]').firstMatch(safeText);
          final aiSource = sourceMatch?.group(1) ?? 'BUILTIN';
          transaction.update(chat, <String, dynamic>{
            'lastAiSource': aiSource,
          });

          wroteMessage = true;
        });
      });
    } catch (_) {
      try {
        await _withFirestoreRetry(() async {
          await messageDoc.set(<String, dynamic>{
            'text': safeText,
            'senderUid': _aiUid,
            'senderRole': 'responder',
            'senderName': _aiDisplayName,
            'isAi': true,
            'requestedByUid': requesterUid,
            'createdAt': FieldValue.serverTimestamp(),
            'type': 'text',
          });
        });
        wroteMessage = true;
      } catch (error) {
        if (error is FirebaseException) {
          _setLastAiFailure(
            'AI chat write rejected (${error.code}). ${error.message ?? 'Check Firestore rules and deployment.'}',
          );
          debugPrint(
            'AI message write failed for chat $sosId: ${error.code} ${error.message}',
          );
        } else {
          _setLastAiFailure(
            'AI chat write failed. Check Firestore rules and deployment.',
          );
          debugPrint('AI message write failed for chat $sosId: $error');
        }
        return false;
      }
    }

    if (!wroteMessage) {
      _setLastAiFailure(
        _lastAiFailure ??
            'AI message was not written. Check participant access and chat status.',
      );
      return false;
    }

    try {
      final aiAssistAlreadySent = await _hasAiAssistSystemMessage(sosId);
      if (!aiAssistAlreadySent) {
        await addAiAssistingSystemMessage(sosId: sosId);
      }
    } catch (_) {
      // Best-effort only.
    }

    _setLastAiFailure(null);
    return true;
  }

  Future<bool> _sendFallbackAiMessage({
    required String sosId,
    required String text,
    required String requesterUid,
  }) async {
    final safeText = text.length > _maxAiMessageLength
      ? text.substring(0, _maxAiMessageLength)
        : text;
    if (safeText.trim().isEmpty) {
      return false;
    }

    try {
      await _withFirestoreRetry(() async {
        await messagesRef(sosId).doc().set(<String, dynamic>{
          'text': safeText,
          'senderUid': _aiUid,
          'senderRole': 'responder',
          'senderName': _aiDisplayName,
          'isAi': true,
          'requestedByUid': requesterUid,
          'createdAt': FieldValue.serverTimestamp(),
          'type': 'text',
        });
      });
      _setLastAiFailure(null);
      return true;
    } catch (error) {
      if (error is FirebaseException) {
        _setLastAiFailure(
          'Fallback AI write failed (${error.code}). ${error.message ?? 'Check Firestore rules and deployment.'}',
        );
        debugPrint(
          'Fallback AI message write failed for chat $sosId: ${error.code} ${error.message}',
        );
      } else {
        _setLastAiFailure(
          'Fallback AI write failed. Check Firestore rules and deployment.',
        );
        debugPrint('Fallback AI message write failed for chat $sosId: $error');
      }
      return false;
    }
  }

  Future<bool> _hasAiAssistSystemMessage(String sosId) async {
    final snapshot = await _withFirestoreRetry(
      () => messagesRef(sosId)
          .where('type', isEqualTo: 'system')
          .where('statusType', isEqualTo: 'ai_assisting')
          .limit(1)
          .get(),
    );

    return snapshot.docs.isNotEmpty;
  }

  Future<bool> _hasAiAutoMessage(String sosId) async {
    final snapshot = await _withFirestoreRetry(
      () => messagesRef(sosId)
          .where('senderName', isEqualTo: _aiDisplayName)
          .orderBy('createdAt', descending: true)
          .limit(20)
          .get(),
    );

    return snapshot.docs.isNotEmpty;
  }

  String? _resolveVictimUid(Map<String, dynamic> chatData) {
    final participants = _asMapList(chatData['participants']);
    for (final entry in participants) {
      if ((entry['role'] as String?) == 'victim') {
        final uid = (entry['uid'] as String?)?.trim();
        if (uid != null && uid.isNotEmpty) {
          return uid;
        }
      }
    }

    final participantUids = _extractParticipantUids(chatData);
    for (final uid in participantUids) {
      if (uid != _aiUid) {
        return uid;
      }
    }
    return null;
  }

  bool _hasHumanResponder(Map<String, dynamic> chatData) {
    final participants = _asMapList(chatData['participants']);
    return participants.any(
      (entry) =>
          (entry['role'] as String?) == 'responder' && entry['isAi'] != true,
    );
  }

  Future<List<Map<String, dynamic>>> _fetchRecentMessages(
    String sosId, {
    required int limit,
  }) async {
    final snapshot = await _withFirestoreRetry(
      () => messagesRef(sosId)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get(const GetOptions(source: Source.serverAndCache)),
    );

    return snapshot.docs
        .map((doc) => doc.data())
        .toList()
        .reversed
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  String _buildAiPrompt({
    required Map<String, dynamic> chatData,
    required List<Map<String, dynamic>> recentMessages,
    required Map<String, dynamic> emergencyContext,
    required String requesterName,
    required String requesterRole,
    required String userPrompt,
    required String? imageDescription,
    required String? voiceTranscript,
    required String askReason,
  }) {
    final overview = chatData['sosOverview'] is Map
        ? Map<String, dynamic>.from(chatData['sosOverview'] as Map)
        : <String, dynamic>{};

    final overviewMessage = (overview['message'] as String?) ?? '';
    final mediaRefs = _collectMediaReferences(
      overview: overview,
      recentMessages: recentMessages,
    );

    final historyLines = recentMessages.map((message) {
      final sender = (message['senderName'] as String?) ??
          (message['senderUid'] as String?) ??
          'Unknown';
      final text = ((message['text'] as String?) ?? '').trim();
      if (text.isEmpty) {
        return '- $sender: [non-text message]';
      }
      return '- $sender: $text';
    }).join('\n');

    final imageSection = (imageDescription ?? '').trim().isEmpty
        ? 'none'
        : imageDescription!.trim();
    final voiceSection = (voiceTranscript ?? '').trim().isEmpty
        ? 'none'
        : voiceTranscript!.trim();

    final mediaSection = mediaRefs.isEmpty ? 'none' : mediaRefs.join('\n');
    final mergedContextText =
        '$userPrompt\n$overviewMessage\n${_summarizeEmergencyContext(emergencyContext)}';
    final countryHint = _inferCountryHint(
      prompt: mergedContextText,
      emergencyContext: emergencyContext,
    );
    final emergencyNumberHint = _resolveEmergencyNumber(
      mergedContextText.toLowerCase(),
      countryHint: countryHint,
    );
    final preferredLanguageCode = _resolvePreferredLanguageCode(
      userPrompt: userPrompt,
      recentMessages: recentMessages,
      emergencyContext: emergencyContext,
    );
    final preferredLanguageLabel = _languageLabelForCode(preferredLanguageCode);

    final trustedVideoIds = _crisisTypeToYoutubeVideoId.values.toSet().join(', ');

    return '''
You are RescueLink AI assisting in an emergency group chat.
Keep responses practical, calm, and safety-first.
Do not claim to dispatch responders. If danger is immediate, instruct user to call the local emergency service.
You are assisting a user in ${countryHint.isEmpty ? 'an unknown country' : countryHint}. The correct emergency number for this region is $emergencyNumberHint.
NEVER suggest calling 911 unless the user is explicitly located in the US/Canada. Keep answers localized correctly.
Respond entirely in $preferredLanguageLabel (${preferredLanguageCode.toUpperCase()}) unless user explicitly asks to switch language.
Write in a polished assistant style using short bullets, bold emphasis for key actions, and clear section labels.
Keep response compact but complete. Do not stop early or leave steps unfinished.
Use short bullets and clear section labels, but use as many lines as needed to fully answer.

CRITICAL CREDIBILITY & VIDEO SAFETY RULE:
Only provide offline, credible map scenarios and fully verified steps. NEVER hallucinate protocols.
Only suggest YouTube videos from this EXACT allowlist of verified, playable video IDs: $trustedVideoIds
NEVER invent YouTube URLs or video IDs. NEVER suggest untrusted or unavailable videos.
If the crisis type does not match any trusted video, omit video suggestions entirely.
If the query is about period pain, menstrual cramps, PMS, or routine cycle symptoms, do NOT suggest CPR or trauma-control videos.
Format video suggestions as: https://www.youtube.com/watch?v=[videoId] where [videoId] is EXACTLY one of: $trustedVideoIds

Conversation context:
- Trigger: $askReason
- Requester name: ${requesterName.trim().isEmpty ? 'Unknown' : requesterName.trim()}
- Requester role: ${_normalizeRole(requesterRole)}
- SOS overview: ${overviewMessage.trim().isEmpty ? 'none' : overviewMessage.trim()}
- Image description: $imageSection
- Voice transcript: $voiceSection
- Preferred response language: $preferredLanguageLabel (${preferredLanguageCode.toUpperCase()})
- Locality hint: ${_summarizeEmergencyContext(emergencyContext)}
- Media references:\n$mediaSection

Recent chat history (oldest to newest):
$historyLines

User request to AI:
$userPrompt

Respond in concise plain text with:
Immediate actions:
What to avoid:
What to share with responders:
Complete the full answer before stopping.
''';
  }

  Future<Map<String, dynamic>> _loadEmergencyContext(String sosId) async {
    final safeSosId = sosId.trim();
    if (safeSosId.isEmpty) {
      return const <String, dynamic>{};
    }

    try {
      final snapshot = await _withFirestoreRetry(
        () => _firestore
            .collection('emergency_requests')
            .doc(safeSosId)
            .get(const GetOptions(source: Source.serverAndCache)),
      );
      final data = snapshot.data();
      if (data == null) {
        return const <String, dynamic>{};
      }
      return Map<String, dynamic>.from(data);
    } catch (_) {
      return const <String, dynamic>{};
    }
  }

  String _inferCountryHint({
    required String prompt,
    required Map<String, dynamic> emergencyContext,
  }) {
    final explicitCountryCode =
        (emergencyContext['countryCode'] as String?)?.trim().toUpperCase();
    if (explicitCountryCode != null && explicitCountryCode.isNotEmpty) {
      return explicitCountryCode;
    }

    final promptCountry = RegExp(
      r'\b(india|us|usa|canada|uk|united kingdom|australia|new zealand|europe|eu)\b',
      caseSensitive: false,
    ).firstMatch(prompt);
    if (promptCountry != null) {
      return promptCountry.group(1)!.trim().toUpperCase();
    }

    final lat = (emergencyContext['latitude'] as num?)?.toDouble();
    final lng = (emergencyContext['longitude'] as num?)?.toDouble();
    final byCoords = _countryFromCoordinates(lat, lng);
    if (byCoords != null) {
      return byCoords;
    }

    return PlatformDispatcher.instance.locale.countryCode?.trim().toUpperCase() ??
        '';
  }

  String? _countryFromCoordinates(double? lat, double? lng) {
    if (lat == null || lng == null) {
      return null;
    }

    if (lat >= 6 && lat <= 38 && lng >= 68 && lng <= 98) {
      return 'IN';
    }
    if (lat >= 24 && lat <= 50 && lng >= -125 && lng <= -66) {
      return 'US';
    }
    if (lat >= 49 && lat <= 61 && lng >= -11 && lng <= 2) {
      return 'UK';
    }
    if (lat >= -44 && lat <= -10 && lng >= 112 && lng <= 154) {
      return 'AU';
    }
    if (lat >= -48 && lat <= -34 && lng >= 166 && lng <= 179) {
      return 'NZ';
    }

    return null;
  }

  String _resolvePreferredLanguageCode({
    required String userPrompt,
    required List<Map<String, dynamic>> recentMessages,
    required Map<String, dynamic> emergencyContext,
  }) {
    final explicit = (emergencyContext['languageCode'] as String?)?.trim();
    if (explicit != null && <String>{'en', 'hi', 'ta'}.contains(explicit)) {
      return explicit;
    }

    final merged = <String>[
      userPrompt,
      ...recentMessages
          .map((m) => (m['text'] as String?) ?? '')
          .where((t) => t.trim().isNotEmpty)
          .take(12),
    ].join('\n');
    final lower = merged.toLowerCase();

    if (RegExp(r'\b(tamil|தமிழ்)\b', caseSensitive: false).hasMatch(lower) ||
        RegExp(r'[\u0B80-\u0BFF]').hasMatch(merged)) {
      return 'ta';
    }

    if (RegExp(r'\b(hindi|हिंदी)\b', caseSensitive: false).hasMatch(lower) ||
        RegExp(r'[\u0900-\u097F]').hasMatch(merged)) {
      return 'hi';
    }

    if (RegExp(r'\benglish\b', caseSensitive: false).hasMatch(lower)) {
      return 'en';
    }

    final localeLang = PlatformDispatcher.instance.locale.languageCode
        .trim()
        .toLowerCase();
    if (<String>{'en', 'hi', 'ta'}.contains(localeLang)) {
      return localeLang;
    }

    return 'en';
  }

  String _languageLabelForCode(String code) {
    switch (code.toLowerCase()) {
      case 'hi':
        return 'Hindi';
      case 'ta':
        return 'Tamil';
      case 'en':
      default:
        return 'English';
    }
  }

  String _summarizeEmergencyContext(Map<String, dynamic> emergencyContext) {
    if (emergencyContext.isEmpty) {
      return 'none';
    }

    final parts = <String>[];
    final lat = (emergencyContext['latitude'] as num?)?.toDouble();
    final lng = (emergencyContext['longitude'] as num?)?.toDouble();
    if (lat != null && lng != null) {
      parts.add('lat=${lat.toStringAsFixed(4)}, lng=${lng.toStringAsFixed(4)}');
    }

    final countryCode = (emergencyContext['countryCode'] as String?)?.trim();
    if (countryCode != null && countryCode.isNotEmpty) {
      parts.add('country=$countryCode');
    }

    final languageCode = (emergencyContext['languageCode'] as String?)?.trim();
    if (languageCode != null && languageCode.isNotEmpty) {
      parts.add('language=$languageCode');
    }

    return parts.isEmpty ? 'none' : parts.join(' | ');
  }

  List<String> _collectMediaReferences({
    required Map<String, dynamic> overview,
    required List<Map<String, dynamic>> recentMessages,
  }) {
    final refs = <String>[];

    final overviewMedia = _asMapList(overview['media']);
    for (final item in overviewMedia) {
      final type = (item['type'] as String?) ?? 'media';
      final url = (item['url'] as String?) ?? '';
      if (url.isNotEmpty) {
        refs.add('- overview $type: $url');
      }
    }

    for (final message in recentMessages) {
      final sender = (message['senderName'] as String?) ?? 'Unknown';

      final attachmentUrl = (message['attachmentUrl'] as String?) ?? '';
      if (attachmentUrl.isNotEmpty) {
        refs.add('- message from $sender attachment: $attachmentUrl');
      }

      final voiceAudioUrl = (message['voiceAudioUrl'] as String?) ?? '';
      if (voiceAudioUrl.isNotEmpty) {
        refs.add('- message from $sender voice: $voiceAudioUrl');
      }

      final mediaItems = _asMapList(message['media']);
      for (final item in mediaItems) {
        final type = (item['type'] as String?) ?? 'media';
        final url = (item['url'] as String?) ?? '';
        if (url.isNotEmpty) {
          refs.add('- message from $sender $type: $url');
        }
      }
    }

    return refs;
  }

  Future<_AiGenerationOutcome> _generateAiReply(String prompt) async {
    if (_geminiApiKey.isEmpty) {
      _logGeminiStatus('missing_api_key');
      return const _AiGenerationOutcome.failure(
        code: 'missing_api_key',
        userMessage:
            'Gemini API key is missing. Run with --dart-define=GEMINI_API_KEY=... or --dart-define-from-file=env/dev.json.',
      );
    }

    _logGeminiStatus(
      'gemini_request_start',
      error:
          'models=${_geminiModelCandidates.join(',')} key_prefix=${_redactApiKey(_geminiApiKey)}',
    );

    var bestFailure = const _GeminiFailure(
      code: 'gemini_error',
      userMessage: 'Gemini API call failed.',
    );

    for (final modelName in _geminiModelCandidates) {
      try {
        final model = GenerativeModel(
          model: modelName,
          apiKey: _geminiApiKey,
          generationConfig: GenerationConfig(
            candidateCount: 1,
            maxOutputTokens: 4096,
            temperature: 0.2,
            topP: 0.95,
            topK: 40,
          ),
        );
        final response = await model
            .generateContent(<Content>[Content.text(prompt)])
            .timeout(_geminiTimeout);
        final text = response.text?.trim() ?? '';

        if (text.isEmpty) {
          bestFailure = _pickMoreUsefulFailure(
            bestFailure,
            const _GeminiFailure(
              code: 'gemini_empty_response',
              userMessage:
                  'Gemini returned an empty response. Please retry shortly.',
            ),
          );
          _logGeminiStatus('gemini_empty_response', model: modelName);
          continue;
        }

        _logGeminiStatus('gemini_success', model: modelName);
        return _AiGenerationOutcome.success(
          text: text,
          modelUsed: modelName,
        );
      } on TimeoutException catch (e) {
        bestFailure = _pickMoreUsefulFailure(
          bestFailure,
          const _GeminiFailure(
            code: 'gemini_timeout',
            userMessage:
                'Gemini request timed out. Network may be slow or unavailable.',
          ),
        );
        _logGeminiStatus('gemini_timeout', model: modelName, error: e);
      } catch (e) {
        final mapped = _classifyGeminiFailure(e);
        bestFailure = _pickMoreUsefulFailure(bestFailure, mapped);
        _logGeminiStatus(
          mapped.code,
          model: modelName,
          error: '${mapped.userMessage} | raw=$e',
        );
      }
    }

    return _AiGenerationOutcome.failure(
      code: bestFailure.code,
      userMessage: bestFailure.userMessage,
    );
  }

  _GeminiFailure _pickMoreUsefulFailure(
    _GeminiFailure current,
    _GeminiFailure candidate,
  ) {
    final currentPriority = _failurePriority(current.code);
    final candidatePriority = _failurePriority(candidate.code);
    return candidatePriority > currentPriority ? candidate : current;
  }

  int _failurePriority(String code) {
    switch (code) {
      case 'missing_api_key':
      case 'gemini_auth_error':
      case 'gemini_quota_exceeded':
      case 'gemini_offline':
      case 'gemini_timeout':
      case 'gemini_service_unavailable':
        return 5;
      case 'gemini_model_unavailable':
        return 3;
      case 'gemini_empty_response':
        return 2;
      case 'gemini_error':
      default:
        return 1;
    }
  }

  String _maybeAppendVisualGuidance({
    required String userPrompt,
    required String aiText,
  }) {
    final links = _trustedVisualLinksForPrompt(userPrompt);

    if (links.isEmpty) {
      return aiText;
    }

    final uniqueLinks = links.toSet().toList();
    final linkLines = uniqueLinks.map((url) => '- $url').join('\n');
    return '$aiText\n\nVisual guides (trusted YouTube videos):\n$linkLines';
  }

  bool _isEmergencyIntent(String prompt) {
    return prompt.contains('emergency') ||
        prompt.contains('urgent') ||
        prompt.contains('help now') ||
        prompt.contains('immediate help') ||
        prompt.contains('accident') ||
        prompt.contains('unconscious') ||
        prompt.contains('not breathing') ||
        prompt.contains('breathing problem') ||
        prompt.contains('shortness of breath') ||
        prompt.contains('severe pain') ||
        prompt.contains('heavy bleeding') ||
        prompt.contains('injured') ||
        prompt.contains('injury') ||
        prompt.contains('collapsed') ||
        prompt.contains('fainted') ||
        prompt.contains('critical') ||
        prompt.contains('danger') ||
        prompt.contains('life threat') ||
        prompt.contains('ambulance') ||
        prompt.contains('first aid') ||
        prompt.contains('cannot move') ||
        prompt.contains('disoriented') ||
        prompt.contains('rescue');
  }

  String _resolveEmergencyNumber(
    String prompt, {
    String? countryHint,
  }) {
    final countryCode =
        PlatformDispatcher.instance.locale.countryCode?.trim().toUpperCase() ??
            '';

    final promptCountry = RegExp(
          r'\b(india|us|usa|canada|uk|united kingdom|australia|new zealand|europe|eu)\b',
          caseSensitive: false,
        ).firstMatch(prompt)?.group(1)?.toLowerCase() ??
        '';

    final explicitHint = countryHint?.trim().toLowerCase() ?? '';
    final effectiveCountry = explicitHint.isNotEmpty
      ? explicitHint
      : (promptCountry.isNotEmpty ? promptCountry : countryCode.toLowerCase());

    switch (effectiveCountry) {
      case 'india':
      case 'in':
      case 'eu':
      case 'europe':
        return '112';
      case 'united kingdom':
      case 'uk':
      case 'gb':
        return '999';
      case 'au':
        return '000';
      case 'nz':
        return '111';
      case 'us':
      case 'usa':
      case 'ca':
        return '911';
      default:
        return '112';
    }
  }

  String _resolveEmergencyServiceLabel(String prompt) {
    if (prompt.contains('fire') || prompt.contains('smoke')) {
      return 'fire services';
    }
    if (prompt.contains('cpr') ||
        prompt.contains('cardiac') ||
        prompt.contains('drown') ||
        prompt.contains('breathing') ||
        prompt.contains('medical') ||
        prompt.contains('injur')) {
      return 'ambulance / medical help';
    }
    if (prompt.contains('women safety') ||
        prompt.contains('assault') ||
        prompt.contains('abuse') ||
        prompt.contains('stalk') ||
        prompt.contains('choking') ||
        prompt.contains('crime')) {
      return 'police / emergency help';
    }
    return 'emergency services';
  }

  List<String> _trustedVisualLinksForPrompt(String userPrompt) {
    final prompt = userPrompt.toLowerCase();
    final matchedVideoIds = <String>{};

    _crisisTypeToYoutubeVideoId.forEach((crisisType, videoId) {
      if (prompt.contains(crisisType)) {
        matchedVideoIds.add(videoId);
      }
    });

    if (matchedVideoIds.isEmpty) {
      return const <String>[];
    }

    return matchedVideoIds
        .map((videoId) => 'https://www.youtube.com/watch?v=$videoId')
        .toList();
  }

  /// Removes YouTube URLs from [text] that are not in the trusted allowlist.
  /// Preserves all other content (paragraphs, instructions, phone numbers, etc.).
  /// Only keeps: https://www.youtube.com/watch?v=[trusted-id] or https://youtu.be/[trusted-id]
  String _sanitizeYoutubeLinksInAiResponse(
    String text, {
    String contextPrompt = '',
  }) {
    if (text.isEmpty) {
      return text;
    }

    final trustedLinksForContext =
        _trustedVisualLinksForPrompt(contextPrompt).toSet();
    final trustedIds = trustedLinksForContext
        .map(
          (url) => RegExp(r'v=([A-Za-z0-9_-]{11})').firstMatch(url)?.group(1),
        )
        .whereType<String>()
        .toSet();

    // If the context does not map to any trusted video, remove all YouTube links.
    if (trustedIds.isEmpty) {
      return text
          .split('\n')
          .map((line) => line
              .replaceAll(
                RegExp(
                  r'https?:\/\/(?:www\.)?youtube\.com\/watch\?v=[A-Za-z0-9_-]{11}',
                  caseSensitive: false,
                ),
                '',
              )
              .replaceAll(
                RegExp(
                  r'https?:\/\/youtu\.be\/[A-Za-z0-9_-]{11}',
                  caseSensitive: false,
                ),
                '',
              )
              .trim())
          .where((line) => line.isNotEmpty)
          .join('\n');
    }

    final lines = text.split('\n');
    final sanitized = <String>[];

    for (final line in lines) {
      // Check if line contains a YouTube URL
      final watchMatch = RegExp(
        r'(https?:\/\/(?:www\.)?youtube\.com\/watch\?v=([A-Za-z0-9_-]{11}))',
        caseSensitive: false,
      ).firstMatch(line);
      final shortMatch = RegExp(
        r'(https?:\/\/youtu\.be\/([A-Za-z0-9_-]{11}))',
        caseSensitive: false,
      ).firstMatch(line);

      if (watchMatch != null) {
        final videoId = watchMatch.group(2) ?? '';
        if (trustedIds.contains(videoId)) {
          // Keep trusted video URL
          sanitized.add(line);
        } else {
          // Remove untrusted video URL, keep rest of line if any
          final beforeUrl = line.substring(0, watchMatch.start).trim();
          final afterUrl = line.substring(watchMatch.end).trim();
          final remainder =
              <String>[beforeUrl, afterUrl].where((s) => s.isNotEmpty).join(' ');
          if (remainder.isNotEmpty) {
            sanitized.add(remainder);
          }
        }
      } else if (shortMatch != null) {
        final videoId = shortMatch.group(2) ?? '';
        if (trustedIds.contains(videoId)) {
          // Keep trusted video URL
          sanitized.add(line);
        } else {
          // Remove untrusted video URL, keep rest of line if any
          final beforeUrl = line.substring(0, shortMatch.start).trim();
          final afterUrl = line.substring(shortMatch.end).trim();
          final remainder =
              <String>[beforeUrl, afterUrl].where((s) => s.isNotEmpty).join(' ');
          if (remainder.isNotEmpty) {
            sanitized.add(remainder);
          }
        }
      } else {
        // No YouTube URL in this line, keep as-is
        sanitized.add(line);
      }
    }

    return sanitized.join('\n');
  }

  String _buildScenarioFallback({
    required String userPrompt,
    required String contextSummary,
    required Map<String, dynamic> emergencyContext,
  }) {
    final prompt = userPrompt.toLowerCase();
    final context = contextSummary.trim();
    final likelyEmergency = _isEmergencyIntent(prompt);
    final countryHint = _inferCountryHint(
      prompt: '$prompt ${context.toLowerCase()}',
      emergencyContext: emergencyContext,
    );
    final emergencyNumber = _resolveEmergencyNumber(
      prompt,
      countryHint: countryHint,
    );
    final emergencyService = _resolveEmergencyServiceLabel(prompt);

    String title = 'Built-in emergency guidance';
    final steps = <String>[];
    final avoid = <String>[];
    final share = <String>[];
    final links = <String>[];
    final clarifying = <String>[];

    void addDefaultShare() {
      share.addAll(<String>[
        'Exact location and nearby landmarks.',
        'Number of injured people and major symptoms.',
        'Visible hazards (fire, smoke, water current, animals, chemicals).',
      ]);
    }

    if (prompt.contains('fire') || prompt.contains('extinguisher')) {
      title = 'Built-in: Fire / extinguisher';
      steps.addAll(<String>[
        'Alert everyone and keep an exit behind you.',
        'If it is a small, contained fire, use PASS: Pull pin, Aim at the base, Squeeze the handle, Sweep side to side.',
        'If the fire is spreading, the room is filling with smoke, or you are unsure of the fire type, evacuate immediately and call ${_resolveEmergencyNumber(prompt)} for ${_resolveEmergencyServiceLabel(prompt)}.',
      ]);
      avoid.addAll(<String>[
        'Do not fight large or spreading fires alone.',
        'Do not use water on electrical or oil fires.',
        'Do not open hot doors if smoke or heat is coming through.',
      ]);
      links.add(
        'https://www.youtube.com/watch?v=Y107-A8Ny-4',
      );
      links.add(
        'https://www.youtube.com/watch?v=PQV71INDaqY',
      );
      addDefaultShare();
    } else if (prompt.contains('drown') || prompt.contains('water rescue')) {
      title = 'Built-in: Drowning / water rescue';
      steps.addAll(<String>[
        'Call ${_resolveEmergencyNumber(prompt)} for ${_resolveEmergencyServiceLabel(prompt)} immediately.',
        'Use reach/throw methods (rope, float) before entering water.',
        'If person is out of water and not breathing, start CPR if trained.',
      ]);
      avoid.addAll(<String>[
        'Do not jump into unsafe current without rescue support.',
        'Do not delay emergency call while searching equipment.',
      ]);
      links.add(
        'https://www.youtube.com/results?search_query=Red+Cross+drowning+first+aid',
      );
      addDefaultShare();
    } else if (prompt.contains('cpr') || prompt.contains('cardiac')) {
      title = 'Built-in: CPR';
      steps.addAll(<String>[
        'Call ${_resolveEmergencyNumber(prompt)} for ${_resolveEmergencyServiceLabel(prompt)} and ask someone to get an AED.',
        'Start chest compressions hard and fast in center of chest.',
        'Use AED prompts as soon as available.',
      ]);
      avoid.addAll(<String>[
        'Do not stop compressions for long pauses.',
        'Do not move person unless area is unsafe.',
      ]);
      links.add(
        'https://www.youtube.com/results?search_query=American+Heart+Association+hands+only+CPR',
      );
      addDefaultShare();
    } else if (prompt.contains('snake')) {
      title = 'Built-in: Snake bite';
      steps.addAll(<String>[
        'Keep person calm and bitten limb still, below heart level if possible.',
        'Remove rings/tight items near swelling area.',
        'Get emergency medical care immediately.',
      ]);
      avoid.addAll(<String>[
        'Do not cut/suck wound or apply ice.',
        'Do not apply tight tourniquet unless instructed by professionals.',
      ]);
      links.add(
        'https://www.youtube.com/results?search_query=WHO+snake+bite+first+aid',
      );
      addDefaultShare();
    } else if (prompt.contains('bee') ||
        prompt.contains('wasp') ||
        prompt.contains('sting')) {
      title = 'Built-in: Bee/wasp stings';
      steps.addAll(<String>[
        'Move away from area and remove stinger by scraping edge (if visible).',
        'Wash area and apply cold pack for swelling.',
        'If breathing trouble, facial swelling, or dizziness occurs: emergency care now.',
      ]);
      avoid.addAll(<String>[
        'Do not squeeze venom sac when removing stinger.',
        'Do not ignore signs of anaphylaxis.',
      ]);
      links.add(
        'https://www.youtube.com/results?search_query=Mayo+Clinic+bee+sting+first+aid',
      );
      addDefaultShare();
    } else if (prompt.contains('insulin') ||
        prompt.contains('diabetes') ||
        prompt.contains('hypogly') ||
        prompt.contains('low sugar') ||
        prompt.contains('high sugar')) {
      title = 'Built-in: Diabetes / insulin emergency';
      steps.addAll(<String>[
        'If conscious and low sugar suspected, give fast sugar (juice, glucose tabs).',
        'Recheck symptoms after 15 minutes; repeat sugar if needed.',
        'If drowsy/unconscious or worsening, seek emergency care now.',
      ]);
      avoid.addAll(<String>[
        'Do not force food or drink into an unconscious person.',
        'Do not delay emergency help if confusion/seizure occurs.',
      ]);
      links.add(
        'https://www.youtube.com/results?search_query=American+Diabetes+Association+hypoglycemia+first+aid',
      );
      addDefaultShare();
    } else if (prompt.contains('pregnan') ||
        prompt.contains('water break') ||
        prompt.contains('labor') ||
        prompt.contains('labour') ||
        prompt.contains('contraction')) {
      title = 'Built-in: Pregnancy labor / water break';
      steps.addAll(<String>[
        'Track contraction timing and fluid color/amount.',
        'Prepare transport to hospital or call emergency support if rapid progression.',
        'Keep mother hydrated, comfortable, and under observation.',
      ]);
      avoid.addAll(<String>[
        'Do not insert anything vaginally after water breaks.',
        'Do not wait at home if heavy bleeding, severe pain, fever, or reduced fetal movement.',
      ]);
      links.add(
        'https://www.youtube.com/results?search_query=ACOG+labor+warning+signs+when+to+go+hospital',
      );
      share.addAll(<String>[
        'Pregnancy week and contraction intervals.',
        'Any bleeding, fluid color, fever, or severe pain.',
      ]);
      addDefaultShare();
    } else if (prompt.contains('women safety') ||
        prompt.contains('harass') ||
        prompt.contains('assault') ||
        prompt.contains('stalk') ||
        prompt.contains('abuse')) {
      title = 'Built-in: Women safety emergency';
      steps.addAll(<String>[
        'Move to a public, well-lit place near trusted people if possible.',
        'Call ${_resolveEmergencyNumber(prompt)} for ${_resolveEmergencyServiceLabel(prompt)} and contact a trusted person immediately.',
        'Preserve evidence (messages, photos, location timeline) when safe.',
      ]);
      avoid.addAll(<String>[
        'Do not confront aggressor alone in isolated areas.',
        'Do not delete evidence that may help legal reporting.',
      ]);
      links.add(
        'https://www.youtube.com/results?search_query=UN+Women+safety+tips+violence+response',
      );
      share.addAll(<String>[
        'Current location and suspect description (if safe to share).',
        'Direction of movement and immediate risk level.',
      ]);
      addDefaultShare();
    } else if (prompt.contains('anxiety') ||
        prompt.contains('panic') ||
        prompt.contains('panic attack')) {
      title = 'Built-in: Anxiety / panic attack';
      steps.addAll(<String>[
        'Guide slow breathing: inhale 4 sec, exhale 6 sec for a few minutes.',
        'Use grounding: name 5 things you see, 4 touch, 3 hear, 2 smell, 1 taste.',
        'Move to a quiet, safe place and stay with a trusted person if available.',
      ]);
      avoid.addAll(<String>[
        'Do not force rapid movement or crowded stimuli.',
        'Do not ignore chest pain or fainting; seek emergency help if severe.',
      ]);
      links.add(
        'https://www.youtube.com/results?search_query=NHS+panic+attack+grounding+breathing+technique',
      );
      addDefaultShare();
    } else if (prompt.contains('stroke')) {
      title = 'Built-in: Stroke warning signs';
      steps.addAll(<String>[
        'Use FAST check: Face droop, Arm weakness, Speech difficulty, Time to call emergency.',
        'Keep person seated and monitored until help arrives.',
        'Note the time symptoms started.',
      ]);
      avoid.addAll(<String>[
        'Do not give food, drink, or random medicines.',
        'Do not wait for symptoms to pass.',
      ]);
      links.add(
        'https://www.youtube.com/results?search_query=American+Stroke+Association+FAST+warning+signs',
      );
      addDefaultShare();
    } else if (prompt.contains('seizure') || prompt.contains('epilep')) {
      title = 'Built-in: Seizure first aid';
      steps.addAll(<String>[
        'Protect head, clear nearby hard objects, and time the seizure.',
        'After convulsions stop, place person on their side.',
        'Call emergency if seizure lasts >5 minutes or repeats.',
      ]);
      avoid.addAll(<String>[
        'Do not restrain movements.',
        'Do not put anything in the mouth.',
      ]);
      links.add(
        'https://www.youtube.com/results?search_query=Epilepsy+Foundation+seizure+first+aid',
      );
      addDefaultShare();
    } else if (prompt.contains('choking') || prompt.contains('heimlich')) {
      title = 'Built-in: Choking first aid';
      steps.addAll(<String>[
        'If severe choking and unable to speak, start back blows and abdominal thrusts if trained.',
        'Call ${_resolveEmergencyNumber(prompt)} for ${_resolveEmergencyServiceLabel(prompt)} immediately.',
        'If unresponsive, begin CPR and continue until help arrives.',
      ]);
      avoid.addAll(<String>[
        'Do not give food or water during active choking.',
        'Do not delay emergency call.',
      ]);
      links.add(
        'https://www.youtube.com/results?search_query=St+John+Ambulance+choking+first+aid',
      );
      addDefaultShare();
    } else {
      title = likelyEmergency
          ? 'Built-in: Emergency triage (unmapped case)'
          : 'Built-in: General emergency guidance';
      steps.addAll(<String>[
        'Move to safer area if possible and reduce immediate risks.',
        'Call ${_resolveEmergencyNumber(prompt)} for ${_resolveEmergencyServiceLabel(prompt)} if danger is immediate.',
        'Stay visible and keep phone charged and reachable.',
      ]);
      avoid.addAll(<String>[
        'Do not attempt high-risk rescue alone.',
        'Do not remain in enclosed smoke/toxic areas.',
      ]);
      links.add(
        'https://www.youtube.com/results?search_query=Red+Cross+first+aid+basics',
      );
      addDefaultShare();

      if (likelyEmergency) {
        clarifying.addAll(<String>[
          'Is the person conscious and breathing normally?',
          'Is there heavy bleeding, severe chest pain, or seizure now?',
          'What exactly happened and how long ago?',
          'Where are you now (landmark/floor/room/road)?',
          'How many people are injured and what are their ages (approx)?',
        ]);
      }
    }

    for (var index = 0; index < steps.length; index++) {
      steps[index] = steps[index]
          .replaceAll(
            'Call emergency services immediately.',
            'Call $emergencyNumber for $emergencyService immediately.',
          )
          .replaceAll(
            'Call emergency services and ask someone to get an AED.',
            'Call $emergencyNumber for $emergencyService and ask someone to get an AED.',
          )
          .replaceAll(
            'Call emergency if seizure lasts >5 minutes or repeats.',
            'Call $emergencyNumber for $emergencyService if seizure lasts >5 minutes or repeats.',
          )
          .replaceAll(
            'Call emergency services and contact a trusted person immediately.',
            'Call $emergencyNumber for $emergencyService and contact a trusted person immediately.',
          )
          .replaceAll(
            'Call local emergency services if danger is immediate.',
            'Call $emergencyNumber for $emergencyService if danger is immediate.',
          );
    }

    final sanitizedContext = context.isEmpty ? 'none' : context;
    final stepsText = steps
        .asMap()
        .entries
        .map((entry) => '${entry.key + 1}. ${entry.value}')
        .join('\n');
    final avoidText = avoid.map((e) => '- $e').join('\n');
    final shareText = share.toSet().map((e) => '- $e').join('\n');
    final trustedLinks = _trustedVisualLinksForPrompt(prompt).toSet();
    final resolvedLinks = <String>[
      ...links,
      ...trustedLinks,
    ].where((url) => trustedLinks.contains(url)).toSet().toList();
    final linksText = resolvedLinks.map((e) => '- $e').join('\n');
    final clarifyingText = clarifying.toSet().map((e) => '- $e').join('\n');
    final includeClarifying = clarifyingText.isNotEmpty;

    return '''
$title
Context considered: $sanitizedContext

    Emergency contact: $emergencyNumber for $emergencyService

Immediate actions:
$stepsText

What to avoid:
$avoidText

What to share with responders:
$shareText

${includeClarifying ? 'Quick checks to reply with:\n$clarifyingText\n' : ''}

Visual guides (trusted YouTube videos):
$linksText
''';
  }

  static String _resolveGeminiApiKey() {
    final candidates = <String>[
      const String.fromEnvironment('GEMINI_API_KEY'),
      const String.fromEnvironment('GOOGLE_GEMINI_API_KEY'),
      const String.fromEnvironment('GOOGLE_API_KEY'),
      const String.fromEnvironment('API_KEY'),
      const String.fromEnvironment('GENAI_API_KEY'),
      const String.fromEnvironment('GEMINI_KEY'),
    ];

    for (final candidate in candidates) {
      final normalized = _normalizeApiKey(candidate);
      if (normalized.isNotEmpty) {
        return normalized;
      }
    }

    return '';
  }

  static String _normalizeApiKey(String raw) {
    var normalized = raw.trim();

    if (normalized.length >= 2 &&
        normalized.startsWith('"') &&
        normalized.endsWith('"')) {
      normalized = normalized.substring(1, normalized.length - 1).trim();
    }

    if (normalized.toLowerCase().startsWith('bearer ')) {
      normalized = normalized.substring(7).trim();
    }

    return normalized;
  }

  static String _redactApiKey(String apiKey) {
    if (apiKey.trim().isEmpty) {
      return 'empty';
    }
    final safe = apiKey.trim();
    final visible = safe.length >= 6 ? safe.substring(0, 6) : safe;
    return '$visible***';
  }

  _GeminiFailure _classifyGeminiFailure(Object error) {
    final message = error.toString().toLowerCase();

    if (message.contains('api key not valid') ||
        message.contains('invalid api key') ||
        message.contains('permission denied') ||
        message.contains('unauthorized') ||
        message.contains('403')) {
      return const _GeminiFailure(
        code: 'gemini_auth_error',
        userMessage: 'Gemini key is invalid or lacks permissions.',
      );
    }

    if (message.contains('404') ||
        (message.contains('model') && message.contains('not found'))) {
      return const _GeminiFailure(
        code: 'gemini_model_unavailable',
        userMessage: 'Requested Gemini model is unavailable for this key.',
      );
    }

    if (message.contains('429') ||
        message.contains('rate limit') ||
        message.contains('quota')) {
      return const _GeminiFailure(
        code: 'gemini_quota_exceeded',
        userMessage: 'Gemini quota/rate limit reached. Please retry soon.',
      );
    }

    if (message.contains('500') ||
        message.contains('503') ||
        message.contains('internal') ||
        message.contains('service unavailable')) {
      return const _GeminiFailure(
        code: 'gemini_service_unavailable',
        userMessage: 'Gemini service is temporarily unavailable.',
      );
    }

    if (message.contains('socketexception') ||
        message.contains('failed host lookup') ||
        message.contains('network') ||
        message.contains('connection') ||
        message.contains('timed out')) {
      return const _GeminiFailure(
        code: 'gemini_offline',
        userMessage: 'Network appears offline or unstable.',
      );
    }

    return const _GeminiFailure(
      code: 'gemini_error',
      userMessage: 'Gemini is temporarily unavailable.',
    );
  }

  String _buildApiFallbackMessage({
    required String reason,
    required String userPrompt,
    required String contextSummary,
    required Map<String, dynamic> emergencyContext,
    required List<Map<String, dynamic>> recentMessages,
  }) {


    final quickFallback = _buildQuickCrisisFallback(
      userPrompt: userPrompt,
      contextSummary: contextSummary,
      emergencyContext: emergencyContext,
    );
    final localFallback = _buildScenarioFallback(
      userPrompt: userPrompt,
      contextSummary: contextSummary,
      emergencyContext: emergencyContext,
    );

    final preferredLanguageCode = _resolvePreferredLanguageCode(
      userPrompt: userPrompt,
      recentMessages: recentMessages,
      emergencyContext: emergencyContext,
    );
    final languageNotice = 'Preferred response language: ${_languageLabelForCode(preferredLanguageCode)}.';
    return 'Here is the offline safety guidance:\n\n$languageNotice\n\n$quickFallback\n\n$localFallback';
  }

  String _buildQuickCrisisFallback({
    required String userPrompt,
    required String contextSummary,
    required Map<String, dynamic> emergencyContext,
  }) {
    final merged =
        '${userPrompt.toLowerCase()} ${contextSummary.toLowerCase()}';
    final countryHint = _inferCountryHint(
      prompt: merged,
      emergencyContext: emergencyContext,
    );
    final emergencyNumber = _resolveEmergencyNumber(
      merged,
      countryHint: countryHint,
    );
    final emergencyService = _resolveEmergencyServiceLabel(merged);

    final type = _detectCrisisType(merged);
    final steps = _quickFallbackByCrisisType[type] ??
        const <String>[
          'Move to a safer area and reduce immediate risk.',
          'Call emergency services now if danger is immediate.',
          'Keep phone available and share exact location.',
        ];

    return '''
Offline quick guide (${type.toUpperCase()}):
1. ${steps[0]}
2. ${steps[1]}
3. ${steps[2]}

Call: $emergencyNumber for $emergencyService.
Share: exact location, number of injured people, and current hazards.
''';
  }

  String _detectCrisisType(String merged) {
    if (merged.contains('fire') || merged.contains('smoke')) {
      return 'fire';
    }
    if (merged.contains('accident') ||
        merged.contains('road') ||
        merged.contains('vehicle') ||
        merged.contains('collision')) {
      return 'road';
    }
    if (merged.contains('flood') ||
        merged.contains('water level') ||
        merged.contains('inundation')) {
      return 'flood';
    }
    if (merged.contains('assault') ||
        merged.contains('violence') ||
        merged.contains('abuse') ||
        merged.contains('harass')) {
      return 'violence';
    }
    if (merged.contains('earthquake') || merged.contains('quake')) {
      return 'earthquake';
    }
    if (merged.contains('lost') || merged.contains('missing')) {
      return 'lost';
    }
    return 'medical';
  }

  void _logGeminiStatus(
    String status, {
    String? model,
    Object? error,
  }) {
    final modelSuffix = model == null ? '' : ' | model=$model';
    final errorSuffix = error == null ? '' : ' | error=$error';
    debugPrint('[ChatService] $status$modelSuffix$errorSuffix');
  }

  Future<void> _ensureAiParticipantPresent(String sosId) async {
    final ref = chatRef(sosId);

    await _withFirestoreRetry(() async {
      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(ref);
        final data = snapshot.data();
        if (data == null) {
          return;
        }

        final participants = _asMapList(data['participants']);
        final participantUids = _extractParticipantUids(data);
        if (participantUids.contains(_aiUid)) {
          return;
        }

        final updatedParticipants = participants.toList()
          ..add(<String, dynamic>{
            'uid': _aiUid,
            'displayName': _aiDisplayName,
            'role': 'responder',
            'isAi': true,
            'joinedAt': Timestamp.now(),
          });
        final updatedUids = participantUids.toSet()..add(_aiUid);

        transaction.set(
          ref,
          <String, dynamic>{
            'participants': updatedParticipants,
            'participantUids': updatedUids.toList(),
          },
          SetOptions(merge: true),
        );
      });
    });
  }

  String _sanitizeAiPrompt(String input, {required String askReason}) {
    var prompt = input.trim();
    if (askReason == 'mention') {
      prompt = prompt.replaceAll(
        RegExp(r'(^|\s)@ai(\b|$)', caseSensitive: false),
        ' ',
      );
      prompt = prompt.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (prompt.isEmpty) {
        return 'Provide immediate safety guidance based on recent chat context.';
      }
    }
    return prompt;
  }

  List<Map<String, dynamic>> _extractOverviewMedia(
      Map<String, dynamic> sosPayload) {
    final media = <Map<String, dynamic>>[];

    final attachmentUrl = sosPayload['attachmentUrl'] as String?;
    if (attachmentUrl != null && attachmentUrl.isNotEmpty) {
      media.add(<String, dynamic>{
        'url': attachmentUrl,
        'type': (sosPayload['attachmentType'] as String?) ?? 'image',
      });
    }

    final voiceAudioUrl = sosPayload['voiceAudioUrl'] as String?;
    if (voiceAudioUrl != null && voiceAudioUrl.isNotEmpty) {
      media.add(<String, dynamic>{
        'url': voiceAudioUrl,
        'type': (sosPayload['voiceAudioType'] as String?) ?? 'audio',
      });
    }

    final rawMedia = sosPayload['media'];
    if (rawMedia is List) {
      media.addAll(
        rawMedia
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .where(
              (item) =>
                  (item['url'] as String?)?.isNotEmpty == true &&
                  (item['type'] as String?)?.isNotEmpty == true,
            ),
      );
    }

    return media;
  }

  Set<String> _extractParticipantUids(Map<String, dynamic> chatData) {
    final fromDedicatedField = (chatData['participantUids'] as List<dynamic>?)
            ?.whereType<String>()
            .toSet() ??
        <String>{};

    if (fromDedicatedField.isNotEmpty) {
      return fromDedicatedField;
    }

    final fromParticipants = _asMapList(chatData['participants'])
        .map((entry) => entry['uid'] as String?)
        .whereType<String>()
        .toSet();
    return fromParticipants;
  }

  List<Map<String, dynamic>> _asMapList(dynamic raw) {
    if (raw is! List) {
      return const <Map<String, dynamic>>[];
    }

    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<void> _deleteMediaForMessageData(
    Map<String, dynamic> messageData, {
    Set<String>? processedMediaUrls,
  }) async {
    final mediaUrls = <String>{};

    final attachmentUrl = (messageData['attachmentUrl'] as String?)?.trim();
    if (attachmentUrl != null && attachmentUrl.isNotEmpty) {
      mediaUrls.add(attachmentUrl);
    }

    final voiceAudioUrl = (messageData['voiceAudioUrl'] as String?)?.trim();
    if (voiceAudioUrl != null && voiceAudioUrl.isNotEmpty) {
      mediaUrls.add(voiceAudioUrl);
    }

    final mediaItems = _asMapList(messageData['media']);
    for (final item in mediaItems) {
      final url = (item['url'] as String?)?.trim();
      if (url != null && url.isNotEmpty) {
        mediaUrls.add(url);
      }
    }

    for (final url in mediaUrls) {
      if (processedMediaUrls != null && !processedMediaUrls.add(url)) {
        continue;
      }
      await _deleteMediaAssetIfPossible(url);
    }
  }

  Future<void> _deleteMediaForChatData(
    Map<String, dynamic> chatData, {
    Set<String>? processedMediaUrls,
  }) async {
    final mediaUrls = <String>{};

    final overview = chatData['sosOverview'] is Map
        ? Map<String, dynamic>.from(chatData['sosOverview'] as Map)
        : <String, dynamic>{};

    final overviewMedia = _asMapList(overview['media']);
    for (final item in overviewMedia) {
      final url = (item['url'] as String?)?.trim();
      if (url != null && url.isNotEmpty) {
        mediaUrls.add(url);
      }
    }

    // Legacy/non-SOS schemas may still store attachment/media directly on chat.
    final chatAttachmentUrl = (chatData['attachmentUrl'] as String?)?.trim();
    if (chatAttachmentUrl != null && chatAttachmentUrl.isNotEmpty) {
      mediaUrls.add(chatAttachmentUrl);
    }

    final chatVoiceAudioUrl = (chatData['voiceAudioUrl'] as String?)?.trim();
    if (chatVoiceAudioUrl != null && chatVoiceAudioUrl.isNotEmpty) {
      mediaUrls.add(chatVoiceAudioUrl);
    }

    final chatMediaItems = _asMapList(chatData['media']);
    for (final item in chatMediaItems) {
      final url = (item['url'] as String?)?.trim();
      if (url != null && url.isNotEmpty) {
        mediaUrls.add(url);
      }
    }

    for (final url in mediaUrls) {
      if (processedMediaUrls != null && !processedMediaUrls.add(url)) {
        continue;
      }
      await _deleteMediaAssetIfPossible(url);
    }
  }

  Future<void> _deleteMediaAssetIfPossible(String mediaUrl) async {
    await _deleteCloudinaryAssetIfPossible(mediaUrl);
    await _deleteFirebaseStorageAssetIfPossible(mediaUrl);
  }

  Future<void> _deleteCloudinaryAssetIfPossible(String mediaUrl) async {
    final endpoint = _cloudinaryDeleteEndpoint.trim();
    if (endpoint.isEmpty) {
      return;
    }

    final publicId = _cloudinaryPublicIdFromUrl(mediaUrl);
    if (publicId == null || publicId.isEmpty) {
      return;
    }

    try {
      await http.post(
        Uri.parse(endpoint),
        headers: <String, String>{
          'Content-Type': 'application/json',
          if (_cloudinaryDeleteToken.trim().isNotEmpty)
            'Authorization': 'Bearer ${_cloudinaryDeleteToken.trim()}',
        },
        body: jsonEncode(<String, dynamic>{
          'publicId': publicId,
          'mediaUrl': mediaUrl,
        }),
      );
    } catch (_) {
      // Best-effort delete only; message removal should still succeed.
    }
  }

  Future<void> _deleteFirebaseStorageAssetIfPossible(String mediaUrl) async {
    final uri = Uri.tryParse(mediaUrl);
    if (uri == null) {
      return;
    }

    final host = uri.host.toLowerCase();
    final isFirebaseStorageHost =
        host.contains('firebasestorage.googleapis.com') ||
        host.contains('storage.googleapis.com');
    if (!isFirebaseStorageHost && uri.scheme != 'gs') {
      return;
    }

    try {
      final ref = FirebaseStorage.instance.refFromURL(mediaUrl);
      await ref.delete();
    } catch (_) {
      // Best-effort delete only; chat/message deletion should still succeed.
    }
  }

  String? _cloudinaryPublicIdFromUrl(String mediaUrl) {
    final uri = Uri.tryParse(mediaUrl);
    if (uri == null || !uri.host.contains('res.cloudinary.com')) {
      return null;
    }

    final segments = uri.pathSegments;
    final uploadIndex = segments.indexOf('upload');
    if (uploadIndex < 0 || uploadIndex + 1 >= segments.length) {
      return null;
    }

    var startIndex = uploadIndex + 1;
    if (segments[startIndex].startsWith('v')) {
      startIndex += 1;
    }
    if (startIndex >= segments.length) {
      return null;
    }

    final publicIdWithExt = segments.sublist(startIndex).join('/');
    final dotIndex = publicIdWithExt.lastIndexOf('.');
    if (dotIndex <= 0) {
      return publicIdWithExt;
    }
    return publicIdWithExt.substring(0, dotIndex);
  }

  String _safeDisplayName(String? raw, {required String fallback}) {
    final trimmed = raw?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return fallback;
    }
    if (trimmed.length > _maxDisplayNameLength) {
      return trimmed.substring(0, _maxDisplayNameLength);
    }
    return trimmed;
  }

  String _normalizeRole(String raw) {
    final normalized = raw.trim().toLowerCase();
    if (normalized == 'victim' || normalized == 'responder') {
      return normalized;
    }
    return 'responder';
  }

  bool _isActiveParticipant(Map<String, dynamic> chatData, String uid) {
    final safeUid = uid.trim();
    if (safeUid.isEmpty) {
      return false;
    }

    final participants = _asMapList(chatData['participants']);
    return participants.any((entry) => (entry['uid'] as String?) == safeUid);
  }

  Future<T> _withFirestoreRetry<T>(Future<T> Function() operation) async {
    FirebaseException? lastFirestoreError;

    for (var attempt = 0; attempt <= _retryBackoff.length; attempt++) {
      try {
        return await operation();
      } on FirebaseException catch (e) {
        lastFirestoreError = e;
        if (!_isTransientFirestoreError(e) || attempt == _retryBackoff.length) {
          rethrow;
        }
      }

      await Future<void>.delayed(_retryBackoff[attempt]);
    }

    throw lastFirestoreError ??
        FirebaseException(plugin: 'cloud_firestore', code: 'unknown');
  }

  bool _isTransientFirestoreError(FirebaseException e) {
    return e.code == 'unavailable' ||
        e.code == 'deadline-exceeded' ||
        e.code == 'aborted';
  }
}

class _AiGenerationOutcome {
  final String? text;
  final String? modelUsed;
  final String code;
  final String userMessage;

  const _AiGenerationOutcome.success({
    required this.text,
    required this.modelUsed,
  })  : code = 'gemini_success',
        userMessage = '';

  const _AiGenerationOutcome.failure({
    required this.code,
    required this.userMessage,
  })  : text = null,
        modelUsed = null;

  bool get hasText => (text ?? '').trim().isNotEmpty;
}

class _GeminiFailure {
  final String code;
  final String userMessage;

  const _GeminiFailure({
    required this.code,
    required this.userMessage,
  });
}
