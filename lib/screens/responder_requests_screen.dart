import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:url_launcher/url_launcher.dart';

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
  final AudioPlayer _voicePlayer = AudioPlayer();
  String? _activeVoiceUrl;
  bool _isVoicePlaying = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refresh();
    });

    _voicePlayer.onPlayerComplete.listen((_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isVoicePlaying = false;
      });
    });
  }

  @override
  void dispose() {
    _voicePlayer.dispose();
    super.dispose();
  }

  Future<void> _openAttachment(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open attachment.')),
      );
    }
  }

  Future<void> _toggleRemoteVoicePlayback(String url) async {
    final isSameTrack = _activeVoiceUrl == url;
    if (isSameTrack && _isVoicePlaying) {
      await _voicePlayer.stop();
      if (mounted) {
        setState(() {
          _isVoicePlaying = false;
        });
      }
      return;
    }

    await _voicePlayer.play(UrlSource(url));
    if (mounted) {
      setState(() {
        _activeVoiceUrl = url;
        _isVoicePlaying = true;
      });
    }
  }

  IconData _severityIcon(String severity) {
    switch (severity.toLowerCase()) {
      case 'critical':
        return Icons.warning_amber_rounded;
      case 'high':
        return Icons.error_outline;
      case 'medium':
        return Icons.report_problem_outlined;
      default:
        return Icons.info_outline;
    }
  }

  Color _severityColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'critical':
        return Colors.red.shade700;
      case 'high':
        return Colors.deepOrange.shade700;
      case 'medium':
        return Colors.amber.shade800;
      default:
        return Colors.blueGrey.shade600;
    }
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
                          Row(
                            children: [
                              Icon(
                                _severityIcon(request.severity),
                                color: _severityColor(request.severity),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  request.requesterName,
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                              ),
                              if (distance != null)
                                Text(
                                  '${distance.toStringAsFixed(1)} km',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 10,
                            runSpacing: 6,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.category_outlined, size: 16),
                                  const SizedBox(width: 4),
                                  Text(request.category),
                                ],
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(_severityIcon(request.severity), size: 16),
                                  const SizedBox(width: 4),
                                  Text(request.severity.toUpperCase()),
                                ],
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.support_agent, size: 16),
                                  const SizedBox(width: 4),
                                  Text(request.recommendedSkill),
                                ],
                              ),
                              if (request.attachmentUrl?.isNotEmpty ?? false)
                                const Icon(Icons.image, size: 18),
                              if (request.voiceAudioUrl?.isNotEmpty ?? false)
                                const Icon(Icons.audiotrack, size: 18),
                              if (request.voiceTranscript?.trim().isNotEmpty ?? false)
                                const Icon(Icons.subtitles, size: 18),
                            ],
                          ),
                          if (request.forcedCriticalByUser)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                'Manual override: CRITICAL',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Colors.red.shade800,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                          if (request.humanReviewRecommended)
                            Container(
                              margin: const EdgeInsets.only(top: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade100,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.orange.shade300),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.psychology_alt_outlined, size: 16),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Human review recommended',
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          color: Colors.orange.shade900,
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(height: 6),
                          Text(request.summary),
                          ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            childrenPadding: const EdgeInsets.only(bottom: 8),
                            title: const Text('View details & media'),
                            children: [
                              if (request.originalMessage.trim().isNotEmpty) ...[
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    'Reporter message:',
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(request.originalMessage),
                                ),
                                const SizedBox(height: 8),
                              ],
                              if (request.voiceTranscript?.trim().isNotEmpty ?? false) ...[
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    'Voice transcript:',
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(request.voiceTranscript!),
                                ),
                                const SizedBox(height: 8),
                              ],
                              if (request.attachmentUrl?.isNotEmpty ?? false) ...[
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      OutlinedButton.icon(
                                        onPressed: () => _openAttachment(request.attachmentUrl!),
                                        icon: const Icon(Icons.image_outlined),
                                        label: const Text('Open image'),
                                      ),
                                    ],
                                  ),
                                ),
                                if (request.attachmentType == 'image') ...[
                                  const SizedBox(height: 6),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.network(
                                      request.attachmentUrl!,
                                      height: 180,
                                      width: double.infinity,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Row(
                                        children: [
                                          const Icon(Icons.broken_image_outlined),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              'Image unavailable in preview. Use Open image.',
                                              style: Theme.of(context).textTheme.bodySmall,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 8),
                              ],
                              if (request.voiceAudioUrl?.isNotEmpty ?? false) ...[
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      OutlinedButton.icon(
                                        onPressed: () => _toggleRemoteVoicePlayback(request.voiceAudioUrl!),
                                        icon: Icon(
                                          (_activeVoiceUrl == request.voiceAudioUrl && _isVoicePlaying)
                                              ? Icons.stop
                                              : Icons.play_arrow,
                                        ),
                                        label: Text(
                                          (_activeVoiceUrl == request.voiceAudioUrl && _isVoicePlaying)
                                              ? 'Stop audio'
                                              : 'Play audio',
                                        ),
                                      ),
                                      TextButton.icon(
                                        onPressed: () => _openAttachment(request.voiceAudioUrl!),
                                        icon: const Icon(Icons.open_in_new),
                                        label: const Text('Open external'),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              if (request.suggestedActions.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    'Suggested actions:',
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                ...request.suggestedActions.take(4).map(
                                      (action) => Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Text('• $action'),
                                      ),
                                    ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 8),
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
