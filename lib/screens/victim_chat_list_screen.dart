import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/providers/app_settings_provider.dart';
import '../core/providers/auth_provider.dart';
import '../services/chat_service.dart';
import '../widgets/account_sheet.dart';
import '../widgets/fixed_footer_navigation_bar.dart';
import 'auth_screen.dart';
import 'group_chat_screen.dart';
import 'home_screen.dart';
import 'map_screen.dart';
import 'responder_requests_screen.dart';

enum _VictimChatFilter { active, cancelled, all }

class VictimChatListScreen extends StatefulWidget {
  const VictimChatListScreen({
    super.key,
    required this.currentUserId,
    required this.currentUserName,
  });

  final String currentUserId;
  final String currentUserName;

  static Future<void> open(
    BuildContext context, {
    required String currentUserId,
    required String currentUserName,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VictimChatListScreen(
          currentUserId: currentUserId,
          currentUserName: currentUserName,
        ),
      ),
    );
  }

  @override
  State<VictimChatListScreen> createState() => _VictimChatListScreenState();
}

class _VictimChatListScreenState extends State<VictimChatListScreen> {
  final ChatService _chatService = ChatService();
  _VictimChatFilter _filter = _VictimChatFilter.active;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  final Set<String> _deletingSosIds = <String>{};

  @override
  void dispose() {
    _searchController.dispose();
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

  Widget _buildSegment({
  required String label,
  required bool selected,
  required VoidCallback onTap,
}) {
  return GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: selected ? Colors.red.shade700 : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: selected ? Colors.white : Colors.grey,
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
    ),
  );
}

