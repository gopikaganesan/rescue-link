import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/providers/app_settings_provider.dart';
import '../services/chat_service.dart';
import '../widgets/translated_text.dart';
import 'group_chat_screen.dart';

class ResponderChatListScreen extends StatefulWidget {
  const ResponderChatListScreen({
    super.key,
    required this.currentUserId,
    required this.currentUserName,
    this.showAllActiveChats = true,
  });

  final String currentUserId;
  final String currentUserName;
  final bool showAllActiveChats;

  static Future<void> open(
    BuildContext context, {
    required String currentUserId,
    required String currentUserName,
    bool showAllActiveChats = true,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ResponderChatListScreen(
          currentUserId: currentUserId,
          currentUserName: currentUserName,
          showAllActiveChats: showAllActiveChats,
        ),
      ),
    );
  }

  @override
  State<ResponderChatListScreen> createState() => _ResponderChatListScreenState();
}

class _ResponderChatListScreenState extends State<ResponderChatListScreen> {
  late bool _showAllActiveChats;
  final ChatService _chatService = ChatService();
  final Set<String> _autoPruneInProgress = <String>{};
  final Set<String> _leavingSosIds = <String>{};
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _showAllActiveChats = widget.showAllActiveChats;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.read<AppSettingsProvider>();
    final chatService = ChatService();
    final stream = _showAllActiveChats
        ? chatService.watchActiveChats()
        : chatService.watchResponderChats(widget.currentUserId);

