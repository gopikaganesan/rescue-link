import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/providers/app_settings_provider.dart';
import '../core/providers/auth_provider.dart';

class AuthScreen extends StatefulWidget {
  final bool showGuestButton;

  const AuthScreen({
    super.key,
    this.showGuestButton = true,
  });

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _displayNameController = TextEditingController();

  bool _isRegisterMode = false;

  @override
  void dispose() {
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final authProvider = context.read<AuthProvider>();
    bool success;

    if (_isRegisterMode) {
      success = await authProvider.register(
        _emailController.text.trim(),
        _displayNameController.text.trim(),
        _passwordController.text.trim(),
        phoneNumber: _phoneController.text.trim(),
      );
    } else {
      success = await authProvider.login(
        _emailController.text.trim(),
        _passwordController.text.trim(),
      );
    }

    if (!mounted) {
      return;
    }

    if (success) {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      return;
    }

    if (!success && authProvider.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(authProvider.error!)),
      );
    }
  }

void _showLanguagePicker() {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      return Consumer<AppSettingsProvider>(
        builder: (context, settings, _) {
          return Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                /// Drag Handle
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade400,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),

                /// Header
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    settings.t('home_select_language'),
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    settings.t('home_choose_preferred_language'),
                    style: TextStyle(color: Colors.red[600]),
                  ),
                ),

                const SizedBox(height: 8),

                /// Switch
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: settings.showAllLanguages,
                  onChanged: settings.setShowAllLanguages,
                  title: Text(
                    settings.t('home_show_all_languages'),
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text(
                    settings.t('home_show_all_languages_hint'),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.red[600],
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                /// Language List (Modern Cards)
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: settings.availableLanguageCodes.map((code) {
                      final isSelected =
                          settings.languageCode == code;

                      return GestureDetector(
                        onTap: () {
                          settings.setLanguage(code);
                          Navigator.of(sheetContext).pop();
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin:
                              const EdgeInsets.symmetric(vertical: 6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.grey[100]
                                : Colors.transparent,
                            borderRadius:
                                BorderRadius.circular(14),
                            border: Border.all(
                              color: isSelected
                                  ? Colors.red
                                  : Colors.red.shade300,
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  settings.languageLabel(code),
                                  style: TextStyle(
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                              if (isSelected)
                                Icon(
                                  Icons.check_circle,
                                  color: Colors.red,
                                ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}


  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettingsProvider>();

    return  Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.language),
            color: Colors.black,
            onPressed: _showLanguagePicker,
            tooltip: settings.t('language'),
          ),
        ],
      ),
      body: SafeArea(
  child: Padding(
    padding: const EdgeInsets.all(16),
    child: Consumer<AuthProvider>(
      builder: (context, authProvider, _) {
        return Form(
          key: _formKey,
          child: Column(
            children: [
              Align(
                alignment: Alignment.center,
                child: Text(
                  _isRegisterMode
                      ? settings.t('auth_create_account_prompt')
                      : settings.t('auth_sign_in_title'),
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),

              const SizedBox(height: 20),

              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      /// Card Container
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color:
                              Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            )
                          ],
                        ),
                        child: Column(
                          children: [
                            if (_isRegisterMode) ...[
                              _modernField(
                                controller: _displayNameController,
                                label: settings.t('auth_display_name'),
                                icon: Icons.person_outline,
                                validator: (value) {
                                  if (value == null ||
                                      value.trim().isEmpty) {
                                    return settings.t(
                                        'auth_enter_display_name');
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 12),
                              _modernField(
                                controller: _phoneController,
                                label: settings.t('auth_phone_number'),
                                icon: Icons.phone_outlined,
                                keyboard: TextInputType.phone,
                              ),
                              const SizedBox(height: 12),
                            ],

                            _modernField(
                              controller: _emailController,
                              label: settings.t('auth_email'),
                              icon: Icons.email_outlined,
                              keyboard: TextInputType.emailAddress,
                              validator: (value) {
                                if (value == null ||
                                    value.trim().isEmpty) {
                                  return settings.t(
                                      'auth_enter_email');
                                }
                                if (!value.contains('@')) {
                                  return settings.t(
                                      'auth_enter_valid_email');
                                }
                                return null;
                              },
                            ),

                            const SizedBox(height: 12),

                            _modernField(
                              controller: _passwordController,
                              label: settings.t('auth_password'),
                              icon: Icons.lock_outline,
                              obscure: true,
                              validator: (value) {
                                if (value == null ||
                                    value.length < 6) {
                                  return settings.t(
                                      'auth_password_min_length');
                                }
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      /// BUTTON
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(16),
                            ),
                          ),
                          onPressed: authProvider.isLoading
                              ? null
                              : _submit,
                          child: authProvider.isLoading
                              ? const SizedBox(
                                  height: 22,
                                  width: 22,
                                  child:
                                      CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white),
                                )
                              : Text(
                                  _isRegisterMode
                                      ? settings.t(
                                          'create_account')
                                      : settings.t('sign_in'),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      /// TOGGLE
                      TextButton(
                        onPressed: authProvider.isLoading
                            ? null
                            : () {
                                setState(() {
                                  _isRegisterMode =
                                      !_isRegisterMode;
                                });
                              },
                        child: Text(
                          _isRegisterMode
                              ? settings.t(
                                  'auth_already_have_account')
                              : settings.t(
                                  'auth_need_account'),
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              /// 🔻 BOTTOM — EXTRA INFO + GUEST
              Column(
                children: [
                  Text(
                    settings.t('auth_phone_otp_disabled'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.grey[400]),
                  ),

                  const SizedBox(height: 12),

                  if (widget.showGuestButton)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding:
                            const EdgeInsets.all(14),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(14),
                        ),
                        side:
                            const BorderSide(color: Colors.red),
                      ),
                      onPressed: authProvider.isLoading
                          ? null
                          : () async {
                              final messenger =
                                  ScaffoldMessenger.of(context);
                              final success =
                                  await authProvider
                                      .ensureAuthenticated();

                              if (!mounted) return;

                              if (!success &&
                                  authProvider.error != null) {
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text(
                                        authProvider.error!),
                                  ),
                                );
                              }
                            },
                      icon: const Icon(Icons.person_outline,
                          color: Colors.red),
                      label: Text(
                        settings.t('continue_guest'),
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    ),
  ),
),


    );
  }

  Widget _modernField({
  required TextEditingController controller,
  required String label,
  required IconData icon,
  TextInputType keyboard = TextInputType.text,
  bool obscure = false,
  String? Function(String?)? validator,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.all(8.0),
        child: Text(label,style: TextStyle(
          fontSize: 12,
          color: Colors.red,
          fontWeight: FontWeight.bold,
        ),),
      ),
      TextFormField(
    controller: controller,
    keyboardType: keyboard,
    obscureText: obscure,
    validator: validator,
    decoration: InputDecoration(
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: Colors.grey.shade100,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: Colors.grey,
        ),
      ),
    ),
  )]);
}

}
