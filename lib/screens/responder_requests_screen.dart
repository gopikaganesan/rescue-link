import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models/emergency_request_model.dart';
import '../core/models/responder_model.dart';
import '../core/providers/app_settings_provider.dart';
import '../core/providers/auth_provider.dart';
import '../core/providers/emergency_request_provider.dart';
import '../core/providers/location_provider.dart';
import '../core/providers/responder_provider.dart';
import '../core/services/responder_matching_service.dart';
import '../widgets/fixed_footer_navigation_bar.dart';
import '../widgets/account_sheet.dart';
import '../widgets/translated_text.dart';
import 'auth_screen.dart';
import 'group_chat_screen.dart';
import 'home_screen.dart';
import 'map_screen.dart';
import 'responder_chat_list_screen.dart';
import 'victim_chat_list_screen.dart';

class ResponderRequestsScreen extends StatefulWidget {
  const ResponderRequestsScreen({super.key});

  @override
  State<ResponderRequestsScreen> createState() =>
      _ResponderRequestsScreenState();
}

class _ResponderRequestsScreenState extends State<ResponderRequestsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refresh();
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  PageRouteBuilder<void> _noTransitionRoute(Widget page) {
    return PageRouteBuilder<void>(
      pageBuilder: (_, __, ___) => page,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      transitionsBuilder: (_, __, ___, child) => child,
    );
  }

  void _showAccountSheet() {
    showAccountSheet(
      context,
      onLogin: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const AuthScreen(showGuestButton: false),
          ),
        );
      },
      onLogout: () async {
        await context.read<AuthProvider>().logout();
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Signed out successfully.')),
        );
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => const AuthScreen(showGuestButton: false),
          ),
          (route) => false,
        );
      },
      onOpenResponderRequests: () {
        Navigator.of(context).pushReplacement(
          _noTransitionRoute(const ResponderRequestsScreen()),
        );
      },
    );
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

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GroupChatScreen(
          sosId: request.id,
          currentUserId: auth.currentUser!.id,
          currentUserName: auth.currentUser!.displayName,
          currentUserRole: 'responder',
        ),
      ),
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

  Widget _chip(IconData icon, String text, Color color) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(fontSize: 11, color: color)),
      ],
    ),
  );
}

Widget _iconChip(IconData icon) {
  return Container(
    padding: const EdgeInsets.all(6),
    decoration: BoxDecoration(
      color: Colors.grey.shade200,
      shape: BoxShape.circle,
    ),
    child: Icon(icon, size: 14),
  );
}