    return Scaffold(
      appBar: AppBar(title: Text(settings.t('title_responder_alerts'))),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Wrap(
              spacing: 8,
              children: <Widget>[
                ChoiceChip(
                  label: Text(settings.t('filter_all_active')),
                  selected: _showAllActiveChats,
                  onSelected: (selected) {
                    if (!selected) {
                      return;
                    }
                    setState(() {
                      _showAllActiveChats = true;
                    });
                  },
                ),
                ChoiceChip(
                  label: Text(settings.t('filter_joined_by_me')),
                  selected: !_showAllActiveChats,
                  onSelected: (selected) {
                    if (!selected) {
                      return;
                    }
                    setState(() {
                      _showAllActiveChats = false;
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
                hintText: settings.t('hint_search_case'),
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
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: stream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text(settings.t('error_failed_load_chats')));
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data?.docs ??
                    const <QueryDocumentSnapshot<Map<String, dynamic>>>[];

                if (docs.isEmpty) {
                  return Center(
                    child: Text(
                      _showAllActiveChats
                          ? settings.t('status_no_active_chats')
                          : settings.t('status_no_joined_chats'),
                    ),
                  );
                }

                final cancelledDocsForUser = docs.where((doc) {
                  final data = doc.data();
                  final status =
                      ((data['status'] as String?) ?? 'active').toLowerCase();
                  return status == 'cancelled' &&
                      _isJoinedByUser(data, widget.currentUserId);
                }).toList();
                if (cancelledDocsForUser.isNotEmpty) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _autoRemoveCancelledChats(cancelledDocsForUser);
                  });
                }

                final sortedDocs = docs.toList()
                  ..sort((a, b) {
                    final aData = a.data();
                    final bData = b.data();

                    if (_showAllActiveChats) {
                      final aJoined = _isJoinedByUser(
                        aData,
                        widget.currentUserId,
                      );
                      final bJoined = _isJoinedByUser(
                        bData,
                        widget.currentUserId,
                      );
                      if (aJoined != bJoined) {
                        return aJoined ? -1 : 1;
                      }
                    }

                    final aTime = _createdAt(aData);
                    final bTime = _createdAt(bData);
                    return bTime.compareTo(aTime);
                  });

                final filteredDocs = sortedDocs.where((doc) {
                  final data = doc.data();
                  final status =
                      ((data['status'] as String?) ?? 'active').toLowerCase();
                  if (status == 'cancelled') {
                    return false;
                  }

                  if (_searchQuery.isEmpty) {
                    return true;
                  }

                  final sosId = ((data['sosId'] as String?) ?? doc.id).toLowerCase();
                  final overview = _asMap(data['sosOverview']);
                  final message =
                      ((overview['message'] as String?) ?? '').toLowerCase();

                  return sosId.contains(_searchQuery) ||
                      message.contains(_searchQuery);
                }).toList();

                if (filteredDocs.isEmpty) {
                  return Center(child: Text(settings.t('status_no_matching_chats')));
                }

                final joinedCount = filteredDocs
                    .where(
                      (doc) =>
                          _isJoinedByUser(doc.data(), widget.currentUserId),
                    )
                    .length;

                return Column(
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            settings
                                .t('responder_chat_showing_joined')
                                .replaceAll('{total}', '${filteredDocs.length}')
                                .replaceAll('{joined}', '$joinedCount'),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            settings.t('responder_chat_tap_hint'),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
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
                            fallback: settings.t('status_no_sos_message_available'),
                            maxLen: 90,
                          );
                          final participantCount = _participantCount(data);
                          final onlineCount = _onlineCount(data);
                          final status = (data['status'] as String?) ?? 'active';
                          final isJoinedByMe = _isJoinedByUser(
                            data,
                            widget.currentUserId,
                          );

                          return ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            title: Row(
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
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                const SizedBox(height: 4),
                                TranslatedText(
                                  message,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: <Widget>[
                                    Expanded(
                                      child: Text(
                                        '${context.read<AppSettingsProvider>().t('label_case_id')}: $sosId',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style:
                                            Theme.of(context).textTheme.bodySmall,
                                      ),
                                    ),
                                    Text(
                                      _timeText(_createdAt(data)),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                  ],
                                ),
                                if (status != 'active') ...<Widget>[
                                  const SizedBox(height: 4),
                                  Text(
                                    status == 'cancelled'
                                        ? context.read<AppSettingsProvider>().t('status_cancelled')
                                        : status.toUpperCase(),
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.w700,
                                          color: status == 'active'
                                              ? Colors.green.shade800
                                              : Colors.red.shade800,
                                        ),
                                  ),
                                ],
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                if (isJoinedByMe)
                                  Icon(
                                    Icons.check_circle,
                                    size: 18,
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                  ),
                              ],
                            ),
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => GroupChatScreen(
                                    sosId: sosId,
                                    currentUserId: widget.currentUserId,
                                    currentUserName: widget.currentUserName,
                                    currentUserRole: 'responder',
                                    enableResponderJoinGate: true,
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _autoRemoveCancelledChats(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    for (final doc in docs) {
      final data = doc.data();
      final sosId = ((data['sosId'] as String?) ?? doc.id).trim();
      if (sosId.isEmpty || _autoPruneInProgress.contains(sosId)) {
        continue;
      }

      _autoPruneInProgress.add(sosId);
      try {
        await _chatService.removeResponderFromChatList(
          sosId: sosId,
          responderUid: widget.currentUserId,
        );
      } catch (_) {
        // Ignore transient errors; next snapshot can retry.
      } finally {
        _autoPruneInProgress.remove(sosId);
      }
    }
  }

  Future<void> _confirmLeaveActiveConversation({
    required String sosId,
    required bool isJoinedByMe,
  }) async {
    if (!isJoinedByMe || _leavingSosIds.contains(sosId)) {
      return;
    }

    final settings = context.read<AppSettingsProvider>();
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(settings.t('dialog_leave_conversation_title')),
            content: Text(
              settings.t('dialog_leave_conversation_body'),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(settings.t('button_cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(settings.t('button_leave')),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed || !mounted) {
      return;
    }

    setState(() {
      _leavingSosIds.add(sosId);
    });

    try {
      await _chatService.removeResponderFromChatList(
        sosId: sosId,
        responderUid: widget.currentUserId,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(settings.t('snackbar_conversation_removed'))),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to leave right now. Please retry.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _leavingSosIds.remove(sosId);
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

  static bool _isJoinedByUser(Map<String, dynamic> data, String userId) {
    if (userId.trim().isEmpty) {
      return false;
    }

    final participantUids = data['participantUids'];
    if (participantUids is List) {
      return participantUids.whereType<String>().contains(userId);
    }

    final participants = data['participants'];
    if (participants is List) {
      return participants
          .whereType<Map>()
          .map((entry) => entry['uid'] as String?)
          .whereType<String>()
          .contains(userId);
    }

    return false;
  }

  static String _safeText(
    String? raw, {
    required String fallback,
    required int maxLen,
  }) {
    final trimmed = raw?.trim();
    final base = (trimmed == null || trimmed.isEmpty) ? fallback : trimmed;
    if (base.length <= maxLen) {
      return base;
    }
    return '${base.substring(0, maxLen)}...';
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

  static String _timeText(DateTime value) {
    final local = value.toLocal();
    final time =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    final date =
        '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}';
    return '$time • $date';
  }
}