import 'dart:async';

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
        forceOffline: commsProvider.forceOfflineAi,
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
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return RadioGroup<String>(
          groupValue: settings.languageCode,
          onChanged: (value) {
            if (value != null) {
              settings.setLanguage(value);
            }
            Navigator.of(sheetContext).pop();
          },
          child: ListView(
            shrinkWrap: true,
            children: settings.availableLanguageCodes
                .map(
                  (code) => RadioListTile<String>(
                    value: code,
                    title: Text(settings.languageLabel(code)),
                  ),
                )
                .toList(),
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
      builder: (sheetContext) {
        if (user == null) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Not signed in'),
          );
        }

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(user.displayName, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(user.email.isEmpty ? (user.phoneNumber ?? 'No email') : user.email),
              const SizedBox(height: 10),
              Text(authProvider.isAnonymousUser ? 'Session: Anonymous' : 'Session: Registered'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (authProvider.isAnonymousUser)
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        _openAuthScreen();
                      },
                      icon: const Icon(Icons.login),
                      label: const Text('Sign In / Create Account'),
                    ),
                  if (!authProvider.isAnonymousUser)
                    TextButton.icon(
                      onPressed: () async {
                        Navigator.of(sheetContext).pop();
                        await _logoutRegisteredUser();
                      },
                      icon: const Icon(Icons.logout),
                      label: const Text('Sign Out'),
                    ),
                  if (user.isResponder)
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        _openResponderRequests();
                      },
                      icon: const Icon(Icons.list_alt),
                      label: const Text('People Needing Help'),
                    ),
                ],
              ),
              if (user.isResponder)
                Consumer<ResponderProvider>(
                  builder: (context, responderProvider, _) {
                    final mine = responderProvider.responders
                        .where((r) => r.userId == user.id)
                        .toList();
                    final isAvailable = mine.isEmpty ? true : mine.first.isAvailable;

                    return Column(
                      children: [
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Responder online'),
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
                            child: const Text('De-register as responder'),
                          ),
                        ),
                      ],
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

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                  Text(
                    'Accessibility',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile.adaptive(
                    title: const Text('Haptic vibration for SOS'),
                    value: settings.hapticsEnabled,
                    onChanged: (value) {
                      settings.setHapticsEnabled(value);
                      setModalState(() {});
                    },
                  ),
                  SwitchListTile.adaptive(
                    title: const Text('Flash light pulse on SOS'),
                    subtitle: const Text('Uses device torch if available'),
                    value: settings.sosFlashEnabled,
                    onChanged: (value) {
                      settings.setSosFlashEnabled(value);
                      setModalState(() {});
                    },
                  ),
                  SwitchListTile.adaptive(
                    title: const Text('High contrast mode'),
                    value: settings.highContrastEnabled,
                    onChanged: (value) {
                      settings.setHighContrastEnabled(value);
                      setModalState(() {});
                    },
                  ),
                  SwitchListTile.adaptive(
                    title: const Text('Enable notifications'),
                    subtitle: const Text('Local SOS status alerts'),
                    value: settings.notificationsEnabled,
                    onChanged: (value) async {
                      if (value) {
                        final granted = await NotificationService.requestPermissions();
                        settings.setNotificationsEnabled(granted);
                        if (!granted && mounted) {
                          _showSnackBar('Notification permission not granted.');
                        }
                      } else {
                        settings.setNotificationsEnabled(false);
                      }
                      setModalState(() {});
                    },
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Expanded(child: Text('Text Size')),
                      Text('${(settings.textScaleFactor * 100).round()}%'),
                    ],
                  ),
                  Slider(
                    min: 0.85,
                    max: 1.6,
                    value: settings.textScaleFactor,
                    onChanged: (value) {
                      settings.setTextScaleFactor(value);
                      setModalState(() {});
                    },
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () {
                        settings.setTextScaleFactor(1.0);
                        setModalState(() {});
                      },
                      icon: const Icon(Icons.restart_alt),
                      label: const Text('Reset text size'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () {
                            _announce(
                              'Accessibility test announcement. SOS button is centered below information cards.',
                            );
                            _showSnackBar('Screen reader announcement sent.');
                          },
                          icon: const Icon(Icons.record_voice_over),
                          label: const Text('Test Voice Prompt'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () async {
                            await _pulseFlash();
                            if (mounted) {
                              _showSnackBar('Flash pulse test completed.');
                            }
                          },
                          icon: const Icon(Icons.flashlight_on),
                          label: const Text('Test Flash'),
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

  void _showCommsSimulationSheet() {
    final comms = context.read<CommsProvider>();
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Comms Simulation', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<CommsMode>(
                    initialValue: comms.mode,
                    decoration: const InputDecoration(
                      labelText: 'Delivery Mode',
                      border: OutlineInputBorder(),
                    ),
                    items: CommsMode.values
                        .map(
                          (mode) => DropdownMenuItem<CommsMode>(
                            value: mode,
                            child: Text(comms.modeLabel(mode)),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        comms.setMode(value);
                        setModalState(() {});
                      }
                    },
                  ),
                  if (comms.mode == CommsMode.meshSimulated ||
                      comms.mode == CommsMode.satelliteSimulated)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade100,
                          border: Border.all(color: Colors.orange.shade300),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info, color: Colors.orange.shade700, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'AI will use offline heuristic only',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Colors.orange.shade900,
                                      fontWeight: FontWeight.w500,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Simulate tower failure'),
                    subtitle: comms.simulateTowerFailure
                        ? Text(
                            'AI will use offline heuristic only',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Colors.red.shade700,
                                  fontWeight: FontWeight.w500,
                                ),
                          )
                        : null,
                    value: comms.simulateTowerFailure,
                    onChanged: (value) {
                      comms.setSimulateTowerFailure(value);
                      setModalState(() {});
                    },
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Device supports satellite (simulated)'),
                    subtitle: comms.deviceSupportsSatellite
                        ? Text(
                            'AI will use offline heuristic only',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Colors.red.shade700,
                                  fontWeight: FontWeight.w500,
                                ),
                          )
                        : null,
                    value: comms.deviceSupportsSatellite,
                    onChanged: (value) {
                      comms.setDeviceSupportsSatellite(value);
                      setModalState(() {});
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'This simulation allows testing disaster/lockdown connectivity fallback without real mesh or satellite hardware.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  if (comms.forceOfflineAi)
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        border: Border.all(color: Colors.red.shade300),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber, color: Colors.red.shade700, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Crisis AI is in offline mode. Gemini API will not be used.',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Colors.red.shade900,
                                    fontWeight: FontWeight.w500,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
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

    return Scaffold(
      appBar: AppBar(
        title: Text(settings.t('app_title')),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.red.shade700,
        actions: [
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
          ),
          IconButton(
            icon: const Icon(Icons.account_circle),
            onPressed: _showAccountSheet,
            tooltip: 'Account',
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
                    const SizedBox(height: 10),
                    Text(
                      settings.t('emergency_subtitle'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 12),
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
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _showAccessibilitySheet,
                            icon: const Icon(Icons.accessibility_new),
                            label: const Text('Accessibility'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _openMap,
                            icon: const Icon(Icons.map),
                            label: const Text('Map'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _emergencyContextController,
                      minLines: 1,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Emergency details (optional)',
                        hintText:
                            'Example: elderly person fell, flood nearby, child missing, no transport',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Location status
                    Consumer<LocationProvider>(
                      builder: (context, locationProvider, _) {
                        return Semantics(
                          label: locationProvider.hasLocation
                              ? 'Location status ready'
                              : 'Location status not ready',
                          child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: locationProvider.hasLocation
                                ? Colors.green.shade50
                                : Colors.orange.shade50,
                            border: Border.all(
                              color: locationProvider.hasLocation
                                  ? Colors.green
                                  : Colors.orange,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                locationProvider.hasLocation
                                    ? Icons.location_on
                                    : Icons.location_off,
                                color: locationProvider.hasLocation
                                    ? Colors.green
                                    : Colors.orange,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                locationProvider.hasLocation
                                    ? settings.t('location_ready')
                                    : settings.t('location_not_ready'),
                                style: TextStyle(
                                  color: Colors.black87,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ));
                      },
                    ),
                    Consumer<LocationProvider>(
                      builder: (context, locationProvider, _) {
                        if (locationProvider.hasLocation) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              ElevatedButton.icon(
                                onPressed: () async {
                                  await locationProvider.openLocationSettings();
                                },
                                icon: const Icon(Icons.gps_fixed),
                                label: const Text('Turn On Location'),
                              ),
                              OutlinedButton.icon(
                                onPressed: () async {
                                  await locationProvider.openPermissionSettings();
                                },
                                icon: const Icon(Icons.app_settings_alt),
                                label: const Text('Grant Permission'),
                              ),
                              TextButton.icon(
                                onPressed: () async {
                                  await locationProvider.refreshLocationStatus(
                                    fetchLocation: true,
                                  );
                                },
                                icon: const Icon(Icons.refresh),
                                label: const Text('Retry'),
                              ),
                            ],
                          ),
                        );
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

              // Bottom section: Quick info
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    // Responders status
                    Consumer<ResponderProvider>(
                      builder: (context, responderProvider, _) {
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.purple.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.purple),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    settings.t('total_responders'),
                                    style: Theme.of(context)
                                        .textTheme.labelLarge,
                                  ),
                                  Text(
                                    responderProvider.responders.length
                                        .toString(),
                                    style: Theme.of(context)
                                        .textTheme.headlineSmall,
                                  ),
                                ],
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    settings.t('nearby_5km'),
                                    style: Theme.of(context)
                                        .textTheme.labelLarge,
                                  ),
                                  Text(
                                    responderProvider.nearbyResponders.length
                                        .toString(),
                                    style: Theme.of(context)
                                        .textTheme.headlineSmall
                                        ?.copyWith(
                                      color: Colors.purple,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