Widget _sectionText(String title, String value) {
  return Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        TranslatedText(value),
      ],
    ),
  );
}

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettingsProvider>();
    return Scaffold(
      appBar: AppBar(
        title: Text(settings.t('button_people_needing_help')),
        actions: [
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragEnd: (details) {
          if (details.primaryVelocity == null) {
            return;
          }

          if (details.primaryVelocity! > 300) {
            Navigator.of(context).pushReplacement(
              _noTransitionRoute(const HomeScreen()),
            );
            return;
          }

          if (details.primaryVelocity! < -300) {
            final auth = context.read<AuthProvider>();
            if (auth.currentUser?.isResponder == true) {
              Navigator.of(context).pushReplacement(
                _noTransitionRoute(
                  ResponderChatListScreen(
                    currentUserId: auth.currentUser!.id,
                    currentUserName: auth.currentUser!.displayName,
                  ),
                ),
              );
            } else {
              Navigator.of(context).pushReplacement(
                _noTransitionRoute(
                  VictimChatListScreen(
                    currentUserId: auth.currentUser?.id ?? '',
                    currentUserName: auth.currentUser?.displayName ?? '',
                  ),
                ),
              );
            }
          }
        },
        child: Consumer<EmergencyRequestProvider>(
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
                        final shouldNotify =
                            ResponderMatchingService.shouldNotifyResponder(
                          responder: me,
                          request: request,
                        );
                        final radius =
                            ResponderMatchingService.radiusKmForSeverity(
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

                    return Container(
  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
  decoration: BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(18),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(0.05),
        blurRadius: 10,
      )
    ],
    border: Border.all(
      color: request.severity == 'critical'
          ? Colors.red.shade300
          : Colors.grey.shade200,
      width: 1.2,
    ),
  ),
  child: Padding(
    padding: const EdgeInsets.all(14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        /// 🔴 HEADER
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: _severityColor(request.severity).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _severityIcon(request.severity),
                color: _severityColor(request.severity),
                size: 20,
              ),
            ),
            const SizedBox(width: 10),

            Expanded(
              child: Text(
                request.requesterName,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ),

            if (distance != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${distance.toStringAsFixed(1)} km',
                  style: const TextStyle(fontSize: 11),
                ),
              ),
          ],
        ),

        const SizedBox(height: 10),

        /// 🧩 TAGS (modern chips)
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [

            _chip(Icons.category_outlined,
                settings.localizedCrisisCategory(request.category),
                Colors.blue),

            _chip(_severityIcon(request.severity),
                request.severity.toUpperCase(),
                _severityColor(request.severity)),

            _chip(Icons.support_agent,
                settings.localizedSkill(request.recommendedSkill),
                Colors.purple),

            if (request.attachmentUrl?.isNotEmpty ?? false)
              _iconChip(Icons.image),

            if (request.voiceAudioUrl?.isNotEmpty ?? false)
              _iconChip(Icons.audiotrack),

            if (request.voiceTranscript?.trim().isNotEmpty ?? false)
              _iconChip(Icons.subtitles),
          ],
        ),

        const SizedBox(height: 10),

        /// 💬 SUMMARY
        TranslatedText(request.summary),

        /// ⚠️ WARNINGS
        if (request.forcedCriticalByUser)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              settings.t('manual_override_critical'),
              style: TextStyle(
                color: Colors.red.shade800,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),

        if (request.humanReviewRecommended)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.orange.shade100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.psychology_alt, size: 16),
                const SizedBox(width: 6),
                Text(
                  settings.t('human_review_recommended'),
                  style: TextStyle(
                    color: Colors.orange.shade900,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),

        /// 📂 EXPANDABLE DETAILS
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 8),
          title: Text(
            settings.t('view_details_and_media'),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          children: [
            if (request.originalMessage.trim().isNotEmpty)
              _sectionText(settings.t('reporter_message'),
                  request.originalMessage),

            if (request.voiceTranscript?.trim().isNotEmpty ?? false)
              _sectionText(settings.t('voice_transcript'),
                  request.voiceTranscript!),

            if (request.attachmentUrl?.isNotEmpty ?? false) ...[
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  request.attachmentUrl!,
                  height: 180,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            ],
          ],
        ),

        const SizedBox(height: 10),

        /// 🔘 ACTIONS
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _navigateInApp(request),
                icon: const Icon(Icons.navigation, size: 18),
                label: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(settings.t('navigate')),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  backgroundColor: Colors.grey.shade100,
                  foregroundColor: Colors.red,
                  side: BorderSide(color: Colors.red.shade300),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _accept(request),
                icon: const Icon(Icons.check, size: 18),
                label: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(settings.t('button_accept')),
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  backgroundColor: Colors.red,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
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
      ),
      bottomNavigationBar: FixedFooterNavigationBar(
        activeIndex: 1,
        onSosTap: () {
          Navigator.of(context).pushReplacement(
            _noTransitionRoute(const HomeScreen()),
          );
        },
        onPeopleTap: () {
          // current screen
        },
        onChatsTap: () {
          final auth = context.read<AuthProvider>();
          if (auth.currentUser?.isResponder == true) {
            Navigator.of(context).pushReplacement(
              _noTransitionRoute(
                ResponderChatListScreen(
                  currentUserId: auth.currentUser!.id,
                  currentUserName: auth.currentUser!.displayName,
                ),
              ),
            );
            return;
          }

          Navigator.of(context).pushReplacement(
            _noTransitionRoute(
              VictimChatListScreen(
                currentUserId: auth.currentUser?.id ?? '',
                currentUserName: auth.currentUser?.displayName ?? '',
              ),
            ),
          );
        },
        onMapTap: () {
          Navigator.of(context).push(
            _noTransitionRoute(const MapScreen()),
          );
        },
        onProfileTap: _showAccountSheet,
      ),
    );
  }
}
