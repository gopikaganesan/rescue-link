import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/models/responder_model.dart';

class ResponderProfileScreen extends StatelessWidget {
  final ResponderModel responder;
  final double? viewerLatitude;
  final double? viewerLongitude;
  final bool isCurrentUserProfile;

  const ResponderProfileScreen({
    super.key,
    required this.responder,
    this.viewerLatitude,
    this.viewerLongitude,
    this.isCurrentUserProfile = false,
  });

  double? get _distanceKm {
    if (viewerLatitude == null || viewerLongitude == null) {
      return null;
    }

    return responder.distanceToLocation(viewerLatitude!, viewerLongitude!);
  }

  Future<void> _callResponder(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final phone = responder.phoneNumber.trim();
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
    final phone = responder.phoneNumber.trim();
    if (phone.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No messaging number available for this responder.')),
      );
      return;
    }

    final uri = Uri.parse(
      'sms:$phone?body=${Uri.encodeComponent('Hi ${responder.name}, this is RescueLink. An SOS request may need your help.')}',
    );

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
      return;
    }

    messenger.showSnackBar(
      const SnackBar(content: Text('Messaging is not supported on this device yet.')),
    );
  }

  Widget _infoTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 4),
                Text(value, style: Theme.of(context).textTheme.titleSmall),
              ],
            ),
          ),
        ],
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
    final distance = _distanceKm;
    final verificationText = responder.verifiedResponder
        ? 'Verified responder'
        : 'Not verified yet';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isCurrentUserProfile ? 'My Responder Profile' : 'Responder Profile',
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.red.shade700, Colors.red.shade400],
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
                        child: Text(
                          responder.name.trim().isEmpty
                              ? '?'
                              : responder.name.trim()[0].toUpperCase(),
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
                              responder.name,
                              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              responder.responderType,
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
                        label: Text(responder.skillsArea),
                        backgroundColor: Colors.white,
                      ),
                      Chip(
                        label: Text(verificationText),
                        backgroundColor: responder.verifiedResponder
                            ? Colors.green.shade50
                            : Colors.orange.shade50,
                      ),
                      Chip(
                        label: Text(
                          responder.isAvailable ? 'Available now' : 'Currently offline',
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
                  responder.rescueCount.toString(),
                  Icons.emoji_people,
                ),
                const SizedBox(width: 12),
                _statCard(
                  context,
                  'Rating',
                  responder.ratingCount == 0
                      ? 'N/A'
                      : responder.averageRating.toStringAsFixed(1),
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
                  responder.ratingCount.toString(),
                  Icons.reviews,
                ),
                const SizedBox(width: 12),
                _statCard(
                  context,
                  'Verification',
                  responder.verifiedResponder ? 'Verified' : 'Pending',
                  Icons.verified_user,
                ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.grey.shade300),
                color: Colors.white,
              ),
              child: Column(
                children: [
                  _infoTile(
                    context: context,
                    icon: Icons.support_agent,
                    title: 'Responder type',
                    value: responder.responderType,
                  ),
                  const SizedBox(height: 12),
                  _infoTile(
                    context: context,
                    icon: Icons.handshake,
                    title: 'Verification level',
                    value: responder.verificationLevel,
                  ),
                  const SizedBox(height: 12),
                  _infoTile(
                    context: context,
                    icon: Icons.phone,
                    title: 'Phone number',
                    value: responder.phoneNumber.isEmpty
                        ? 'Not shared'
                        : responder.phoneNumber,
                  ),
                  const SizedBox(height: 12),
                  _infoTile(
                    context: context,
                    icon: Icons.calendar_month,
                    title: 'Responder since',
                    value: MaterialLocalizations.of(context)
                        .formatMediumDate(responder.registeredAt),
                  ),
                  if (distance != null) ...[
                    const SizedBox(height: 12),
                    _infoTile(
                      context: context,
                      icon: Icons.place,
                      title: 'Distance from you',
                      value: '${distance.toStringAsFixed(1)} km away',
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Contact',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 12),
            if (isCurrentUserProfile)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Text(
                  'You are viewing your own responder profile. Call and message actions are kept here for the emergency flow and can be connected to the future in-app messaging service later.',
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
            const SizedBox(height: 18),
            Text(
              'Notes',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Text(
                responder.ratingCount == 0
                    ? 'No rescued-person ratings have been recorded yet.'
                    : 'Ratings are shown as an average from rescued people. Rescue count and verification state are ready for the future backend update.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}