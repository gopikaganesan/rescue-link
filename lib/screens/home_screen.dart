import 'dart:async';
import 'package:animated_bottom_navigation_bar/animated_bottom_navigation_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:provider/provider.dart';
import 'package:torch_light/torch_light.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/providers/app_settings_provider.dart';
import '../core/providers/auth_provider.dart';
import '../core/providers/comms_provider.dart';
import '../core/providers/crisis_provider.dart';
import '../core/providers/emergency_request_provider.dart';
import '../core/providers/location_provider.dart';
import '../core/providers/responder_provider.dart';
import '../core/services/notification_service.dart';
import '../core/services/responder_matching_service.dart';
import 'auth_screen.dart';
import 'responder_registration_screen.dart';
import 'responder_requests_screen.dart';
import 'map_screen.dart';
import '../widgets/sos_button.dart';
import 'dart:ui';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isSosInProgress = false;
  Timer? _responderPollingTimer;
  final Set<String> _notifiedRequestIds = <String>{};
  String _lastDeliveryRoute = 'Internet route';
  String? _currentSosRequestId; // Track current SOS for cancellation
  int _bottomNavIndex = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeScreen();
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
  }

  

  Future<void> _syncPushProfile() async {
    final auth = context.read<AuthProvider>();
    final responders = context.read<ResponderProvider>();
    final user = auth.currentUser;
    if (user == null) {
      return;
    }

    final myResponder = responders.responders.where((r) => r.userId == user.id).toList();
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
    final me = auth.currentUser;
    if (me == null || !me.isResponder) {
      return;
    }

    final responders = context.read<ResponderProvider>();
    final requests = context.read<EmergencyRequestProvider>();

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

      final radius = ResponderMatchingService.radiusKmForSeverity(request.severity);
      final distance = responder.distanceToLocation(request.latitude, request.longitude);
      if (distance > radius) {
        continue;
      }

      _notifiedRequestIds.add(request.id);
      await NotificationService.showSosAlert(
        title: 'New Nearby SOS (${request.severity.toUpperCase()})',
        body: '${request.category} • ${request.recommendedSkill} • ${distance.toStringAsFixed(1)} km',
      );
    }
  }

  /// Handle SOS button press
  Future<void> _handleSOSPress() async {
    if (_isSosInProgress) {
      return;
    }

    setState(() {
      _isSosInProgress = true;
    });

    try {
      final authProvider = context.read<AuthProvider>();
      final crisisProvider = context.read<CrisisProvider>();
      final emergencyRequestProvider = context.read<EmergencyRequestProvider>();
      final locationProvider = context.read<LocationProvider>();
      final responderProvider = context.read<ResponderProvider>();
      final settings = context.read<AppSettingsProvider>();
      final commsProvider = context.read<CommsProvider>();

      if (settings.sosFlashEnabled) {
        await _pulseFlash();
      }

      if (!locationProvider.hasLocation) {
        _showSnackBar('Requesting your location...');
        await locationProvider.refreshLocationStatus(fetchLocation: true);
      }

      if (!locationProvider.hasLocation || authProvider.currentUser == null) {
        _showSnackBar('Unable to determine location. Please try again.');
        return;
      }

      await responderProvider.fetchResponders();

      // Update user location
      authProvider.updateUserLocation(
        locationProvider.latitude!,
        locationProvider.longitude!,
      );

        final aiInput =
          'SOS triggered by ${authProvider.currentUser!.displayName} near '
          '${locationProvider.latitude!.toStringAsFixed(4)}, '
          '${locationProvider.longitude!.toStringAsFixed(4)}. '
          '${_emergencyContextController.text.trim().isEmpty ? 'Potential emergency needs urgent support.' : _emergencyContextController.text.trim()}';

      await crisisProvider.classifyCrisis(
        aiInput,
        availableSkills: responderProvider.responders
            .map((responder) => responder.skillsArea)
            .toSet()
            .toList(),
      );

      // Find nearby responders within 5km
      responderProvider.findNearbyResponders(
        locationProvider.latitude!,
        locationProvider.longitude!,
        5.0,
        requiredSkill: crisisProvider.latestAnalysis?.recommendedSkill,
      );

      final analysis = crisisProvider.latestAnalysis;
      final requestId = await emergencyRequestProvider.createRequest(
        requesterUserId: authProvider.currentUser!.id,
        requesterName: authProvider.currentUser!.displayName,
        latitude: locationProvider.latitude!,
        longitude: locationProvider.longitude!,
        category: analysis?.category ?? 'General Emergency',
        severity: analysis?.severity ?? 'medium',
        summary: analysis?.summary ?? 'SOS triggered by user',
        recommendedSkill: analysis?.recommendedSkill ?? 'General Support',
      );

      _currentSosRequestId = requestId;

      final cloudWriteSucceeded = requestId != null;
      _lastDeliveryRoute = commsProvider.resolveDeliveryRoute(
        cloudWriteSucceeded: cloudWriteSucceeded,
        hasNearbyResponders: responderProvider.nearbyResponders.isNotEmpty,
      );

      if (responderProvider.error != null) {
        _showSnackBar(responderProvider.error!);
      }
      if (emergencyRequestProvider.error != null) {
        _showSnackBar(emergencyRequestProvider.error!);
      }

      if (settings.notificationsEnabled) {
        await NotificationService.showSosAlert(
          title: 'SOS Triggered',
          body:
              'Alert sent near ${locationProvider.latitude!.toStringAsFixed(3)}, ${locationProvider.longitude!.toStringAsFixed(3)}',
        );
      }

      _showSOSConfirmation();
    } catch (_) {
      _showSnackBar('SOS could not complete. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          _isSosInProgress = false;
        });
      }
    }
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
    final crisisProvider = context.read<CrisisProvider>();
    final locationProvider =
        context.read<LocationProvider>();
    final responderProvider =
        context.read<ResponderProvider>();
    final analysis = crisisProvider.latestAnalysis;
    final emergencyRequestProvider =
        context.read<EmergencyRequestProvider>();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.green.shade50,
        title: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 28),
            const SizedBox(width: 8),
            const Expanded(child: Text('✓ SOS Received')),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  border: Border.all(color: Colors.green, width: 2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SOS has been broadcast to nearby responders.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade800,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Location: ${locationProvider.latitude?.toStringAsFixed(4)}, '
                      '${locationProvider.longitude?.toStringAsFixed(4)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Nearby Responders: ${responderProvider.nearbyResponders.length}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              if (responderProvider.nearbyResponders.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    'ℹ️ No nearby responders yet. Use emergency call/SMS as secondary backup.',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: Colors.orange[800]),
                  ),
                ),
              if (analysis != null) ...[
                const SizedBox(height: 16),
                Text(
                  'Analysis Results',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Category: ${analysis.category}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                Text(
                  'Severity: ${analysis.severity}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                Text(
                  'Skill Match: ${analysis.recommendedSkill}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (analysis.suggestedActions.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Recommended Actions:',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  ...analysis.suggestedActions.take(3).map(
                        (action) => Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Text('• $action',
                              style: Theme.of(context).textTheme.bodySmall),
                        ),
                      ),
                ],
                if (analysis.offlineMode)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      '🔌 Offline Mode (AI Fallback Active)',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.orange[800]),
                    ),
                  ),
              ],
              const SizedBox(height: 8),
              Text(
                'Route: $_lastDeliveryRoute',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey[600],
                    ),
              ),
            ],
          ),
        ),
        actions: [
          // Cancel SOS - prominent red button
          ElevatedButton.icon(
            onPressed: () async {
              if (_currentSosRequestId != null) {
                await emergencyRequestProvider
                    .cancelRequest(_currentSosRequestId!);
                _currentSosRequestId = null;
              }
              Navigator.pop(dialogContext);
              _showSnackBar('SOS cancelled.');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.close),
            label: const Text('Cancel SOS'),
          ),
          const SizedBox(width: 8),
          // View Map button
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(dialogContext);
              _openMap();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade600,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.map),
            label: const Text('View Map'),
          ),
          if (responderProvider.nearbyResponders.isEmpty) ...[
            const SizedBox(width: 8),
            // Call Emergency button
            ElevatedButton.icon(
              onPressed: () async {
                Navigator.pop(dialogContext);
                await _makeEmergencyCall();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade600,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.call),
              label: const Text('Call 112'),
            ),
          ],
        ],
      ),
    );

    _announce('SOS activated. Nearby responders have been notified.');
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
    SemanticsService.announce(message, TextDirection.ltr);
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

  void _openAuthScreen() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const AuthScreen(showGuestButton: false),
      ),
    );
  }

  Future<void> _logoutRegisteredUser() async {
    await context.read<AuthProvider>().logout();
    if (mounted) {
      _showSnackBar('Signed out successfully.');
    }
  }

