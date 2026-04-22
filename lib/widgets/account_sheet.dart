import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/providers/app_settings_provider.dart';
import '../core/providers/auth_provider.dart';

Future<void> showAccountSheet(
  BuildContext context, {
  Future<void> Function()? onLogin,
  Future<void> Function()? onLogout,
  VoidCallback? onOpenResponderRequests,
  bool? isResponderAvailable,
  ValueChanged<bool>? onToggleAvailability,
  Future<void> Function()? onDeregisterResponder,
}) {
  final authProvider = context.read<AuthProvider>();
  final user = authProvider.currentUser;
  final settings = context.read<AppSettingsProvider>();

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: true,
    enableDrag: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) {
      if (user == null) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                alignment: Alignment.center,
                child: Container(
                  height: 4,
                  width: 40,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              Text(
                settings.t('status_not_signed_in'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text(
                settings.t('status_please_sign_in'),
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 20),
              if (onLogin != null)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      Navigator.of(sheetContext).pop();
                      await onLogin();
                    },
                    icon: const Icon(Icons.login),
                    label: Text(settings.t('account_signin_create')),
                  ),
                ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  child: Text(settings.t('button_close')),
                ),
              ),
            ],
          ),
        );
      }

      final displayName = settings.localizedDisplayName(user.displayName);
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Align(
              alignment: Alignment.center,
              child: Container(
                height: 4,
                width: 40,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  child: Text(
                    displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U',
                    style: const TextStyle(fontSize: 20),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        user.email.isEmpty
                            ? (user.phoneNumber ?? settings.t('auth_no_email'))
                            : user.email,
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Chip(
              label: Text(
                authProvider.isAnonymousUser
                    ? settings.t('account_anonymous_session')
                    : settings.t('account_registered_account'),
              ),
            ),
            const SizedBox(height: 20),
            Column(
              children: [
                if (authProvider.isAnonymousUser && onLogin != null)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        Navigator.of(sheetContext).pop();
                        await onLogin();
                      },
                      icon: const Icon(Icons.login),
                      label: Text(settings.t('account_signin_create')),
                    ),
                  ),
                if (!authProvider.isAnonymousUser && onLogout != null)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        Navigator.of(sheetContext).pop();
                        await onLogout();
                      },
                      icon: const Icon(Icons.logout),
                      label: Text(settings.t('button_sign_out')),
                    ),
                  ),
                if (user.isResponder && onOpenResponderRequests != null)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        onOpenResponderRequests();
                      },
                      icon: const Icon(Icons.list_alt),
                      label: Text(settings.t('button_people_needing_help')),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (user.isResponder &&
                isResponderAvailable != null &&
                onToggleAvailability != null)
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: Colors.grey.shade300),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: Text(settings.t('label_responder_online')),
                        value: isResponderAvailable,
                        onChanged: onToggleAvailability,
                      ),
                      if (onDeregisterResponder != null)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: () async {
                              Navigator.of(sheetContext).pop();
                              await onDeregisterResponder();
                            },
                            child: Text(
                              settings.t('responder_deregister'),
                              style: TextStyle(color: Colors.red),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () => Navigator.of(sheetContext).pop(),
                child: Text(settings.t('button_close')),
              ),
            ),
          ],
        ),
      );
    },
  );
}
