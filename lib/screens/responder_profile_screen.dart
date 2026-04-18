import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../core/models/responder_model.dart';
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
    final messenger = ScaffoldMessenger.of(context);
    final phone = widget.responder.phoneNumber.trim();
    if (phone.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No phone number available for this responder.')),
      );
      return;
    }

    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
      return;
    }

    messenger.showSnackBar(
      const SnackBar(content: Text('Could not open the dialer on this device.')),
    );
  }

  Future<void> _messageResponder(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final phone = widget.responder.phoneNumber.trim();
    if (phone.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No messaging number available for this responder.')),
      );
      return;
    }

    final uri = Uri.parse(
      'sms:$phone?body=${Uri.encodeComponent('Hi ${widget.responder.name}, this is RescueLink. An SOS request may need your help.')}',
    );

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
      return;
    }

    messenger.showSnackBar(
      const SnackBar(content: Text('Messaging is not supported on this device yet.')),
    );
  }

  Future<void> _showReviewAndRatingDialog() async {
    final currentUserId = widget.currentUserId;
    if (currentUserId == null || currentUserId.trim().isEmpty) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
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
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Review ${widget.responder.name}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Give both a rating and a review.'),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (i) {
                    return IconButton(
                      icon: Icon(
                        i < selectedRating ? Icons.star : Icons.star_border,
                        color: Colors.amber,
                        size: 34,
                      ),
                      onPressed: isSubmitting
                          ? null
                          : () {
                              setDialogState(() => selectedRating = i + 1.0);
                            },
                    );
                  }),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  initialValue: reviewText,
                  onChanged: (value) {
                    reviewText = value;
                    setDialogState(() {});
                  },
                  maxLines: 4,
                  maxLength: 400,
                  enabled: !isSubmitting,
                  decoration: const InputDecoration(
                    hintText: 'Share your experience with this responder...',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            if (hasExistingReview)
              TextButton(
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                onPressed: isSubmitting
                    ? null
                    : () async {
                        if (!ctx.mounted) {
                          return;
                        }
                        setDialogState(() {
                          isSubmitting = true;
                        });
                        try {
                          await reviewRef.delete();
                        } catch (e) {
                          if (ctx.mounted) {
                            setDialogState(() {
                              isSubmitting = false;
                            });
                          }
                          if (mounted) {
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text('Unable to delete review: $e'),
                              ),
                            );
                          }
                          return;
                        }
                        if (!ctx.mounted) {
                          return;
                        }
                        Navigator.pop(ctx);
                        if (mounted) {
                          messenger.showSnackBar(
                            const SnackBar(content: Text('Review deleted.')),
                          );
                        }
                      },
                child: const Text('Delete'),
              ),
            TextButton(
              onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: isSubmitting ||
                      (selectedRating <= 0 && reviewText.trim().isEmpty)
                  ? null
                  : () async {
                      if (!ctx.mounted) {
                        return;
                      }
                      setDialogState(() {
                        isSubmitting = true;
                      });
                      final updatePayload = <String, dynamic>{
                        'reviewerUid': currentUserId,
                        'reviewerName': widget.currentUserName ?? 'Anonymous',
                        'responderUid': widget.responder.id,
                        'responderName': widget.responder.name,
                        'review': reviewText.trim(),
                        'updatedAt': FieldValue.serverTimestamp(),
                      };
                      if (selectedRating > 0) {
                        updatePayload['rating'] = selectedRating;
                      }
                      try {
                        await reviewRef.set(updatePayload, SetOptions(merge: true));
                      } catch (e) {
                        if (ctx.mounted) {
                          setDialogState(() {
                            isSubmitting = false;
                          });
                        }
                        if (mounted) {
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text('Unable to save review: $e'),
                            ),
                          );
                        }
                        return;
                      }
                      if (!ctx.mounted) {
                        return;
                      }
                      Navigator.pop(ctx);
                      if (mounted) {
                        messenger.showSnackBar(
                          const SnackBar(content: Text('Review saved.')),
                        );
                      }
                    },
              child: const Text('Save Review'),
            ),
          ],
        ),
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
    final isAi = widget.responder.id == 'rescuelink_ai';
    final verificationText = widget.responder.verifiedResponder
        ? 'Verified responder'
        : 'Not verified yet';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isCurrentUserProfile ? 'My Responder Profile' : (isAi ? 'AI Assistant Profile' : 'Responder Profile'),
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
                        ? [Colors.blue.shade800, Colors.blue.shade500] 
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
                                  widget.responder.name,
                                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  widget.responder.responderType,
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
                            label: Text(widget.responder.skillsArea),
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
                                widget.responder.isAvailable ? 'Available now' : 'Currently offline',
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
                      'Rescues',
                      widget.responder.rescueCount.toString(),
                      Icons.emoji_people,
                    ),
                    const SizedBox(width: 12),
                    _statCard(
                      context,
                      'Rating',
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
                      'Reviews',
                      reviewData.length.toString(),
                      Icons.reviews,
                    ),
                    const SizedBox(width: 12),
                    _statCard(
                      context,
                      'Identity',
                      isAi ? 'AI Core' : (widget.responder.verifiedResponder ? 'Verified' : 'Unverified'),
                      Icons.verified_user,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                if (!isAi) ...[
                  Text(
                    'Contact',
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
                      child: const Text(
                        'This is your responder profile view.',
                      ),
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
                            label: const Text('Call'),
                          ),
                        ),
                        SizedBox(
                          width: 160,
                          child: OutlinedButton.icon(
                            onPressed: () => _messageResponder(context),
                            icon: const Icon(Icons.message),
                            label: const Text('Message'),
                          ),
                        ),
                      ],
                    ),
                ],
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Community Reviews',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    if (!widget.isCurrentUserProfile && widget.currentUserId != null)
                      TextButton.icon(
                        onPressed: _showReviewAndRatingDialog,
                        icon: const Icon(Icons.add_reaction_outlined),
                        label: const Text('Rate & Review'),
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
                    child: const Text('No reviews yet. Be the first to share your experience!'),
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
                      final name = rev['reviewerName'] as String? ?? 'Anonymous';
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
                                  child: const Text('Edit/Delete'),
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