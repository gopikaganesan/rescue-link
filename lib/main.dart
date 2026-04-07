import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'core/providers/app_settings_provider.dart';
import 'core/providers/auth_provider.dart';
import 'core/providers/comms_provider.dart';
import 'core/providers/crisis_provider.dart';
import 'core/providers/emergency_request_provider.dart';
import 'core/providers/location_provider.dart';
import 'core/providers/responder_provider.dart';
import 'core/services/notification_service.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  await NotificationService.initialize();
  runApp(const RescueLinkApp());
}

class RescueLinkApp extends StatelessWidget {
  const RescueLinkApp({super.key});

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