void _showLanguagePicker() {
  final settings = context.read<AppSettingsProvider>();

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      return Container(
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
            const Text(
              "Select Language",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 4),

            const Text(
              "Choose your preferred language",
              style: TextStyle(color: Colors.grey),
            ),

            const SizedBox(height: 16),

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
                              ? Colors.blue.withOpacity(0.1)
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected
                                ? Colors.blue
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
      );
    },
  );
}

void _showAccountSheet() {
  final authProvider = context.read<AuthProvider>();
  final user = authProvider.currentUser;

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) {
      if (user == null) {
        return const Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: Text('Not signed in')),
        );
      }

      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 🔹 Drag handle
            Container(
              height: 4,
              width: 40,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(10),
              ),
            ),

            // 🔹 Profile Header
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  child: Text(
                    user.displayName.isNotEmpty
                        ? user.displayName[0].toUpperCase()
                        : 'U',
                    style: const TextStyle(fontSize: 20),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.displayName,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        user.email.isEmpty
                            ? (user.phoneNumber ?? 'No email')
                            : user.email,
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // 🔹 Session Chip
            Align(
              alignment: Alignment.centerLeft,
              child: Chip(
                label: Text(
                  authProvider.isAnonymousUser
                      ? 'Anonymous Session'
                      : 'Registered Account',
                ),
              ),
            ),

            const SizedBox(height: 20),

            // 🔹 Actions Section
            Column(
              children: [
                if (authProvider.isAnonymousUser)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        _openAuthScreen();
                      },
                      icon: const Icon(Icons.login),
                      label: const Text('Sign In / Create Account'),
                    ),
                  ),

                if (!authProvider.isAnonymousUser)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        Navigator.of(sheetContext).pop();
                        await _logoutRegisteredUser();
                      },
                      icon: const Icon(Icons.logout),
                      label: const Text('Sign Out'),
                    ),
                  ),

                if (user.isResponder)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        _openResponderRequests();
                      },
                      icon: const Icon(Icons.list_alt),
                      label: const Text('People Needing Help'),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 16),

            // 🔹 Responder Section
            if (user.isResponder)
              Consumer<ResponderProvider>(
                builder: (context, responderProvider, _) {
                  final mine = responderProvider.responders
                      .where((r) => r.userId == user.id)
                      .toList();

                  final isAvailable =
                      mine.isEmpty ? true : mine.first.isAvailable;

                  return Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: Colors.grey.shade300),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Responder Online'),
                            value: isAvailable,
                            onChanged: _toggleAvailability,
                          ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              onPressed: () async {
                                Navigator.of(sheetContext).pop();
                                await _deregisterResponder();
                              },
                              child: const Text(
                                'De-register as responder',
                                style: TextStyle(color: Colors.red),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      );
    },
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
                        children: const [
                          Icon(Icons.accessibility_new,
                              color: Colors.white),
                          SizedBox(width: 10),
                          Text(
                            'Accessibility',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // 🔧 Settings Cards
                    _buildSwitchCard(
                      title: 'Haptic vibration for SOS',
                      icon: Icons.vibration,
                      value: settings.hapticsEnabled,
                      onChanged: (v) {
                        settings.setHapticsEnabled(v);
                        setModalState(() {});
                      },
                    ),

                    _buildSwitchCard(
                      title: 'Flash light pulse on SOS',
                      subtitle: 'Uses device torch if available',
                      icon: Icons.flashlight_on,
                      value: settings.sosFlashEnabled,
                      onChanged: (v) {
                        settings.setSosFlashEnabled(v);
                        setModalState(() {});
                      },
                    ),

                    _buildSwitchCard(
                      title: 'High contrast mode',
                      icon: Icons.contrast,
                      value: settings.highContrastEnabled,
                      onChanged: (v) {
                        settings.setHighContrastEnabled(v);
                        setModalState(() {});
                      },
                    ),

                    _buildSwitchCard(
                      title: 'Enable notifications',
                      subtitle: 'Local SOS status alerts',
                      icon: Icons.notifications_active,
                      value: settings.notificationsEnabled,
                      onChanged: (value) async {
                        if (value) {
                          final granted =
                              await NotificationService.requestPermissions();
                          settings.setNotificationsEnabled(granted);

                          if (!granted && mounted) {
                            _showSnackBar(
                                'Notification permission not granted.');
                          }
                        } else {
                          settings.setNotificationsEnabled(false);
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
                              const Expanded(child: Text('Text Size')),
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
                              label: const Text(
                                'Reset',
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
                          onPressed: () {
                            _announce(
                              'Accessibility test announcement. SOS button is centered below information cards.',
                            );
                            _showSnackBar(
                                'Screen reader announcement sent.');
                          },
                          icon: const Icon(Icons.record_voice_over),
                          label: const Text('Voice Test'),
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
                                  'Flash pulse test completed.');
                            }
                          },
                          icon: const Icon(Icons.flashlight_on),
                          label: const Text('Flash Test'),
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
                      children: const [
                        Icon(Icons.wifi_tethering, color: Colors.white),
                        SizedBox(width: 10),
                        Text(
                          'Comms Simulation',
                          style: TextStyle(
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
  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
  decoration: BoxDecoration(
    color: Colors.grey.shade100,
    borderRadius: BorderRadius.circular(18),
    border: Border.all(
      color: Colors.red.withOpacity(0.3),
    ),
  ),
  child: DropdownButtonHideUnderline(
    child: DropdownButton<CommsMode>(
      value: comms.mode,
      isExpanded: true,
      icon: const Icon(Icons.keyboard_arrow_down, color: Colors.red),
      dropdownColor: Colors.white,
      borderRadius: BorderRadius.circular(16),

      // Selected item display
      selectedItemBuilder: (context) {
        return CommsMode.values.map((mode) {
          return Row(
            children: [
              Text(
                comms.modeLabel(mode),
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          );
        }).toList();
      },

      items: CommsMode.values.map((mode) {
        return DropdownMenuItem<CommsMode>(
          value: mode,
          child: Row(
            children: [
              Text(comms.modeLabel(mode)),
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
                    title: 'Simulate tower failure',
                    icon: Icons.signal_cellular_off,
                    value: comms.simulateTowerFailure,
                    onChanged: (v) {
                      comms.setSimulateTowerFailure(v);
                      setModalState(() {});
                    },
                  ),

                  _buildCommsSwitch(
                    title: 'Device supports satellite',
                    subtitle: 'Simulated capability',
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
                      color: Colors.red.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.red.withOpacity(0.3)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Icon(Icons.info_outline, color: Colors.red),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'This simulation allows testing disaster or lockdown connectivity fallback without real mesh or satellite hardware.',
                            style: TextStyle(fontSize: 13),
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

    await responderProvider.setResponderAvailability(
      userId: userId,
      isAvailable: value,
    );

    final mine = responderProvider.responders.where((r) => r.userId == userId).toList();
    final profile = mine.isEmpty ? null : mine.first;
    await NotificationService.syncDeviceProfile(
      userId: userId,
      isResponder: authProvider.currentUser?.isResponder ?? false,
      isAvailable: value,
      skill: profile?.skillsArea,
      responderType: profile?.responderType,
    );

    if (mounted) {
      _showSnackBar(value ? 'Responder is online.' : 'Responder is offline.');
    }
  }

  final TextEditingController _emergencyContextController =
      TextEditingController();

  Future<void> _makeEmergencyCall() async {
    final uri = Uri.parse('tel:112');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      _showSnackBar('Could not open dialer. Please call 112 manually.');
    }
  }

  Future<void> _sendEmergencySms() async {
    final location = context.read<LocationProvider>();
    final lat = location.latitude?.toStringAsFixed(5) ?? 'unknown';
    final lng = location.longitude?.toStringAsFixed(5) ?? 'unknown';
    final text = _emergencyContextController.text.trim().isEmpty
        ? 'Emergency help needed. My location: $lat,$lng'
        : '${_emergencyContextController.text.trim()}. Location: $lat,$lng';
    final uri = Uri.parse('sms:112?body=${Uri.encodeComponent(text)}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      _showSnackBar('Could not open SMS app.');
    }
  }

  @override
  void dispose() {
    _responderPollingTimer?.cancel();
    _emergencyContextController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettingsProvider>();
    final authProvider = context.watch<AuthProvider>();

     // Build icon list dynamically
        final List<IconData> iconList = [
          Icons.language,
          if (authProvider.currentUser?.isResponder == true)
            Icons.support_agent,
          Icons.cell_tower,
          Icons.map,
          Icons.account_circle,
        ];

        // Map actions
        final List<VoidCallback> actions = [
          _showLanguagePicker,
          if (authProvider.currentUser?.isResponder == true)
            _openResponderRequests,
          _showCommsSimulationSheet,
          _openMap,
          _showAccountSheet,
        ];

    return Scaffold(
      appBar: AppBar(
        title: Text(settings.t('app_title'),style: TextStyle(fontWeight: FontWeight.bold),),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.red.shade700,
        actions: [
          /*
          Semantics(
            button: true,
            label: 'Switch app language',
            child: IconButton(
              icon: const Icon(Icons.language),
              onPressed: _showLanguagePicker,
              tooltip: settings.t('language'),
            ),
          ),
          Consumer<AuthProvider>(
            builder: (context, authProvider, _) {
              if (authProvider.currentUser?.isResponder != true) {
                return const SizedBox.shrink();
              }
              return IconButton(
                icon: const Icon(Icons.support_agent),
                onPressed: _openResponderRequests,
                tooltip: 'People needing help',
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.cell_tower),
            onPressed: _showCommsSimulationSheet,
            tooltip: 'Connectivity simulation',
          ),
          IconButton(
            icon: const Icon(Icons.map),
            onPressed: _openMap,
            tooltip: 'Responders map',
          ),*/
         
          IconButton(
            icon: const Icon(Icons.accessibility_new),
            onPressed: _showAccessibilitySheet,
            tooltip: 'Accessibility',
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Column(
            children: [
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
                    /*
                    Text(
                      settings.t('emergency_subtitle'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey[600],
                      ),
                    ),*/
                     // Bottom section: Quick info
              Padding(
        padding: const EdgeInsets.all(20.0),
        child: Consumer<ResponderProvider>(
          builder: (context, responderProvider, _) {
            return IntrinsicHeight(
              child :Row(
              children: [
                Expanded(
                  child: _actionCard(
                    title: settings.t('total_responders'),
                    value:
                        responderProvider.responders.length.toString(),
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
                ),]
                ));})),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _openResponderAction,
                        icon: const Icon(Icons.health_and_safety),
                        label: Text(
                          authProvider.currentUser?.isResponder == true
                              ? 'Responder Dashboard'
                              : settings.t('become_responder'),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  
                    TextField(
  controller: _emergencyContextController,
  minLines: 1,
  maxLines: 3,
  cursorColor: Colors.red,

  decoration: InputDecoration(
    labelText: 'Emergency details (optional)',
    hintText:
        'Example: elderly person fell, flood nearby, child missing, no transport',

    filled: true,
    fillColor: Colors.red.shade50,

    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: Colors.red.shade200),
    ),

    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: Colors.red.shade300, width: 1.2),
    ),

    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: Colors.red.shade600, width: 2),
    ),

    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: Colors.red),
    ),

    labelStyle: TextStyle(color: Colors.red.shade700),
    hintStyle: TextStyle(color: Colors.red.shade300),

    contentPadding: const EdgeInsets.symmetric(
      horizontal: 16,
      vertical: 14,
    ),

    prefixIcon: Icon(
      Icons.warning_amber_rounded,
      color: Colors.red.shade400,
    ),
  ),
),
                    // Location status
                    Consumer<LocationProvider>(
  builder: (context, locationProvider, _) {
    final isReady = locationProvider.hasLocation;

    return !isReady ?Container(
      margin: const EdgeInsets.symmetric( vertical: 10),
      padding: const EdgeInsets.symmetric( horizontal: 16,vertical: 14),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          // LEFT TEXT + ICON
          Expanded(
            child: Row(
              children: [
                Icon(
                  isReady ? Icons.location_on : Icons.location_off,
                  color: isReady ? Colors.greenAccent : Colors.orangeAccent,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isReady
                        ? settings.t('location_ready')
                        : settings.t('location_not_ready'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // RIGHT BUTTON
          if (!isReady)
            _actionChip(
              label: "Fix",
              onTap: () async {
  if (!locationProvider.hasLocation) {
    await locationProvider.openPermissionSettings();
  } else {
    await locationProvider.openLocationSettings();
  }
}
            ),
        ],
      ),
    ): SizedBox(height: 50);
  },
),
                  ],
                ),
              ),

              // Center section: SOS Button
              Consumer<AuthProvider>(
                builder: (context, authProvider, _) {
                  return Consumer<ResponderProvider>(
                    builder: (context, responderProvider, _) {
                      return SOSButton(
                        onPressed: _handleSOSPress,
                        isLoading: _isSosInProgress,
                        enableHaptics: settings.hapticsEnabled,
                      );
                    },
                  );
                },
              ),

              const SizedBox(height: 20),

             
            ],
          ),
        ),
      ),
      bottomNavigationBar: AnimatedBottomNavigationBar(
            icons: iconList,
            activeIndex: _bottomNavIndex,
            gapLocation: GapLocation.none,
            notchSmoothness: NotchSmoothness.verySmoothEdge,
            backgroundColor: Colors.red.shade700,
            activeColor: Colors.white,
            inactiveColor: Colors.white70,
            onTap: (index) {
              setState(() {
                _bottomNavIndex = index;
              });

              // Trigger same AppBar actions
              actions[index]();
            },
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
            color: Colors.red.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 32,
            color: Colors.red.shade700,
          ),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.red.shade600,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: Colors.red.shade900,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
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

Widget _styledButton({
  required String label,
  required IconData icon,
  required VoidCallback onPressed,
}) {
  return OutlinedButton.icon(
    onPressed: onPressed,
    icon: Icon(icon, size: 20),
    label: Text(label),
    style: OutlinedButton.styleFrom(
      padding: const EdgeInsets.all(8),
      
      // Rounded modern shape
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),

      // Border style
      side: BorderSide(
        color: Colors.red.shade400,
        width: 1.5,
      ),

      // Background (light red)
      backgroundColor: Colors.red.shade50,

      // Text & icon color
      foregroundColor: Colors.red.shade700,

      // Subtle elevation feel
      shadowColor: Colors.red.withOpacity(0.2),
      elevation: 2,
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
        color: value ? Colors.red.withOpacity(0.08) : Colors.grey.shade100,
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
        activeColor: Colors.red,
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
        color: value ? Colors.red.withOpacity(0.08) : Colors.grey.shade100,
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
        activeColor: Colors.red,
      ),
    ),
  );
}