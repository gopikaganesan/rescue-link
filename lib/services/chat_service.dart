import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

class ChatService {
  ChatService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _geminiApiKey = const String.fromEnvironment('GEMINI_API_KEY');

  static const int _maxMessageLength = 1000;
  static const int _maxDisplayNameLength = 80;
  static const String _aiUid = 'rescuelink_ai';
  static const String _aiDisplayName = 'RescueLink AI';
  static const String _geminiModel = 'gemini-1.5-flash';
  static const Duration _geminiTimeout = Duration(seconds: 12);

  final FirebaseFirestore _firestore;
  final String _geminiApiKey;
  static const List<Duration> _retryBackoff = <Duration>[
    Duration(milliseconds: 300),
    Duration(milliseconds: 700),
    Duration(milliseconds: 1200),
  ];

  CollectionReference<Map<String, dynamic>> get _chats =>
      _firestore.collection('chats');

  DocumentReference<Map<String, dynamic>> chatRef(String sosId) =>
      _chats.doc(sosId);

  CollectionReference<Map<String, dynamic>> messagesRef(String sosId) =>
      chatRef(sosId).collection('messages');

  Future<void> createChatOnSos({
    required String sosId,
    required String victimUid,
    String? victimName,
    required String sosMessage,
    List<Map<String, dynamic>> media = const <Map<String, dynamic>>[],
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
    final ref = chatRef(sosId);
    if (deleteDocument) {
      await ref.delete();
      return;
    }

    await ref.set(
      <String, dynamic>{
        'status': 'cancelled',
        'cancelledAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
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
    final prompt = _buildAiPrompt(
      chatData: chatData,
      recentMessages: recentMessages,
      requesterName: 'Victim',
      requesterRole: 'victim',
      userPrompt:
          'No human responder has joined yet. Provide immediate, practical emergency guidance now.',
      imageDescription: null,
      voiceTranscript: null,
      askReason: 'auto_no_human_responder',
    );

    final aiText = await _generateAiReply(prompt);
    if (aiText.isEmpty) {
      return false;
    }

    await _sendAiMessage(
      sosId: safeSosId,
      text: aiText,
      trigger: 'auto_no_human_responder',
      requesterUid: null,
    );
    return true;
  }

  Future<bool> sendMessageToAI({
    required String sosId,
    required String requesterUid,
    required String requesterName,
    required String requesterRole,
    required String userPrompt,
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

    if (safeSosId.isEmpty || safeRequesterUid.isEmpty || safePrompt.isEmpty) {
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

    final participantUids = _extractParticipantUids(chatData);
    if (!participantUids.contains(safeRequesterUid)) {
      return false;
    }

    final recentMessages = await _fetchRecentMessages(safeSosId, limit: 20);
    final prompt = _buildAiPrompt(
      chatData: chatData,
      recentMessages: recentMessages,
      requesterName: requesterName,
      requesterRole: requesterRole,
      userPrompt: safePrompt,
      imageDescription: imageDescription,
      voiceTranscript: voiceTranscript,
      askReason: askReason,
    );

    final aiText = await _generateAiReply(prompt);
    if (aiText.isEmpty) {
      return false;
    }

    await _sendAiMessage(
      sosId: safeSosId,
      text: aiText,
      trigger: askReason,
      requesterUid: safeRequesterUid,
    );
    return true;
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
        if (!participantUids.contains(safeSenderUid)) {
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

  Future<void> joinResponder({
    required String sosId,
    required String responderUid,
    required String responderName,
  }) async {
    final ref = chatRef(sosId);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      final data = snapshot.data() ?? <String, dynamic>{};
      final status = (data['status'] as String?) ?? 'active';
      if (status == 'cancelled') {
        return;
      }

      final rawParticipants =
          data['participants'] as List<dynamic>? ?? <dynamic>[];
      final participants = rawParticipants
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList();

      final alreadyJoined =
          participants.any((entry) => entry['uid'] == responderUid);
      if (alreadyJoined) {
        return;
      }

      final participantUids = _extractParticipantUids(data)..add(responderUid);

      participants.add(<String, dynamic>{
        'uid': responderUid,
        'displayName': _safeDisplayName(responderName, fallback: 'Responder'),
        'role': 'responder',
        'joinedAt': Timestamp.now(),
      });

      transaction.set(
        ref,
        <String, dynamic>{
          'participants': participants,
          'participantUids': participantUids.toList(),
          'responderPresence': <String, dynamic>{
            ...(data['responderPresence'] is Map
                ? Map<String, dynamic>.from(data['responderPresence'] as Map)
                : <String, dynamic>{}),
            responderUid: false,
          },
        },
        SetOptions(merge: true),
      );
    });
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
      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(ref);
        final data = snapshot.data() ?? <String, dynamic>{};

        final participants = _asMapList(data['participants']);
        final updatedParticipants = participants
            .where((entry) => !((entry['uid'] as String?) == safeResponderUid &&
                (entry['role'] as String?) == 'responder' &&
                entry['isAi'] != true))
            .toList();

        if (updatedParticipants.length == participants.length) {
          return;
        }

        final updatedParticipantUids = updatedParticipants
            .map((entry) => entry['uid'] as String?)
            .whereType<String>()
            .toSet();

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

  Future<void> _sendAiMessage({
    required String sosId,
    required String text,
    required String trigger,
    required String? requesterUid,
  }) async {
    final safeText = text.length > _maxMessageLength
        ? text.substring(0, _maxMessageLength)
        : text;
    if (safeText.trim().isEmpty) {
      return;
    }

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
        if (!participantUids.contains(_aiUid)) {
          return;
        }

        transaction.set(messageDoc, <String, dynamic>{
          'text': safeText,
          'senderUid': _aiUid,
          'senderRole': 'responder',
          'senderName': _aiDisplayName,
          'createdAt': FieldValue.serverTimestamp(),
          'type': 'text',
          'isAi': true,
          'aiMeta': <String, dynamic>{
            'trigger': trigger,
            'requesterUid': requesterUid,
          },
        });
      });
    });
  }

  Future<bool> _hasAiAutoMessage(String sosId) async {
    final snapshot = await _withFirestoreRetry(
      () => messagesRef(sosId)
          .where('senderUid', isEqualTo: _aiUid)
          .orderBy('createdAt', descending: true)
          .limit(20)
          .get(),
    );

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final aiMeta = data['aiMeta'];
      if (aiMeta is Map && aiMeta['trigger'] == 'auto_no_human_responder') {
        return true;
      }
    }

    return false;
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
          .get(),
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

    return '''
You are RescueLink AI assisting in an emergency group chat.
Keep responses practical, calm, and safety-first.
Do not claim to dispatch responders. If danger is immediate, instruct user to call local emergency services immediately.

Conversation context:
- Trigger: $askReason
- Requester name: ${requesterName.trim().isEmpty ? 'Unknown' : requesterName.trim()}
- Requester role: ${_normalizeRole(requesterRole)}
- SOS overview: ${overviewMessage.trim().isEmpty ? 'none' : overviewMessage.trim()}
- Image description: $imageSection
- Voice transcript: $voiceSection
- Media references:\n$mediaSection

Recent chat history (oldest to newest):
$historyLines

User request to AI:
$userPrompt

Respond in concise plain text with:
1) immediate steps,
2) what to avoid,
3) what info to share with responders.
''';
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

  Future<String> _generateAiReply(String prompt) async {
    if (_geminiApiKey.isEmpty) {
      return _fallbackAiReply();
    }

    try {
      final model = GenerativeModel(model: _geminiModel, apiKey: _geminiApiKey);
      final response = await model.generateContent(
          <Content>[Content.text(prompt)]).timeout(_geminiTimeout);
      final text = response.text?.trim() ?? '';
      if (text.isEmpty) {
        return _fallbackAiReply();
      }
      return text;
    } catch (_) {
      return _fallbackAiReply();
    }
  }

  String _fallbackAiReply() {
    return 'I can help with immediate safety steps. Move to a safer area if possible, '
        'avoid risky actions, and share your exact location, number of injured people, '
        'and visible hazards while waiting for responders.';
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
