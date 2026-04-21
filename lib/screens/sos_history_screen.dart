import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/providers/app_settings_provider.dart';
import '../core/providers/emergency_request_provider.dart';
import '../services/chat_service.dart';
import 'group_chat_screen.dart';
import 'package:geocoding/geocoding.dart';


class SosHistoryScreen extends StatelessWidget {
  const SosHistoryScreen({
    super.key,
    required this.currentUserId,
    required this.currentUserName,
  });

  final String currentUserId;
  final String currentUserName;

  Future<String> getAddress(double lat, double lng) async {
  try {
    final placemarks = await placemarkFromCoordinates(lat, lng);
    final p = placemarks.first;

    return "${p.street}, ${p.locality}, ${p.administrativeArea}, ${p.country}";
  } catch (e) {
    return "Unknown location";
  }
}

  String _translateSeverityLabel(AppSettingsProvider settings, String severity) {
    final normalized = severity.trim().toLowerCase();
    if (normalized.isEmpty) {
      return settings.t('severity_unknown');
    }

    final key = 'severity_$normalized';
    final translated = settings.t(key);
    if (translated != key) {
      return translated;
    }

    return severity.toUpperCase();
  }

  String _translateCategoryLabel(AppSettingsProvider settings, String category) {
    final normalized = category.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    final key = 'category_$normalized';
    final translated = settings.t(key);
    if (translated != key) {
      return translated;
    }

    return category;
  }

