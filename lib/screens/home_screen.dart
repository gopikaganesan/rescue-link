import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import '../widgets/fixed_footer_navigation_bar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:torch_light/torch_light.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/providers/app_settings_provider.dart';
import '../core/providers/auth_provider.dart';
import '../core/providers/comms_provider.dart';
import '../core/providers/crisis_provider.dart';
import '../core/providers/emergency_request_provider.dart';
import '../core/models/user_model.dart';
import '../core/providers/location_provider.dart';
import '../core/providers/sos_status_provider.dart';
import '../core/providers/responder_provider.dart';
import '../core/services/notification_service.dart';
import '../core/services/responder_matching_service.dart';
import '../core/services/sos_service.dart';
import 'auth_screen.dart';
import 'group_chat_screen.dart';
import 'sos_history_screen.dart';
import 'victim_chat_list_screen.dart';
import 'responder_chat_list_screen.dart';
import 'responder_registration_screen.dart';
import 'responder_requests_screen.dart';
import 'map_screen.dart';
import '../widgets/account_sheet.dart';
import '../widgets/sos_button.dart';

enum _HomeHeaderMenuOption {
  language,
  accessibility,
  commsSimulation,
  viewSosHistory,
  aboutApp,
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isSosInProgress = false;
  Timer? _responderPollingTimer;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _openChatHeadsSub;
  final Map<String, StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>
      _openChatMessageSubs =
      <String, StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>{};
  final Map<String, bool> _chatNotificationPreferenceBySosId = <String, bool>{};
  final Set<String> _primedChatSosIds = <String>{};
  final Map<String, String> _lastSeenChatMessageIdBySosId = <String, String>{};
  String? _chatWatcherUserId;
  final Set<String> _notifiedRequestIds = <String>{};
  String _lastDeliveryRoute = '';
  String? _currentSosRequestId; // Track current SOS for cancellation
  bool _isSosDialogVisible = false;
  bool _isSosCancelRequested = false;
  SosCancellationToken? _sosCancellationToken;
  final ImagePicker _imagePicker = ImagePicker();
  final SpeechToText _speechToText = SpeechToText();
  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _voicePreviewPlayer = AudioPlayer();
  final FlutterTts _flutterTts = FlutterTts();
  StreamSubscription<void>? _voicePreviewCompleteSub;
  bool _speechReady = false;
  bool _isTranscribing = false;
  bool _isRecordingClip = false;
  bool _isPreviewPlaying = false;
  bool _includeVoiceClip = false;
  bool _forceCriticalSeverity = false;
  XFile? _selectedImage;
  String? _voiceTranscript;
  String? _voiceAudioPath;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeScreen();
    });
    _initializeSpeech();
    _configureVoiceTestTts();
    _voicePreviewCompleteSub = _voicePreviewPlayer.onPlayerComplete.listen((_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isPreviewPlaying = false;
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final sosStatus = context.read<SosStatusProvider>();
      sosStatus.addListener(_onSosStatusChanged);
      _onSosStatusChanged();
    });
  }

  /// Initialize location and responder data
  Future<void> _initializeScreen() async {
    final locationProvider = context.read<LocationProvider>();
    final responderProvider = context.read<ResponderProvider>();
    final emergencyProvider = context.read<EmergencyRequestProvider>();

    // Request location permission
    await locationProvider.requestLocationPermission();
    await responderProvider.fetchResponders();
    await emergencyProvider.retryPendingSync();
    await _syncPushProfile();
    _startResponderAlertPolling();
    _startOpenAppChatNotificationWatchers();
  }

  Future<void> _initializeSpeech() async {
    try {
      _speechReady = await _speechToText.initialize(
        onStatus: (status) {
          if (status == 'notListening' && mounted) {
            setState(() {
              _isTranscribing = false;
            });
          }
        },
        onError: (error) {
          if (mounted) {
            setState(() {
              _isTranscribing = false;
            });
          }
        },
      );
    } catch (_) {
      _speechReady = false;
    }

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _configureVoiceTestTts() async {
    try {
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.setPitch(1.0);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setLanguage('en-US');
    } catch (_) {
      // Ignore if TTS setup is not available.
    }
  }

  Future<void> _runVoiceTest(String message) async {
    await _flutterTts.stop();
    _announce(message);
    try {
      await _flutterTts.speak(message);
    } catch (_) {
      // Silent fallback if TTS is unavailable.
    }
  }

  Future<void> _syncPushProfile() async {
    final auth = context.read<AuthProvider>();
    final responders = context.read<ResponderProvider>();
    final user = auth.currentUser;
    if (user == null) {
      return;
    }

    final myResponder =
        responders.responders.where((r) => r.userId == user.id).toList();
    final profile = myResponder.isEmpty ? null : myResponder.first;

    await NotificationService.syncDeviceProfile(
      userId: user.id,
      isResponder: user.isResponder,
      isAvailable: profile?.isAvailable ?? false,
      skill: profile?.skillsArea,
      responderType: profile?.responderType,
    );
  }

  void _startResponderAlertPolling() {
    _responderPollingTimer?.cancel();
    _responderPollingTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _checkResponderAlerts();
    });
  }

  Future<void> _checkResponderAlerts() async {
    final auth = context.read<AuthProvider>();
    final settings = context.read<AppSettingsProvider>();
    if (!settings.notificationsEnabled) {
      return;
    }

    final me = auth.currentUser;
    if (me == null || !me.isResponder) {
      return;
    }

    final responders = context.read<ResponderProvider>();
    final requests = context.read<EmergencyRequestProvider>();

    await _checkResponderAlertsWithProviders(
      me: me,
      settings: settings,
      responders: responders,
      requests: requests,
    );
  }

  Future<void> _checkResponderAlertsWithProviders({
    required UserModel me,
    required AppSettingsProvider settings,
    required ResponderProvider responders,
    required EmergencyRequestProvider requests,
  }) async {
    await responders.fetchResponders();
    await requests.fetchOpenRequests();

    final mine = responders.responders.where((r) => r.userId == me.id).toList();
    if (mine.isEmpty) {
      return;
    }

    final responder = mine.first;
    for (final request in requests.openRequests) {
      if (_notifiedRequestIds.contains(request.id)) {
        continue;
      }

      if (!ResponderMatchingService.shouldNotifyResponder(
        responder: responder,
        request: request,
      )) {
        continue;
      }

      final radius =
          ResponderMatchingService.radiusKmForSeverity(request.severity);
      final distance =
          responder.distanceToLocation(request.latitude, request.longitude);
      if (distance > radius) {
        continue;
      }

      final title = settings
          .t('notification_new_nearby_sos_title')
          .replaceAll('{severity}', request.severity.toUpperCase());
      final body = settings
          .t('notification_new_nearby_sos_body')
          .replaceAll(
              '{category}', settings.localizedCrisisCategory(request.category))
          .replaceAll('{skill}', request.recommendedSkill)
          .replaceAll('{distance}', distance.toStringAsFixed(1));

      _notifiedRequestIds.add(request.id);
      await NotificationService.showResponderSosAlert(
        requestId: request.id,
        title: title,
        body: body,
      );
    }
  }

  void _startOpenAppChatNotificationWatchers() {
    final auth = context.read<AuthProvider>();
    final settings = context.read<AppSettingsProvider>();
    final user = auth.currentUser;
    if (user == null || !settings.notificationsEnabled) {
      _stopOpenAppChatNotificationWatchers();
      return;
    }

    if (_chatWatcherUserId == user.id && _openChatHeadsSub != null) {
      return;
    }

    _stopOpenAppChatNotificationWatchers();
    _chatWatcherUserId = user.id;

    _openChatHeadsSub = FirebaseFirestore.instance
        .collection('chats')
        .where('participantUids', arrayContains: user.id)
        .where('status', isEqualTo: 'active')
        .snapshots()
        .listen((snapshot) {
      final activeChatIds = snapshot.docs.map((doc) => doc.id).toSet();

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final preferences = (data['notificationPreferences'] as Map?) ??
            const <String, dynamic>{};
        _chatNotificationPreferenceBySosId[doc.id] =
            preferences[user.id] != false;

        if (!_openChatMessageSubs.containsKey(doc.id)) {
          _watchLatestChatMessage(doc.id, user.id);
        }
      }

      final staleIds = _openChatMessageSubs.keys
          .where((id) => !activeChatIds.contains(id))
          .toList();
      for (final staleId in staleIds) {
        _openChatMessageSubs.remove(staleId)?.cancel();
        _chatNotificationPreferenceBySosId.remove(staleId);
        _primedChatSosIds.remove(staleId);
        _lastSeenChatMessageIdBySosId.remove(staleId);
      }
    });
  }

  void _watchLatestChatMessage(String sosId, String currentUserId) {
    final sub = FirebaseFirestore.instance
        .collection('chats')
        .doc(sosId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(1)
        .snapshots()
        .listen((snapshot) async {
      if (!mounted || snapshot.docs.isEmpty) {
        return;
      }

      final latest = snapshot.docs.first;
      final latestId = latest.id;

      if (!_primedChatSosIds.contains(sosId)) {
        _primedChatSosIds.add(sosId);
        _lastSeenChatMessageIdBySosId[sosId] = latestId;
        return;
      }

      if (_lastSeenChatMessageIdBySosId[sosId] == latestId) {
        return;
      }
      _lastSeenChatMessageIdBySosId[sosId] = latestId;

      final isEnabled = _chatNotificationPreferenceBySosId[sosId] != false;
      if (!isEnabled) {
        return;
      }

      final data = latest.data();
      final senderUid = (data['senderUid'] as String?)?.trim() ?? '';
      final isAi = data['isAi'] == true || senderUid == 'rescuelink_ai';
      final isSystem =
          data['isSystem'] == true || (data['type'] as String?) == 'system';
      if (senderUid.isEmpty || senderUid == currentUserId || isAi || isSystem) {
        return;
      }

      final senderName =
          ((data['senderName'] as String?)?.trim().isNotEmpty ?? false)
              ? context
                  .read<AppSettingsProvider>()
                  .localizedDisplayName((data['senderName'] as String).trim())
              : context.read<AppSettingsProvider>().t('name_participant');
      final text = (data['text'] as String?)?.trim() ?? '';
      final preview = text.isEmpty
          ? 'Sent an attachment'
          : (text.length > 120 ? '${text.substring(0, 117)}...' : text);

      await NotificationService.showChatMessageAlert(
        title: 'New message in group chat',
        body: '$senderName: $preview',
        chatSosId: sosId,
      );
    });

    _openChatMessageSubs[sosId] = sub;
  }

  void _stopOpenAppChatNotificationWatchers() {
    _openChatHeadsSub?.cancel();
    _openChatHeadsSub = null;

    for (final sub in _openChatMessageSubs.values) {
      sub.cancel();
    }
    _openChatMessageSubs.clear();
    _chatNotificationPreferenceBySosId.clear();
    _primedChatSosIds.clear();
    _lastSeenChatMessageIdBySosId.clear();
    _chatWatcherUserId = null;
  }

  /// Handle SOS button press
  Future<void> _handleSOSPress() async {
    if (_isSosInProgress) {
      return;
    }

    _sosCancellationToken = SosCancellationToken();
    _isSosCancelRequested = false;
    setState(() {
      _isSosInProgress = true;
    });

    try {
      final sosService = SosService();
      final commsProvider = context.read<CommsProvider>();
      final responderProvider = context.read<ResponderProvider>();
      final appSettings = context.read<AppSettingsProvider>();
      final authProvider = context.read<AuthProvider>();
      final crisisProvider = context.read<CrisisProvider>();
      final emergencyRequestProvider = context.read<EmergencyRequestProvider>();
      final locationProvider = context.read<LocationProvider>();

      // Execute the SOS flow via the service
      final requestId = await sosService.triggerSos(
        SosTriggerContext(
          authProvider: authProvider,
          crisisProvider: crisisProvider,
          emergencyRequestProvider: emergencyRequestProvider,
          locationProvider: locationProvider,
          responderProvider: responderProvider,
          settings: appSettings,
          commsProvider: commsProvider,
          customMessage: _emergencyContextController.text.trim(),
          imageFile: _selectedImage,
          voiceAudioPath: _voiceAudioPath,
          forceCritical: _forceCriticalSeverity,
          cancelToken: _sosCancellationToken,
        ),
      );

      if (!mounted) return;

      if (requestId != null) {
        _currentSosRequestId = requestId;
        context.read<SosStatusProvider>().setActiveSos(requestId);

        // Track the route (for UI feedback)
        _lastDeliveryRoute = commsProvider.resolveDeliveryRoute(
          settings: appSettings,
          cloudWriteSucceeded: true,
          hasNearbyResponders: responderProvider.nearbyResponders.isNotEmpty,
        );

        _showSOSConfirmation();
      } else if (_isSosCancelRequested) {
        _showSnackBar(appSettings.t('snackbar_sos_send_cancelled'));
      } else {
        _showSnackBar(appSettings.t('snackbar_sos_incomplete'));
      }
    } catch (e) {
      if (!mounted) return;
      _showSnackBar(
        context
            .read<AppSettingsProvider>()
            .t('snackbar_sos_error')
            .replaceAll('{error}', e.toString()),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSosInProgress = false;
        });
      }
    }
  }

  // Note: The previous logic (lines 354-574) is now encapsulated in SosService.

  Future<void> _cancelActiveSosButton(String? requestId) async {
    if (requestId == null) {
      return;
    }

    final emergencyRequestProvider = context.read<EmergencyRequestProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final settings = context.read<AppSettingsProvider>();

    final cancelled = await emergencyRequestProvider.cancelRequest(requestId);
    if (!mounted) {
      return;
    }

    if (cancelled) {
      context.read<SosStatusProvider>().clearActiveSos();
      setState(() {
        _currentSosRequestId = null;
      });
      messenger.showSnackBar(
        SnackBar(content: Text(settings.t('snackbar_cancel_sos_successful'))),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(content: Text(settings.t('snackbar_cancel_sos_failed'))),
      );
    }
  }

  void _onSosStatusChanged() {
    final sosStatus = context.read<SosStatusProvider>();
    if (sosStatus.hasActiveSos && !_isSosDialogVisible && mounted) {
      _currentSosRequestId = sosStatus.activeSosId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        if (!_isSosDialogVisible) {
          _showSOSConfirmation();
        }
      });
    }
  }

  Future<void> _cancelPendingSos() async {
    if (!_isSosInProgress) {
      return;
    }

    _sosCancellationToken?.cancel();
    _isSosCancelRequested = true;
    setState(() {
      _isSosInProgress = false;
    });
    final settings = context.read<AppSettingsProvider>();
    _showSnackBar(settings.t('snackbar_sos_send_cancelled'));
  }

  Future<void> _pulseFlash() async {
    try {
      await TorchLight.enableTorch();
      await Future<void>.delayed(const Duration(milliseconds: 350));
      await TorchLight.disableTorch();
    } catch (_) {
      // Device may not support flashlight control.
    }
  }

  /// Show SOS confirmation dialog
  void _showSOSConfirmation() {
    final settings = context.read<AppSettingsProvider>();
    final crisisProvider = context.read<CrisisProvider>();
    final locationProvider = context.read<LocationProvider>();
    final responderProvider = context.read<ResponderProvider>();
    final analysis = crisisProvider.latestAnalysis;
    final emergencyRequestProvider = context.read<EmergencyRequestProvider>();
    final messenger = ScaffoldMessenger.of(context);

    _isSosDialogVisible = true;

    Widget _infoRow(String label, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Text("$label: $value"),
  );
}

