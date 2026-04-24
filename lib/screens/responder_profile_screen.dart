import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../core/models/responder_model.dart';
import '../core/providers/app_settings_provider.dart';
import '../core/utils/chat_message_utils.dart';

class ResponderProfileScreen extends StatefulWidget {
  final ResponderModel responder;
  final double? viewerLatitude;
  final double? viewerLongitude;
  final bool isCurrentUserProfile;
  final String? currentUserId;
  final String? currentUserName;

  const ResponderProfileScreen({
    super.key,
    required this.responder,
    this.viewerLatitude,
    this.viewerLongitude,
    this.isCurrentUserProfile = false,
    this.currentUserId,
    this.currentUserName,
  });

  @override
  State<ResponderProfileScreen> createState() => _ResponderProfileScreenState();
}

class _ResponderProfileScreenState extends State<ResponderProfileScreen> {
  Future<void> _callResponder(BuildContext context) async {
    final settings = context.read<AppSettingsProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final phone = widget.responder.phoneNumber.trim();
    if (phone.isEmpty) {
      messenger.showSnackBar(
        SnackBar(content: Text(settings.t('profile_no_phone_number'))),
      );
      return;
    }

    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
      return;
    }

    messenger.showSnackBar(
      SnackBar(content: Text(settings.t('profile_could_not_open_dialer'))),
    );
  }

  Future<void> _messageResponder(BuildContext context) async {
    final settings = context.read<AppSettingsProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final phone = widget.responder.phoneNumber.trim();
    if (phone.isEmpty) {
      messenger.showSnackBar(
        SnackBar(content: Text(settings.t('profile_no_messaging_number'))),
      );
      return;
    }

    final uri = Uri.parse(
      'sms:$phone?body=${Uri.encodeComponent(settings.t('profile_sms_template').replaceAll('{name}', settings.localizedDisplayName(widget.responder.name)))}',
    );

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
      return;
    }

    messenger.showSnackBar(
      SnackBar(content: Text(settings.t('profile_messaging_not_supported'))),
    );
  }

  Future<void> _showReviewAndRatingDialog() async {
    final currentUserId = widget.currentUserId;
    if (currentUserId == null || currentUserId.trim().isEmpty) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final settings = context.read<AppSettingsProvider>();
    final reviewDocId = '${currentUserId}_${widget.responder.id}';
    final directReviewRef = FirebaseFirestore.instance
        .collection('responder_reviews')
        .doc(reviewDocId);
    DocumentReference<Map<String, dynamic>> reviewRef = directReviewRef;
    var reviewSnapshot = await directReviewRef.get();

    if (!reviewSnapshot.exists) {
      final fallback = await FirebaseFirestore.instance
          .collection('responder_reviews')
          .where('reviewerUid', isEqualTo: currentUserId)
          .where('responderUid', isEqualTo: widget.responder.id)
          .get();
      if (fallback.docs.isNotEmpty) {
        final selectedDoc =
            pickLatestByUpdatedAt<QueryDocumentSnapshot<Map<String, dynamic>>>(
                  fallback.docs,
                  (doc) => doc.data()['updatedAt'],
                ) ??
                fallback.docs.first;
        reviewSnapshot = selectedDoc;
        reviewRef = selectedDoc.reference;
      }
    }

    final reviewData = reviewSnapshot.data() ?? <String, dynamic>{};
    double selectedRating = (reviewData['rating'] as num?)?.toDouble() ?? 0;
    var reviewText = (reviewData['review'] as String?) ?? '';
    final hasExistingReview = reviewSnapshot.exists;
    var isSubmitting = false;

    if (!mounted) {
      return;
    }

await showDialog<void>(
  context: context,
  barrierColor: Colors.black54,
  builder: (ctx) => StatefulBuilder(
    builder: (ctx, setDialogState) {
      return Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            color: Theme.of(context).colorScheme.surface,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              /// 🧑 Title
              Text(
                settings.t('profile_review_title').replaceAll(
                  '{name}',
                  settings.localizedDisplayName(widget.responder.name),
                ),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),

              const SizedBox(height: 6),

              /// Subtitle
              Text(
                settings.t('profile_give_rating_review'),
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 13,
                ),
              ),

              const SizedBox(height: 16),

              /// ⭐ Rating (modern style)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(5, (i) {
                  final isSelected = i < selectedRating;

                  return GestureDetector(
                    onTap: isSubmitting
                        ? null
                        : () {
                            setDialogState(() {
                              selectedRating = i + 1.0;
                            });
                          },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.amber.withOpacity(0.15)
                            : Colors.transparent,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.star,
                        size: 32,
                        color: isSelected
                            ? Colors.amber
                            : Colors.grey.shade400,
                      ),
                    ),
                  );
                }),
              ),

              const SizedBox(height: 16),

              /// ✍️ Review input
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: TextFormField(
                  initialValue: reviewText,
                  onChanged: (value) {
                    reviewText = value;
                    setDialogState(() {});
                  },
                  maxLines: 4,
                  maxLength: 400,
                  enabled: !isSubmitting,
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: settings.t('profile_share_experience'),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
              ),

              const SizedBox(height: 18),

              /// 🔘 Actions (modern buttons)
              Row(
                children: [

                  /// Delete (if exists)
                  if (hasExistingReview)
                    Expanded(
                      child: TextButton(
                        onPressed: isSubmitting
                            ? null
                            : () async {
                                setDialogState(() => isSubmitting = true);
                                try {
                                  await reviewRef.delete();
                                } catch (e) {
                                  setDialogState(() => isSubmitting = false);
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        '${settings.t('profile_unable_delete_review')}$e',
                                      ),
                                    ),
                                  );
                                  return;
                                }
                                Navigator.pop(ctx);
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      settings.t('profile_review_deleted'),
                                    ),
                                  ),
                                );
                              },
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.red,
                        ),
                        child: Text(settings.t('menu_delete_chat')),
                      ),
                    ),

                  if (hasExistingReview) const SizedBox(width: 8),

                  /// Cancel
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                          isSubmitting ? null : () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(settings.t('profile_cancel')),
                    ),
                  ),

                  const SizedBox(width: 8),

                  /// Save
                  Expanded(
                    child: ElevatedButton(
                      onPressed: isSubmitting ||
                              (selectedRating <= 0 &&
                                  reviewText.trim().isEmpty)
                          ? null
                          : () async {
                              setDialogState(() => isSubmitting = true);

                              final updatePayload = {
                                'reviewerUid': currentUserId,
                                'reviewerName':
                                    widget.currentUserName ??
                                        settings.t('name_anonymous'),
                                'responderUid': widget.responder.id,
                                'responderName': widget.responder.name,
                                'review': reviewText.trim(),
                                'updatedAt':
                                    FieldValue.serverTimestamp(),
                              };

                              if (selectedRating > 0) {
                                updatePayload['rating'] =
                                    selectedRating;
                              }

                              try {
                                await reviewRef.set(
                                  updatePayload,
                                  SetOptions(merge: true),
                                );
                              } catch (e) {
                                setDialogState(
                                    () => isSubmitting = false);
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      '${settings.t('profile_unable_save_review')}$e',
                                    ),
                                  ),
                                );
                                return;
                              }

                              Navigator.pop(ctx);
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(
                                    settings.t('profile_review_saved'),
                                  ),
                                ),
                              );
                            },
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: isSubmitting
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : Text(settings.t('profile_save_review')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  ),
);
  }


  Widget _statCard(
    BuildContext context,
    String label,
    String value,
    IconData icon,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.red.shade100),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Colors.red.shade700),
            const SizedBox(height: 10),
            Text(value, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettingsProvider>();
    final isAi = widget.responder.id == 'rescuelink_ai';
    final responderDisplayName = isAi
        ? settings.t('chat_rescue_link_ai')
        : settings.localizedDisplayName(widget.responder.name);
    final verificationText = widget.responder.verifiedResponder
      ? settings.t('profile_verified_responder')
      : settings.t('profile_not_verified_yet');

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isCurrentUserProfile
              ? settings.t('profile_my_responder_profile')
              : (isAi ? settings.t('profile_ai_assistant') : settings.t('profile_responder_profile')),style:TextStyle(fontWeight:FontWeight.bold),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('responder_reviews')
            .where('responderUid', isEqualTo: widget.responder.id)
            .snapshots(),
        builder: (context, snapshot) {
          final reviewDocs = snapshot.data?.docs ?? [];
          final reviewData = reviewDocs.map((d) => d.data() as Map<String, dynamic>).toList();
          
          double avgRating = 0;
          if (reviewData.isNotEmpty) {
            final validRatings = reviewData.where((r) => r.containsKey('rating')).map((r) => r['rating'] as num);
            if (validRatings.isNotEmpty) {
              avgRating = validRatings.reduce((a, b) => a + b) / validRatings.length;
            }
          } else {
            avgRating = widget.responder.averageRating;
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isAi 
                        ? [Colors.red.shade900, Colors.red.shade600] 
                        : [Colors.red.shade700, Colors.red.shade400],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 30,
                            backgroundColor: Colors.white.withValues(alpha: 0.2),
                            child: isAi 
                              ? const Icon(Icons.auto_awesome, color: Colors.white, size: 30)
                              : Text(
                                  widget.responder.name.trim().isEmpty
                                      ? '?'
                                      : widget.responder.name.trim()[0].toUpperCase(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  responderDisplayName,
                                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  settings.localizedResponderType(widget.responder.responderType),
                                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                        color: Colors.white.withValues(alpha: 0.95),
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Chip(
                            label: Text(settings.localizedSkill(widget.responder.skillsArea)),
                            backgroundColor: Colors.white,
                          ),
                          Chip(
                            label: Text(verificationText),
                            backgroundColor: widget.responder.verifiedResponder
                                ? Colors.green.shade50
                                : Colors.orange.shade50,
                          ),
                          if (!isAi)
                            Chip(
                              label: Text(
                                widget.responder.isAvailable
                                    ? settings.t('profile_available_now')
                                    : settings.t('profile_currently_offline'),
                              ),
                              backgroundColor: Colors.white,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _statCard(
                      context,
                      settings.t('profile_rescues'),
                      widget.responder.rescueCount.toString(),
                      Icons.emoji_people,
                    ),
                    const SizedBox(width: 12),
                    _statCard(
                      context,
                      settings.t('profile_rating'),
                      avgRating == 0
                          ? 'N/A'
                          : avgRating.toStringAsFixed(1),
                      Icons.star,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _statCard(
                      context,
                      settings.t('profile_reviews'),
                      reviewData.length.toString(),
                      Icons.reviews,
                    ),
                    const SizedBox(width: 12),
                    _statCard(
                      context,
                      settings.t('profile_identity'),
                      isAi
                          ? settings.t('profile_ai_core')
                          : (widget.responder.verifiedResponder
                              ? settings.t('profile_verified')
                              : settings.t('profile_unverified')),
                      Icons.verified_user,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                if (!isAi) ...[
                  Text(
                    settings.t('profile_contact'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 12),
                  if (widget.isCurrentUserProfile)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text(settings.t('profile_this_is_your_view')),
                    )
                  else
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        SizedBox(
                          width: 160,
                          child: ElevatedButton.icon(
                            onPressed: () => _callResponder(context),
                            icon: const Icon(Icons.call),
                            label: Text(settings.t('profile_call')),
                          ),
                        ),
                        SizedBox(
                          width: 160,
                          child: OutlinedButton.icon(
                            onPressed: () => _messageResponder(context),
                            icon: const Icon(Icons.message),
                            label: Text(settings.t('profile_message')),
                          ),
                        ),
                      ],
                    ),
                ],
                const SizedBox(height: 24),
                Row(
  children: [
    Expanded(
      child: Text(
        settings.t('profile_community_reviews'),
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
        overflow: TextOverflow.ellipsis, // ✅ prevents overflow
      ),
    ),
    if (!widget.isCurrentUserProfile && widget.currentUserId != null)
      TextButton.icon(
        onPressed: _showReviewAndRatingDialog,
        icon: const Icon(Icons.add_reaction_outlined, color: Colors.red),
        label: Text(
          settings.t('profile_rate_review'),
          style: const TextStyle(color: Colors.red),
        ),
      ),
  ],
),
                const SizedBox(height: 12),
                if (reviewData.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text(settings.t('profile_no_reviews_yet')),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: reviewData.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final rev = reviewData[index];
                      final rating = (rev['rating'] as num?)?.toDouble() ?? 0;
                      final text = rev['review'] as String? ?? '';
                      final rawName = rev['reviewerName'] as String?;
                      final name = settings.localizedDisplayName(
                        (rawName == null || rawName.trim().isEmpty)
                            ? settings.t('name_anonymous')
                            : rawName,
                      );
                      final date = rev['updatedAt'] is Timestamp 
                          ? (rev['updatedAt'] as Timestamp).toDate() 
                          : DateTime.now();
                      final isMine = rev['reviewerUid'] == widget.currentUserId;

                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isMine ? Colors.blue.shade50 : Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                      Text(
                                        DateFormat('MMM d, yyyy').format(date),
                                        style: Theme.of(context).textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                                if (rating > 0)
                                  Row(
                                    children: List.generate(5, (i) => Icon(
                                      Icons.star,
                                      size: 14,
                                      color: i < rating ? Colors.amber : Colors.grey.shade300,
                                    )),
                                  ),
                              ],
                            ),
                            if (text.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Text(text),
                            ],
                            if (isMine) ...[
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: _showReviewAndRatingDialog,
                                  child: Text(settings.t('profile_edit_delete')),
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                const SizedBox(height: 100), // Bottom padding
              ],
            ),
          );
        },
      ),
    );
  }
}