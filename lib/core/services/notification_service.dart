import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  NotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static Future<void> Function(String sosId)? _onChatNotificationTap;
    static Future<void> Function(String requestId, String actionId)?
      _onSosNotificationTap;
  static String? _pendingChatSosId;
    static Map<String, String>? _pendingSosNotification;

    static const String _payloadTypeKey = 'notificationType';
    static const String _payloadTypeChat = 'chat';
    static const String _payloadTypeSos = 'sos';

    static const String sosAcceptAction = 'sos_accept';
    static const String sosNavigateAction = 'sos_navigate';

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'rescue_link_alerts',
    'Rescue Alerts',
    description: 'Emergency alerts and status updates',
    importance: Importance.high,
  );

  static Future<void> initialize() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidInit);

    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        _handleLocalNotificationTap(
          payload: response.payload,
          actionId: response.actionId,
        );
      },
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    await initializePushMessaging();
  }

  static Future<void> initializePushMessaging() async {
    await _messaging.requestPermission(alert: true, badge: true, sound: true);
    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      final title = message.notification?.title ?? 'RescueLink Alert';
      final body = message.notification?.body ?? 'New emergency update';
      final chatSosId = _extractChatSosId(message.data);
      if (chatSosId.isNotEmpty) {
        await showChatMessageAlert(
          title: title,
          body: body,
          chatSosId: chatSosId,
        );
        return;
      }

      final requestId = _extractRequestId(message.data);
      if (requestId.isNotEmpty) {
        await showResponderSosAlert(
          requestId: requestId,
          title: title,
          body: body,
        );
        return;
      }

      await showSosAlert(title: title, body: body);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _dispatchRemoteMessageNavigation(message);
    });

    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _dispatchRemoteMessageNavigation(initialMessage);
    }
  }

  static void setOnChatNotificationTap(
    Future<void> Function(String sosId) handler,
  ) {
    _onChatNotificationTap = handler;
    _flushPendingChatNavigation();
  }

  static void setOnSosNotificationTap(
    Future<void> Function(String requestId, String actionId) handler,
  ) {
    _onSosNotificationTap = handler;
    _flushPendingSosNavigation();
  }

  static void _dispatchRemoteMessageNavigation(RemoteMessage message) {
    final sosId = _extractChatSosId(message.data);
    if (sosId.isNotEmpty) {
      _queueOrHandleChatNavigation(sosId);
      return;
    }

    final requestId = _extractRequestId(message.data);
    if (requestId.isEmpty) {
      return;
    }
    _queueOrHandleSosNavigation(requestId, sosNavigateAction);
  }

  static String _chatPayload(String sosId) {
    return jsonEncode(<String, String>{
      _payloadTypeKey: _payloadTypeChat,
      'chatSosId': sosId,
    });
  }

  static String _sosPayload(String requestId) {
    return jsonEncode(<String, String>{
      _payloadTypeKey: _payloadTypeSos,
      'requestId': requestId,
    });
  }

  static void _handleLocalNotificationTap({
    required String? payload,
    required String? actionId,
  }) {
    if (payload == null || payload.trim().isEmpty) {
      return;
    }

    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map) {
        return;
      }

      final payloadType = (decoded[_payloadTypeKey] as String?)?.trim();
      if (payloadType == _payloadTypeSos) {
        final requestId = _extractRequestId(decoded);
        if (requestId.isEmpty) {
          return;
        }
        final resolvedAction = (actionId?.trim().isNotEmpty ?? false)
            ? actionId!.trim()
            : sosNavigateAction;
        _queueOrHandleSosNavigation(requestId, resolvedAction);
        return;
      }

      final sosId = _extractChatSosId(decoded);
      if (sosId.isEmpty) {
        return;
      }
      _queueOrHandleChatNavigation(sosId);
    } catch (_) {
      // Ignore malformed payloads to keep notifications resilient.
    }
  }

  static String _extractChatSosId(Map<dynamic, dynamic> data) {
    final fromChat = (data['chatSosId'] as String?)?.trim();
    if (fromChat != null && fromChat.isNotEmpty) {
      return fromChat;
    }
    return '';
  }

  static String _extractRequestId(Map<dynamic, dynamic> data) {
    final requestId = (data['requestId'] as String?)?.trim();
    if (requestId != null && requestId.isNotEmpty) {
      return requestId;
    }
    return '';
  }

  static void _queueOrHandleChatNavigation(String sosId) {
    final handler = _onChatNotificationTap;
    if (handler == null) {
      _pendingChatSosId = sosId;
      return;
    }
    handler(sosId);
  }

  static void _flushPendingChatNavigation() {
    final pending = _pendingChatSosId;
    final handler = _onChatNotificationTap;
    if (pending == null || handler == null) {
      return;
    }
    _pendingChatSosId = null;
    handler(pending);
  }

  static void _queueOrHandleSosNavigation(String requestId, String actionId) {
    final handler = _onSosNotificationTap;
    if (handler == null) {
      _pendingSosNotification = <String, String>{
        'requestId': requestId,
        'actionId': actionId,
      };
      return;
    }
    handler(requestId, actionId);
  }

  static void _flushPendingSosNavigation() {
    final pending = _pendingSosNotification;
    final handler = _onSosNotificationTap;
    if (pending == null || handler == null) {
      return;
    }
    _pendingSosNotification = null;
    handler(
      pending['requestId'] ?? '',
      pending['actionId'] ?? sosNavigateAction,
    );
  }

  static String _normalizeTopic(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll('&', 'and')
        .replaceAll(RegExp(r'[^a-z0-9_]'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  static Future<void> syncDeviceProfile({
    required String userId,
    required bool isResponder,
    required bool isAvailable,
    String? skill,
    String? responderType,
  }) async {
    final token = await _messaging.getToken();
    if (token == null || token.isEmpty) {
      return;
    }

    final deviceRef = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('devices')
        .doc(token);

    await deviceRef.set(<String, dynamic>{
      'token': token,
      'platform': 'flutter',
      'isResponder': isResponder,
      'isAvailable': isAvailable,
      'skill': skill,
      'responderType': responderType,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final knownTopics = <String>{
      'responder_general',
      'responder_medical_emergency',
      'responder_fire_and_rescue',
      'responder_search_and_rescue',
      'responder_elderly_assist',
      'responder_women_safety',
      'responder_child_safety',
      'responder_shelter_and_evacuation',
      'responder_food_and_water_supply',
      'responder_essential_medicines',
      'responder_mobility_support',
      'responder_communication_relay',
      'responder_logistics_and_transport',
      'responder_off_duty_authority',
      'responder_police',
      'responder_civil_defense',
    };

    for (final topic in knownTopics) {
      await _messaging.unsubscribeFromTopic(topic);
    }

    if (!isResponder || !isAvailable) {
      return;
    }

    await _messaging.subscribeToTopic('responder_general');

    final normalizedSkill = _normalizeTopic(skill ?? 'general');
    if (normalizedSkill.isNotEmpty) {
      await _messaging.subscribeToTopic('responder_$normalizedSkill');
    }

    final normalizedType = _normalizeTopic(responderType ?? '');
    if (normalizedType.isNotEmpty) {
      await _messaging.subscribeToTopic('responder_$normalizedType');
    }
  }

  static Future<bool> requestPermissions() async {
    final androidImpl =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    final granted = await androidImpl?.requestNotificationsPermission();
    return granted ?? true;
  }

  static Future<void> showSosAlert({
    required String title,
    required String body,
    String? payload,
  }) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'rescue_link_alerts',
        'Rescue Alerts',
        channelDescription: 'Emergency alerts and status updates',
        importance: Importance.high,
        priority: Priority.high,
      ),
    );

    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
      payload: payload,
    );
  }

  static Future<void> showChatMessageAlert({
    required String title,
    required String body,
    required String chatSosId,
  }) async {
    await showSosAlert(
      title: title,
      body: body,
      payload: _chatPayload(chatSosId),
    );
  }

  static Future<void> showResponderSosAlert({
    required String requestId,
    required String title,
    required String body,
    bool includeActions = true,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      'rescue_link_alerts',
      'Rescue Alerts',
      channelDescription: 'Emergency alerts and status updates',
      importance: Importance.high,
      priority: Priority.high,
      actions: includeActions
          ? <AndroidNotificationAction>[
              const AndroidNotificationAction(
                sosAcceptAction,
                'Accept',
                showsUserInterface: true,
              ),
              const AndroidNotificationAction(
                sosNavigateAction,
                'Navigate',
                showsUserInterface: true,
              ),
            ]
          : null,
    );

    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      NotificationDetails(android: androidDetails),
      payload: _sosPayload(requestId),
    );
  }
}
