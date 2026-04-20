import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_settings_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/comms_provider.dart';
import '../providers/crisis_provider.dart';
import '../providers/emergency_request_provider.dart';
import '../providers/location_provider.dart';
import '../providers/responder_provider.dart';
import '../providers/sos_status_provider.dart';
import 'notification_service.dart';
import 'sos_service.dart';
import '../../screens/group_chat_screen.dart';
import '../../screens/map_screen.dart';
import '../../screens/responder_requests_screen.dart';

class AppLaunchService {
  AppLaunchService(this.navigatorKey);

  final GlobalKey<NavigatorState> navigatorKey;
  late final AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;

  void init() {
    _appLinks = AppLinks();
    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      if (navigatorKey.currentContext != null) {
        _handleDeepLink(uri);
      }
    });
  }

  void dispose() {
    _linkSubscription?.cancel();
  }

  void registerNotificationHandlers() {
    NotificationService.setOnChatNotificationTap(_openChatFromNotification);
    NotificationService.setOnSosNotificationTap(_openSosFromNotification);
  }

  Future<void> _handleDeepLink(Uri uri) async {
    if (uri.scheme != 'rescue-link' || uri.host != 'sos') {
      return;
    }

    final context = navigatorKey.currentContext;
    if (context == null) {
      return;
    }

    final message = uri.queryParameters['message'] ?? uri.queryParameters['msg'];
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final sosStatus = Provider.of<SosStatusProvider>(context, listen: false);

    if (!auth.isAuthenticated) {
      return;
    }

    final crisisProvider = Provider.of<CrisisProvider>(context, listen: false);
    final emergencyRequestProvider =
        Provider.of<EmergencyRequestProvider>(context, listen: false);
    final locationProvider = Provider.of<LocationProvider>(context, listen: false);
    final responderProvider = Provider.of<ResponderProvider>(context, listen: false);
    final settings = Provider.of<AppSettingsProvider>(context, listen: false);
    final commsProvider = Provider.of<CommsProvider>(context, listen: false);

    final sosService = SosService();
    final requestId = await sosService.triggerSos(
      SosTriggerContext(
        authProvider: auth,
        crisisProvider: crisisProvider,
        emergencyRequestProvider: emergencyRequestProvider,
        locationProvider: locationProvider,
        responderProvider: responderProvider,
        settings: settings,
        commsProvider: commsProvider,
        customMessage: message,
      ),
    );

    if (requestId != null) {
      sosStatus.setActiveSos(requestId);
    }
  }

  Future<void> _openChatFromNotification(String sosId) async {
    final safeSosId = sosId.trim();
    if (safeSosId.isEmpty) {
      return;
    }

    final context = navigatorKey.currentContext;
    if (context == null) {
      return;
    }

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final user = auth.currentUser;
    if (user == null) {
      return;
    }

    final userName = user.displayName.trim().isNotEmpty
        ? user.displayName
        : 'RescueLink User';

    final nav = navigatorKey.currentState;
    if (nav == null) {
      return;
    }

    await nav.push(
      MaterialPageRoute<void>(
        builder: (_) => GroupChatScreen(
          sosId: safeSosId,
          currentUserId: user.id,
          currentUserName: userName,
          currentUserRole: user.isResponder ? 'responder' : 'victim',
          enableResponderJoinGate: user.isResponder,
        ),
      ),
    );
  }

  Future<void> _openSosFromNotification(
    String requestId,
    String actionId,
  ) async {
    final safeRequestId = requestId.trim();
    if (safeRequestId.isEmpty) {
      return;
    }

    final nav = navigatorKey.currentState;
    final context = navigatorKey.currentContext;
    if (context == null || nav == null) {
      return;
    }

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final user = auth.currentUser;
    if (user == null) {
      return;
    }

    final userName = user.displayName.trim().isNotEmpty
        ? user.displayName
        : 'RescueLink User';

    if (actionId == NotificationService.sosAcceptAction && user.isResponder) {
      final emergencyProvider =
          Provider.of<EmergencyRequestProvider>(context, listen: false);
      await emergencyProvider.acceptRequest(
        requestId: safeRequestId,
        responderUserId: user.id,
      );

      await nav.push(
        MaterialPageRoute<void>(
          builder: (_) => GroupChatScreen(
            sosId: safeRequestId,
            currentUserId: user.id,
            currentUserName: userName,
            currentUserRole: 'responder',
          ),
        ),
      );
      return;
    }

    if (actionId == NotificationService.sosNavigateAction) {
      final requestSnap = await FirebaseFirestore.instance
          .collection('emergency_requests')
          .doc(safeRequestId)
          .get();
      final requestData = requestSnap.data();
      final lat = (requestData?['latitude'] as num?)?.toDouble();
      final lng = (requestData?['longitude'] as num?)?.toDouble();
      final requesterName =
          (requestData?['requesterName'] as String?)?.trim() ?? 'SOS Request';

      if (lat != null && lng != null) {
        await nav.push(
          MaterialPageRoute<void>(
            builder: (_) => MapScreen(
              targetLatitude: lat,
              targetLongitude: lng,
              targetTitle: requesterName,
            ),
          ),
        );
        return;
      }
    }

    await nav.push(
      MaterialPageRoute<void>(
        builder: (_) => const ResponderRequestsScreen(),
      ),
    );
  }
}
