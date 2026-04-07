import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  NotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'rescue_link_alerts',
    'Rescue Alerts',
    description: 'Emergency alerts and status updates',
    importance: Importance.high,
  );

  static Future<void> initialize() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidInit);

    await _plugin.initialize(settings);

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
      await showSosAlert(title: title, body: body);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((_) {
      // Navigation can be added later via app-level route handling.
    });
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
    );
  }
}