Widget _buildBadge({
  IconData? icon,
  String? value,
  String? label,
  required Color color,
}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withOpacity(0.15),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 4),
        ],
        Text(
          value ?? label ?? '',
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w600,
            fontSize: 11,
          ),
        ),
      ],
    ),
  );
}

  @override
  Widget build(BuildContext context) {
    final settings = context.read<AppSettingsProvider>();
    final auth = context.read<AuthProvider>();

    return Scaffold(
      appBar: AppBar(title: Text(settings.t('title_my_sos_chats'))),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragEnd: (details) {
          if (details.primaryVelocity == null) {
            return;
          }

          if (details.primaryVelocity! > 300) {
            if (auth.currentUser?.isResponder == true) {
              Navigator.of(context).pushReplacement(
                _noTransitionRoute(const ResponderRequestsScreen()),
              );
            } else {
              Navigator.of(context).pushReplacement(
                _noTransitionRoute(const HomeScreen()),
              );
            }
            return;
          }

          if (details.primaryVelocity! < -300) {
            Navigator.of(context).push(
              _noTransitionRoute(const MapScreen()),
            );
          }
        },
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: Container(
  padding: const EdgeInsets.all(6),
  decoration: BoxDecoration(
    color: Colors.grey.shade300,
    borderRadius: BorderRadius.circular(20),
  ),
  child: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _buildSegment(
        label: context.read<AppSettingsProvider>().t('filter_active'),
        selected: _filter == _VictimChatFilter.active,
        onTap: () {
          setState(() {
            _filter = _VictimChatFilter.active;
          });
        },
      ),
      _buildSegment(
        label: context.read<AppSettingsProvider>().t('filter_cancelled'),
        selected: _filter == _VictimChatFilter.cancelled,
        onTap: () {
          setState(() {
            _filter = _VictimChatFilter.cancelled;
          });
        },
      ),
      _buildSegment(
        label: context.read<AppSettingsProvider>().t('filter_all'),
        selected: _filter == _VictimChatFilter.all,
        onTap: () {
          setState(() {
            _filter = _VictimChatFilter.all;
          });
        },
      ),
    ],
  ),
),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: TextField(
                controller: _searchController,
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value.trim().toLowerCase();
                  });
                },
                decoration: InputDecoration(
                  hintText:
                      context.read<AppSettingsProvider>().t('hint_search_case'),
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchQuery.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _searchQuery = '';
                            });
                          },
                          icon: const Icon(Icons.clear),
                        ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(25),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(25),
                    borderSide: BorderSide(color: Colors.red.shade300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(25),
                    borderSide: BorderSide(
                      color: Colors.red,
                      width: 1.4,
                    ),
                  ),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surface,
                  isDense: true,
                ),
              ),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _chatService.watchVictimChats(widget.currentUserId),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                        child: Text(context
                            .read<AppSettingsProvider>()
                            .t('error_failed_load_chats')));
                  }

                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final docs = snapshot.data?.docs ??
                      const <QueryDocumentSnapshot<Map<String, dynamic>>>[];

                  if (docs.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(context
                            .read<AppSettingsProvider>()
                            .t('status_no_sos_chats_found')),
                      ),
                    );
                  }

                  final sortedDocs = docs.toList()
                    ..sort(
                      (a, b) =>
                          _createdAt(b.data()).compareTo(_createdAt(a.data())),
                    );

                  final filteredDocs = sortedDocs.where((doc) {
                    final data = doc.data();
                    if (_filter == _VictimChatFilter.all) {
                      // continue to search matching below
                    } else {
                      final status = ((data['status'] as String?) ?? 'active')
                          .trim()
                          .toLowerCase();
                      if (_filter == _VictimChatFilter.active &&
                          status == 'cancelled') {
                        return false;
                      }
                      if (_filter == _VictimChatFilter.cancelled &&
                          status != 'cancelled') {
                        return false;
                      }
                    }

                    if (_searchQuery.isEmpty) {
                      return true;
                    }

                    final sosId =
                        ((data['sosId'] as String?) ?? doc.id).toLowerCase();
                    final overview = _asMap(data['sosOverview']);
                    final msg =
                        ((overview['message'] as String?) ?? '').toLowerCase();
                    final crisisType =
                        ((overview['crisisType'] as String?) ?? '')
                            .toLowerCase();
                    return sosId.contains(_searchQuery) ||
                        msg.contains(_searchQuery) ||
                        crisisType.contains(_searchQuery);
                  }).toList();

                  if (filteredDocs.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          _filter == _VictimChatFilter.cancelled
                              ? 'No cancelled chats found.'
                              : _filter == _VictimChatFilter.active
                                  ? 'No active chats found.'
                                  : 'No chats found.',
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    itemCount: filteredDocs.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      color: Colors.grey.shade300,
                    ),
                    itemBuilder: (context, index) {
                      final doc = filteredDocs[index];
                      final data = doc.data();

                      final sosId = (data['sosId'] as String?) ?? doc.id;
                      final overview = _asMap(data['sosOverview']);
                      final chatTitle = _humanFriendlyChatTitle(
                        data: data,
                        sosId: sosId,
                        settings: settings,
                      );
                      final message = _safeText(
                        overview['message'] as String?,
                        fallback: settings.t('status_no_sos_message_available'),
                        maxLen: 84,
                      );
                      final status = ((data['status'] as String?) ?? 'active')
                          .toLowerCase();
                      final createdAt = _createdAt(data);
                      final isCancelled = status == 'cancelled';
                      final isDeleting = _deletingSosIds.contains(sosId);
                      final participantCount = _participantCount(data);
                      final onlineCount = _onlineCount(data);

                      return InkWell(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => GroupChatScreen(
                                sosId: sosId,
                                currentUserId: widget.currentUserId,
                                currentUserName: widget.currentUserName,
                                currentUserRole: 'victim',
                                enableResponderJoinGate: false,
                              ),
                            ),
                          );
                        },
                        child: Padding(
  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
  child: Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.grey.shade100,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.2),
          blurRadius: 8,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        /// MAIN CONTENT
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              /// TOP ROW (Title + time)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      chatTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  Text(
                    _timeText(createdAt),
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: Colors.grey),
                  ),
                ],
              ),

              const SizedBox(height: 6),

              /// BADGES ROW (instead of tiny icons + numbers)
              Wrap(
                spacing: 8,
                children: [
                  _buildBadge(
                    icon: Icons.circle,
                    value: '$onlineCount',
                    color: Colors.green,
                  ),
                  _buildBadge(
                    icon: Icons.group,
                    value: '$participantCount',
                    color: Colors.redAccent,
                  ),
                  _buildBadge(
                    label:
                        '${settings.t('label_case_id')}: $sosId',
                    color: Colors.blueGrey,
                  ),
                ],
              ),

              const SizedBox(height: 8),

              /// MESSAGE PREVIEW
              Text(
                message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.red.shade300,
                ),
              ),

              /// CANCELLED LABEL
              if (isCancelled) ...[
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    settings.t('status_cancelled'),
                    style: TextStyle(
                      color: Colors.red.shade400,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),

        /// ACTIONS
        Column(
          children: [
            if (isCancelled)
              isDeleting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _confirmDeleteCancelledChat(
                        sosId: sosId,
                      ),
                    ),
            Icon(
              Icons.chevron_right,
              color: Colors.grey.shade600,
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
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: FixedFooterNavigationBar(
        activeIndex: 1,
        showPeople: false,
        onSosTap: () {
          Navigator.of(context).pushReplacement(
            _noTransitionRoute(const HomeScreen()),
          );
        },
        onPeopleTap: () {},
        onChatsTap: () {},
        onMapTap: () {
          Navigator.of(context).push(
            _noTransitionRoute(const MapScreen()),
          );
        },
        onProfileTap: _showAccountSheet,
      ),
    );

    
  }

  Future<void> _confirmDeleteCancelledChat({required String sosId}) async {
    final settings = context.read<AppSettingsProvider>();
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(settings.t('dialog_delete_cancelled_chat_title')),
            content: Text(
              settings.t('dialog_delete_cancelled_chat_body'),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(settings.t('button_keep')),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: Text(settings.t('button_delete')),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed || !mounted) {
      return;
    }

    setState(() {
      _deletingSosIds.add(sosId);
    });

    try {
      await _chatService.deleteEntireChat(
        sosId: sosId,
        deleteMediaFromCloudinary: true,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(settings.t('snackbar_cancelled_chat_deleted'))),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(settings.t('snackbar_failed_delete_chat'))),
      );
    } finally {
      if (mounted) {
        setState(() {
          _deletingSosIds.remove(sosId);
        });
      }
    }
  }

  static Map<String, dynamic> _asMap(dynamic raw) {
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    return <String, dynamic>{};
  }

  static DateTime _createdAt(Map<String, dynamic> data) {
    final raw = data['createdAt'];
    if (raw is Timestamp) {
      return raw.toDate();
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  static int _participantCount(Map<String, dynamic> data) {
    final participants = data['participants'];
    if (participants is List) {
      return participants.length;
    }
    return 0;
  }

  static int _onlineCount(Map<String, dynamic> data) {
    final presence = data['responderPresence'];
    if (presence is Map) {
      return presence.values.where((value) => value == true).length;
    }

    final raw = data['onlineCount'];
    if (raw is num) {
      return raw.toInt();
    }
    return 0;
  }

  static String _safeText(
    String? raw, {
    required String fallback,
    required int maxLen,
  }) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) {
      return fallback;
    }
    if (value.length <= maxLen) {
      return value;
    }
    return '${value.substring(0, maxLen)}...';
  }

  static String _timeText(DateTime value) {
    final local = value.toLocal();
    final date =
        '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
    final time =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    return '$date $time';
  }

  static String _humanFriendlyChatTitle({
    required Map<String, dynamic> data,
    required String sosId,
    required AppSettingsProvider settings,
  }) {
    final overview = _asMap(data['sosOverview']);

    final customTitle = (overview['title'] as String?)?.trim();
    if (customTitle != null && customTitle.isNotEmpty) {
      return customTitle;
    }

    final crisisType = ((overview['crisisType'] as String?) ??
            (data['crisisType'] as String?) ??
            '')
        .trim();

    final participants = data['participants'];
    if (participants is List) {
      for (final entry in participants.whereType<Map>()) {
        final role = ((entry['role'] as String?) ?? '').toLowerCase();
        final displayName = (entry['displayName'] as String?)?.trim() ?? '';
        if (role == 'victim' && displayName.isNotEmpty) {
          if (displayName.toLowerCase() == 'victim') {
            break;
          }
          final localizedName = settings.localizedDisplayName(displayName);
          final localizedCrisis = settings.localizedCrisisCategory(crisisType);
          final crisisLabel = localizedCrisis == crisisType
              ? _toTitleCase(crisisType)
              : localizedCrisis;
          return crisisType.isNotEmpty
              ? '$crisisLabel: $localizedName'
              : settings
                  .t('chat_title_emergency_with_name')
                  .replaceAll('{name}', localizedName);
        }
      }
    }

    if (crisisType.isNotEmpty) {
      final localizedCrisis = settings.localizedCrisisCategory(crisisType);
      final crisisLabel = localizedCrisis == crisisType
          ? _toTitleCase(crisisType)
          : localizedCrisis;
      return settings
          .t('chat_title_crisis_emergency')
          .replaceAll('{crisis}', crisisLabel);
    }

    final chatId = sosId.length >= 6 ? sosId.substring(0, 6) : sosId;
    return settings.t('chat_title_emergency_chat').replaceAll('{id}', chatId);
  }

  static String _toTitleCase(String input) {
    final words = input
        .split(RegExp(r'\s+'))
        .where((word) => word.trim().isNotEmpty)
        .toList();
    if (words.isEmpty) {
      return input;
    }

    return words
        .map(
          (word) =>
              '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}',
        )
        .join(' ');
  }
}
