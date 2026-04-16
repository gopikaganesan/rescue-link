import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../core/services/media_upload_service.dart';
import '../services/chat_service.dart';

class GroupChatScreen extends StatefulWidget {
  const GroupChatScreen({
    super.key,
    required this.sosId,
    required this.currentUserId,
    required this.currentUserName,
    required this.currentUserRole,
    this.enableResponderJoinGate = true,
  });

  final String sosId;
  final String currentUserId;
  final String currentUserName;
  final String currentUserRole;
  final bool enableResponderJoinGate;

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen>
    with WidgetsBindingObserver {
  static const int _maxMessageLength = 1000;

  final ChatService _chatService = ChatService();
  final MediaUploadService _mediaUploadService =
      MediaUploadService.fromEnvironment();
  final ImagePicker _imagePicker = ImagePicker();
  final SpeechToText _speechToText = SpeechToText();
  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPreviewPlayer = AudioPlayer();
  final AudioPlayer _chatAudioPlayer = AudioPlayer();
  final TextEditingController _controller = TextEditingController();
  bool _isSending = false;
  bool _isJoining = false;
  bool _isRepairing = false;
  bool _speechReady = false;
  bool _isTranscribing = false;
  bool _isRecordingClip = false;
  bool _isPreviewPlaying = false;
  bool _isChatAudioPlaying = false;
  Timer? _autoRepairTimer;
  bool _autoRepairEnabled = false;
  String? _setupStatusText;
  bool _viewOverviewOnly = false;
  bool _presenceOnline = false;
  bool _presenceTargetOnline = false;
  bool _isAskingAi = false;
  bool _autoAiAttempted = false;
  bool _autoAiInFlight = false;
  String? _pendingImageDescription;
  String? _pendingVoiceTranscript;
  XFile? _selectedImageAttachment;
  String? _voiceAudioPath;
  String? _playingChatAudioUrl;
  Duration _chatAudioPosition = Duration.zero;
  Duration _chatAudioDuration = Duration.zero;
  StreamSubscription<Duration>? _chatAudioPositionSub;
  StreamSubscription<Duration>? _chatAudioDurationSub;
  StreamSubscription<void>? _chatAudioCompleteSub;

  bool get _isResponder => widget.currentUserRole == 'responder';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeSpeech();
    _chatAudioPositionSub = _chatAudioPlayer.onPositionChanged.listen((value) {
      if (!mounted) {
        return;
      }
      setState(() {
        _chatAudioPosition = value;
      });
    });
    _chatAudioDurationSub = _chatAudioPlayer.onDurationChanged.listen((value) {
      if (!mounted) {
        return;
      }
      setState(() {
        _chatAudioDuration = value;
      });
    });
    _chatAudioCompleteSub = _chatAudioPlayer.onPlayerComplete.listen((_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isChatAudioPlaying = false;
        _chatAudioPosition = Duration.zero;
      });
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_presenceOnline) {
      return;
    }

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _updateResponderPresence(false);
      return;
    }

    if (state == AppLifecycleState.resumed) {
      _updateResponderPresence(true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoRepairTimer?.cancel();
    _clearPresenceOnDispose();
    _speechToText.stop();
    _audioRecorder.dispose();
    _audioPreviewPlayer.dispose();
    _chatAudioPositionSub?.cancel();
    _chatAudioDurationSub?.cancel();
    _chatAudioCompleteSub?.cancel();
    _chatAudioPlayer.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_isSending || _isAskingAi) {
      return;
    }

    final text = _controller.text.trim();
    final hasAttachment = _selectedImageAttachment != null ||
        (_voiceAudioPath?.isNotEmpty == true);
    if (text.isEmpty && !hasAttachment) {
      return;
    }

    setState(() {
      _isSending = true;
    });

    try {
      final uploadedAttachment = await _uploadAttachmentIfNeeded();
      final attachmentUrl = uploadedAttachment?['url'] as String?;
      final attachmentType = uploadedAttachment?['type'] as String?;

      final effectiveText = text.isEmpty &&
              _pendingVoiceTranscript != null &&
              _pendingVoiceTranscript!.trim().isNotEmpty
          ? _pendingVoiceTranscript!.trim()
          : text;

      final shouldAskAiFromMention =
          _chatService.shouldTriggerAiFromText(effectiveText);

      await _chatService.sendMessage(
        sosId: widget.sosId,
        senderUid: widget.currentUserId,
        senderRole: widget.currentUserRole,
        senderName: widget.currentUserName,
        text: effectiveText,
        attachmentUrl: attachmentUrl,
        attachmentType: attachmentType,
        voiceAudioUrl: attachmentType == 'audio/wav' ? attachmentUrl : null,
        voiceAudioType: attachmentType == 'audio/wav' ? 'audio/wav' : null,
        voiceTranscript: _pendingVoiceTranscript,
      );

      if (shouldAskAiFromMention) {
        final aiSent = await _requestAiReplySafely(
          userPrompt: effectiveText,
          askReason: 'mention',
        );
        if (aiSent) {
          _clearPendingMultimodalContext();
        }
      }

      _controller.clear();
      _selectedImageAttachment = null;
      _voiceAudioPath = null;
      _pendingVoiceTranscript = null;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Message could not be sent. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  Future<Map<String, String>?> _uploadAttachmentIfNeeded() async {
    final image = _selectedImageAttachment;
    if (image != null) {
      final imageUrl = await _mediaUploadService.uploadEmergencyImage(
        image: image,
        userId: widget.currentUserId,
      );
      if (imageUrl == null || imageUrl.trim().isEmpty) {
        return null;
      }

      return <String, String>{
        'url': imageUrl,
        'type': 'image',
      };
    }

    final voicePath = _voiceAudioPath;
    if (voicePath == null || voicePath.trim().isEmpty) {
      return null;
    }

    final audioUrl = await _mediaUploadService.uploadEmergencyVoice(
      localPath: voicePath,
      userId: widget.currentUserId,
    );
    if (audioUrl == null || audioUrl.trim().isEmpty) {
      return null;
    }

    return <String, String>{
      'url': audioUrl,
      'type': 'audio/wav',
    };
  }

  Future<void> _initializeSpeech() async {
    try {
      final ready = await _speechToText.initialize();
      if (!mounted) {
        return;
      }
      setState(() {
        _speechReady = ready;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _speechReady = false;
      });
    }
  }

  Future<void> _pickImageAttachment() async {
    if (_isSending || _isAskingAi) {
      return;
    }

    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
        maxWidth: 1600,
      );
      if (picked == null || !mounted) {
        return;
      }

      setState(() {
        _selectedImageAttachment = picked;
        _voiceAudioPath = null;
        _pendingImageDescription = 'User attached a photo from gallery.';
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to pick image right now.')),
        );
      }
    }
  }

  Future<void> _pickCameraAttachment() async {
    if (_isSending || _isAskingAi) {
      return;
    }

    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 1600,
      );
      if (picked == null || !mounted) {
        return;
      }

      setState(() {
        _selectedImageAttachment = picked;
        _voiceAudioPath = null;
        _pendingImageDescription =
            'User attached a photo captured from camera.';
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to open camera right now.')),
        );
      }
    }
  }

  Future<void> _toggleVoiceTranscription() async {
    if (_isSending || _isAskingAi) {
      return;
    }

    if (!_speechReady) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Voice transcription is unavailable.')),
        );
      }
      return;
    }

    if (_isTranscribing) {
      await _speechToText.stop();
      if (mounted) {
        setState(() {
          _isTranscribing = false;
        });
      }
      return;
    }

    await _speechToText.listen(
      onResult: (result) {
        if (!mounted) {
          return;
        }

        final words = result.recognizedWords.trim();
        if (words.isEmpty) {
          return;
        }

        setState(() {
          _isTranscribing = !result.finalResult;
          _pendingVoiceTranscript = words;
          _controller.text = words;
          _controller.selection = TextSelection.fromPosition(
            TextPosition(offset: _controller.text.length),
          );
        });
      },
      listenOptions: SpeechListenOptions(
        partialResults: true,
        listenMode: ListenMode.dictation,
      ),
      listenFor: const Duration(minutes: 1),
      pauseFor: const Duration(seconds: 6),
    );

    if (mounted) {
      setState(() {
        _isTranscribing = true;
      });
    }
  }

  Future<void> _toggleVoiceRecording() async {
    if (_isSending || _isAskingAi) {
      return;
    }

    final canRecordAudio = await _audioRecorder.hasPermission();
    if (!canRecordAudio) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Microphone permission is required for audio attach.'),
          ),
        );
      }
      return;
    }

    if (_isRecordingClip) {
      final path = await _audioRecorder.stop();
      if (!mounted) {
        return;
      }

      setState(() {
        _isRecordingClip = false;
        if (path != null && path.trim().isNotEmpty) {
          _voiceAudioPath = path;
          _selectedImageAttachment = null;
          _pendingVoiceTranscript ??=
              _controller.text.trim().isEmpty ? null : _controller.text.trim();
        }
      });
      return;
    }

    final tempDir = await getTemporaryDirectory();
    final voicePath =
        '${tempDir.path}/group_clip_${DateTime.now().millisecondsSinceEpoch}.wav';
    await _audioRecorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: voicePath,
    );

    if (mounted) {
      setState(() {
        _isRecordingClip = true;
      });
    }
  }

  Future<void> _previewVoiceAttachment() async {
    final voicePath = _voiceAudioPath;
    if (voicePath == null || voicePath.trim().isEmpty) {
      return;
    }

    if (_isPreviewPlaying) {
      await _audioPreviewPlayer.stop();
      if (mounted) {
        setState(() {
          _isPreviewPlaying = false;
        });
      }
      return;
    }

    await _audioPreviewPlayer.play(DeviceFileSource(voicePath));
    if (mounted) {
      setState(() {
        _isPreviewPlaying = true;
      });
    }

    _audioPreviewPlayer.onPlayerComplete.first.then((_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isPreviewPlaying = false;
      });
    });
  }

  Future<void> _showAttachmentOptions() async {
    if (_isSending || _isAskingAi) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Photo from gallery'),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickImageAttachment();
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: const Text('Photo from camera'),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickCameraAttachment();
                },
              ),
              ListTile(
                leading: Icon(
                  _isRecordingClip ? Icons.stop_circle_outlined : Icons.mic,
                ),
                title: Text(
                  _isRecordingClip
                      ? 'Stop recording audio'
                      : 'Record audio clip',
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  _toggleVoiceRecording();
                },
              ),
              ListTile(
                leading: Icon(
                  _isTranscribing ? Icons.hearing_disabled : Icons.hearing,
                ),
                title: Text(
                  _isTranscribing
                      ? 'Stop voice transcription'
                      : 'Start voice transcription',
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  _toggleVoiceTranscription();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _askAiFromComposer() async {
    if (_isAskingAi || _isSending) {
      return;
    }

    final prompt = _controller.text.trim();
    final effectivePrompt = prompt.isEmpty
        ? 'Provide immediate safety guidance based on recent chat context.'
        : prompt;

    setState(() {
      _isAskingAi = true;
    });

    try {
      final aiSent = await _requestAiReplySafely(
        userPrompt: effectivePrompt,
        askReason: 'ask_button',
      );
      if (aiSent) {
        _clearPendingMultimodalContext();
        _controller.clear();
      }
    } finally {
      if (mounted) {
        setState(() {
          _isAskingAi = false;
        });
      }
    }
  }

  Future<bool> _requestAiReply({
    required String userPrompt,
    required String askReason,
  }) async {
    return _chatService.sendMessageToAI(
      sosId: widget.sosId,
      requesterUid: widget.currentUserId,
      requesterName: widget.currentUserName,
      requesterRole: widget.currentUserRole,
      userPrompt: userPrompt,
      imageDescription: _pendingImageDescription,
      voiceTranscript: _pendingVoiceTranscript,
      askReason: askReason,
    );
  }

  Future<bool> _requestAiReplySafely({
    required String userPrompt,
    required String askReason,
  }) async {
    try {
      return await _requestAiReply(
          userPrompt: userPrompt, askReason: askReason);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'AI assistant is temporarily unavailable. Please try again.'),
          ),
        );
      }
      return false;
    }
  }

  void _clearPendingMultimodalContext() {
    _pendingImageDescription = null;
    _pendingVoiceTranscript = null;
  }

  void _tryAutoAiAssist({
    required bool chatLoaded,
    required String status,
  }) {
    if (_autoAiAttempted ||
        _autoAiInFlight ||
        !chatLoaded ||
        status == 'cancelled') {
      return;
    }

    _autoAiInFlight = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await _chatService.sendAutoAiInstructionsIfNeeded(
          sosId: widget.sosId,
        );
      } catch (_) {
        // Keep chat stable even if background AI assist fails.
      } finally {
        _autoAiAttempted = true;
        _autoAiInFlight = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('RescueLink Group Chat'),
        actions: <Widget>[
          _buildChatActionsMenu(),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _chatService.watchChat(widget.sosId),
        builder: (context, chatSnapshot) {
          final chatLoaded = chatSnapshot.hasData;
          final chatData = chatSnapshot.data?.data() ?? <String, dynamic>{};
          final overview = _asMap(chatData['sosOverview']);
          final overviewMessage =
              (overview['message'] as String?) ?? 'No SOS message available';
          final overviewMedia = _asMediaList(overview['media']);
          final status = (chatData['status'] as String?) ?? 'active';
          final responderOnlineCount = _resolveResponderOnlineCount(chatData);
          final participants = _asMapList(chatData['participants']);
          final participantUids = _resolveParticipantUids(
            chatData: chatData,
            participants: participants,
          );
          final isResponder = _isResponder;
          final hasJoined = participants.any(
              (entry) => (entry['uid'] as String?) == widget.currentUserId);
          final showJoinGate =
              widget.enableResponderJoinGate && isResponder && !hasJoined;
          final canSendInChat = status != 'cancelled' &&
              participantUids.contains(widget.currentUserId);
          final shouldAutoRepair =
              !canSendInChat && status != 'cancelled' && !showJoinGate;

          _tryAutoAiAssist(chatLoaded: chatLoaded, status: status);

          _syncAutoRepairState(
            shouldAutoRepair: shouldAutoRepair,
            overviewMessage: overviewMessage,
            overviewMedia: overviewMedia,
          );

          final shouldBeOnline =
              status != 'cancelled' && !showJoinGate && hasJoined;
          _queuePresenceUpdate(shouldBeOnline);

          return Column(
            children: <Widget>[
              _buildHeader(
                context,
                responderOnlineCount: responderOnlineCount,
              ),
              _buildOverviewCard(
                context,
                message: overviewMessage,
                media: overviewMedia,
              ),
              if (showJoinGate)
                _buildJoinSection(
                  context,
                  participants: participants,
                  isCancelled: status == 'cancelled',
                ),
              if (status == 'cancelled')
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text('This SOS has been cancelled.'),
                ),
              if (_setupStatusText != null && shouldAutoRepair)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _setupStatusText!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              if (!showJoinGate || !_viewOverviewOnly)
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _chatService.watchMessages(widget.sosId),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return const Center(
                          child: Text('Failed to load messages'),
                        );
                      }

                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final docs = snapshot.data?.docs ??
                          const <QueryDocumentSnapshot<Map<String, dynamic>>>[];

                      if (docs.isEmpty) {
                        return const Center(
                          child:
                              Text('No messages yet. Start the conversation.'),
                        );
                      }

                      return ListView.builder(
                        reverse: true,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final data = docs[index].data();
                          final senderUid =
                              (data['senderUid'] as String?) ?? '';
                          final isAiMessage = data['isAi'] == true ||
                              senderUid == 'rescuelink_ai';
                          final senderName = _uiDisplayName(
                            data['senderName'] as String?,
                            fallback: 'Unknown',
                          );
                          final text = (data['text'] as String?) ?? '';
                          final attachmentUrl =
                              (data['attachmentUrl'] as String?) ?? '';
                          final voiceAudioUrl =
                              (data['voiceAudioUrl'] as String?) ?? '';
                          final attachmentType =
                              (data['attachmentType'] as String?)
                                      ?.toLowerCase() ??
                                  '';
                          final hasImageAttachment = attachmentUrl.isNotEmpty &&
                              (attachmentType.isEmpty ||
                                  attachmentType.contains('image'));
                          final chatAudioUrl = attachmentUrl.isNotEmpty
                              ? attachmentUrl
                              : voiceAudioUrl;
                          final hasAudioAttachment = chatAudioUrl.isNotEmpty &&
                              (attachmentType.contains('audio') ||
                                  voiceAudioUrl.isNotEmpty);
                          final isMine = senderUid == widget.currentUserId;

                          final rawCreatedAt = data['createdAt'];
                          DateTime? createdAt;
                          if (rawCreatedAt is Timestamp) {
                            createdAt = rawCreatedAt.toDate();
                          }

                          return Align(
                            alignment: isMine
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 5),
                              padding: const EdgeInsets.all(10),
                              constraints: const BoxConstraints(maxWidth: 320),
                              decoration: BoxDecoration(
                                color: isAiMessage
                                    ? Theme.of(context)
                                        .colorScheme
                                        .tertiaryContainer
                                    : isMine
                                        ? Theme.of(context)
                                            .colorScheme
                                            .primaryContainer
                                        : Theme.of(context)
                                            .colorScheme
                                            .surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    isAiMessage
                                        ? '$senderName • AI'
                                        : senderName,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(text),
                                  if (hasImageAttachment) ...<Widget>[
                                    const SizedBox(height: 8),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.network(
                                        attachmentUrl,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Container(
                                          width: 180,
                                          height: 120,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .surfaceContainerHighest,
                                          alignment: Alignment.center,
                                          child:
                                              const Text('Image unavailable'),
                                        ),
                                      ),
                                    ),
                                  ],
                                  if (hasAudioAttachment) ...<Widget>[
                                    const SizedBox(height: 8),
                                    _buildAudioAttachmentBubble(chatAudioUrl),
                                  ],
                                  if (createdAt != null) ...<Widget>[
                                    const SizedBox(height: 6),
                                    Text(
                                      _timeText(createdAt),
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              if (showJoinGate && _viewOverviewOnly)
                const Padding(
                  padding: EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child:
                        Text('Overview-only mode. Join conversation to chat.'),
                  ),
                ),
              if (!showJoinGate)
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            IconButton(
                              onPressed:
                                  canSendInChat ? _showAttachmentOptions : null,
                              icon: const Icon(Icons.attach_file),
                              tooltip: 'Attach',
                            ),
                            Expanded(
                              child: TextField(
                                controller: _controller,
                                enabled: canSendInChat,
                                maxLength: _maxMessageLength,
                                textInputAction: TextInputAction.send,
                                minLines: 1,
                                maxLines: 4,
                                onSubmitted: (_) {
                                  if (canSendInChat) {
                                    _send();
                                  }
                                },
                                decoration: const InputDecoration(
                                  hintText: 'Type a message',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              onPressed:
                                  !canSendInChat || _isSending || _isAskingAi
                                      ? null
                                      : _send,
                              icon: _isSending
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.send),
                              tooltip: 'Send',
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: <Widget>[
                            const Spacer(),
                            TextButton.icon(
                              onPressed:
                                  !canSendInChat || _isAskingAi || _isSending
                                      ? null
                                      : _askAiFromComposer,
                              icon: _isAskingAi
                                  ? const SizedBox(
                                      height: 14,
                                      width: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.smart_toy_outlined),
                              label: const Text('Ask AI'),
                            ),
                          ],
                        ),
                        if (_selectedImageAttachment != null)
                          Padding(
                            padding: const EdgeInsets.only(
                                top: 8, left: 8, right: 8),
                            child: Row(
                              children: <Widget>[
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: Image.network(
                                    Uri.file(_selectedImageAttachment!.path)
                                        .toString(),
                                    width: 52,
                                    height: 52,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      width: 52,
                                      height: 52,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .surfaceContainerHighest,
                                      alignment: Alignment.center,
                                      child:
                                          const Icon(Icons.image_not_supported),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Image ready to send',
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                ),
                                IconButton(
                                  onPressed: () {
                                    setState(() {
                                      _selectedImageAttachment = null;
                                      _pendingImageDescription = null;
                                    });
                                  },
                                  icon: const Icon(Icons.close),
                                  tooltip: 'Remove image',
                                ),
                              ],
                            ),
                          ),
                        if (_voiceAudioPath != null)
                          Padding(
                            padding: const EdgeInsets.only(
                                top: 8, left: 8, right: 8),
                            child: Row(
                              children: <Widget>[
                                IconButton(
                                  onPressed: _previewVoiceAttachment,
                                  icon: Icon(
                                    _isPreviewPlaying
                                        ? Icons.stop_circle_outlined
                                        : Icons.play_circle_outline,
                                  ),
                                  tooltip: 'Preview voice clip',
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    'Voice clip ready to send',
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                ),
                                IconButton(
                                  onPressed: () {
                                    setState(() {
                                      _voiceAudioPath = null;
                                      _isPreviewPlaying = false;
                                    });
                                  },
                                  icon: const Icon(Icons.close),
                                  tooltip: 'Remove voice clip',
                                ),
                              ],
                            ),
                          ),
                        if (_isRecordingClip)
                          Padding(
                            padding: const EdgeInsets.only(
                                top: 8, left: 8, right: 8),
                            child: Row(
                              children: <Widget>[
                                const SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Recording audio... tap attach and choose stop.',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        if (_isTranscribing)
                          Padding(
                            padding: const EdgeInsets.only(
                                top: 8, left: 8, right: 8),
                            child: Text(
                              'Voice transcription is active.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        if (!canSendInChat && status != 'cancelled')
                          Padding(
                            padding: const EdgeInsets.only(
                                top: 4, left: 8, right: 8),
                            child: Row(
                              children: <Widget>[
                                Expanded(
                                  child: Text(
                                    'You are not a participant in this chat.',
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                TextButton(
                                  onPressed: _isRepairing
                                      ? null
                                      : () {
                                          _retryChatSetup(
                                            overviewMessage: overviewMessage,
                                            overviewMedia: overviewMedia,
                                            silent: false,
                                          );
                                        },
                                  child: _isRepairing
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Text('Retry Setup'),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildJoinSection(
    BuildContext context, {
    required List<Map<String, dynamic>> participants,
    required bool isCancelled,
  }) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Participants (${participants.length})',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            if (participants.isEmpty)
              const Text('No participants yet')
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: participants.map((entry) {
                  final uid = (entry['uid'] as String?) ?? 'unknown';
                  final role = (entry['role'] as String?) ?? 'participant';
                  final displayName = _uiDisplayName(
                    entry['displayName'] as String?,
                    fallback: uid,
                  );
                  final label =
                      entry['isAi'] == true ? 'RescueLink AI' : displayName;
                  return Chip(label: Text('$label ($role)'));
                }).toList(),
              ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                ElevatedButton(
                  onPressed:
                      _isJoining || isCancelled ? null : _joinConversation,
                  child: _isJoining
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Join Conversation'),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: isCancelled
                      ? null
                      : () {
                          setState(() {
                            _viewOverviewOnly = true;
                          });
                        },
                  child: const Text('View Overview Only'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _joinConversation() async {
    setState(() {
      _isJoining = true;
      _viewOverviewOnly = false;
    });

    try {
      await _chatService.joinResponder(
        sosId: widget.sosId,
        responderUid: widget.currentUserId,
        responderName: widget.currentUserName,
      );
      await _updateResponderPresence(true);
    } finally {
      if (mounted) {
        setState(() {
          _isJoining = false;
        });
      }
    }
  }

  Widget _buildChatActionsMenu() {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _chatService.watchChat(widget.sosId),
      builder: (context, snapshot) {
        final chatData = snapshot.data?.data() ?? <String, dynamic>{};
        final status = (chatData['status'] as String?) ?? 'active';
        final participants = _asMapList(chatData['participants']);
        final hasJoined = participants.any(
          (entry) => (entry['uid'] as String?) == widget.currentUserId,
        );

        final canDeleteForVictim =
            widget.currentUserRole == 'victim' && hasJoined;
        final canLeaveForResponder =
            _isResponder && hasJoined && status != 'cancelled';

        if (!canDeleteForVictim && !canLeaveForResponder) {
          return const SizedBox.shrink();
        }

        return PopupMenuButton<String>(
          tooltip: 'Chat actions',
          onSelected: (value) {
            if (value == 'delete_chat') {
              _confirmDeleteChatForVictim();
              return;
            }
            if (value == 'leave_chat') {
              _confirmLeaveResponderChat();
            }
          },
          itemBuilder: (context) => <PopupMenuEntry<String>>[
            if (canDeleteForVictim)
              const PopupMenuItem<String>(
                value: 'delete_chat',
                child: Text('Delete Chat (Victim)'),
              ),
            if (canLeaveForResponder)
              const PopupMenuItem<String>(
                value: 'leave_chat',
                child: Text('Leave Chat (Responder)'),
              ),
          ],
        );
      },
    );
  }

  Future<void> _confirmDeleteChatForVictim() async {
    final shouldDelete = await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Text('Delete chat?'),
              content: const Text(
                'This removes the SOS group chat document for this incident.',
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Delete'),
                ),
              ],
            );
          },
        ) ??
        false;
    if (!shouldDelete) {
      return;
    }

    try {
      await _chatService.cancelChatFromSosId(
        sosId: widget.sosId,
        deleteDocument: true,
      );

      if (!mounted) {
        return;
      }

      Navigator.of(context).maybePop();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to delete chat right now. Please retry.'),
          ),
        );
      }
    }
  }

  Future<void> _confirmLeaveResponderChat() async {
    final shouldLeave = await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Text('Leave responder chat?'),
              content: const Text(
                'You will stop receiving messages in this group chat until you join again.',
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Leave'),
                ),
              ],
            );
          },
        ) ??
        false;
    if (!shouldLeave) {
      return;
    }

    try {
      await _chatService.leaveResponder(
        sosId: widget.sosId,
        responderUid: widget.currentUserId,
      );
      await _chatService.clearResponderPresence(
        sosId: widget.sosId,
        responderUid: widget.currentUserId,
      );

      if (!mounted) {
        return;
      }

      Navigator.of(context).maybePop();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to leave chat right now. Please retry.'),
          ),
        );
      }
    }
  }

  Widget _buildAudioAttachmentBubble(String audioUrl) {
    final isCurrent = _playingChatAudioUrl == audioUrl;
    final isPlaying = isCurrent && _isChatAudioPlaying;
    final duration = isCurrent ? _chatAudioDuration : Duration.zero;
    final position = isCurrent ? _chatAudioPosition : Duration.zero;
    final progress = duration.inMilliseconds <= 0
        ? 0.0
        : (position.inMilliseconds / duration.inMilliseconds)
            .clamp(0.0, 1.0)
            .toDouble();

    return Container(
      width: 220,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              IconButton(
                constraints:
                    const BoxConstraints.tightFor(width: 30, height: 30),
                padding: EdgeInsets.zero,
                onPressed: () => _toggleChatAudioPlayback(audioUrl),
                icon: Icon(
                  isPlaying
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_fill,
                  size: 24,
                ),
                tooltip: isPlaying ? 'Pause' : 'Play',
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isCurrent
                      ? '${_formatDuration(position)} / ${_formatDuration(duration)}'
                      : 'Voice attachment',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(value: progress),
        ],
      ),
    );
  }

  Future<void> _toggleChatAudioPlayback(String audioUrl) async {
    if (_playingChatAudioUrl == audioUrl) {
      if (_isChatAudioPlaying) {
        await _chatAudioPlayer.pause();
        if (mounted) {
          setState(() {
            _isChatAudioPlaying = false;
          });
        }
        return;
      }

      await _chatAudioPlayer.resume();
      if (mounted) {
        setState(() {
          _isChatAudioPlaying = true;
        });
      }
      return;
    }

    await _chatAudioPlayer.stop();
    await _chatAudioPlayer.play(UrlSource(audioUrl));
    if (mounted) {
      setState(() {
        _playingChatAudioUrl = audioUrl;
        _isChatAudioPlaying = true;
        _chatAudioPosition = Duration.zero;
        _chatAudioDuration = Duration.zero;
      });
    }
  }

  String _formatDuration(Duration duration) {
    final safeDuration = duration.isNegative ? Duration.zero : duration;
    final totalSeconds = safeDuration.inSeconds;
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _retryChatSetup({
    required String overviewMessage,
    required List<Map<String, dynamic>> overviewMedia,
    bool silent = false,
  }) async {
    if (_isRepairing) {
      return;
    }

    setState(() {
      _isRepairing = true;
    });

    Object? lastError;
    var chatReady = false;

    try {
      chatReady = await _chatService.ensureChatFromEmergencyRequest(
        sosId: widget.sosId,
      );
    } catch (e) {
      lastError = e;
      chatReady = false;
    }

    if (chatReady && widget.currentUserRole == 'victim') {
      try {
        chatReady = await _chatService.ensureVictimParticipant(
          sosId: widget.sosId,
          victimUid: widget.currentUserId,
          victimName: widget.currentUserName,
        );
      } catch (e) {
        lastError = e;
        chatReady = false;
      }
    }

    if (!chatReady && widget.currentUserRole == 'victim') {
      try {
        await _chatService.createChatOnSos(
          sosId: widget.sosId,
          victimUid: widget.currentUserId,
          victimName: widget.currentUserName,
          sosMessage: overviewMessage.trim().isEmpty
              ? 'Potential emergency needs urgent support.'
              : overviewMessage,
          media: overviewMedia,
        );
      } catch (e) {
        lastError = e;
      }

      try {
        chatReady = await _chatService.ensureChatFromEmergencyRequest(
          sosId: widget.sosId,
        );
      } catch (e) {
        lastError = e;
        chatReady = false;
      }

      if (chatReady) {
        try {
          chatReady = await _chatService.ensureVictimParticipant(
            sosId: widget.sosId,
            victimUid: widget.currentUserId,
            victimName: widget.currentUserName,
          );
        } catch (e) {
          lastError = e;
          chatReady = false;
        }
      }
    }

    if (mounted) {
      if (chatReady) {
        _setupStatusText = null;
      } else {
        _setupStatusText = silent
            ? 'Reconnecting to chat service... retrying automatically.'
            : _chatSetupFailureText(lastError);
      }

      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              chatReady
                  ? 'Chat setup refreshed. You can try sending now.'
                  : _chatSetupFailureText(lastError),
            ),
          ),
        );
      }

      setState(() {
        _isRepairing = false;
      });
    }
  }

  void _syncAutoRepairState({
    required bool shouldAutoRepair,
    required String overviewMessage,
    required List<Map<String, dynamic>> overviewMedia,
  }) {
    if (shouldAutoRepair == _autoRepairEnabled) {
      return;
    }

    _autoRepairEnabled = shouldAutoRepair;

    if (!shouldAutoRepair) {
      _autoRepairTimer?.cancel();
      _autoRepairTimer = null;
      if (_setupStatusText != null && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) {
            return;
          }
          setState(() {
            _setupStatusText = null;
          });
        });
      }
      return;
    }

    _setupStatusText =
        'Reconnecting to chat service... retrying automatically.';
    _autoRepairTimer?.cancel();
    _autoRepairTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!mounted || !_autoRepairEnabled || _isRepairing) {
        return;
      }

      _retryChatSetup(
        overviewMessage: overviewMessage,
        overviewMedia: overviewMedia,
        silent: true,
      );
    });
  }

  Widget _buildHeader(
    BuildContext context, {
    required int responderOnlineCount,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'RescueLink Group Chat • $responderOnlineCount responders online',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
    );
  }

  Widget _buildOverviewCard(
    BuildContext context, {
    required String message,
    required List<Map<String, dynamic>> media,
  }) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'SOS Overview',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(message),
            if (media.isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              SizedBox(
                height: 72,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: media.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final item = media[index];
                    final type = (item['type'] as String?) ?? 'media';
                    final url = (item['url'] as String?) ?? '';
                    final isImage = type.toLowerCase().contains('image');

                    if (isImage && url.isNotEmpty) {
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          url,
                          width: 72,
                          height: 72,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _mediaFallback(type),
                        ),
                      );
                    }

                    return _mediaFallback(type);
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _mediaFallback(String type) {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: Colors.black12,
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Text(
        type,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 11),
      ),
    );
  }

  int _resolveResponderOnlineCount(Map<String, dynamic> chatData) {
    final status = (chatData['status'] as String?) ?? 'active';
    if (status == 'cancelled') {
      return 0;
    }

    final presence = _asBoolMap(chatData['responderPresence']);
    if (presence.isNotEmpty) {
      return presence.values.where((value) => value).length;
    }

    final onlineCountRaw = chatData['onlineCount'];
    if (onlineCountRaw is num) {
      return onlineCountRaw.toInt();
    }

    final participants = _asMapList(chatData['participants']);
    return participants
        .where((entry) =>
            (entry['role'] as String?) == 'responder' && entry['isAi'] != true)
        .length;
  }

  Map<String, dynamic> _asMap(dynamic raw) {
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    return <String, dynamic>{};
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

  Map<String, bool> _asBoolMap(dynamic raw) {
    if (raw is! Map) {
      return const <String, bool>{};
    }

    final result = <String, bool>{};
    raw.forEach((key, value) {
      if (key is String && value is bool) {
        result[key] = value;
      }
    });
    return result;
  }

  Set<String> _resolveParticipantUids({
    required Map<String, dynamic> chatData,
    required List<Map<String, dynamic>> participants,
  }) {
    final fromField = _asStringSet(chatData['participantUids']);
    if (fromField.isNotEmpty) {
      return fromField;
    }

    return participants
        .map((entry) => entry['uid'] as String?)
        .whereType<String>()
        .toSet();
  }

  Set<String> _asStringSet(dynamic raw) {
    if (raw is! List) {
      return const <String>{};
    }

    return raw.whereType<String>().toSet();
  }

  List<Map<String, dynamic>> _asMediaList(dynamic raw) {
    return _asMapList(raw);
  }

  void _queuePresenceUpdate(bool shouldBeOnline) {
    if (!_isResponder) {
      return;
    }

    if (_presenceTargetOnline == shouldBeOnline &&
        _presenceOnline == shouldBeOnline) {
      return;
    }

    _presenceTargetOnline = shouldBeOnline;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _updateResponderPresence(_presenceTargetOnline);
    });
  }

  Future<void> _updateResponderPresence(bool isOnline) async {
    if (!_isResponder || _presenceOnline == isOnline) {
      return;
    }

    _presenceOnline = isOnline;
    _presenceTargetOnline = isOnline;
    await _chatService.setResponderPresence(
      sosId: widget.sosId,
      responderUid: widget.currentUserId,
      isOnline: isOnline,
    );
  }

  void _clearPresenceOnDispose() {
    if (!_isResponder) {
      return;
    }

    _presenceOnline = false;
    _presenceTargetOnline = false;

    _chatService.clearResponderPresence(
      sosId: widget.sosId,
      responderUid: widget.currentUserId,
    );
  }

  String _chatSetupFailureText(Object? error) {
    if (error is FirebaseException) {
      switch (error.code) {
        case 'permission-denied':
          return 'Chat permission denied. Please sign in again and retry.';
        case 'unavailable':
          return 'Network unavailable while opening chat. Please retry.';
        case 'failed-precondition':
          return 'Chat setup missing backend index/precondition. Please retry shortly.';
        case 'not-found':
          return 'SOS chat record not found yet. Please retry in a moment.';
        case 'invalid-argument':
          return 'Chat payload validation failed. Please retry setup.';
      }
    }
    return 'Chat setup failed. Please retry.';
  }

  String _timeText(DateTime dateTime) {
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _uiDisplayName(String? raw, {required String fallback}) {
    final trimmed = raw?.trim();
    final base = (trimmed == null || trimmed.isEmpty) ? fallback : trimmed;
    const maxUiNameLength = 40;
    if (base.length <= maxUiNameLength) {
      return base;
    }
    return '${base.substring(0, maxUiNameLength)}...';
  }
}
