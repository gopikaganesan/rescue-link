import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/chat_service.dart';
import 'group_chat_screen.dart';

class VictimChatListScreen extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final chatService = ChatService();

    return Scaffold(
      appBar: AppBar(title: const Text('My SOS Chats')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: chatService.watchVictimChats(currentUserId),
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
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text('No SOS chats found yet.'),
              ),
            );
          }

          final sortedDocs = docs.toList()
            ..sort((a, b) => _createdAt(b.data()).compareTo(_createdAt(a.data())));

          return ListView.separated(
            itemCount: sortedDocs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final doc = sortedDocs[index];
              final data = doc.data();

              final sosId = (data['sosId'] as String?) ?? doc.id;
              final overview = _asMap(data['sosOverview']);
              final message = _safeText(
                overview['message'] as String?,
                fallback: 'No SOS message available',
                maxLen: 100,
              );
              final status = (data['status'] as String?) ?? 'active';
              final createdAt = _createdAt(data);

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
                    Text('Status: ${status.toUpperCase()} • ${_timeText(createdAt)}'),
                  ],
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => GroupChatScreen(
                        sosId: sosId,
                        currentUserId: currentUserId,
                        currentUserName: currentUserName,
                        currentUserRole: 'victim',
                        enableResponderJoinGate: false,
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
}