  static Future<void> open(
    BuildContext context, {
    required String currentUserId,
    required String currentUserName,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SosHistoryScreen(
          currentUserId: currentUserId,
          currentUserName: currentUserName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.read<AppSettingsProvider>();
    return Scaffold(
      appBar: AppBar(
        title: Text(settings.t('button_view_sos_history')),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('emergency_requests')
            .where('requesterUserId', isEqualTo: currentUserId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(settings.t('error_failed_load_chats')),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data?.docs ?? const [];
          DateTime? parseTimestamp(Object? raw) {
            if (raw is Timestamp) return raw.toDate();
            if (raw is DateTime) return raw;
            return null;
          }

          final filteredDocs = docs.where((doc) {
            final data = doc.data();
            final status =
                ((data['status'] as String?) ?? 'open').toLowerCase();
            if (status != 'cancelled') {
              return true;
            }
            final createdAt = parseTimestamp(data['createdAt']) ??
                DateTime.fromMillisecondsSinceEpoch(0);
            final cancelledAt = parseTimestamp(data['cancelledAt']);
            if (cancelledAt == null) {
              return true;
            }
            final difference = cancelledAt.difference(createdAt).inSeconds;
            return difference > 30;
          }).toList();

          final sortedDocs = filteredDocs
            ..sort((a, b) {
              final aCreated = a.data()['createdAt'];
              final bCreated = b.data()['createdAt'];
              final aDate = aCreated is Timestamp
                  ? aCreated.toDate()
                  : aCreated is DateTime
                      ? aCreated
                      : DateTime.fromMillisecondsSinceEpoch(0);
              final bDate = bCreated is Timestamp
                  ? bCreated.toDate()
                  : bCreated is DateTime
                      ? bCreated
                      : DateTime.fromMillisecondsSinceEpoch(0);
              return bDate.compareTo(aDate);
            });
          if (sortedDocs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Text(settings.t('status_no_sos_history')),
              ),
            );
          }

          return ListView.separated(
            itemCount: sortedDocs.length,
            separatorBuilder: (_, __) => Divider(color: Colors.grey.shade300),
            itemBuilder: (context, index) {
              final data = sortedDocs[index].data();
              final sosId = (data['id'] as String?) ?? sortedDocs[index].id;
              final status =
                  ((data['status'] as String?) ?? 'open').toLowerCase();
              final summary = (data['summary'] as String?)?.trim() ??
                  (data['originalMessage'] as String?)?.trim() ??
                  settings.t('status_no_sos_message_available');
              final createdAtRaw = data['createdAt'];
              final createdAt = createdAtRaw is Timestamp
                  ? createdAtRaw.toDate()
                  : createdAtRaw is DateTime
                      ? createdAtRaw
                      : DateTime.now();
              final formattedTime = MaterialLocalizations.of(context)
                  .formatFullDate(createdAt)
                  .toString();
              final category = (data['category'] as String?)?.trim();
              final severity =
                  ((data['severity'] as String?) ?? 'low').toLowerCase();
              final severityLabel =
                  _translateSeverityLabel(settings, severity);
              final severityValue = severity.toUpperCase();
              final severityColor = severityValue == 'CRITICAL'
                  ? Colors.red.shade700
                  : severityValue == 'HIGH'
                      ? Colors.orange.shade700
                      : Colors.green.shade700;
              final categoryLabel = category == null || category.isEmpty
                  ? settings.t('status_unknown')
                  : _translateCategoryLabel(settings, category);
              final isActiveStatus = status == 'open' || status == 'active';
              final statusLabelText = status == 'cancelled'
                  ? settings.t('status_cancelled')
                  : isActiveStatus
                      ? settings.t('status_active')
                      : settings.t('status_unknown');

              return Padding(
  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
  child: ListTile(
                tileColor: Colors.grey[100],
                shape: RoundedRectangleBorder(
  borderRadius: BorderRadius.circular(12),
),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                title: Text(
                  summary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Container(
  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
  decoration: BoxDecoration(
    color: severityColor.withAlpha(38),
    borderRadius: BorderRadius.circular(20), // fully rounded
  ),
  child: Text(
    severityLabel,
    style: TextStyle(
      color: severityColor,
      fontWeight: FontWeight.w600,
      fontSize: 12,
    ),
  ),
),
                        Container(
  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
  decoration: BoxDecoration(
    color: status == 'cancelled'
        ? Colors.red.shade50
        : Colors.green.shade50,
    borderRadius: BorderRadius.circular(20),
  ),
  child: Text(
    statusLabelText,
    style: TextStyle(
      color: status == 'cancelled'
          ? Colors.red.shade700
          : Colors.green.shade700,
      fontWeight: FontWeight.w600,
      fontSize: 12,
    ),
  ),
),
                      ],
                    ),
                    const SizedBox(height: 6),
                   const SizedBox(height: 6),

// Case ID
RichText(
  text: TextSpan(
    children: [
      TextSpan(
        text: '${settings.t('label_case_id')}: ',
        style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
      ),
      TextSpan(
        text: sosId,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 13,
          color: Colors.black,
        ),
      ),
    ],
  ),
),

// Category
RichText(
  text: TextSpan(
    children: [
      TextSpan(
        text: '${settings.t('category_label')}: ',
        style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
      ),
      TextSpan(
        text: categoryLabel,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 13,
          color: Colors.black,
        ),
      ),
    ],
  ),
),

// Severity (highlight with color)
RichText(
  text: TextSpan(
    children: [
      TextSpan(
        text: '${settings.t('severity_label')}: ',
        style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
      ),
      TextSpan(
        text: severityLabel,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 13,
          color: severityColor,
        ),
      ),
    ],
  ),
),

// Time
Text(
  formattedTime,
  style: TextStyle(
    color: Colors.grey.shade600,
    fontSize: 12,
  ),
),
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (status != 'cancelled')
                      IconButton(
                        onPressed: () async {
                          final provider =
                              context.read<EmergencyRequestProvider>();
                          final cancelled = await provider.cancelRequest(sosId);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(cancelled
                                  ? settings.t('snackbar_cancel_sos_successful')
                                  : settings.t('snackbar_cancel_sos_failed')),
                            ),
                          );
                        },
                        icon: const Icon(Icons.cancel),
                        color: Colors.red.shade700,
                        tooltip: settings.t('button_cancel_sos'),
                      ),
                    Icon(
                      status == 'cancelled'
                          ? Icons.cancel
                          : Icons.chevron_right,
                      color: status == 'cancelled' ? Colors.red.shade700 : null,
                    ),
                  ],
                ),
                onTap: () => _showSosDetails(context, data, sosId, status),
                onLongPress: status == 'cancelled'
                    ? () => _confirmDeleteCancelledSos(context, sosId)
                    : null,
              ));
            },
          );
        },
      ),
    );
  }

  Future<void> _confirmDeleteCancelledSos(
    BuildContext context,
    String sosId,
  ) async {
    final settings = context.read<AppSettingsProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final chatDoc =
        await FirebaseFirestore.instance.collection('chats').doc(sosId).get();
    if (!context.mounted) {
      return;
    }
    final chatExists = chatDoc.exists;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(chatExists
                ? settings.t('dialog_delete_cancelled_chat_title')
                : settings.t('dialog_delete_cancelled_summary_title')),
            content: Text(chatExists
                ? settings.t('dialog_delete_cancelled_chat_body')
                : settings.t('dialog_delete_cancelled_summary_body')),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(settings.t('button_keep')),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: Text(chatExists
                    ? settings.t('button_delete_chat')
                    : settings.t('button_delete_summary')),
              ),
            ],
          ),
        ) ??
        false;

    if (!context.mounted || !confirmed) {
      return;
    }

    if (chatDoc.exists) {
      try {
        await ChatService().deleteEntireChat(
          sosId: sosId,
          deleteMediaFromCloudinary: true,
        );
        messenger.showSnackBar(
          SnackBar(
            content: Text(settings.t('snackbar_cancelled_chat_deleted')),
          ),
        );
      } catch (_) {
        messenger.showSnackBar(
          SnackBar(content: Text(settings.t('snackbar_failed_delete_chat'))),
        );
      }
    } else {
      try {
        await FirebaseFirestore.instance
            .collection('emergency_requests')
            .doc(sosId)
            .delete();
        messenger.showSnackBar(
          SnackBar(
              content: Text(settings.t('snackbar_cancelled_summary_deleted'))),
        );
      } catch (_) {
        messenger.showSnackBar(
          SnackBar(content: Text(settings.t('snackbar_failed_delete_summary'))),
        );
      }
    }
  }

  Future<void> _showSosDetails(
    BuildContext context,
    Map<String, dynamic> data,
    String sosId,
    String status,
  ) async {
    final settings = context.read<AppSettingsProvider>();
    final summary = (data['summary'] as String?)?.trim() ??
        (data['originalMessage'] as String?)?.trim() ??
        settings.t('status_no_sos_message_available');
    final category = (data['category'] as String?)?.trim();
    final categoryLabel = category == null || category.isEmpty
        ? settings.t('status_unknown')
        : _translateCategoryLabel(settings, category);
    final severity = (data['severity'] as String?)?.trim();
    final severityLabel = _translateSeverityLabel(settings, severity ?? 'unknown');
    final address = (data['address'] as String?)?.trim();
    final location = address ??
        ((data['latitude'] as num?) != null &&
                (data['longitude'] as num?) != null
            ? '${(data['latitude'] as num).toDouble().toStringAsFixed(4)}, ${(data['longitude'] as num).toDouble().toStringAsFixed(4)}'
            : null);

    final chatDoc =
        await FirebaseFirestore.instance.collection('chats').doc(sosId).get();
    if (!context.mounted) {
      return;
    }
    final chatExists = chatDoc.exists;
    final isActiveStatus = status == 'open' || status == 'active';

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(16),
  ),
  backgroundColor: Colors.white,
  title: const Text('SOS Details'),

  content: SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 🔹 Summary
        Text(
          summary,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),

        const SizedBox(height: 16),

        // 🔹 Info Section
        _infoRow(settings.t('label_case_id'), sosId),
        _infoRow(settings.t('category_label'), categoryLabel),
        _infoRow(settings.t('severity_label'), severityLabel),

        if (location != null) ...[
          _infoRow(settings.t('label_location'), location),
        ],

        if (status == 'cancelled') ...[
          const SizedBox(height: 8),
          Text(
            settings.t('status_cancelled'),
            style: TextStyle(
              color: Colors.red.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],

        if (status != 'cancelled' && !chatExists) ...[
          const SizedBox(height: 12),
          Text(
            settings.t('status_chat_summary_preserved'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    ),
  ),

  actionsPadding:
      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),

  actions: [
    if (status != 'cancelled')
      TextButton(
        onPressed: () async {
          Navigator.of(dialogContext).pop();

          final provider =
              context.read<EmergencyRequestProvider>();
          final cancelled = await provider.cancelRequest(sosId);

          if (!context.mounted) return;

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(cancelled
                  ? settings.t('snackbar_cancel_sos_successful')
                  : settings.t('snackbar_cancel_sos_failed')),
            ),
          );
        },
        style: TextButton.styleFrom(
          foregroundColor: Colors.red.shade700,
        ),
        child: Text(settings.t('button_cancel_sos')),
      ),

    if (status != 'cancelled' && chatExists)
      FilledButton.icon(
        icon: const Icon(Icons.chat, size: 18),
        onPressed: () {
          Navigator.of(dialogContext).pop();

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
        label: Text(settings.t('button_open_chat')),
      ),

    if (status == 'cancelled')
      FilledButton.icon(
        icon: const Icon(Icons.delete, size: 18),
        style: FilledButton.styleFrom(
          backgroundColor: Colors.red.shade700,
        ),
        onPressed: () {
          Navigator.of(dialogContext).pop();
          _confirmDeleteCancelledSos(context, sosId);
        },
        label: Text(chatExists
            ? settings.t('button_delete_chat')
            : settings.t('button_delete_summary')),
      ),

    TextButton(
      onPressed: () => Navigator.of(dialogContext).pop(),
      child: Text(settings.t('button_close')),
    ),
  ],
);
      },
    );
  }

  Widget _infoRow(String label, String value, {Color? valueColor}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: '$label: ',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 12,
            ),
          ),
          TextSpan(
            text: value,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: valueColor ?? Colors.black,
            ),
          ),
        ],
      ),
    ),
  );
}

}
