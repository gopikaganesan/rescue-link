import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/providers/app_settings_provider.dart';
import '../core/services/media_upload_service.dart';
import '../core/services/text_translation_service.dart';
import '../core/utils/chat_message_utils.dart';
import '../widgets/translated_text.dart';
import '../services/chat_service.dart';
import '../core/models/responder_model.dart';
import 'responder_profile_screen.dart';

class AIHighlightingController extends TextEditingController {
  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (text.isEmpty) {
      return const TextSpan();
    }

    final children = <TextSpan>[];
    final regex = RegExp(r'@ai\b', caseSensitive: false);
    int lastIndex = 0;

    for (final match in regex.allMatches(text)) {
      if (match.start > lastIndex) {
        children.add(TextSpan(
          text: text.substring(lastIndex, match.start),
          style: style,
        ));
      }
      children.add(TextSpan(
        text: match.group(0),
        style: style?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ) ??
            const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
      ));
      lastIndex = match.end;
    }

    if (lastIndex < text.length) {
      children.add(TextSpan(
        text: text.substring(lastIndex),
        style: style,
      ));
    }

    return TextSpan(style: style, children: children);
  }
}

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
  with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final ChatService _chatService = ChatService();
  final MediaUploadService _mediaUploadService =
      MediaUploadService.fromEnvironment();
    final TextTranslationService _textTranslationService =
      TextTranslationService();
  final AIHighlightingController _controller = AIHighlightingController();
  final ImagePicker _imagePicker = ImagePicker();
  final SpeechToText _speechToText = SpeechToText();
  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPreviewPlayer = AudioPlayer();
  final AudioPlayer _chatAudioPlayer = AudioPlayer();
  final FlutterTts _flutterTts = FlutterTts();
  late final AnimationController _typingDotsController;
  static const int _maxMessageLength = 1000;
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
  bool _showFullOverview = false;
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
  String? _speakingMessageId;
  Duration _chatAudioPosition = Duration.zero;
  Duration _chatAudioDuration = Duration.zero;
  StreamSubscription<Duration>? _chatAudioPositionSub;
  StreamSubscription<Duration>? _chatAudioDurationSub;
  StreamSubscription<void>? _chatAudioCompleteSub;
  Map<String, dynamic>? _sosRequestData;
  List<String> _detectedNumbersInDraft = [];
  final Map<String, String> _translatedMessageTextById = <String, String>{};
  final Map<String, String> _translationSourceTextById = <String, String>{};
  final Set<String> _translationInFlightIds = <String>{};
  String? _lastTranslationLanguageCode;

  bool get _isResponder => widget.currentUserRole == 'responder';
  bool get _canManageResponders => widget.currentUserRole == 'victim';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _typingDotsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _initializeSpeech();
    _configureTextToSpeech();
    _loadMasterSosData();
    _controller.addListener(_onComposeTextChange);
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

  Future<void> _loadMasterSosData() async {
    final requestData = await _chatService.fetchEmergencyRequest(widget.sosId);
    if (!mounted) {
      return;
    }
    setState(() {
      _sosRequestData = requestData;
    });
  }

  void _onComposeTextChange() {
    final detectedNumbers = _extractPhoneNumbers(_controller.text);
    if (_detectedNumbersInDraft.length == detectedNumbers.length &&
        _detectedNumbersInDraft.every(detectedNumbers.contains)) {
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _detectedNumbersInDraft = detectedNumbers;
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
    _typingDotsController.dispose();
    _autoRepairTimer?.cancel();
    _clearPresenceOnDispose();
    _speechToText.stop();
    _audioRecorder.dispose();
    _audioPreviewPlayer.dispose();
    _flutterTts.stop();
    _chatAudioPositionSub?.cancel();
    _chatAudioDurationSub?.cancel();
    _chatAudioCompleteSub?.cancel();
    _chatAudioPlayer.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_isSending) {
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
      final attachmentUrl = uploadedAttachment?['url'];
      final attachmentType = uploadedAttachment?['type'];

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
      _hapticLight();

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
    if (_isSending) {
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
    if (_isSending) {
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
    if (_isSending) {
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
    if (_isSending) {
      return;
    }

    final canRecordAudio = await _audioRecorder.hasPermission();
    if (!canRecordAudio) {
      if (mounted) {
          final settings = context.read<AppSettingsProvider>();
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(settings.t('chat_microphone_required')),
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

  Future<void> _askAiFromComposer() async {
    if (_isAskingAi || _isSending) {
      return;
    }

    final prompt = _controller.text.trim();
    final effectivePrompt = prompt.isEmpty
        ? 'Analyze the current emergency chat context. Generate content for possible scenarios that could evolve from this, and provide actionable step-by-step maps/protocols according to each scenario.'
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
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _chatService.watchChat(widget.sosId),
      builder: (context, chatSnapshot) {
        final chatLoaded = chatSnapshot.hasData;
        final chatData = chatSnapshot.data?.data() ?? <String, dynamic>{};
        final overview = _asMap(chatData['sosOverview']);
        final overviewMessage =
            (overview['message'] as String?) ?? 'No SOS message available';
        final overviewMedia = _asMediaList(overview['media']);
        // Master fallback from the SOS master record if chat data is incomplete
        final masterLat = _asDouble(_sosRequestData?['latitude']) ??
            _asDouble(_sosRequestData?['victimLatitude']) ??
            _asDouble(_sosRequestData?['requesterLatitude']) ??
            _asDouble(
                (_sosRequestData?['victimLocation'] as Map?)?['latitude']);
        final masterLng = _asDouble(_sosRequestData?['longitude']) ??
            _asDouble(_sosRequestData?['victimLongitude']) ??
            _asDouble(_sosRequestData?['requesterLongitude']) ??
            _asDouble(
                (_sosRequestData?['victimLocation'] as Map?)?['longitude']);
        final masterAddress = (_sosRequestData?['address'] as String?) ??
            (_sosRequestData?['victimAddress'] as String?) ??
            (_sosRequestData?['requesterAddress'] as String?);

        final overviewWithLocation = <String, dynamic>{
          ...overview,
          if (!overview.containsKey('latitude'))
            'latitude': _asDouble(chatData['latitude']) ??
                _asDouble(chatData['victimLatitude']) ??
                _asDouble(chatData['requesterLatitude']) ??
                _asDouble((chatData['victimLocation'] as Map?)?['latitude']) ??
                (chatData['location'] is GeoPoint
                    ? (chatData['location'] as GeoPoint).latitude
                    : null) ??
                masterLat,
          if (!overview.containsKey('longitude'))
            'longitude': _asDouble(chatData['longitude']) ??
                _asDouble(chatData['victimLongitude']) ??
                _asDouble(chatData['requesterLongitude']) ??
                _asDouble((chatData['victimLocation'] as Map?)?['longitude']) ??
                (chatData['location'] is GeoPoint
                    ? (chatData['location'] as GeoPoint).longitude
                    : null) ??
                masterLng,
          if (!overview.containsKey('address'))
            'address': (overview['address'] as String?)?.isNotEmpty == true
                ? overview['address']
                : (chatData['address'] ??
                    chatData['victimAddress'] ??
                    chatData['requesterAddress'] ??
                    masterAddress),
        };
        final status = (chatData['status'] as String?) ?? 'active';
        final responderOnlineCount = _resolveResponderOnlineCount(chatData);
        final participants = _asMapList(chatData['participants']);
        final notificationPreferences =
          _asMap(chatData['notificationPreferences']);
        final chatNotificationsEnabled =
          notificationPreferences[widget.currentUserId] != false;
        final participantUids = _resolveParticipantUids(
          chatData: chatData,
          participants: participants,
        );
        final blockedUids =
            (chatData['blockedUids'] as List<dynamic>?)?.cast<String>() ??
                <String>[];
        final joinRequests = (chatData['joinRequests'] as List<dynamic>?)
                ?.cast<Map<String, dynamic>>() ??
            <Map<String, dynamic>>[];
        final isResponder = _isResponder;
        final hasJoined = participants
            .any((entry) => (entry['uid'] as String?) == widget.currentUserId);
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

        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.read<AppSettingsProvider>().t('chat_group_title'),
                  style: const TextStyle(fontSize: 16),
                ),
                Row(
                  children: [
                    const Icon(Icons.circle, size: 10, color: Colors.green),
                    const SizedBox(width: 4),
                    Text(
                        context
                            .read<AppSettingsProvider>()
                            .t('chat_online_count')
                            .replaceAll('{count}', '$responderOnlineCount'),
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.normal,
                            color: Colors.green)),
                    const SizedBox(width: 12),
                    _buildAiStatusBadge(chatData),
                  ],
                ),
              ],
            ),
            actions: <Widget>[
              _buildChatActionsMenu(
                participants,
                chatNotificationsEnabled: chatNotificationsEnabled,
              ),
            ],
          ),
          body: Column(
            children: <Widget>[
              _buildOverviewCard(
                context,
                message: overviewMessage,
                media: overviewMedia,
                overview: overviewWithLocation,
              ),
              if (_canManageResponders &&
                  joinRequests.any((r) => r['status'] == 'pending'))
                _buildJoinRequestsHeader(joinRequests),
              if (showJoinGate)
                _buildJoinSection(
                  context,
                  participants: participants,
                  blockedUids: blockedUids,
                  joinRequests: joinRequests,
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
                  child: Text(context.read<AppSettingsProvider>().t('chat_sos_cancelled')),
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
                        return Center(
                          child: Text(context.read<AppSettingsProvider>().t('chat_failed_load_messages')),
                        );
                      }

                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final docs = snapshot.data?.docs ??
                          const <QueryDocumentSnapshot<Map<String, dynamic>>>[];

                      final targetLanguageCode = context
                          .watch<AppSettingsProvider>()
                          .languageCode
                          .trim()
                          .toLowerCase();
                      _scheduleMessageTranslations(
                        docs: docs,
                        targetLanguageCode: targetLanguageCode,
                      );

                      if (docs.isEmpty) {
                        return Center(
                          child: Text(context.read<AppSettingsProvider>().t('chat_no_messages_yet')),
                        );
                      }

                      return ListView.builder(
                        reverse: true,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final docId = docs[index].id;
                          final data = docs[index].data();
                          final senderUid =
                              (data['senderUid'] as String?) ?? '';
                          final isAiMessage = data['isAi'] == true ||
                              senderUid == 'rescuelink_ai';
                          final senderName = _uiDisplayName(
                            data['senderName'] as String?,
                            fallback: context
                                .read<AppSettingsProvider>()
                                .t('name_user'),
                          );
                          final rawText = (data['text'] as String?) ?? '';
                          final text = _translatedMessageTextById[docId] ?? rawText;
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

                          final isSystem = data['type'] == 'system' ||
                              data['isSystem'] == true;

                          if (isSystem) {
                            return Container(
                              margin: const EdgeInsets.symmetric(vertical: 8),
                              alignment: Alignment.center,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Text(
                                  text,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.w500,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                ),
                              ),
                            );
                          }

                          return Semantics(
                            container: true,
                            label: _buildMessageSemanticLabel(
                              senderName: senderName,
                              text: text,
                              isAiMessage: isAiMessage,
                              createdAt: createdAt,
                              hasImageAttachment: hasImageAttachment,
                              hasAudioAttachment: hasAudioAttachment,
                            ),
                            child: Align(
                              alignment: isMine
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: Row(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (!isMine && !isSystem)
                                  Padding(
                                    padding:
                                        const EdgeInsets.only(right: 8, top: 4),
                                    child: GestureDetector(
                                      onTap: () => _showResponderOptions(
                                        context: context,
                                        participantData: {
                                          'uid': senderUid,
                                          'displayName': senderName,
                                          'isAi': isAiMessage,
                                        },
                                        responderName: senderName,
                                      ),
                                      child: CircleAvatar(
                                        radius: 16,
                                        backgroundColor: isAiMessage
                                            ? Colors.purple.shade100
                                            : Theme.of(context)
                                                .colorScheme
                                                .primaryContainer,
                                        child: Text(
                                          senderName.isNotEmpty
                                              ? senderName[0].toUpperCase()
                                              : '?',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: isAiMessage
                                                ? Colors.purple
                                                : Theme.of(context)
                                                    .colorScheme
                                                    .primary,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                Flexible(
                                  child: GestureDetector(
                                    onLongPress: () {
                                      if (isMine &&
                                          (hasImageAttachment ||
                                              hasAudioAttachment)) {
                                        showDialog(
                                          context: context,
                                          builder: (context) => AlertDialog(
                                            title: const Text('Delete Message'),
                                            content: const Text(
                                                'Do you want to delete this message and its media?'),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(context),
                                                child: const Text('Cancel'),
                                              ),
                                              TextButton(
                                                onPressed: () async {
                                                  Navigator.pop(context);
                                                  final deleted = await _chatService
                                                      .deleteMessageWithMedia(
                                                    sosId: widget.sosId,
                                                    messageId: docId,
                                                    requestedByUid:
                                                        widget.currentUserId,
                                                  );
                                                  if (!mounted) {
                                                    return;
                                                  }
                                                  ScaffoldMessenger.of(this.context)
                                                      .showSnackBar(
                                                    SnackBar(
                                                      content: Text(
                                                        deleted
                                                            ? 'Message and media deleted.'
                                                            : 'Unable to delete this media message.',
                                                      ),
                                                    ),
                                                  );
                                                },
                                                child: const Text('Delete',
                                                    style: TextStyle(
                                                        color: Colors.red)),
                                              ),
                                            ],
                                          ),
                                        );
                                      }
                                    },
                                    child: Container(
                                      margin: const EdgeInsets.symmetric(
                                          vertical: 5),
                                      padding: const EdgeInsets.all(10),
                                      constraints: BoxConstraints(
                                        maxWidth:
                                            MediaQuery.of(context).size.width *
                                                0.84,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isAiMessage
                                            ? Colors.red.shade50
                                            : isMine
                                                ? Theme.of(context)
                                                    .colorScheme
                                                    .primaryContainer
                                                : Theme.of(context)
                                                    .colorScheme
                                                    .surfaceContainerHighest,
                                        borderRadius: BorderRadius.circular(18),
                                        border: Border.all(
                                          color: isAiMessage
                                              ? Colors.red.shade200
                                              : isMine
                                                  ? Theme.of(context)
                                                      .colorScheme
                                                      .primary
                                                      .withValues(alpha: 0.16)
                                                  : Theme.of(context)
                                                      .colorScheme
                                                      .outlineVariant
                                                      .withValues(alpha: 0.22),
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: <Widget>[
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: <Widget>[
                                              Flexible(
                                                child: Text(
                                                  isAiMessage
                                                    ? '${context.read<AppSettingsProvider>().localizedDisplayName(senderName)} • ${context.read<AppSettingsProvider>().t('name_ai')}'
                                                      : senderName,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .labelMedium
                                                      ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: isAiMessage
                                                            ? Colors
                                                                .red.shade900
                                                            : null,
                                                      ),
                                                ),
                                              ),
                                              if (text.trim().isNotEmpty) ...<Widget>[
                                                const SizedBox(width: 6),
                                                Semantics(
                                                  button: true,
                                                  label: _speakingMessageId == docId
                                                      ? 'Stop reading this message'
                                                      : 'Listen to this message',
                                                  child: IconButton(
                                                    visualDensity:
                                                        VisualDensity.compact,
                                                    constraints:
                                                        const BoxConstraints(
                                                      minWidth: 28,
                                                      minHeight: 28,
                                                    ),
                                                    padding: EdgeInsets.zero,
                                                    onPressed: () {
                                                      _toggleMessageReadAloud(
                                                        messageId: docId,
                                                        senderName: senderName,
                                                        text: text,
                                                      );
                                                    },
                                                    icon: Icon(
                                                      _speakingMessageId == docId
                                                          ? Icons.stop_circle
                                                          : Icons.volume_up,
                                                      size: 16,
                                                    ),
                                                    tooltip:
                                                        _speakingMessageId ==
                                                            docId
                                                        ? 'Stop listening'
                                                        : 'Listen',
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          AnimatedSize(
                                            duration: const Duration(milliseconds: 220),
                                            curve: Curves.easeOutCubic,
                                            alignment: Alignment.topLeft,
                                            child: isAiMessage
                                                ? _buildAiMessageContent(
                                                    context, text)
                                                : _buildLinkableText(
                                                    context, text),
                                          ),
                                          if (hasImageAttachment) ...<Widget>[
                                            const SizedBox(height: 8),
                                            ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              child: Image.network(
                                                attachmentUrl,
                                                fit: BoxFit.cover,
                                                errorBuilder: (_, __, ___) =>
                                                    Container(
                                                  width: 180,
                                                  height: 120,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .surfaceContainerHighest,
                                                  alignment: Alignment.center,
                                                  child: const Text(
                                                      'Image unavailable'),
                                                ),
                                              ),
                                            ),
                                          ],
                                          if (hasAudioAttachment) ...<Widget>[
                                            const SizedBox(height: 8),
                                            _buildAudioAttachmentBubble(
                                                chatAudioUrl),
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
                                  ),
                                ),
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
                Padding(
                  padding: EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      context.read<AppSettingsProvider>().t('chat_overview_only_hint'),
                    ),
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
                        // Ask AI Button (Placed above chat box)
                        if (canSendInChat)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              children: <Widget>[
                                const Spacer(),
                                Container(
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary
                                        .withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary
                                          .withValues(alpha: 0.2),
                                      width: 1,
                                    ),
                                  ),
                                  child: TextButton.icon(
                                    style: TextButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12),
                                    ),
                                    onPressed: _isAskingAi || _isSending
                                        ? null
                                        : _askAiFromComposer,
                                    icon: _isAskingAi
                                      ? _typingDots(context)
                                        : Icon(
                                            Icons.volunteer_activism,
                                            size: 18,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary,
                                          ),
                                    label: Text(
                                      context.read<AppSettingsProvider>().t('chat_ask_ai_assistant'),
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        // Real-time Phone Detection Chips
                        if (_detectedNumbersInDraft.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: _detectedNumbersInDraft
                                    .map((phoneNumber) => Padding(
                                          padding:
                                              const EdgeInsets.only(right: 8),
                                          child: ActionChip(
                                            avatar: const Icon(Icons.phone,
                                                size: 14),
                                            label: Text('Call $phoneNumber'),
                                            onPressed: () =>
                                                _callEmergencyNumber(
                                                    phoneNumber),
                                            backgroundColor: Colors.red[50],
                                            side: BorderSide(
                                                color: Colors.red
                                                    .withValues(alpha: 0.2)),
                                          ),
                                        ))
                                    .toList(),
                              ),
                            ),
                          ),
                        // Attachments Preview (Placed above chat box)
                        if (_selectedImageAttachment != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: <Widget>[
                                GestureDetector(
                                  onTap: () async {
                                    final uri = Uri.file(
                                        _selectedImageAttachment!.path);
                                    if (await canLaunchUrl(uri)) {
                                      await launchUrl(uri);
                                    }
                                  },
                                  child: ClipRRect(
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
                                        child: const Icon(
                                            Icons.image_not_supported),
                                      ),
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
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: <Widget>[
                                IconButton(
                                  onPressed: _previewVoiceAttachment,
                                  icon: Icon(
                                    _isPreviewPlaying
                                        ? Icons.stop_circle_outlined
                                        : Icons.play_circle_fill,
                                    color:
                                        Theme.of(context).colorScheme.primary,
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
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: <Widget>[
                                const SizedBox(
                                  width: 12,
                                  height: 12,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Recording audio... tap mic again to stop.',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        if (_isTranscribing)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              'Voice transcription is active...',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        // Chat Input Box
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: <Widget>[
                            Expanded(
                              child: TextField(
                                controller: _controller,
                                enabled: canSendInChat,
                                maxLength: _maxMessageLength,
                                textInputAction: TextInputAction.send,
                                minLines: 1,
                                maxLines: 4,
                                onSubmitted: (_) {
                                  if (canSendInChat) _send();
                                },
                                decoration: InputDecoration(
                                  hintText: context.read<AppSettingsProvider>().t('chat_type_message'),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 12),
                                  prefixIcon: IconButton(
                                    icon: Icon(_isTranscribing
                                        ? Icons.stop
                                        : Icons.transcribe),
                                    onPressed: canSendInChat
                                        ? _toggleVoiceTranscription
                                        : null,
                                    tooltip: _isTranscribing
                                      ? context.read<AppSettingsProvider>().t('tooltip_stop_voice_to_text')
                                      : context.read<AppSettingsProvider>().t('tooltip_voice_to_text'),
                                  ),
                                  suffixIcon: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // Mic: record audio clip
                                      IconButton(
                                        icon: Icon(_isRecordingClip
                                            ? Icons.stop_circle
                                            : Icons.mic),
                                        color: _isRecordingClip
                                            ? Colors.red
                                            : null,
                                        onPressed: canSendInChat
                                            ? _toggleVoiceRecording
                                            : null,
                                        tooltip: _isRecordingClip
                                            ? 'Stop recording'
                                            : 'Record audio clip',
                                      ),
                                      // Attach: camera / gallery / location
                                      IconButton(
                                        icon: const Icon(Icons.attach_file),
                                        onPressed: canSendInChat
                                            ? () => _showAttachOptions(context)
                                            : null,
                                        tooltip: 'Attach',
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Send button minimized
                            Container(
                              margin: const EdgeInsets.only(
                                  bottom:
                                      4), // better center alignment with text field
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: canSendInChat
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.grey,
                              ),
                              child: IconButton(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                    minWidth: 40, minHeight: 40),
                                icon: _isSending
                                    ? const SizedBox(
                                        height: 18,
                                        width: 18,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white),
                                      )
                                    : const Icon(Icons.send,
                                        size: 20, color: Colors.white),
                                onPressed:
                                    !canSendInChat || _isSending || _isAskingAi
                                        ? null
                                        : _send,
                                tooltip: 'Send',
                              ),
                            ),
                          ],
                        ),
                        if (!canSendInChat && status != 'cancelled')
                          Padding(
                            padding: const EdgeInsets.only(
                                top: 8, left: 8, right: 8),
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
                                              strokeWidth: 2),
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
          ),
        );
      },
    );
  }

  Widget _buildJoinRequestsHeader(List<Map<String, dynamic>> requests) {
    final pending = requests.where((r) => r['status'] == 'pending').toList();
    if (pending.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .primaryContainer
            .withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color:
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.read<AppSettingsProvider>().t('chat_pending_join_requests'),
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ...pending.map((req) {
            final uid = req['uid'] as String;
            final name = _uiDisplayName(
              req['displayName'] as String?,
              fallback: context.read<AppSettingsProvider>().t('name_user'),
            );
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() :
                      context.read<AppSettingsProvider>().t('name_user')[0].toUpperCase(),
                ),
              ),
              title: Text(name),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: () => _handleJoinRequest(uid, name, 'rejected'),
                    child: Text(context.read<AppSettingsProvider>().t('button_reject'),
                        style: TextStyle(color: Colors.red)),
                  ),
                  FilledButton(
                    onPressed: () => _handleJoinRequest(uid, name, 'approved'),
                    child: Text(context.read<AppSettingsProvider>().t('button_accept')),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Future<void> _handleJoinRequest(
      String uid, String name, String status) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (!mounted) return;

      await _chatService.resolveJoinRequest(
        sosId: widget.sosId,
        request: {'uid': uid, 'displayName': name},
        approved: status == 'approved',
      );

      if (!mounted) return;
      final settings = context.read<AppSettingsProvider>();
      final localizedStatus = status == 'approved'
          ? settings.t('status_approved')
          : settings.t('status_rejected');
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            settings
                .t('chat_request_status')
                .replaceAll('{status}', localizedStatus)
                .replaceAll('{name}', name),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Widget _buildJoinSection(
    BuildContext context, {
    required List<Map<String, dynamic>> participants,
    required List<String> blockedUids,
    required List<Map<String, dynamic>> joinRequests,
    required bool isCancelled,
  }) {
    final settings = context.read<AppSettingsProvider>();
    final isBlocked = blockedUids.contains(widget.currentUserId);
    final requestStatus = _latestJoinRequestStatus(
      joinRequests: joinRequests,
      uid: widget.currentUserId,
    );

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              settings
                  .t('chat_participants_count')
                  .replaceAll('{count}', '${participants.length}'),
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            if (participants.isEmpty)
              Text(settings.t('chat_no_participants_yet'))
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
                  final label = entry['isAi'] == true
                      ? settings.t('chat_rescue_link_ai')
                      : displayName;
                  final localizedRole = settings.localizedDisplayName(role);
                  return ActionChip(
                    label: Text('$label ($localizedRole)'),
                    onPressed: entry['isAi'] == true
                        ? null
                        : () => _showResponderProfile(uid),
                    backgroundColor:
                        uid == widget.currentUserId ? Colors.red.shade50 : null,
                  );
                }).toList(),
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                ElevatedButton(
                  onPressed: _isJoining ||
                          isCancelled ||
                          requestStatus == 'pending' ||
                          requestStatus == 'rejected'
                      ? null
                      : () {
                          if (isBlocked) {
                            _requestApproval();
                          } else {
                            _joinConversation();
                          }
                        },
                  child: _isJoining
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          requestStatus == 'pending'
                              ? settings.t('chat_join_request_pending')
                              : requestStatus == 'rejected'
                                  ? settings.t('chat_join_permanently_blocked')
                                  : isBlocked
                                      ? settings.t('chat_join_request_to_join')
                                      : settings.t('chat_join_conversation'),
                        ),
                ),
                Tooltip(
                  message: settings.t('chat_toggle_overview_tooltip'),
                  child: OutlinedButton(
                    onPressed: isCancelled
                        ? null
                        : () {
                            setState(() {
                              _viewOverviewOnly = !_viewOverviewOnly;
                            });
                          },
                    child: Text(
                      _viewOverviewOnly
                          ? settings.t('chat_view_chat_preview')
                          : settings.t('chat_view_overview_only'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String? _latestJoinRequestStatus({
    required List<Map<String, dynamic>> joinRequests,
    required String uid,
  }) {
    if (uid.trim().isEmpty) {
      return null;
    }

    final mine = joinRequests
        .where((request) => (request['uid'] as String?) == uid)
        .toList();
    if (mine.isEmpty) {
      return null;
    }

    int millisForRequest(Map<String, dynamic> request) {
      final preferred = request['requestedAt'] ??
          request['resolvedAt'] ??
          request['updatedAt'];
      if (preferred is Timestamp) {
        return preferred.millisecondsSinceEpoch;
      }
      return 0;
    }

    mine.sort((a, b) => millisForRequest(a).compareTo(millisForRequest(b)));
    return mine.last['status'] as String?;
  }

  Future<void> _requestApproval() async {
    setState(() => _isJoining = true);
    final messenger = ScaffoldMessenger.of(context);
    final settings = context.read<AppSettingsProvider>();
    try {
      await _chatService.requestJoinApproval(
        sosId: widget.sosId,
        responderUid: widget.currentUserId,
        responderName: widget.currentUserName,
      );
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(
          settings.t('chat_join_request_sent'),
        ),
      ));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            settings
                .t('chat_failed_request')
                .replaceAll('{error}', '$e'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isJoining = false);
    }
  }

  Future<void> _showResponderProfile(String uid) async {
    if (uid.isEmpty || uid == 'unknown') return;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final settings = context.read<AppSettingsProvider>();

    try {
      messenger.showSnackBar(
        SnackBar(
          content: Text(settings.t('chat_fetching_profile')),
          duration: const Duration(milliseconds: 500),
        ),
      );

      final snapshot = await FirebaseFirestore.instance
          .collection('responders')
          .doc(uid)
          .get();

      if (!mounted) return;

      if (!snapshot.exists) {
        messenger.showSnackBar(
          SnackBar(content: Text(settings.t('chat_profile_not_found'))),
        );
        return;
      }

      final data = snapshot.data()!;
      data['id'] = snapshot.id;
      final responderModel = ResponderModel.fromMap(data);

      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => ResponderProfileScreen(
            responder: responderModel,
            currentUserId: widget.currentUserId,
            currentUserName: widget.currentUserName,
            isCurrentUserProfile: uid == widget.currentUserId,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('${settings.t('chat_failed_load_profile')}$e')),
      );
    }
  }

  Future<void> _joinConversation() async {
    setState(() {
      _isJoining = true;
      _viewOverviewOnly = false;
    });

    final messenger = ScaffoldMessenger.of(context);

    try {
      // 1. Join Chat (Participant List)
      await _chatService.joinResponder(
        sosId: widget.sosId,
        responderUid: widget.currentUserId,
        responderName: widget.currentUserName,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _viewOverviewOnly = false;
      });

      // 2. Presence (Online Status)
      try {
        if (!mounted) {
          return;
        }
        await _updateResponderPresence(true);
      } catch (presErr) {
        debugPrint('Presence error: $presErr');
      }
    } catch (e) {
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text('Unable to join chat: $e'),
          backgroundColor: Colors.red.shade800,
          action: SnackBarAction(
            label: 'Retry',
            textColor: Colors.white,
            onPressed: _joinConversation,
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isJoining = false;
        });
      }
    }
  }

  Widget _buildChatActionsMenu(
    List<Map<String, dynamic>> contextParticipants, {
    required bool chatNotificationsEnabled,
  }) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _chatService.watchChat(widget.sosId),
      builder: (context, snapshot) {
        final chatData = snapshot.data?.data() ?? <String, dynamic>{};
        final status = (chatData['status'] as String?) ?? 'active';
        final participants = _asMapList(chatData['participants']);
        final participantUids = _asStringSet(chatData['participantUids']);
        final hasJoined = participantUids.contains(widget.currentUserId) ||
            participants.any(
              (entry) => (entry['uid'] as String?) == widget.currentUserId,
            );

        final canDeleteForVictim =
            widget.currentUserRole == 'victim' && hasJoined;
        final canLeaveForResponder =
            _isResponder && hasJoined && status != 'cancelled';
        final canShowNotificationToggle = hasJoined;

        if (!canDeleteForVictim &&
            !canLeaveForResponder &&
          !canShowNotificationToggle &&
            contextParticipants.isEmpty) {
          return const SizedBox.shrink();
        }

        return PopupMenuButton<String>(
          tooltip: context.read<AppSettingsProvider>().t('chat_actions_tooltip'),
          onSelected: (value) {
            if (value == 'view_responders') {
              _showRespondersList(context, contextParticipants);
              return;
            }
            if (value == 'delete_chat') {
              _confirmDeleteChatForVictim();
              return;
            }
            if (value == 'leave_chat') {
              _confirmLeaveResponderChat();
              return;
            }
            if (value == 'toggle_notifications') {
              _toggleChatNotifications(!chatNotificationsEnabled);
            }
          },
          itemBuilder: (context) => <PopupMenuEntry<String>>[
            PopupMenuItem<String>(
              value: 'view_responders',
              child: Text(context.read<AppSettingsProvider>().t('chat_view_responders')),
            ),
            if (canShowNotificationToggle)
              PopupMenuItem<String>(
                value: 'toggle_notifications',
                child: Text(
                  chatNotificationsEnabled
                      ? context.read<AppSettingsProvider>().t('menu_disable_notifications')
                      : context.read<AppSettingsProvider>().t('menu_enable_notifications'),
                ),
              ),
            if (canDeleteForVictim)
              PopupMenuItem<String>(
                value: 'delete_chat',
                child: Text(context.read<AppSettingsProvider>().t('chat_delete_chat_victim')),
              ),
            if (canLeaveForResponder)
              PopupMenuItem<String>(
                value: 'leave_chat',
                child: Text(context.read<AppSettingsProvider>().t('chat_leave_chat_responder')),
              ),
          ],
        );
      },
    );
  }

  void _showRespondersList(
      BuildContext context, List<Map<String, dynamic>> participants) {
    final responders =
        participants.where((p) => p['role'] == 'responder').toList();

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.read<AppSettingsProvider>().t('chat_active_responders').replaceAll('{count}', '${responders.length}'),
                style: Theme.of(ctx)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              if (responders.isEmpty)
                Text(context.read<AppSettingsProvider>().t('chat_no_participants_yet'))
              else
                Expanded(
                  child: ListView.builder(
                    itemCount: responders.length,
                    itemBuilder: (context, index) {
                      final p = responders[index];
                      final responderUid = (p['uid'] as String?) ?? '';
                      final isAi = (p['isAi'] as bool?) ?? false;
                      final name = _uiDisplayName(p['displayName'] as String?,
                          fallback: context.read<AppSettingsProvider>().t('name_responder'));
                      return ListTile(
                        leading: GestureDetector(
                          onTap: () {
                            Navigator.pop(ctx);
                            if (isAi) {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => ResponderProfileScreen(
                                    responder: ResponderModel.ai(),
                                    currentUserId: widget.currentUserId,
                                    currentUserName: widget.currentUserName,
                                    isCurrentUserProfile: false,
                                  ),
                                ),
                              );
                              return;
                            }
                            _showResponderProfile(responderUid);
                          },
                          child: CircleAvatar(
                            backgroundColor:
                                Theme.of(context).colorScheme.primaryContainer,
                            child: const Icon(Icons.person),
                          ),
                        ),
                        title: Text(name,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(context.read<AppSettingsProvider>().t('chat_tap_avatar_profile')),
                        trailing: PopupMenuButton<String>(
                          icon: const Icon(Icons.more_horiz),
                          onSelected: (value) {
                            Navigator.pop(ctx);
                            if (value == 'review') {
                              if (isAi) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content:
                                        Text('AI Assistant cannot be reviewed.'),
                                  ),
                                );
                                return;
                              }
                              _showReviewAndRatingDialog(
                                responderUid: responderUid,
                                responderName: name,
                              );
                              return;
                            }
                            if (value == 'remove') {
                              _confirmRemoveResponder(
                                messenger: ScaffoldMessenger.of(context),
                                responderUid: responderUid,
                                responderName: name,
                              );
                            }
                          },
                          itemBuilder: (menuContext) => <PopupMenuEntry<String>>[
                            const PopupMenuItem<String>(
                              value: 'review',
                              child: Text('Review & Rating'),
                            ),
                            if (_canManageResponders && !isAi &&
                                responderUid != widget.currentUserId)
                              const PopupMenuItem<String>(
                                value: 'remove',
                                child: Text('Remove Responder'),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
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
                'This closes the SOS group chat for this incident.',
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
        deleteDocument: false,
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
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to leave chat right now. Please retry.'),
        ),
      );
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
    _hapticSelection();
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

  void _configureTextToSpeech() {
    _flutterTts.setCompletionHandler(() {
      if (!mounted) {
        return;
      }
      setState(() {
        _speakingMessageId = null;
      });
    });
    _flutterTts.setCancelHandler(() {
      if (!mounted) {
        return;
      }
      setState(() {
        _speakingMessageId = null;
      });
    });
    unawaited(_flutterTts.setSpeechRate(0.46));
    unawaited(_flutterTts.setPitch(1.0));
    unawaited(_flutterTts.setVolume(1.0));
    unawaited(_applyPreferredTtsLanguage());
  }

  void _scheduleMessageTranslations({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    required String targetLanguageCode,
  }) {
    if (_lastTranslationLanguageCode != targetLanguageCode) {
      _lastTranslationLanguageCode = targetLanguageCode;
      _translatedMessageTextById.clear();
      _translationSourceTextById.clear();
      _translationInFlightIds.clear();
    }

    for (final doc in docs) {
      final docId = doc.id;
      final data = doc.data();
      final rawText = ((data['text'] as String?) ?? '').trim();
      if (rawText.isEmpty) {
        continue;
      }

      final lastSource = _translationSourceTextById[docId];
      if (lastSource == rawText && _translatedMessageTextById.containsKey(docId)) {
        continue;
      }
      if (_translationInFlightIds.contains(docId)) {
        continue;
      }

      _translationInFlightIds.add(docId);
      unawaited(_translateAndCacheMessage(
        docId: docId,
        rawText: rawText,
        targetLanguageCode: targetLanguageCode,
      ));
    }
  }

  Future<void> _translateAndCacheMessage({
    required String docId,
    required String rawText,
    required String targetLanguageCode,
  }) async {
    final translated = await _textTranslationService.translate(
      text: rawText,
      targetLanguageCode: targetLanguageCode,
    );

    _translationInFlightIds.remove(docId);
    if (!mounted) {
      return;
    }

    if (_lastTranslationLanguageCode != targetLanguageCode) {
      return;
    }

    setState(() {
      _translationSourceTextById[docId] = rawText;
      _translatedMessageTextById[docId] = translated;
    });
  }

  Future<void> _applyPreferredTtsLanguage({String? preferredLocale}) async {
    final languageCode =
        context.read<AppSettingsProvider>().languageCode.trim().toLowerCase();
    final appPreferredLocale = _preferredTtsLocale(languageCode);
    final localeCandidates = <String>[
      if (preferredLocale != null && preferredLocale.trim().isNotEmpty)
        preferredLocale.trim(),
      appPreferredLocale,
      'en-IN',
      'en-US',
    ];

    final triedLocales = <String>{};
    for (final locale in localeCandidates) {
      if (!triedLocales.add(locale)) {
        continue;
      }
      try {
        await _flutterTts.setLanguage(locale);
        return;
      } catch (_) {
        // Keep trying the next locale until one is supported.
      }
    }
  }

  String? _ttsLocaleFromDisplayedText(String text) {
    final safeText = text.trim();
    if (safeText.isEmpty) {
      return null;
    }

    if (RegExp(r'[\u0B80-\u0BFF]').hasMatch(safeText)) {
      return 'ta-IN';
    }
    if (RegExp(r'[\u0C00-\u0C7F]').hasMatch(safeText)) {
      return 'te-IN';
    }
    if (RegExp(r'[\u0C80-\u0CFF]').hasMatch(safeText)) {
      return 'kn-IN';
    }
    if (RegExp(r'[\u0D00-\u0D7F]').hasMatch(safeText)) {
      return 'ml-IN';
    }
    if (RegExp(r'[\u0980-\u09FF]').hasMatch(safeText)) {
      return 'bn-IN';
    }
    if (RegExp(r'[\u0A80-\u0AFF]').hasMatch(safeText)) {
      return 'gu-IN';
    }
    if (RegExp(r'[\u0A00-\u0A7F]').hasMatch(safeText)) {
      return 'pa-IN';
    }
    if (RegExp(r'[\u0B00-\u0B7F]').hasMatch(safeText)) {
      return 'or-IN';
    }
    if (RegExp(r'[\u0900-\u097F]').hasMatch(safeText)) {
      return 'hi-IN';
    }
    if (RegExp(r'[\u3040-\u30FF]').hasMatch(safeText)) {
      return 'ja-JP';
    }
    if (RegExp(r'[\uAC00-\uD7AF]').hasMatch(safeText)) {
      return 'ko-KR';
    }
    if (RegExp(r'[\u4E00-\u9FFF]').hasMatch(safeText)) {
      return 'zh-CN';
    }

    return null;
  }

  String _preferredTtsLocale(String languageCode) {
    const localeByLanguage = <String, String>{
      'en': 'en-IN',
      'hi': 'hi-IN',
      'ta': 'ta-IN',
      'te': 'te-IN',
      'kn': 'kn-IN',
      'bn': 'bn-IN',
      'mr': 'mr-IN',
      'gu': 'gu-IN',
      'pa': 'pa-IN',
      'or': 'or-IN',
      'ml': 'ml-IN',
      'zh': 'zh-CN',
      'ja': 'ja-JP',
      'ko': 'ko-KR',
    };
    return localeByLanguage[languageCode] ?? 'en-IN';
  }

  Future<void> _toggleMessageReadAloud({
    required String messageId,
    required String senderName,
    required String text,
  }) async {
    final safeText = _cleanAiMessageForVoiceAndSemantics(text);
    if (safeText.isEmpty) {
      return;
    }

    if (_speakingMessageId == messageId) {
      await _flutterTts.stop();
      if (!mounted) {
        return;
      }
      setState(() {
        _speakingMessageId = null;
      });
      _hapticSelection();
      return;
    }

    await _flutterTts.stop();
    if (!mounted) {
      return;
    }
    setState(() {
      _speakingMessageId = messageId;
    });
    _hapticLight();
    final textLocale = _ttsLocaleFromDisplayedText(safeText);
    await _applyPreferredTtsLanguage(preferredLocale: textLocale);
    await _flutterTts.speak(safeText);
  }

  String _buildMessageSemanticLabel({
    required String senderName,
    required String text,
    required bool isAiMessage,
    required DateTime? createdAt,
    required bool hasImageAttachment,
    required bool hasAudioAttachment,
  }) {
    final senderLabel = isAiMessage
        ? '$senderName, ${context.read<AppSettingsProvider>().t('chat_ai_assistant_label')}'
        : senderName;
    final timeLabel = createdAt == null ? '' : ' at ${_timeText(createdAt)}';
    final parts = <String>['Message from $senderLabel$timeLabel'];
    final safeText = _cleanAiMessageForVoiceAndSemantics(text);
    if (safeText.isNotEmpty) {
      parts.add(safeText);
    }
    if (hasImageAttachment) {
      parts.add('Includes image attachment');
    }
    if (hasAudioAttachment) {
      parts.add('Includes audio attachment');
    }
    return parts.join('. ');
  }

  Future<void> _toggleChatNotifications(bool enabled) async {
    try {
      await _chatService.setChatNotificationPreference(
        sosId: widget.sosId,
        userId: widget.currentUserId,
        enabled: enabled,
      );
      _hapticSelection();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled
                ? 'Chat notifications enabled for this conversation.'
                : 'Chat notifications disabled for this conversation.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to update notification setting right now.'),
        ),
      );
    }
  }

  void _hapticLight() {
    final enabled = context.read<AppSettingsProvider>().hapticsEnabled;
    if (!enabled) {
      return;
    }
    HapticFeedback.lightImpact();
  }

  void _hapticSelection() {
    final enabled = context.read<AppSettingsProvider>().hapticsEnabled;
    if (!enabled) {
      return;
    }
    HapticFeedback.selectionClick();
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

    final defaultMessage =
        context.read<AppSettingsProvider>().t('sos_default_message');
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
              ? defaultMessage
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

  double? _asDouble(dynamic val) {
    if (val == null) return null;
    if (val is num) return val.toDouble();
    if (val is String) return double.tryParse(val);
    if (val is GeoPoint) return val.latitude;
    return null;
  }

  void _showAttachOptions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take photo'),
              onTap: () {
                Navigator.pop(ctx);
                _pickCameraAttachment();
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Pick from gallery'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImageAttachment();
              },
            ),
            ListTile(
              leading: const Icon(Icons.location_on_outlined),
              title: const Text('Share my location'),
              onTap: () {
                Navigator.pop(ctx);
                _shareCurrentLocation();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAiStatusBadge(Map<String, dynamic> chatData) {
    // We assume AI is Active by default unless the last verified source was BUILTIN (fallback)
    final aiSource = (chatData['lastAiSource'] as String?) ?? '';
    final isFallback = aiSource == 'BUILTIN';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isFallback ? Icons.memory : Icons.auto_awesome,
          size: 12,
          color: isFallback ? Colors.orange[700] : Colors.blue[800],
        ),
        const SizedBox(width: 4),
        Text(
          isFallback ? 'AI Offline' : 'AI Active',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.normal,
            color: isFallback ? Colors.orange[700] : Colors.blue[800],
          ),
        ),
      ],
    );
  }

  Widget _typingDots(BuildContext context) {
    return AnimatedBuilder(
      animation: _typingDotsController,
      builder: (context, child) {
        final progress = _typingDotsController.value;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            final phase = (progress + (index * 0.2)) % 1.0;
            final opacity = 0.35 + (phase * 0.65);
            final scale = 0.85 + (phase * 0.25);
            return Opacity(
              opacity: opacity,
              child: Transform.scale(
                scale: scale,
                child: Container(
                  width: 7,
                  height: 7,
                  margin: EdgeInsets.only(left: index == 0 ? 0 : 4),
                  decoration: BoxDecoration(
                    color: Colors.red.shade500,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }

  Future<void> _shareCurrentLocation() async {
    if (!mounted) return;
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.denied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permission denied.')),
          );
        }
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );
      final lat = pos.latitude.toStringAsFixed(6);
      final lng = pos.longitude.toStringAsFixed(6);
      // Use geo: URI — Android shows an "Open with" chooser for Maps/navigation apps
      final locationMsg =
          '📍 My Location\ngeo:$lat,$lng\nhttps://maps.google.com/?q=$lat,$lng';

      await _chatService.sendMessage(
        sosId: widget.sosId,
        senderUid: widget.currentUserId,
        senderName: widget.currentUserName,
        senderRole: widget.currentUserRole,
        text: locationMsg,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not get location: $e')),
        );
      }
    }
  }

  void _showResponderOptions({
    required BuildContext context,
    required Map<String, dynamic> participantData,
    required String responderName,
  }) {
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final isAi = (participantData['isAi'] as bool?) ?? false;
    final responderUid =
        isAi ? 'rescuelink_ai' : ((participantData['uid'] as String?) ?? '');
    final safeResponderName = isAi ? 'RescueLink AI' : responderName;

    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(
                safeResponderName,
                style: Theme.of(ctx)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(context.read<AppSettingsProvider>().t('chat_view_profile')),
              onTap: () {
                Navigator.pop(ctx);
                if (isAi) {
                  nav.push(
                    MaterialPageRoute<void>(
                      builder: (_) => ResponderProfileScreen(
                        responder: ResponderModel.ai(),
                        currentUserId: widget.currentUserId,
                        currentUserName: widget.currentUserName,
                        isCurrentUserProfile: false,
                      ),
                    ),
                  );
                  return;
                }
                _showResponderProfile(responderUid);
              },
            ),
            ListTile(
              leading: const Icon(Icons.rate_review_outlined),
              title: Text(context.read<AppSettingsProvider>().t('profile_rate_review')),
              onTap: () {
                Navigator.pop(ctx);
                if (isAi) {
                  messenger.showSnackBar(
                    SnackBar(
                        content: Text(context.read<AppSettingsProvider>().t('chat_ai_cannot_review'))),
                  );
                  return;
                }
                _showReviewAndRatingDialog(
                  responderUid: responderUid,
                  responderName: safeResponderName,
                );
              },
            ),
            if (_canManageResponders && !isAi &&
                responderUid != widget.currentUserId) ...[
              const Divider(height: 1),
              ListTile(
                leading:
                    const Icon(Icons.person_remove_outlined, color: Colors.red),
                title: const Text('Remove from Chat',
                    style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmRemoveResponder(
                    messenger: messenger,
                    responderUid: responderUid,
                    responderName: safeResponderName,
                  );
                },
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _confirmRemoveResponder({
    required ScaffoldMessengerState messenger,
    required String responderUid,
    required String responderName,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Responder?'),
        content: Text(
            'Are you sure you want to remove $responderName from this conversation? They will not be able to rejoin without your approval.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await _chatService.removeResponder(
                  sosId: widget.sosId,
                  responderUid: responderUid,
                  responderName: responderName,
                  removedByUid: widget.currentUserId,
                );
                messenger.showSnackBar(
                  SnackBar(content: Text('$responderName has been removed.')),
                );
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(content: Text('Failed to remove: $e')),
                );
              }
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  Future<void> _showReviewAndRatingDialog({
    required String responderUid,
    required String responderName,
  }) async {
    if (responderUid.trim().isEmpty) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final reviewDocId = '${widget.currentUserId}_$responderUid';
    final directReviewRef = FirebaseFirestore.instance
        .collection('responder_reviews')
        .doc(reviewDocId);
    DocumentReference<Map<String, dynamic>> reviewRef = directReviewRef;
    var reviewSnapshot = await directReviewRef.get();

    if (!reviewSnapshot.exists) {
      final fallback = await FirebaseFirestore.instance
          .collection('responder_reviews')
          .where('reviewerUid', isEqualTo: widget.currentUserId)
          .where('responderUid', isEqualTo: responderUid)
          .get();
      if (fallback.docs.isNotEmpty) {
        final selectedDoc =
            pickLatestByUpdatedAt<QueryDocumentSnapshot<Map<String, dynamic>>>(
                  fallback.docs,
                  (doc) => doc.data()['updatedAt'],
                ) ??
                fallback.docs.first;
        reviewSnapshot = selectedDoc;
        reviewRef = selectedDoc.reference;
      }
    }

    final reviewData = reviewSnapshot.data() ?? <String, dynamic>{};

    double selectedRating = (reviewData['rating'] as num?)?.toDouble() ?? 0;
    var reviewText = (reviewData['review'] as String?) ?? '';
    final hasExistingReview = reviewSnapshot.exists;
    var isSubmitting = false;

    if (!mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Review $responderName'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Give both a rating and a review.'),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (i) {
                    return IconButton(
                      icon: Icon(
                        i < selectedRating ? Icons.star : Icons.star_border,
                        color: Colors.amber,
                        size: 36,
                      ),
                      onPressed: () =>
                          setDialogState(() => selectedRating = i + 1.0),
                    );
                  }),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  initialValue: reviewText,
                  onChanged: (value) {
                    reviewText = value;
                    setDialogState(() {});
                  },
                  maxLines: 4,
                  maxLength: 400,
                  enabled: !isSubmitting,
                  decoration: InputDecoration(
                    hintText: context.read<AppSettingsProvider>().t('chat_describe_experience'),
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            if (hasExistingReview)
              TextButton(
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                onPressed: isSubmitting
                    ? null
                    : () async {
                        if (!ctx.mounted) {
                          return;
                        }
                        setDialogState(() {
                          isSubmitting = true;
                        });
                  try {
                    await reviewRef.delete();
                  } catch (e) {
                    if (ctx.mounted) {
                      setDialogState(() {
                        isSubmitting = false;
                      });
                    }
                    if (mounted) {
                      messenger.showSnackBar(
                        SnackBar(content: Text('Unable to delete review: $e')),
                      );
                    }
                    return;
                  }
                  if (!ctx.mounted) {
                    return;
                  }
                  Navigator.pop(ctx);
                  if (!mounted) {
                    return;
                  }
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Review deleted.')),
                  );
                    },
                child: const Text('Delete'),
              ),
            TextButton(
              onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: isSubmitting ||
                      (selectedRating <= 0 && reviewText.trim().isEmpty)
                  ? null
                  : () async {
                      if (!ctx.mounted) {
                        return;
                      }
                      setDialogState(() {
                        isSubmitting = true;
                      });
                    final updatePayload = <String, dynamic>{
                      'reviewerUid': widget.currentUserId,
                      'reviewerName': widget.currentUserName,
                      'responderUid': responderUid,
                      'responderName': responderName,
                      'review': reviewText.trim(),
                      'updatedAt': FieldValue.serverTimestamp(),
                    };
                    if (selectedRating > 0) {
                      updatePayload['rating'] = selectedRating;
                    }
                    try {
                      await reviewRef.set(updatePayload, SetOptions(merge: true));
                    } catch (e) {
                      if (ctx.mounted) {
                        setDialogState(() {
                          isSubmitting = false;
                        });
                      }
                      if (mounted) {
                        messenger.showSnackBar(
                          SnackBar(content: Text('Unable to save review: $e')),
                        );
                      }
                      return;
                    }
                    if (!ctx.mounted) {
                      return;
                    }
                    Navigator.pop(ctx);
                    if (mounted) {
                      messenger.showSnackBar(
                        SnackBar(content: Text('Review saved for $responderName')),
                      );
                    }
                    },
                child: const Text('Save Review'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewCard(
    BuildContext context, {
    required String message,
    required List<Map<String, dynamic>> media,
    Map<String, dynamic> overview = const {},
  }) {
    final isExpanded = _showFullOverview;
    return AnimatedSize(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: Card(
        elevation: 2,
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            setState(() {
              _showFullOverview = !_showFullOverview;
            });
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    Icons.emergency_outlined,
                    size: 20,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isExpanded
                          ? context.read<AppSettingsProvider>().t('chat_emergency_overview')
                          : message,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  if (!isExpanded) ...[
                    if (media.isNotEmpty)
                      Row(
                        children: media.take(3).map((item) {
                          final type = (item['type'] as String?) ?? '';
                          IconData iconData = Icons.insert_drive_file;
                          if (type.contains('image')) {
                            iconData = Icons.image;
                          }
                          if (type.contains('audio')) {
                            iconData = Icons.audiotrack;
                          }
                          if (type.contains('video')) {
                            iconData = Icons.videocam;
                          }
                          return Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Icon(iconData, size: 14, color: Colors.grey),
                          );
                        }).toList(),
                      ),
                    if (overview.containsKey('latitude') ||
                        overview.containsKey('address'))
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Icon(Icons.location_on,
                            size: 14, color: Colors.red[700]),
                      ),
                  ],
                  const SizedBox(width: 4),
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 22,
                    color: Colors.grey[600],
                  ),
                ],
              ),
              if (isExpanded) ...<Widget>[
                const SizedBox(height: 10),
                TranslatedText(message),
                // Show SOS trigger location if available
                Builder(builder: (context) {
                  final lat = _asDouble(overview['latitude']);
                  final lng = _asDouble(overview['longitude']);
                  final address = (overview['address'] as String?)?.trim();
                  final coordStr = lat != null
                      ? '${lat.toStringAsFixed(5)}, ${lng?.toStringAsFixed(5)}'
                      : '';
                  final displayText =
                      address?.isNotEmpty == true ? address! : coordStr;
                  final mapsUrl = lat != null
                      ? 'https://maps.google.com/?q=${lat.toStringAsFixed(6)},${lng?.toStringAsFixed(6)}'
                      : null;
                  if (lat == null && address == null) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: GestureDetector(
                      onTap: lat != null
                          ? () async {
                              // Try geo: URI first (Android navigation chooser),
                              // fall back to Google Maps web URL.
                              final geoUri = Uri.parse(
                                  'geo:${lat.toStringAsFixed(6)},${lng?.toStringAsFixed(6)}');
                              try {
                                await launchUrl(geoUri,
                                    mode: LaunchMode.externalApplication);
                              } catch (_) {
                                final webUri = Uri.parse(
                                    'https://maps.google.com/?q=${lat.toStringAsFixed(6)},${lng?.toStringAsFixed(6)}');
                                await launchUrl(webUri,
                                    mode: LaunchMode.externalApplication);
                              }
                            }
                          : null,
                      child: Row(
                        children: <Widget>[
                          const Icon(Icons.location_on,
                              size: 16, color: Colors.red),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              displayText,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: mapsUrl != null
                                        ? Colors.blue[700]
                                        : null,
                                    decoration: mapsUrl != null
                                        ? TextDecoration.underline
                                        : null,
                                  ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (mapsUrl != null)
                            const Icon(Icons.open_in_new,
                                size: 14, color: Colors.blue),
                        ],
                      ),
                    ),
                  );
                }),
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
                          // Try displaying the image URL in a clean pop-up module.
                          return GestureDetector(
                            onTap: () {
                              showDialog(
                                context: context,
                                builder: (_) => Dialog(
                                  backgroundColor: Colors.transparent,
                                  insetPadding: const EdgeInsets.all(12),
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      InteractiveViewer(
                                        child: ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          child: Image.network(url,
                                              fit: BoxFit.contain),
                                        ),
                                      ),
                                      Positioned(
                                        right: 0,
                                        top: 0,
                                        child: IconButton(
                                          icon: const Icon(Icons.cancel,
                                              color: Colors.white, size: 32),
                                          onPressed: () =>
                                              Navigator.of(context).pop(),
                                        ),
                                      )
                                    ],
                                  ),
                                ),
                              );
                            },
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                url,
                                width: 72,
                                height: 72,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    _mediaFallback(type),
                              ),
                            ),
                          );
                        }

                        // For non-images (e.g. audio), also allow tapping to open embedded viewer.
                        return GestureDetector(
                          onTap: () {
                            if (url.isNotEmpty) {
                              showDialog(
                                context: context,
                                builder: (_) => AlertDialog(
                                  title: const Text('Audio Note'),
                                  content: _buildAudioAttachmentBubble(url),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(),
                                      child: const Text('Close'),
                                    ),
                                  ],
                                ),
                              );
                            }
                          },
                          child: _mediaFallback(type),
                        );
                      },
                    ),
                  ),
                ],
              ],
              ],
            ),
          ),
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
        type.contains('/') ? type.split('/').last : type,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 11),
      ),
    );
  }

  Widget _buildAiMessageContent(BuildContext context, String text) {
    // Extract source and status markers
    String cleanText = text;
    String? sourceMarker;
    String? statusMarker;

    final sourceMatch =
        RegExp(r'\[\[AI_SOURCE:(GEMINI|BUILTIN)\]\]').firstMatch(text);
    if (sourceMatch != null) {
      sourceMarker = sourceMatch.group(1);
      cleanText = cleanText.replaceFirst(sourceMatch.group(0)!, '').trim();
    }

    final statusMatch = RegExp(r'\[\[AI_STATUS:([^\]]+)\]\]').firstMatch(text);
    if (statusMatch != null) {
      statusMarker = statusMatch.group(1);
      cleanText = cleanText.replaceFirst(statusMatch.group(0)!, '').trim();
    }

    if (statusMarker != null &&
        statusMarker.toUpperCase().contains('GENERATING')) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _typingDots(context),
          const SizedBox(width: 10),
          Text(
            'AI is typing',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.red.shade800,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      );
    }

    // Extract all YouTube video IDs in order and deduplicate.
    final youtubeIds = extractYoutubeVideoIds(cleanText);
    final visibleText = youtubeIds.isNotEmpty
      ? _removeYoutubeUrlsForDisplay(cleanText)
      : cleanText;

    // Extract phone numbers
    final phoneNumbers = _extractPhoneNumbers(visibleText);

    // Split text by markdown elements and build widgets
    final lines = visibleText.split('\n');
    final widgets = <Widget>[];

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      if (RegExp(r'^#{1,6}\s+').hasMatch(trimmed)) {
        final headingText = trimmed.replaceFirst(RegExp(r'^#{1,6}\s+'), '');
        widgets.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            headingText,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.red.shade900,
                  fontWeight: FontWeight.bold,
                ),
          ),
        ));
      } else if (trimmed.startsWith('-') || trimmed.startsWith('*')) {
        // Bullet point
        final bulletText = trimmed.substring(1).trim();
        widgets.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('• ',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              Expanded(
                child: DefaultTextStyle(
                  style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                        height: 1.35,
                        color: Colors.red.shade900,
                      ),
                  child: _buildBoldAwareText(context, bulletText),
                ),
              ),
            ],
          ),
        ));
      } else if (RegExp(r'^\d+\.\s*').hasMatch(trimmed)) {
        // Numbered list
        final match = RegExp(r'^(\d+)\.\s*(.*) $').firstMatch('$trimmed\u0000');
        if (match != null) {
          widgets.add(Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('${match.group(1)}. ',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Expanded(
                  child: DefaultTextStyle(
                    style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                          height: 1.35,
                          color: Colors.red.shade900,
                        ),
                    child: _buildBoldAwareText(context, match.group(2)!),
                  ),
                ),
              ],
            ),
          ));
        }
      } else {
        // Regular text with bold/italic support
        widgets.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: DefaultTextStyle(
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                  height: 1.35,
                  color: Colors.red.shade900,
                ),
            child: _buildBoldAwareText(context, trimmed),
          ),
        ));
      }
    }

    // Add source and status badges
    if (sourceMarker != null || statusMarker != null) {
      widgets.add(const SizedBox(height: 12));
      widgets.add(Wrap(
        spacing: 8,
        children: <Widget>[
          if (sourceMarker != null)
            Tooltip(
              message: sourceMarker == 'GEMINI'
                  ? 'Gemini AI'
                  : 'Offline Built-in AI',
              child: Icon(
                sourceMarker == 'GEMINI' ? Icons.auto_awesome : Icons.memory,
                size: 16,
                color: sourceMarker == 'GEMINI'
                    ? Colors.blue[800]
                    : Colors.orange[800],
              ),
            ),
          if (statusMarker != null)
            Tooltip(
              message: 'Status: ${statusMarker.toUpperCase()}',
              child: Icon(
                statusMarker.toUpperCase().contains('SUCCESS')
                    ? Icons.check_circle_outline
                    : Icons.info_outline,
                size: 16,
                color: statusMarker.toUpperCase().contains('SUCCESS')
                    ? Colors.green
                    : Colors.grey,
              ),
            ),
        ],
      ));
    }

    // Add one embedded-style preview card per discovered YouTube video.
    if (youtubeIds.isNotEmpty) {
      widgets.add(const SizedBox(height: 12));
      for (var index = 0; index < youtubeIds.length; index++) {
        widgets.add(
          Padding(
            padding: EdgeInsets.only(bottom: index == youtubeIds.length - 1 ? 0 : 8),
            child: _buildYoutubePreviewCard(
              context,
              youtubeIds[index],
              index: index,
              total: youtubeIds.length,
            ),
          ),
        );
      }
    }

    // Add call buttons if phone numbers found (already deduplicated via .toSet())
    if (phoneNumbers.isNotEmpty) {
      widgets.add(const SizedBox(height: 8));
      widgets.add(_buildCallButtons(context, phoneNumbers));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  String _removeYoutubeUrlsForDisplay(String text) {
    final withoutWatchUrls = text.replaceAll(
      RegExp(
        r'https?:\/\/(?:www\.)?youtube\.com\/watch\?v=[A-Za-z0-9_-]{11}',
        caseSensitive: false,
      ),
      '',
    );
    final withoutShortUrls = withoutWatchUrls.replaceAll(
      RegExp(
        r'https?:\/\/youtu\.be\/[A-Za-z0-9_-]{11}',
        caseSensitive: false,
      ),
      '',
    );

    return withoutShortUrls
        .split('\n')
        .map((line) => line.trimRight())
        .where((line) => line.trim().isNotEmpty)
        .join('\n');
  }

  String _cleanAiMessageForVoiceAndSemantics(String text) {
    var cleaned = text;
    cleaned = cleaned.replaceAll(RegExp(r'\[\[AI_SOURCE:(GEMINI|BUILTIN)\]\]'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\[\[AI_STATUS:[^\]]+\]\]'), '');
    cleaned = _removeYoutubeUrlsForDisplay(cleaned);

    final lines = cleaned
        .split('\n')
        .map((line) {
          var trimmed = line.trim();
          trimmed = trimmed.replaceFirst(RegExp(r'^#{1,6}\s+'), '');
          trimmed = trimmed.replaceFirst(RegExp(r'^\d+\.\s*'), '');
          trimmed = trimmed.replaceFirst(RegExp(r'^[\-*]\s*'), '');
          return trimmed;
        })
        .where((line) => line.isNotEmpty)
        .toList();

    cleaned = lines.join('. ');
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'\*\*(.+?)\*\*'),
      (match) => match.group(1) ?? '',
    );
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'__(.+?)__'),
      (match) => match.group(1) ?? '',
    );
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'\*(.+?)\*'),
      (match) => match.group(1) ?? '',
    );
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'_(.+?)_'),
      (match) => match.group(1) ?? '',
    );

    return cleaned.trim();
  }

  Widget _buildYoutubePreviewCard(
    BuildContext context,
    String youtubeId, {
    required int index,
    required int total,
  }) {
    final youtubeUrl = Uri.parse('https://www.youtube.com/watch?v=$youtubeId');
    final thumbnailUrl =
        'https://img.youtube.com/vi/$youtubeId/hqdefault.jpg';
    final title = total > 1
        ? 'Watch AI Visual Guide ${index + 1}/$total'
        : 'Watch AI Visual Guidance Video';

    return GestureDetector(
      onTap: () async {
        try {
          await launchUrl(youtubeUrl, mode: LaunchMode.inAppWebView);
        } catch (_) {
          await launchUrl(youtubeUrl, mode: LaunchMode.externalApplication);
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.red[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red[200]!),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(
                      thumbnailUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: Colors.red[100],
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.ondemand_video,
                          color: Colors.red[300],
                          size: 42,
                        ),
                      ),
                    ),
                    Container(color: Colors.black.withValues(alpha: 0.15)),
                    Center(
                      child: Icon(
                        Icons.play_circle_fill,
                        color: Colors.white.withValues(alpha: 0.95),
                        size: 56,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        color: Colors.red[900],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Icon(Icons.open_in_new, color: Colors.red[400], size: 18),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Renders plain chat text but makes geo: and https: URLs tappable.
  Widget _buildLinkableText(BuildContext context, String text) {
    // Pattern matches geo:lat,lng  or  https://...
    final urlPattern =
        RegExp(r'(geo:\-?\d+(\.\d+)?,\-?\d+(\.\d+)?)|(https?://[^\s]+)');
    final matches = urlPattern.allMatches(text);

    final spans = <InlineSpan>[];
    int last = 0;
    final style = DefaultTextStyle.of(context).style;
    final linkStyle = style.copyWith(
      color: Colors.blue[700],
      decoration: TextDecoration.underline,
    );

    for (final m in matches) {
      if (m.start > last) {
        spans.add(TextSpan(text: text.substring(last, m.start), style: style));
      }
      final url = m.group(0)!;
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: GestureDetector(
          onTap: () async {
            try {
              await launchUrl(Uri.parse(url),
                  mode: LaunchMode.externalApplication);
            } catch (_) {
              await launchUrl(Uri.parse(url), mode: LaunchMode.inAppWebView);
            }
          },
          child: Text(
            url.startsWith('geo:') ? '📍 Open in Maps' : url,
            style: linkStyle,
          ),
        ),
      ));
      last = m.end;
    }
    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last), style: style));
    }

    final Widget messageText = matches.isEmpty
        ? Text(text)
        : RichText(
            textScaler: MediaQuery.textScalerOf(context),
            text: TextSpan(children: spans),
          );

    final phoneNumbers = _extractPhoneNumbers(text);
    if (phoneNumbers.isEmpty) {
      return messageText;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        messageText,
        const SizedBox(height: 8),
        _buildCallButtons(context, phoneNumbers),
      ],
    );
  }

  Widget _buildBoldAwareText(BuildContext context, String text) {
    final parts = <TextSpan>[];
    final regex = RegExp(r'(\*\*|__)(.+?)\1|(\*|_)(.+?)\3');
    int lastIndex = 0;

    for (final match in regex.allMatches(text)) {
      if (match.start > lastIndex) {
        parts.add(TextSpan(text: text.substring(lastIndex, match.start)));
      }

      final matchedText = match.group(2) ?? match.group(4) ?? '';
      final isStrong = match.group(1) != null;

      parts.add(TextSpan(
        text: matchedText,
        style: isStrong
            ? const TextStyle(fontWeight: FontWeight.bold)
            : const TextStyle(fontStyle: FontStyle.italic),
      ));
      lastIndex = match.end;
    }

    if (lastIndex < text.length) {
      parts.add(TextSpan(text: text.substring(lastIndex)));
    }

    return RichText(
      textScaler: MediaQuery.textScalerOf(context),
      text: TextSpan(
        style: DefaultTextStyle.of(context).style.copyWith(height: 1.35),
        children: parts,
      ),
    );
  }

  List<String> _extractPhoneNumbers(String text) {
    // Match only genuine short emergency codes (3-4 digits) or full phone numbers.
    // Avoids matching arbitrary 2-digit numbers like "77" that appear in normal text.
    final phonePattern = RegExp(
      r'(?<!\d)(?:'
      r'\d{3,4}|' // 3–4 digit short codes: 112, 100, 108, 911
      r'\+?\d(?:[\s.\-()]?\d){9,14}' // 10–15 digits with optional separators
      r')(?!\d)',
    );
    // Additional filter: skip numbers that are clearly not emergency/phone numbers
    const knownPhoneMinValue =
        100; // nothing below 100 is a real emergency number
    return phonePattern
        .allMatches(text)
        .map((m) => m.group(0)!.replaceAll(RegExp(r'[\s().-]'), ''))
        .where((phoneNumber) {
          final parsed = int.tryParse(phoneNumber);
          // If it parsed as a plain integer and is < 100, skip it
          return parsed == null || parsed >= knownPhoneMinValue;
        })
        .toSet()
        .toList();
  }

  // Emergency number logic is now handled in ChatService logic where appropriate.
  // We keep local helpers for the real-time chips.

  Widget _buildCallButtons(BuildContext context, List<String> phoneNumbers) {
    return Wrap(
      spacing: 8,
      children: phoneNumbers
          .map((phoneNum) => GestureDetector(
                onTap: () => _callEmergencyNumber(phoneNum),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: Colors.red[100],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Text('📞', style: TextStyle(fontSize: 14)),
                      const SizedBox(width: 4),
                      Text(phoneNum,
                          style: const TextStyle(fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              ))
          .toList(),
    );
  }

  Future<void> _callEmergencyNumber(String phoneNumber) async {
    final cleanNumber = phoneNumber.replaceAll(RegExp(r'[^\d+]'), '');
    final uri = Uri(scheme: 'tel', path: cleanNumber);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
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
    final localized = context.read<AppSettingsProvider>().localizedDisplayName(base);
    const maxUiNameLength = 40;
    if (localized.length <= maxUiNameLength) {
      return localized;
    }
    return '${localized.substring(0, maxUiNameLength)}...';
  }
}

// YoutubeVideoEmbed removed — YouTube videos now open via native app (LaunchMode.externalApplication)
// to bypass iframe embed error 152 restrictions on official emergency content channels.