Widget _actionBtn(String text, IconData icon, Color color, VoidCallback onTap) {
  return ElevatedButton.icon(
    onPressed: onTap,
    icon: Icon(icon),
    label: Text(text),
    style: ElevatedButton.styleFrom(
      backgroundColor: color,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),
  );
}

    showDialog(
  context: context,
  barrierDismissible: false,
  builder: (dialogContext) => Dialog(
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
    ),
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
  color: Colors.white,
  borderRadius: BorderRadius.circular(20),
  boxShadow: [
    BoxShadow(
      color: Colors.black.withOpacity(0.08),
      blurRadius: 12,
    ),
  ],
),
      constraints: const BoxConstraints(maxHeight: 600),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          /// 🔝 HEADER
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check, color: Colors.green),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  settings.t('status_sos_received'),
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          /// 📦 CONTENT
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  /// STATUS CARD
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.green.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SOS broadcasted successfully',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '📍 ${locationProvider.latitude?.toStringAsFixed(4)}, '
                          '${locationProvider.longitude?.toStringAsFixed(4)}',
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  /// RESPONDERS
                  Row(
                    children: [
                      const Icon(Icons.people, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        'Nearby Responders: ${responderProvider.nearbyResponders.length}',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ],
                  ),

                  if (responderProvider.nearbyResponders.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        settings.t('no_nearby_responders_hint'),
                        style: TextStyle(color: Colors.orange.shade700),
                      ),
                    ),

                  /// 🤖 AI SECTION
                  if (analysis != null) ...[
                    const SizedBox(height: 16),
                    Divider(),

                    Text(
                      "AI Analysis",
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),

                    const SizedBox(height: 8),

                    _infoRow("Category",
                        settings.localizedCrisisCategory(analysis.category)),
                    _infoRow("Severity", analysis.severity),
                    _infoRow("Skill",
                        settings.localizedSkill(analysis.recommendedSkill)),

                    if (analysis.confidence > 0)
                      _infoRow("Confidence",
                          "${(analysis.confidence * 100).toStringAsFixed(0)}%"),

                    if (analysis.humanReviewRecommended)
                      Text(
                        "⚠ Human review recommended",
                        style: TextStyle(color: Colors.orange.shade800),
                      ),

                    if (analysis.suggestedActions.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text("Actions",
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      ...analysis.suggestedActions.take(3).map(
                            (e) => Text("• $e"),
                          ),
                    ],
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          /// 🔘 ACTIONS (WRAPPED)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _actionBtn(
                "Cancel",
                Icons.close,
                Colors.red,
                () => _cancelCurrentSosRequest(
                  _currentSosRequestId,
                  dialogContext,
                  emergencyRequestProvider,
                  messenger,
                ),
              ),
              _actionBtn(
                "Map",
                Icons.map,
                Colors.grey.shade500,
                () {
                  Navigator.pop(dialogContext);
                  _openMap();
                },
              ),
              if (_currentSosRequestId != null)
                _actionBtn(
                  "Chat",
                  Icons.chat,
                  Colors.grey.shade500,
                  () {
                    Navigator.pop(dialogContext);
                    _openCurrentSosChat();
                  },
                ),
              if (responderProvider.nearbyResponders.isEmpty)
                _actionBtn(
                  "Call",
                  Icons.call,
                  Colors.red,
                  () async {
                    Navigator.pop(dialogContext);
                    await _makeEmergencyCall();
                  },
                ),
            ],
          ),
        ],
      ),
    ),
  ),
).then((_) { if (!mounted) { return; } setState(() { _isSosDialogVisible = false; }); });

    _announce(context.read<AppSettingsProvider>().t('status_sos_activated'));
  }

  Future<void> _cancelCurrentSosRequest(
    String? requestId,
    BuildContext dialogContext,
    EmergencyRequestProvider emergencyRequestProvider,
    ScaffoldMessengerState messenger,
  ) async {
    if (requestId == null) {
      return;
    }

    final dialogNavigator = Navigator.of(dialogContext);
    await emergencyRequestProvider.cancelRequest(requestId);
    if (!mounted) {
      return;
    }

    context.read<SosStatusProvider>().clearActiveSos();
    _currentSosRequestId = null;
    dialogNavigator.pop();
    messenger.showSnackBar(
      SnackBar(
          content: Text(
              context.read<AppSettingsProvider>().t('snackbar_sos_cancelled'))),
    );
  }

  void _showEmergencyInfoBalloon() {
    final settings = context.read<AppSettingsProvider>();
    final commsProvider = context.read<CommsProvider>();
    final crisisProvider = context.read<CrisisProvider>();

    final aiStatus =
        crisisProvider.latestAnalysis?.aiStatus ?? 'local_heuristic_response';
    final aiStatusLabel = aiStatus == 'gemini_success'
        ? settings.t('home_ai_status_gemini_success')
        : aiStatus == 'missing_api_key'
            ? settings.t('home_ai_status_missing_api_key')
            : aiStatus == 'forced_offline'
                ? settings.t('home_ai_status_forced_offline')
                : aiStatus == 'gemini_empty_response'
                    ? settings.t('home_ai_status_empty_response')
                    : aiStatus == 'gemini_error'
                        ? settings.t('home_ai_status_gemini_error')
                        : settings.t('home_ai_status_local_heuristic');

    final String voiceStatusKey = _speechReady
        ? 'home_emergency_info_voice_ready'
        : 'home_emergency_info_voice_unavailable';
    final String fallbackStatusKey = commsProvider.forceOfflineAi
        ? 'home_emergency_info_fallback_active'
        : 'button_powered_by_gemini';

    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        final infoTextStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.blueGrey.shade800,
              fontSize: 14,
            );

        return AlertDialog(
          title: Row(
            children: [
              Expanded(child: Text(settings.t('home_emergency_info_title'))),
              IconButton(
                icon: const Icon(Icons.close,color: Colors.red),
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStatusRow(
                icon: Icons.mic,
                text: settings.t(voiceStatusKey),
                style: infoTextStyle,
              ),
              const SizedBox(height: 10),
              _buildStatusRow(
                icon: Icons.smart_toy,
                text: settings
                    .t('home_ai_status')
                    .replaceAll('{status}', aiStatusLabel),
                style: infoTextStyle,
              ),
              const SizedBox(height: 10),
              _buildStatusRow(
                icon: Icons.wifi_off,
                text: settings.t(fallbackStatusKey),
                style: infoTextStyle,
              ),
              const SizedBox(height: 10),
              _buildStatusRow(
                icon: Icons.accessibility_new,
                text: settings
                    .t('home_emergency_info_accessibility_transcription'),
                style: infoTextStyle,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatusRow({
    required IconData icon,
    required String text,
    required TextStyle? style,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.red.shade700),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: style,
          ),
        ),
      ],
    );
  }

  /// Show snackbar message
  void _showSnackBar(String message) {
    _announce(message);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _announce(String message) {
    final view = View.of(context);
    SemanticsService.sendAnnouncement(view, message, TextDirection.ltr);
  }

  void _showAboutAppDialog() {
    final settings = context.read<AppSettingsProvider>();

Widget _featureItem(IconData icon, String text, Color color) {
  return Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: color.withAlpha(30),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    ),
  );
}

    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return AlertDialog(
  backgroundColor: Colors.white,
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(16),
  ),

  title: Row(
    children: [
      Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(Icons.info_outline, color: Colors.blue.shade700),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          settings.t('home_about_app_title'),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    ],
  ),

  content: SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 🔹 Description
        Text(
          settings.t('home_about_app_description'),
          style: TextStyle(
            color: Colors.grey.shade700,
            height: 1.4,
          ),
        ),

        const SizedBox(height: 16),

        // 🔹 Features
        _featureItem(Icons.warning_amber_rounded,
            settings.t('home_about_app_feature_sos'), Colors.red),

        _featureItem(Icons.smart_toy,
            settings.t('home_about_app_feature_ai'), Colors.blue),

        _featureItem(Icons.accessibility_new,
            settings.t('home_about_app_feature_accessibility'), Colors.green),

        _featureItem(Icons.shield,
            settings.t('home_about_app_feature_resilience'), Colors.orange),
      ],
    ),
  ),

  actionsPadding:
      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),

  actions: [
    TextButton(
      onPressed: () => Navigator.of(dialogContext).pop(),
      child: Text(
        settings.t('button_close'),
        style: TextStyle(color: Colors.grey.shade700),
      ),
    ),

    FilledButton.icon(
      icon: const Icon(Icons.open_in_new, size: 18),
      onPressed: () async {
        final uri = Uri.parse(
            'https://github.com/gopikaganesan/rescue-link');

        if (await canLaunchUrl(uri)) {
          await launchUrl(uri,
              mode: LaunchMode.externalApplication);
        } else if (mounted) {
          _showSnackBar(
              settings.t('home_about_app_github_failed'));
        }
      },
      label: Text(settings.t('home_about_app_github')),
    ),
  ],
);
      },
    );

    
  }

  void _openResponderRegistration() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const ResponderRegistrationScreen(),
      ),
    );
  }

  void _openResponderAction() {
    final auth = context.read<AuthProvider>();
    if (auth.currentUser?.isResponder == true) {
      _openResponderRequests();
      return;
    }
    _openResponderRegistration();
  }

  void _openMap() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const MapScreen(),
      ),
    );
  }

  void _openResponderRequests() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const ResponderRequestsScreen(),
      ),
    );
  }

  void _openChats() {
    final auth = context.read<AuthProvider>();
    final user = auth.currentUser;
    if (user == null) {
      _showSnackBar(context
          .read<AppSettingsProvider>()
          .t('snackbar_sign_in_to_view_chats'));
      return;
    }

    if (user.isResponder) {
      ResponderChatListScreen.open(
        context,
        currentUserId: user.id,
        currentUserName: context
            .read<AppSettingsProvider>()
            .localizedDisplayName(user.displayName),
      );
      return;
    }

    VictimChatListScreen.open(
      context,
      currentUserId: user.id,
      currentUserName: context
          .read<AppSettingsProvider>()
          .localizedDisplayName(user.displayName),
    );
  }

  void _openCurrentSosChat() {
    final authProvider = context.read<AuthProvider>();
    final user = authProvider.currentUser;
    final sosId = _currentSosRequestId;

    if (user == null || sosId == null) {
      _showSnackBar(
          context.read<AppSettingsProvider>().t('status_chat_not_ready'));
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GroupChatScreen(
          sosId: sosId,
          currentUserId: user.id,
          currentUserName: context
              .read<AppSettingsProvider>()
              .localizedDisplayName(user.displayName),
          currentUserRole: 'victim',
          enableResponderJoinGate: false,
        ),
      ),
    );
  }

  Future<void> _openAuthScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const AuthScreen(showGuestButton: false),
      ),
    );
  }

  Future<void> _logoutRegisteredUser() async {
    await context.read<AuthProvider>().logout();
    if (mounted) {
      _showSnackBar(
          context.read<AppSettingsProvider>().t('snackbar_signed_out'));
    }
  }

  void _showLanguagePicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Consumer<AppSettingsProvider>(
          builder: (context, settings, _) => Container(
            padding: const EdgeInsets.only(top: 12, bottom: 20),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle
                Container(
                  width: 40,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),

                // Title
                Text(
                  settings.t('home_select_language'),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  settings.t('home_choose_preferred_language'),
                  style: TextStyle(color: Colors.grey),
                ),

                const SizedBox(height: 12),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: SwitchListTile.adaptive(
                    value: settings.showAllLanguages,
                    onChanged: settings.setShowAllLanguages,
                    title: Text(settings.t('home_show_all_languages')),
                    subtitle: Text(settings.t('home_show_all_languages_hint')),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                ),

                const SizedBox(height: 8),

                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: settings.availableLanguageCodes.length,
                    itemBuilder: (context, index) {
                      final code = settings.availableLanguageCodes[index];
                      final isSelected = settings.languageCode == code;

                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () {
                            settings.setLanguage(code);
                            Navigator.pop(sheetContext);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 14),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Colors.red.withValues(alpha: 0.1)
                                  : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isSelected
                                    ? Colors.red
                                    : Colors.transparent,
                              ),
                            ),
                            child: Row(
                              children: [
                                // Language Icon
                                CircleAvatar(
                                  backgroundColor: Colors.red.shade50,
                                  child: const Icon(Icons.language,
                                      color: Colors.red),
                                ),

                                const SizedBox(width: 12),

                                // Language Label
                                Expanded(
                                  child: Text(
                                    settings.languageLabel(code),
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: isSelected
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ),

                                // Selected check
                                if (isSelected)
                                  const Icon(Icons.check_circle,
                                      color: Colors.red),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showAccountSheet() {
    final authProvider = context.read<AuthProvider>();

    showAccountSheet(
      context,
      onLogin: () async {
        await _openAuthScreen();
      },
      onLogout: () async {
        await _logoutRegisteredUser();
        if (!mounted) {
          return;
        }
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => const AuthScreen(showGuestButton: false),
          ),
          (route) => false,
        );
      },
      onOpenResponderRequests: _openResponderRequests,
      isResponderAvailable: authProvider.currentUser?.isResponder == true
          ? context
                  .read<ResponderProvider>()
                  .responderForUserId(authProvider.currentUser!.id)
                  ?.isAvailable ??
              true
          : null,
      onToggleAvailability: authProvider.currentUser?.isResponder == true
          ? (value) async {
              await _toggleAvailability(value);
            }
          : null,
      onDeregisterResponder: authProvider.currentUser?.isResponder == true
          ? _deregisterResponder
          : null,
    );
  }

  void _showAccessibilitySheet() {
    final settings = context.read<AppSettingsProvider>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              decoration: const BoxDecoration(
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                color: Colors.white,
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Drag Handle
                      Container(
                        width: 40,
                        height: 5,
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),

                      // 🔴 Header
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Colors.red, Colors.redAccent],
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.accessibility_new,
                                color: Colors.white),
                            const SizedBox(width: 10),
                            Text(
                              settings.t('title_accessibility'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          settings.t('accessibility_screen_reader_hint'),
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 14,
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // 🔧 Settings Cards
                      _buildSwitchCard(
                        title: settings.t('label_haptics'),
                        icon: Icons.vibration,
                        value: settings.hapticsEnabled,
                        onChanged: (v) {
                          settings.setHapticsEnabled(v);
                          if (mounted) {
                            _showSnackBar(v
                                ? settings.t('accessibility_haptics_enabled')
                                : settings.t('accessibility_haptics_disabled'));
                          }
                          setModalState(() {});
                        },
                      ),

                      _buildSwitchCard(
                        title: settings.t('label_flashlight'),
                        subtitle: settings.t('label_flashlight_hint'),
                        icon: Icons.flashlight_on,
                        value: settings.sosFlashEnabled,
                        onChanged: (v) {
                          settings.setSosFlashEnabled(v);
                          if (mounted) {
                            _showSnackBar(v
                                ? settings.t('accessibility_flashlight_enabled')
                                : settings
                                    .t('accessibility_flashlight_disabled'));
                          }
                          setModalState(() {});
                        },
                      ),

                      _buildSwitchCard(
                        title: settings.t('label_high_contrast'),
                        icon: Icons.contrast,
                        value: settings.highContrastEnabled,
                        onChanged: (v) {
                          settings.setHighContrastEnabled(v);
                          setModalState(() {});
                        },
                      ),

                      _buildSwitchCard(
                        title: settings.t('label_notifications'),
                        subtitle: settings.t('label_notifications_hint'),
                        icon: Icons.notifications_active,
                        value: settings.notificationsEnabled,
                        onChanged: (value) async {
                          if (value) {
                            final granted =
                                await NotificationService.requestPermissions();
                            settings.setNotificationsEnabled(granted);

                            if (granted) {
                              _startOpenAppChatNotificationWatchers();
                            } else {
                              _stopOpenAppChatNotificationWatchers();
                            }

                            if (!granted && mounted) {
                              _showSnackBar(settings
                                  .t('notification_permission_not_granted'));
                            }
                          } else {
                            settings.setNotificationsEnabled(false);
                            _stopOpenAppChatNotificationWatchers();
                          }
                          setModalState(() {});
                        },
                      ),

                      const SizedBox(height: 12),

                      // 🔤 Text Size Card
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.text_fields,
                                    color: Colors.red),
                                const SizedBox(width: 8),
                                Expanded(
                                    child: Text(settings.t('label_text_size'))),
                                Text(
                                  '${(settings.textScaleFactor * 100).round()}%',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                activeTrackColor: Colors.red,
                                thumbColor: Colors.red,
                              ),
                              child: Slider(
                                min: 0.85,
                                max: 1.6,
                                value: settings.textScaleFactor,
                                onChanged: (value) {
                                  settings.setTextScaleFactor(value);
                                  setModalState(() {});
                                },
                              ),
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: () {
                                  settings.setTextScaleFactor(1.0);
                                  setModalState(() {});
                                },
                                icon: const Icon(Icons.restart_alt,
                                    color: Colors.red),
                                label: Text(
                                  settings.t('button_reset'),
                                  style: TextStyle(color: Colors.red),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 14),

                      // 🧪 Test Buttons
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: () async {
                              await _runVoiceTest(
                                settings.t('accessibility_announcement_text'),
                              );
                              if (mounted) {
                                _showSnackBar(settings
                                    .t('accessibility_announcement_sent'));
                              }
                            },
                            icon: const Icon(Icons.record_voice_over),
                            label: Text(context
                                .read<AppSettingsProvider>()
                                .t('button_voice_test')),
                          ),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red,
                              side: const BorderSide(color: Colors.red),
                            ),
                            onPressed: () async {
                              await _pulseFlash();
                              if (mounted) {
                                _showSnackBar(
                                    settings.t('flash_test_completed'));
                              }
                            },
                            icon: const Icon(Icons.flashlight_on),
                            label: Text(context
                                .read<AppSettingsProvider>()
                                .t('button_flash_test')),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showCommsSimulationSheet() {
    final comms = context.read<CommsProvider>();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Drag Handle
                    Center(
                      child: Container(
                        width: 40,
                        height: 5,
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),

                    // 🔴 Header
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Colors.red, Colors.redAccent],
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.wifi_tethering, color: Colors.white),
                          const SizedBox(width: 10),
                          Text(
                            context
                                .read<AppSettingsProvider>()
                                .t('comms_simulation_title'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: Colors.red.withValues(alpha: 0.3),
                        ),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<CommsMode>(
                          value: comms.mode,
                          isExpanded: true,
                          icon: const Icon(Icons.keyboard_arrow_down,
                              color: Colors.red),
                          dropdownColor: Colors.white,
                          borderRadius: BorderRadius.circular(16),

                          // Selected item display
                          selectedItemBuilder: (context) {
                            final settings =
                                context.read<AppSettingsProvider>();
                            return CommsMode.values.map((mode) {
                              return Row(
                                children: [
                                  Text(
                                    comms.modeLabel(mode, settings),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              );
                            }).toList();
                          },

                          items: CommsMode.values.map((mode) {
                            final settings =
                                context.read<AppSettingsProvider>();
                            return DropdownMenuItem<CommsMode>(
                              value: mode,
                              child: Row(
                                children: [
                                  Text(comms.modeLabel(mode, settings)),
                                ],
                              ),
                            );
                          }).toList(),

                          onChanged: (value) {
                            if (value != null) {
                              comms.setMode(value);
                              setModalState(() {});
                            }
                          },
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // 🔧 Switch Cards
                    _buildCommsSwitch(
                      title: context
                          .read<AppSettingsProvider>()
                          .t('comms_simulate_tower_failure'),
                      icon: Icons.signal_cellular_off,
                      value: comms.simulateTowerFailure,
                      onChanged: (v) {
                        comms.setSimulateTowerFailure(v);
                        setModalState(() {});
                      },
                    ),

                    _buildCommsSwitch(
                      title: context
                          .read<AppSettingsProvider>()
                          .t('comms_device_supports_satellite'),
                      subtitle: context
                          .read<AppSettingsProvider>()
                          .t('comms_simulated_capability'),
                      icon: Icons.satellite_alt,
                      value: comms.deviceSupportsSatellite,
                      onChanged: (v) {
                        comms.setDeviceSupportsSatellite(v);
                        setModalState(() {});
                      },
                    ),

                    const SizedBox(height: 14),

                    // ⚠️ Info Box
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: Colors.red.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.info_outline, color: Colors.red),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              context
                                  .read<AppSettingsProvider>()
                                  .t('comms_simulation_info'),
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _deregisterResponder() async {
    final authProvider = context.read<AuthProvider>();
    final responderProvider = context.read<ResponderProvider>();
    final userId = authProvider.currentUser?.id;
    if (userId == null) {
      return;
    }

    await responderProvider.removeResponderByUserId(userId);
    authProvider.unregisterAsResponder();
    await NotificationService.syncDeviceProfile(
      userId: userId,
      isResponder: false,
      isAvailable: false,
    );
    if (mounted) {
      _showSnackBar('You are now de-registered as responder.');
    }
  }

  Future<void> _toggleAvailability(bool value) async {
    final authProvider = context.read<AuthProvider>();
    final responderProvider = context.read<ResponderProvider>();
    final userId = authProvider.currentUser?.id;
    if (userId == null) {
      return;
    }

    final snackMessage = context
        .read<AppSettingsProvider>()
        .t(value ? 'snackbar_responder_online' : 'snackbar_responder_offline');

    await responderProvider.setResponderAvailability(
      userId: userId,
      isAvailable: value,
    );

    final mine =
        responderProvider.responders.where((r) => r.userId == userId).toList();
    final profile = mine.isEmpty ? null : mine.first;
    await NotificationService.syncDeviceProfile(
      userId: userId,
      isResponder: authProvider.currentUser?.isResponder ?? false,
      isAvailable: value,
      skill: profile?.skillsArea,
      responderType: profile?.responderType,
    );

    if (mounted) {
      _showSnackBar(snackMessage);
    }
  }

  final TextEditingController _emergencyContextController =
      TextEditingController();

  Future<void> _makeEmergencyCall() async {
    final uri = Uri.parse('tel:112');
    final failureMessage =
        context.read<AppSettingsProvider>().t('snackbar_dialer_failed');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      _showSnackBar(failureMessage);
    }
  }

  Future<void> _toggleVoiceInput() async {
    if (!_speechReady) {
      _showSnackBar(context
          .read<AppSettingsProvider>()
          .t('snackbar_voice_input_unavailable'));
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
        setState(() {
          _isTranscribing = true;
          _voiceTranscript = words.isEmpty ? _voiceTranscript : words;
          if (words.isNotEmpty &&
              (result.finalResult ||
                  _emergencyContextController.text.trim().isEmpty)) {
            _emergencyContextController.text = words;
            _emergencyContextController.selection = TextSelection.fromPosition(
              TextPosition(offset: _emergencyContextController.text.length),
            );
          }
        });
      },
      listenOptions: SpeechListenOptions(
        partialResults: true,
        listenMode: ListenMode.dictation,
      ),
      listenFor: const Duration(minutes: 2),
      pauseFor: const Duration(seconds: 8),
      localeId: _speechLocaleForLanguage(
          context.read<AppSettingsProvider>().languageCode),
    );

    if (mounted) {
      setState(() {
        _isTranscribing = true;
      });
    }
  }

  Future<void> _toggleVoiceClipRecording() async {
    final canRecordAudio = await _audioRecorder.hasPermission();
    if (!canRecordAudio) {
      _showSnackBar(
          'Microphone permission is required for voice clip recording.');
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
          _includeVoiceClip = true;
        }
      });
      return;
    }

    final tempDir = await getTemporaryDirectory();
    final voicePath =
        '${tempDir.path}/clip_${DateTime.now().millisecondsSinceEpoch}.wav';
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

  Future<void> _pickCameraImage() async {
    final file = await _imagePicker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
    );

    if (file == null) {
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _selectedImage = file;
    });
  }

  void _removePhotoAttachment() {
    setState(() {
      _selectedImage = null;
    });
  }

  Future<void> _removeVoiceAttachment() async {
    await _voicePreviewPlayer.stop();
    if (!mounted) {
      return;
    }
    setState(() {
      _voiceAudioPath = null;
      _includeVoiceClip = false;
      _isPreviewPlaying = false;
      _isRecordingClip = false;
    });
  }

  Future<void> _previewSelectedPhoto() async {
    final image = _selectedImage;
    if (image == null) {
      return;
    }

    final imageBytes = await image.readAsBytes();
    if (!mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.photo_library_outlined),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        image.name.isEmpty ? 'Attached photo' : image.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 4.0,
                    child: Image.memory(
                      imageBytes,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAttachmentCard({
    required IconData icon,
    required String fileName,
    required String fileKind,
    required String semanticsLabel,
    required VoidCallback onOpen,
    required VoidCallback onRemove,
    IconData? openIcon,
    IconData? statusIcon,
    Color? statusColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: Colors.blueGrey.shade50,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, size: 18, color: Colors.blueGrey.shade700),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 170),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  fileName,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                Text(
                  fileKind,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                ),
              ],
            ),
          ),
          if (statusIcon != null) ...[
            const SizedBox(width: 8),
            Icon(statusIcon,
                size: 16, color: statusColor ?? Colors.green.shade700),
          ],
          const SizedBox(width: 2),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: semanticsLabel,
            onPressed: onOpen,
            icon: Icon(openIcon ?? Icons.visibility_outlined, size: 18),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Remove attachment',
            onPressed: onRemove,
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }

  String _speechLocaleForLanguage(String languageCode) {
    switch (languageCode) {
      case 'hi':
        return 'hi-IN';
      case 'ta':
        return 'ta-IN';
      case 'en':
      default:
        return 'en-IN';
    }
  }

  Future<void> _toggleLocalVoicePreview() async {
    final localPath = _voiceAudioPath;
    if (localPath == null || localPath.trim().isEmpty) {
      return;
    }

    if (_isPreviewPlaying) {
      await _voicePreviewPlayer.stop();
      if (mounted) {
        setState(() {
          _isPreviewPlaying = false;
        });
      }
      return;
    }

    await _voicePreviewPlayer.play(DeviceFileSource(localPath));
    if (mounted) {
      setState(() {
        _isPreviewPlaying = true;
      });
    }
  }

  @override
  void dispose() {
    _responderPollingTimer?.cancel();
    _stopOpenAppChatNotificationWatchers();
    _flutterTts.stop();
    _speechToText.stop();
    _audioRecorder.dispose();
    _voicePreviewCompleteSub?.cancel();
    _voicePreviewPlayer.dispose();
    _emergencyContextController.dispose();
    super.dispose();
  }

  PageRouteBuilder<void> _noTransitionRoute(Widget page) {
    return PageRouteBuilder<void>(
      pageBuilder: (_, __, ___) => page,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      transitionsBuilder: (_, __, ___, child) => child,
    );
  }

  Future<void> _handleHomeHeaderMenuSelection(
      _HomeHeaderMenuOption option) async {
    final authProvider = context.read<AuthProvider>();

    switch (option) {
      case _HomeHeaderMenuOption.language:
        _showLanguagePicker();
        break;
      case _HomeHeaderMenuOption.accessibility:
        _showAccessibilitySheet();
        break;
      case _HomeHeaderMenuOption.commsSimulation:
        _showCommsSimulationSheet();
        break;
      case _HomeHeaderMenuOption.viewSosHistory:
        final currentUser = authProvider.currentUser;
        if (currentUser != null) {
          SosHistoryScreen.open(
            context,
            currentUserId: currentUser.id,
            currentUserName: currentUser.displayName,
          );
        }
        break;
      case _HomeHeaderMenuOption.aboutApp:
        _showAboutAppDialog();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettingsProvider>();
    final authProvider = context.watch<AuthProvider>();

    void showResponderOnlySnackbar() {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(settings.t('snackbar_responder_only_feature')),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(settings.t('app_title'),style:TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.red.shade700,
        actions: [
          PopupMenuButton<_HomeHeaderMenuOption>(
            icon: const Icon(Icons.more_vert),
            onSelected: _handleHomeHeaderMenuSelection,
            itemBuilder: (_) => <PopupMenuEntry<_HomeHeaderMenuOption>>[
              PopupMenuItem<_HomeHeaderMenuOption>(
                value: _HomeHeaderMenuOption.language,
                child: Row(
                  children: [
                    const Icon(Icons.language, color: Colors.red),
                    const SizedBox(width: 8),
                    Text(settings.t('home_select_language'),style:TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              PopupMenuItem<_HomeHeaderMenuOption>(
                value: _HomeHeaderMenuOption.accessibility,
                child: Row(
                  children: [
                    const Icon(Icons.accessibility_new, color: Colors.red),
                    const SizedBox(width: 8),
                    Text(settings.t('title_accessibility'),style:TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              PopupMenuItem<_HomeHeaderMenuOption>(
                value: _HomeHeaderMenuOption.commsSimulation,
                child: Row(
                  children: [
                    const Icon(Icons.wifi_tethering, color: Colors.red),
                    const SizedBox(width: 8),
                    Text(settings.t('comms_simulation_title'),style:TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              PopupMenuItem<_HomeHeaderMenuOption>(
                value: _HomeHeaderMenuOption.viewSosHistory,
                child: Row(
                  children: [
                    const Icon(Icons.history, color: Colors.red),
                    const SizedBox(width: 8),
                    Text(settings.t('button_view_sos_history'),style:TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              PopupMenuItem<_HomeHeaderMenuOption>(
                value: _HomeHeaderMenuOption.aboutApp,
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Colors.red),
                    const SizedBox(width: 8),
                    Text(settings.t('button_about_app'),style:TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragEnd: (details) {
            if (details.primaryVelocity != null &&
                details.primaryVelocity! < -300) {
              final auth = context.read<AuthProvider>();
              if (auth.currentUser?.isResponder == true) {
                Navigator.of(context).pushReplacement(
                  _noTransitionRoute(const ResponderRequestsScreen()),
                );
              } else {
                _openChats();
              }
            }
          },
          child: SingleChildScrollView(
              child: Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Column(children: [
                    // Top section: Info
                    Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            settings.t('emergency_prompt'),
                            style: Theme.of(context).textTheme.headlineSmall,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _openResponderAction,
                              icon: const Icon(Icons.health_and_safety),
                              label: Text(
                                authProvider.currentUser?.isResponder == true
                                    ? settings.t('button_responder_dashboard')
                                    : settings.t('become_responder'),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Padding(
                              padding: const EdgeInsets.all(20.0),
                              child: Consumer<ResponderProvider>(
                                  builder: (context, responderProvider, _) {
                                return IntrinsicHeight(
                                    child: Row(children: [
                                  Expanded(
                                    child: _actionCard(
                                      title: settings.t('total_responders'),
                                      value: responderProvider.responders.length
                                          .toString(),
                                      icon: Icons.people,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: _actionCard(
                                      title: settings.t('nearby_5km'),
                                      value: responderProvider
                                          .nearbyResponders.length
                                          .toString(),
                                      icon: Icons.location_on,
                                    ),
                                  ),
                                ]));
                              })),
                          const SizedBox(height: 8),
                          Consumer<LocationProvider>(
                            builder: (context, locationProvider, _) {
                              if (locationProvider.hasLocation) {
                                return const SizedBox.shrink();
                              }

                              return Container(
                                margin: const EdgeInsets.symmetric(vertical: 10),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.location_off,
                                            color: Colors.orangeAccent,
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              settings.t('location_not_ready'),
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    _actionChip(
                                      label: 'Fix',
                                      onTap: () async {
                                        if (!locationProvider.hasLocation) {
                                          await locationProvider
                                              .openPermissionSettings();
                                        } else {
                                          await locationProvider
                                              .openLocationSettings();
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                          Consumer<AuthProvider>(
                            builder: (context, authProvider, _) {
                              final sosStatus =
                                  context.watch<SosStatusProvider>();
                              final activeSosId =
                                  sosStatus.activeSosId ?? _currentSosRequestId;
                              final hasActiveSos = activeSosId != null;
                              return Consumer<ResponderProvider>(
                                builder: (context, responderProvider, _) {
                                  final isCancelMode =
                                      _isSosInProgress || hasActiveSos;
                                  return Column(
                                    children: [
                                      if (hasActiveSos)
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 12.0),
                                          child: Container(
                                            width: double.infinity,
                                            decoration: BoxDecoration(
                                              color: Colors.red.shade50,
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                              border: Border.all(
                                                  color: Colors.red.shade200),
                                            ),
                                            padding: const EdgeInsets.all(14),
                                            child: Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    settings
                                                        .t('status_sos_active'),
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .bodyMedium
                                                        ?.copyWith(
                                                          color: Colors
                                                              .red.shade900,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                        ),
                                                  ),
                                                ),
                                                TextButton(
                                                  onPressed: () =>
                                                      _cancelActiveSosButton(
                                                          activeSosId),
                                                  style: TextButton.styleFrom(
                                                    foregroundColor:
                                                        Colors.red.shade900,
                                                  ),
                                                  child: Text(settings
                                                      .t('button_cancel_sos')),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      SOSButton(
                                        onPressed: isCancelMode
                                            ? (_isSosInProgress
                                                ? _cancelPendingSos
                                                : () => _cancelActiveSosButton(
                                                    activeSosId))
                                            : _handleSOSPress,
                                        isLoading: _isSosInProgress,
                                        enableHaptics: settings.hapticsEnabled,
                                        isActive: isCancelMode,
                                        activeLabel:
                                            settings.t('button_cancel_sos'),
                                        activeSubLabel: _isSosInProgress
                                            ? settings.t(
                                                'sos_button_cancel_sending_hint')
                                            : settings
                                                .t('sos_button_cancel_hint'),
                                      ),
                                    ],
                                  );
                                },
                              );
                            },
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              IconButton(
                                icon: Icon(Icons.info_outline,
                                    color: Colors.red.shade700),
                                tooltip: 'Info',
                                onPressed: _showEmergencyInfoBalloon,
                              ),
                              FilterChip(
                                selected: _forceCriticalSeverity,
                                label: Text(context
                                    .read<AppSettingsProvider>()
                                    .t('button_force_critical')),
                                selectedColor: Colors.red.shade100,
                                checkmarkColor: Colors.red.shade800,
                                onSelected: (value) {
                                  setState(() {
                                    _forceCriticalSeverity = value;
                                  });
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Container(
  padding: const EdgeInsets.all(10),
  decoration: BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(20),
    border: Border.all(color: Colors.red.shade200),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(0.05),
        blurRadius: 8,
        offset: const Offset(0, 3),
      ),
    ],
  ),
  child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [

      // 🔴 TOP INPUT FIELD
      TextField(
        controller: _emergencyContextController,
        minLines: 1,
        maxLines: 3,
        cursorColor: Colors.red,
        decoration: InputDecoration(
          hintText: settings.t('hint_emergency_details_example'),
          hintStyle: TextStyle(color: Colors.red.shade300),

          filled: true,
          fillColor: Colors.red.shade50,

          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),

          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),

          // 🎤 Voice-to-text
          suffixIcon: IconButton(
            icon: Icon(
              _isTranscribing ? Icons.stop : Icons.mic_none,
              color: Colors.red.shade700,
            ),
            onPressed: _speechReady ? _toggleVoiceInput : null,
          ),
        ),
      ),

      const SizedBox(height: 8),

      // ⚫ BOTTOM ACTION ROW
      Row(
        children: [

          _actionBtn(
            icon: Icons.camera_alt_outlined,
            onTap: _pickCameraImage,
          ),

          const SizedBox(width: 8),

          _actionBtn(
            icon: _isRecordingClip
                ? Icons.stop_circle
                : Icons.keyboard_voice_rounded,
            onTap: _toggleVoiceClipRecording,
            isActive: _isRecordingClip,
          ),
        ],
      ),
    ],
  ),
),
                        
                          if (_selectedImage != null ||
                              (_voiceAudioPath != null &&
                                  _voiceAudioPath!.isNotEmpty)) ...[
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    if (_selectedImage != null)
                                      _buildAttachmentCard(
                                        icon: Icons.image_outlined,
                                        fileName: _selectedImage!.name.isEmpty
                                            ? 'photo_attachment.jpg'
                                            : _selectedImage!.name,
                                        fileKind:
                                            settings.t('attachment_photo'),
                                        semanticsLabel: settings
                                            .t('semantics_view_attached_photo'),
                                        onOpen: _previewSelectedPhoto,
                                        onRemove: _removePhotoAttachment,
                                      ),
                                    if (_selectedImage != null &&
                                        _voiceAudioPath != null &&
                                        _voiceAudioPath!.isNotEmpty)
                                      const SizedBox(width: 8),
                                    if (_voiceAudioPath != null &&
                                        _voiceAudioPath!.isNotEmpty)
                                      _buildAttachmentCard(
                                        icon: Icons.graphic_eq_rounded,
                                        fileName: 'voice_clip.wav',
                                        fileKind:
                                            settings.t('attachment_voice'),
                                        semanticsLabel: settings.t(
                                            'semantics_play_attached_voice_clip'),
                                        onOpen: _toggleLocalVoicePreview,
                                        onRemove: _removeVoiceAttachment,
                                        openIcon: _isPreviewPlaying
                                            ? Icons.stop
                                            : Icons.play_arrow,
                                        statusIcon: _includeVoiceClip
                                            ? Icons.link
                                            : Icons.link_off,
                                        statusColor: _includeVoiceClip
                                            ? Colors.teal.shade700
                                            : Colors.grey.shade600,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          /*
                      if (false)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'AI status: ${crisisProvider.latestAnalysis!.aiStatus == '"' "'gemini_success'" '"' ? '"' "'Gemini API response received'" '"' : crisisProvider.latestAnalysis!.aiStatus == '"' "'missing_api_key'" '"' ? '"' "'Gemini key missing, local fallback used'" '"' : crisisProvider.latestAnalysis!.aiStatus == '"' "'forced_offline'" '"' ? '"' "'Simulation mode forced local fallback'" '"' : crisisProvider.latestAnalysis!.aiStatus == '"' "'gemini_empty_response'" '"' ? '"' "'Gemini returned empty response, local fallback used'" '"' : crisisProvider.latestAnalysis!.aiStatus == '"' "'gemini_error'" '"' ? '"' "'Gemini call failed, local fallback used'" '"' : '"' "'Local heuristic response'" '"'}',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Colors.blueGrey.shade700,
                                      fontWeight: FontWeight.w600,
                                    ),
                          ),
                        ),*/

                          const SizedBox(height: 12),
                        ],
                      ),
                    ),
                  ])))),
      bottomNavigationBar: FixedFooterNavigationBar(
        activeIndex: 0,
        showPeople: authProvider.currentUser?.isResponder == true,
        onSosTap: () {},
        onPeopleTap: authProvider.currentUser?.isResponder == true
            ? _openResponderRequests
            : showResponderOnlySnackbar,
        onChatsTap: _openChats,
        onMapTap: _openMap,
        onProfileTap: _showAccountSheet,
      ),
    );
  }
}

Widget _actionCard({
  required String title,
  required String value,
  required IconData icon,
}) {
  return CustomPaint(
    painter: DashedBorderPainter(),
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.red.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
        mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
            icon,
            size: 32,
            color: Colors.red.shade700,
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              color: Colors.red.shade900,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
            ]
          ) ,
          const SizedBox(height: 6),
          Text(
            title,
            style: TextStyle(
              color: Colors.red.shade600,
              fontWeight: FontWeight.w600,
            ),
          ),
          
        ],
      ),
    ),
  );
}

Widget _actionChip({
  required String label,
  required VoidCallback onTap,
}) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.red,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    ),
  );
}

// ---------------- DASHED BORDER ----------------
class DashedBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const dashWidth = 6;
    const dashSpace = 4;

    final paint = Paint()
      ..color = Colors.red
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(20),
    );

    final path = Path()..addRRect(rect);
    final metrics = path.computeMetrics();

    for (var metric in metrics) {
      double distance = 0;
      while (distance < metric.length) {
        final next = distance + dashWidth;
        canvas.drawPath(
          metric.extractPath(distance, next),
          paint,
        );
        distance = next + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

Widget _actionBtn({
  required IconData icon,
  required VoidCallback onTap,
  bool isActive = false,
}) {
  return Container(
    height: 42,
    width: 42,
    decoration: BoxDecoration(
      color: isActive ? Colors.red.shade600 : Colors.black,
      shape: BoxShape.circle,
    ),
    child: IconButton(
      icon: Icon(icon, size: 20),
      color: Colors.white,
      onPressed: onTap,
    ),
  );
}


Widget _buildSwitchCard({
  required String title,
  String? subtitle,
  required IconData icon,
  required bool value,
  required Function(bool) onChanged,
}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Container(
      decoration: BoxDecoration(
        color:
            value ? Colors.red.withValues(alpha: 0.08) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: value ? Colors.red : Colors.transparent,
        ),
      ),
      child: SwitchListTile.adaptive(
        value: value,
        onChanged: onChanged,
        title: Text(title),
        subtitle: subtitle != null ? Text(subtitle) : null,
        secondary: Icon(icon, color: Colors.red),
        activeThumbColor: Colors.red,
      ),
    ),
  );
}

Widget _buildCommsSwitch({
  required String title,
  String? subtitle,
  required IconData icon,
  required bool value,
  required Function(bool) onChanged,
}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Container(
      decoration: BoxDecoration(
        color:
            value ? Colors.red.withValues(alpha: 0.08) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: value ? Colors.red : Colors.transparent,
        ),
      ),
      child: SwitchListTile.adaptive(
        value: value,
        onChanged: onChanged,
        title: Text(title),
        subtitle: subtitle != null ? Text(subtitle) : null,
        secondary: Icon(icon, color: Colors.red),
        activeThumbColor: Colors.red,
      ),
    ),
  );
}
