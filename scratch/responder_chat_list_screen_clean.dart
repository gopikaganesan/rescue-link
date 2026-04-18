import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/chat_service.dart';
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
  State<ResponderChatListScreen> createState() =>
      _ResponderChatListScreenState();
}

class _ResponderChatListScreenState extends State<ResponderChatListScreen> {
  late bool _showAllActiveChats;
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
    final chatService = ChatService();
    final stream = _showAllActiveChats
        ? chatService.watchActiveChats()
        : chatService.watchResponderChats(widget.currentUserId);

    return Scaffold(
      appBar: AppBar(title: const Text('Responder Chats')),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Wrap(
              spacing: 8,
              children: <Widget>[
                ChoiceChip(
                  label: const Text('All Active'),
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
                  label: const Text('Joined By Me'),
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
                hintText: 'Search by SOS ID or message',
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
                  return const Center(child: Text('Failed to load chats'));
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
                          ? 'No active chats right now.'
                          : 'You have not joined any chats yet.',
                    ),
                  );
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
                  if (_searchQuery.isEmpty) {
                    return true;
                  }

                  final data = doc.data();
                  final sosId = ((data['sosId'] as String?) ?? doc.id).toLowerCase();
                  final overview = _asMap(data['sosOverview']);
                  final message =
                      ((overview['message'] as String?) ?? '').toLowerCase();

                  return sosId.contains(_searchQuery) ||
                      message.contains(_searchQuery);
                }).toList();

                if (filteredDocs.isEmpty) {
                  return const Center(
                    child: Text('No chats match your search.'),
                  );
                }

                final joinedCount = filteredDocs
                    .where(
                      (doc) => _isJoinedByUser(doc.data(), widget.currentUserId),
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
                            'Showing ${filteredDocs.length} chats ΓÇó Joined $joinedCount',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Tap a chat to open conversation. Join happens inside chat if needed.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        itemCount: filteredDocs.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final doc = filteredDocs[index];
                          final data = doc.data();

                          final sosId = (data['sosId'] as String?) ?? doc.id;
                          final overview = _asMap(data['sosOverview']);
                          final message = _safeText(
                            overview['message'] as String?,
                            fallback: 'No SOS message available',
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
                            title: Text('SOS: $sosId'),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                const SizedBox(height: 4),
                                Text(
                                  message,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Participants: $participantCount ΓÇó Online responders: $onlineCount ΓÇó Status: $status ΓÇó Joined: ${isJoinedByMe ? 'Yes' : 'No'}',
                                ),
                                const SizedBox(height: 6),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: status == 'active'
                                          ? Colors.green.shade50
                                          : Colors.red.shade50,
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                        color: status == 'active'
                                            ? Colors.green.shade300
                                            : Colors.red.shade300,
                                      ),
                                    ),
                                    child: Text(
                                      status.toUpperCase(),
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: status == 'active'
                                                ? Colors.green.shade800
                                                : Colors.red.shade800,
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                if (isJoinedByMe)
                                  Icon(
                                    Icons.check_circle,
                                    size: 18,
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                                const SizedBox(width: 6),
                                const Icon(Icons.chevron_right),
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
}
