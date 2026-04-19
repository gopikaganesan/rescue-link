import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:app_links/app_links.dart';
import 'package:home_widget/home_widget.dart';

import 'firebase_options.dart';
import 'core/providers/app_settings_provider.dart';
import 'core/providers/auth_provider.dart';
import 'core/providers/comms_provider.dart';
import 'core/providers/crisis_provider.dart';
import 'core/providers/emergency_request_provider.dart';
import 'core/providers/location_provider.dart';
import 'core/providers/responder_provider.dart';
import 'core/services/notification_service.dart';
import 'core/services/sos_service.dart';
import 'screens/auth_screen.dart';
import 'screens/group_chat_screen.dart';
import 'screens/home_screen.dart';
import 'screens/map_screen.dart';
import 'screens/responder_requests_screen.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
}

/// Callback for HomeWidget button clicks
@pragma('vm:entry-point')
Future<void> _homeWidgetBackgroundCallback(Uri? uri) async {
  if (uri?.host == 'sos' || uri?.scheme == 'rescue-link') {
    // Note: This runs in a background isolate. 
    // We would need to initialize minimal Firebase/Providers if we want full logic.
    // For now, we'll let the app open via the pending intent we set in Kotlin.
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  await NotificationService.initialize();
  
  // Register HomeWidget interactivity
  await HomeWidget.registerInteractivityCallback(_homeWidgetBackgroundCallback);
  
  runApp(const RescueLinkApp());
}

class RescueLinkApp extends StatefulWidget {
  const RescueLinkApp({super.key});

  @override
  State<RescueLinkApp> createState() => _RescueLinkAppState();
}

class _RescueLinkAppState extends State<RescueLinkApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    NotificationService.setOnChatNotificationTap(_openChatFromNotification);
    NotificationService.setOnSosNotificationTap(_openSosFromNotification);
    _initDeepLinks();
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  void _initDeepLinks() {
    _appLinks = AppLinks();
    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      _handleDeepLink(uri);
    });
  }

  Future<void> _handleDeepLink(Uri uri) async {
    if (uri.scheme == 'rescue-link' && uri.host == 'sos') {
      final context = _navigatorKey.currentContext;
      if (context == null) return;

      final message = uri.queryParameters['message'] ?? uri.queryParameters['msg'];
      
      // Navigate to Home and show prompt or auto-trigger
      // For safety, we navigate to the main screen first
      _navigatorKey.currentState?.popUntil((route) => route.isFirst);
      
      // Use the SosService to trigger the flow
      // We pass the message from the voice assistant / deep link
      final sosService = SosService();
      
      // Let's show a snackbar or small overlay first confirm? 
      // Current plan recommendation was to open app for confirmation.
      // We can trigger the logic but maybe HomeScreen will show the dialog.
      
      // We'll use a broadcast or just call the service if we are authenticated
      final auth = Provider.of<AuthProvider>(context, listen: false);
      if (auth.isAuthenticated) {
        await sosService.triggerSos(context, customMessage: message);
      }
    }
  }

  Future<void> _openChatFromNotification(String sosId) async {
    final safeSosId = sosId.trim();
    if (safeSosId.isEmpty) {
      return;
    }

    final context = _navigatorKey.currentContext;
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

    await Navigator.of(context).push(
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

    final nav = _navigatorKey.currentState;
    final context = _navigatorKey.currentContext;
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

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppSettingsProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => CommsProvider()),
        ChangeNotifierProvider(create: (_) => CrisisProvider()),
        ChangeNotifierProvider(create: (_) => EmergencyRequestProvider()),
        ChangeNotifierProvider(create: (_) => LocationProvider()),
        ChangeNotifierProvider(create: (_) => ResponderProvider()),
      ],
      child: Consumer<AppSettingsProvider>(
        builder: (context, settings, _) {
          return MaterialApp(
            title: 'RescueLink',
            debugShowCheckedModeBanner: false,
            navigatorKey: _navigatorKey,
            theme: ThemeData(
              useMaterial3: true,
              colorScheme: settings.highContrastEnabled
                  ? const ColorScheme.highContrastLight()
                  : ColorScheme.fromSeed(
                      seedColor: Colors.red,
                      brightness: Brightness.light,
                    ),
              appBarTheme: AppBarTheme(
                elevation: 0,
                backgroundColor:
                    settings.highContrastEnabled ? Colors.black : Colors.red.shade700,
                foregroundColor: Colors.white,
              ),
              elevatedButtonTheme: ElevatedButtonThemeData(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade600,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 32,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
            builder: (context, child) {
              final mq = MediaQuery.of(context);
              return MediaQuery(
                data: mq.copyWith(textScaler: TextScaler.linear(settings.textScaleFactor)),
                child: child ?? const SizedBox.shrink(),
              );
            },
            home: const AuthWrapper(),
          );
        },
      ),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, _) {
        if (authProvider.isAuthenticated && authProvider.currentUser != null) {
          return const HomeScreen();
        }

        if (authProvider.isLoading) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        return const AuthScreen();
      },
    );
  }
}
