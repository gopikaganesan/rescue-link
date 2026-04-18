import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/providers/app_settings_provider.dart';
import '../services/chat_service.dart';
import 'group_chat_screen.dart';

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

  @override
  Widget build(BuildContext context) {
    final settings = context.read<AppSettingsProvider>();

    return Scaffold(
      appBar: AppBar(title: Text(settings.t('title_my_sos_chats'))),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                ChoiceChip(
                  label: Text(context.read<AppSettingsProvider>().t('filter_active')),
                  selected: _filter == _VictimChatFilter.active,
                  onSelected: (_) {
                    setState(() {
                      _filter = _VictimChatFilter.active;
                    });
                  },
                ),
                ChoiceChip(
                  label: Text(context.read<AppSettingsProvider>().t('filter_cancelled')),
                  selected: _filter == _VictimChatFilter.cancelled,
                  onSelected: (_) {
                    setState(() {
                      _filter = _VictimChatFilter.cancelled;
                    });
                  },
                ),
                ChoiceChip(
                  label: Text(context.read<AppSettingsProvider>().t('filter_all')),
                  selected: _filter == _VictimChatFilter.all,
                  onSelected: (_) {
                    setState(() {
                      _filter = _VictimChatFilter.all;
                    });
                  },
                ),
              ],
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
                hintText: context.read<AppSettingsProvider>().t('hint_search_case'),
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
                  borderRadius: BorderRadius.circular(16),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
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
                  return Center(child: Text(context.read<AppSettingsProvider>().t('error_failed_load_chats')));
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
                      child: Text(context.read<AppSettingsProvider>().t('status_no_sos_chats_found')),
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
                    final status =
                        ((data['status'] as String?) ?? 'active').toLowerCase();
                    if (_filter == _VictimChatFilter.active && status == 'cancelled') {
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

                  final sosId = ((data['sosId'] as String?) ?? doc.id).toLowerCase();
                  final overview = _asMap(data['sosOverview']);
                  final msg =
                      ((overview['message'] as String?) ?? '').toLowerCase();
                  final crisisType =
                      ((overview['crisisType'] as String?) ?? '').toLowerCase();
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
                    );
                    final message = _safeText(
                      overview['message'] as String?,
                      fallback: 'No SOS message available',
                      maxLen: 84,
                    );
                    final status =
                        ((data['status'] as String?) ?? 'active').toLowerCase();
                    final createdAt = _createdAt(data);
                    final isCancelled = status == 'cancelled';
                    final isDeleting = _deletingSosIds.contains(sosId);
                    final participantCount = _participantCount(data);
                    final onlineCount = _onlineCount(data);

                    return InkWell(
                      onTap: isCancelled
                          ? null
                          : () {
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
                        padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Expanded(
                                        child: Text(
                                          chatTitle,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: <Widget>[
                                          Icon(
                                            Icons.circle,
                                            size: 10,
                                            color: Colors.green.shade700,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            '$onlineCount',
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelSmall
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.green.shade700,
                                                ),
                                          ),
                                          const SizedBox(width: 10),
                                          Icon(
                                            Icons.group,
                                            size: 10,
                                            color: Colors.redAccent.shade700,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            '$participantCount',
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelSmall
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.redAccent.shade700,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    message,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: <Widget>[
                                      Expanded(
                                        child: Text(
                                          '${settings.t('label_case_id')}: $sosId',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style:
                                              Theme.of(context).textTheme.bodySmall,
                                        ),
                                      ),
                                      Text(
                                        _timeText(createdAt),
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ],
                                  ),
                                  if (isCancelled) ...<Widget>[
                                    const SizedBox(height: 4),
                                    Text(
                                      settings.t('status_cancelled'),
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                            color: Colors.red.shade700,
                                          ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (isCancelled)
                              isDeleting
                                  ? const Padding(
                                      padding: EdgeInsets.only(left: 8, top: 2),
                                      child: SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    )
                                  : IconButton(
                                      tooltip: settings.t('tooltip_delete_cancelled_chat'),
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: () =>
                                          _confirmDeleteCancelledChat(sosId: sosId),
                                    ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.chevron_right,
                              color: Colors.grey.shade600,
                            ),
                          ],
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
    final date = '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
    final time = '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    return '$date $time';
  }

  static String _humanFriendlyChatTitle({
    required Map<String, dynamic> data,
    required String sosId,
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
          return crisisType.isNotEmpty
              ? '${_toTitleCase(crisisType)}: $displayName'
              : 'Emergency: $displayName';
        }
      }
    }

    if (crisisType.isNotEmpty) {
      return '${_toTitleCase(crisisType)} emergency';
    }

    return 'Emergency chat ${sosId.length >= 6 ? sosId.substring(0, 6) : sosId}';
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
