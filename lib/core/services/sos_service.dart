import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'package:torch_light/torch_light.dart';

import '../providers/app_settings_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/comms_provider.dart';
import '../providers/crisis_provider.dart';
import '../providers/emergency_request_provider.dart';
import '../providers/location_provider.dart';
import '../providers/responder_provider.dart';
import '../services/notification_service.dart';
import '../services/media_upload_service.dart';

class SosCancellationToken {
  bool _isCanceled = false;

  bool get isCanceled => _isCanceled;

  void cancel() {
    _isCanceled = true;
  }
}

class SosTriggerContext {
  const SosTriggerContext({
    required this.authProvider,
    required this.crisisProvider,
    required this.emergencyRequestProvider,
    required this.locationProvider,
    required this.responderProvider,
    required this.settings,
    required this.commsProvider,
    this.customMessage,
    this.imageFile,
    this.voiceAudioPath,
    this.forceCritical = false,
    this.cancelToken,
  });

  final AuthProvider authProvider;
  final CrisisProvider crisisProvider;
  final EmergencyRequestProvider emergencyRequestProvider;
  final LocationProvider locationProvider;
  final ResponderProvider responderProvider;
  final AppSettingsProvider settings;
  final CommsProvider commsProvider;
  final String? customMessage;
  final XFile? imageFile;
  final String? voiceAudioPath;
  final bool forceCritical;
  final SosCancellationToken? cancelToken;
}

class SosService {
  static final SosService _instance = SosService._internal();
  factory SosService() => _instance;
  SosService._internal();

  final MediaUploadService _mediaUploadService = MediaUploadService.fromEnvironment();

  /// Core logic to trigger an SOS alert.
  /// Can be called from UI, background tasks, or deep links.
  Future<String?> triggerSos(
    SosTriggerContext request,
  ) async {
    final authProvider = request.authProvider;
    final crisisProvider = request.crisisProvider;
    final emergencyRequestProvider = request.emergencyRequestProvider;
    final locationProvider = request.locationProvider;
    final responderProvider = request.responderProvider;
    final settings = request.settings;
    final commsProvider = request.commsProvider;
    final customMessage = request.customMessage;
    final imageFile = request.imageFile;
    final voiceAudioPath = request.voiceAudioPath;
    final forceCritical = request.forceCritical;
    final cancelToken = request.cancelToken;

    // 1. Visual/Haptic Feedback (Flash)
    if (settings.sosFlashEnabled) {
      try {
        await TorchLight.enableTorch();
        await Future<void>.delayed(const Duration(milliseconds: 350));
        await TorchLight.disableTorch();
      } catch (_) {}
    }

    // 2. Ensure Location
    if (cancelToken?.isCanceled == true) {
      return null;
    }

    if (!locationProvider.hasLocation) {
      await locationProvider.refreshLocationStatus(fetchLocation: true);
    }

    if (!locationProvider.hasLocation || authProvider.currentUser == null) {
      return null;
    }

    // 3. Update User Location
    authProvider.updateUserLocation(
      locationProvider.latitude!,
      locationProvider.longitude!,
    );

    // 4. Prepare Message
    final baseMessageParts = <String>[];
    if (customMessage != null && customMessage.trim().isNotEmpty) {
      baseMessageParts.add(customMessage.trim());
    }

    // 5. Handle Assets (AI Analysis Input)
    Uint8List? imageBytes;
    String? imageMimeType;
    if (imageFile != null) {
      imageBytes = await imageFile.readAsBytes();
      imageMimeType = _getContentTypeForName(imageFile.name);
    }

    if (cancelToken?.isCanceled == true) {
      return null;
    }

    // 6. AI Crisis Analysis
    final aiInput = 'SOS triggered by ${authProvider.currentUser!.displayName}. '
        'Context: ${customMessage ?? "Emergency alert"}. '
        'Location: ${locationProvider.latitude}, ${locationProvider.longitude}';

    await crisisProvider.classifyCrisis(
      aiInput,
      availableSkills: responderProvider.responders
          .map((r) => r.skillsArea)
          .toSet()
          .toList(),
      forceOffline: commsProvider.forceOfflineAi,
      imageBytes: imageBytes,
      imageMimeType: imageMimeType,
    );

    // 7. Upload Media
    String? attachmentUrl;
    if (imageFile != null) {
      try {
        attachmentUrl = await _mediaUploadService.uploadEmergencyImage(
          image: imageFile,
          userId: authProvider.currentUser!.id,
        );
      } catch (_) {}
    }

    String? voiceAudioUrl;
    if (cancelToken?.isCanceled == true) {
      return null;
    }

    if (voiceAudioPath != null) {
      try {
        voiceAudioUrl = await _mediaUploadService.uploadEmergencyVoice(
          localPath: voiceAudioPath,
          userId: authProvider.currentUser!.id,
        );
      } catch (_) {}
    }

    if (cancelToken?.isCanceled == true) {
      return null;
    }

    // 8. Create Emergency Request
    final analysis = crisisProvider.latestAnalysis;
    final finalSeverity = forceCritical ? 'critical' : (analysis?.severity ?? 'medium');

    final requestId = await emergencyRequestProvider.createRequest(
      requesterUserId: authProvider.currentUser!.id,
      requesterName: authProvider.currentUser!.displayName,
      latitude: locationProvider.latitude!,
      longitude: locationProvider.longitude!,
      category: analysis?.category ?? 'General Emergency',
      severity: finalSeverity,
      originalMessage: customMessage ?? 'SOS Triggered',
      voiceTranscript: analysis?.summary, // Or use actual transcript if passed
      voiceAudioUrl: voiceAudioUrl,
      voiceAudioType: voiceAudioUrl != null ? 'audio/wav' : null,
      attachmentUrl: attachmentUrl,
      attachmentType: attachmentUrl != null ? 'image' : null,
      summary: analysis?.summary ?? 'SOS triggered by user',
      recommendedSkill: analysis?.recommendedSkill ?? 'General Support',
      suggestedActions: analysis?.suggestedActions ?? const <String>[],
      aiConfidence: analysis?.confidence,
      humanReviewRecommended: analysis?.humanReviewRecommended ?? false,
      forcedCriticalByUser: forceCritical,
    );

    // 9. Notifications
    if (settings.notificationsEnabled) {
      await NotificationService.showSosAlert(
        title: 'SOS Triggered',
        body: 'Alert sent. Help is on the way.',
      );
    }

    return requestId;
  }

  String _getContentTypeForName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png')) return 'image/png';
    return 'image/jpeg';
  }
}
