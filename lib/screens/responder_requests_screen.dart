import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models/emergency_request_model.dart';
import '../core/models/responder_model.dart';
import '../core/providers/auth_provider.dart';
import '../core/providers/emergency_request_provider.dart';
import '../core/providers/location_provider.dart';
import '../core/providers/responder_provider.dart';
import '../core/services/responder_matching_service.dart';
import 'map_screen.dart';

class ResponderRequestsScreen extends StatefulWidget {
  const ResponderRequestsScreen({super.key});

  @override
  State<ResponderRequestsScreen> createState() => _ResponderRequestsScreenState();
}

class _ResponderRequestsScreenState extends State<ResponderRequestsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refresh();
    });
  }

  Future<void> _refresh() async {
    final responders = context.read<ResponderProvider>();
    final requests = context.read<EmergencyRequestProvider>();

    await responders.fetchResponders();

    await requests.fetchOpenRequests();
  }

  ResponderModel? _findCurrentResponder() {
    final auth = context.read<AuthProvider>();
    final responders = context.read<ResponderProvider>();
    final me = auth.currentUser;
    if (me == null) {
      return null;
    }

    final mine = responders.responders.where((r) => r.userId == me.id).toList();
    return mine.isEmpty ? null : mine.first;
  }

  double? _distanceKm(EmergencyRequestModel request) {
    final me = _findCurrentResponder();
    if (me == null) {
      return null;
    }
    return me.distanceToLocation(request.latitude, request.longitude);
  }

  Future<void> _accept(EmergencyRequestModel request) async {
    final auth = context.read<AuthProvider>();
    if (auth.currentUser == null) {
      return;
    }

    await context.read<EmergencyRequestProvider>().acceptRequest(
          requestId: request.id,
          responderUserId: auth.currentUser!.id,
        );

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Help request accepted.')),
    );
  }

  void _navigateInApp(EmergencyRequestModel request) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MapScreen(
          targetLatitude: request.latitude,
          targetLongitude: request.longitude,
          targetTitle: request.requesterName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('People Needing Help'),
        actions: [
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Consumer<EmergencyRequestProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.error != null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(provider.error!),
              ),
            );
          }

          if (provider.openRequests.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text('No open requests right now.'),
              ),
            );
          }

          return Consumer<LocationProvider>(
            builder: (context, location, __) {
              final me = _findCurrentResponder();
              final visible = me == null
                  ? provider.openRequests
                  : provider.openRequests.where((request) {
                      final shouldNotify = ResponderMatchingService.shouldNotifyResponder(
                        responder: me,
                        request: request,
                      );
                      final radius = ResponderMatchingService.radiusKmForSeverity(
                        request.severity,
                      );
                      final distance = me.distanceToLocation(
                        request.latitude,
                        request.longitude,
                      );
                      return shouldNotify && distance <= radius;
                    }).toList();

              if (visible.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('No matching requests near you right now.'),
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: visible.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final request = visible[index];
                  final distance = _distanceKm(request);

                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            request.requesterName,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 6),
                          Text('Category: ${request.category}'),
                          Text('Severity: ${request.severity.toUpperCase()}'),
                          Text('Need: ${request.recommendedSkill}'),
                          const SizedBox(height: 4),
                          Text(request.summary),
                          if (distance != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text('${distance.toStringAsFixed(1)} km away'),
                            ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => _navigateInApp(request),
                                  icon: const Icon(Icons.navigation),
                                  label: const Text('Navigate'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () => _accept(request),
                                  icon: const Icon(Icons.check),
                                  label: const Text('Accept'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
