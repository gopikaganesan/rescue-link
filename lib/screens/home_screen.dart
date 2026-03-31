import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/providers/auth_provider.dart';
import '../core/providers/crisis_provider.dart';
import '../core/providers/location_provider.dart';
import '../core/providers/responder_provider.dart';
import 'responder_registration_screen.dart';
import 'map_screen.dart';
import '../widgets/sos_button.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    _initializeScreen();
  }

  /// Initialize location and responder data
  Future<void> _initializeScreen() async {
    final locationProvider =
        context.read<LocationProvider>();

    // Request location permission
    await locationProvider.requestLocationPermission();
  }

  /// Handle SOS button press
  Future<void> _handleSOSPress() async {
    final authProvider = context.read<AuthProvider>();
    final crisisProvider = context.read<CrisisProvider>();
    final locationProvider =
        context.read<LocationProvider>();
    final responderProvider =
        context.read<ResponderProvider>();

    if (!locationProvider.hasLocation) {
      _showSnackBar('Requesting your location...');
      await locationProvider.getCurrentLocation();
    }

    if (locationProvider.hasLocation && authProvider.currentUser != null) {
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
          'Potential emergency needs urgent support.';

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
        5.0, // 5km radius
        requiredSkill: crisisProvider.latestAnalysis?.recommendedSkill,
      );

      // Show SOS confirmation
      _showSOSConfirmation();
    } else {
      _showSnackBar('Unable to determine location. Please try again.');
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

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('🚨 SOS Activated'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your location has been shared.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            Text(
              'Location: ${locationProvider.latitude?.toStringAsFixed(4)}, '
              '${locationProvider.longitude?.toStringAsFixed(4)}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Text(
              'Nearby Responders: ${responderProvider.nearbyResponders.length}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            if (analysis != null) ...[
              const SizedBox(height: 16),
              Text(
                'AI Category: ${analysis.category}',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              Text(
                'Severity: ${analysis.severity}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              Text(
                'Suggested Skill: ${analysis.recommendedSkill}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (analysis.offlineMode)
                Text(
                  'AI Mode: Offline Fallback',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.orange[800]),
                ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(dialogContext);
              _openMap();
            },
            icon: const Icon(Icons.map),
            label: const Text('View Map'),
          ),
        ],
      ),
    );
  }

  /// Show snackbar message
  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _openResponderRegistration() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const ResponderRegistrationScreen(),
      ),
    );
  }

  void _openMap() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const MapScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('RescueLink'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.red.shade700,
        actions: [
          IconButton(
            icon: const Icon(Icons.map),
            onPressed: _openMap,
            tooltip: 'View responders map',
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: SizedBox(
          height: MediaQuery.of(context).size.height -
              kToolbarHeight -
              MediaQuery.of(context).padding.top,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Top section: Info
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      'In an Emergency?',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Press the SOS button below to alert nearby responders',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _openResponderRegistration,
                        icon: const Icon(Icons.health_and_safety),
                        label: const Text('Become A Responder'),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Location status
                    Consumer<LocationProvider>(
                      builder: (context, locationProvider, _) {
                        return Container(
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
                                    ? 'Location: Ready'
                                    : 'Location: Not Ready',
                                style: TextStyle(
                                  color: locationProvider.hasLocation
                                      ? Colors.green
                                      : Colors.orange,
                                  fontWeight: FontWeight.w600,
                                ),
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
                        isLoading: responderProvider.isLoading,
                      );
                    },
                  );
                },
              ),

              // Bottom section: Quick info
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    // Auth status
                    Consumer<AuthProvider>(
                      builder: (context, authProvider, _) {
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'User Info',
                                style: Theme.of(context)
                                    .textTheme.labelLarge
                                    ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              if (authProvider.currentUser != null)
                                Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Name: ${authProvider.currentUser!.displayName}',
                                      style: Theme.of(context)
                                          .textTheme.bodySmall,
                                    ),
                                    Text(
                                      'Email: ${authProvider.currentUser!.email}',
                                      style: Theme.of(context)
                                          .textTheme.bodySmall,
                                    ),
                                    Text(
                                      'Type: ${authProvider.currentUser!.isResponder ? "Responder" : "User"}',
                                      style: Theme.of(context)
                                          .textTheme.bodySmall,
                                    ),
                                  ],
                                )
                              else
                                Text(
                                  'Not logged in',
                                  style: Theme.of(context)
                                      .textTheme.bodySmall
                                      ?.copyWith(
                                    color: Colors.red,
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
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
                                    'Total Responders',
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
                                    'Nearby (5km)',
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
