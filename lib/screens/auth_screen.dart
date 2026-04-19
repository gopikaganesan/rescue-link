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
      builder: (sheetContext) {
        return Consumer<AppSettingsProvider>(
          builder: (context, settings, _) {
            return ListView(
              shrinkWrap: true,
              children: [
                ListTile(
                  title: Text(settings.t('home_select_language')),
                  subtitle: Text(settings.t('home_choose_preferred_language')),
                ),
                SwitchListTile.adaptive(
                  value: settings.showAllLanguages,
                  onChanged: settings.setShowAllLanguages,
                  title: Text(settings.t('home_show_all_languages')),
                  subtitle: Text(settings.t('home_show_all_languages_hint')),
                ),
                ...settings.availableLanguageCodes.map(
                  (code) => RadioListTile<String>(
                    value: code,
                    title: Text(settings.languageLabel(code)),
                    onChanged: (value) {
                      if (value != null) {
                        settings.setLanguage(value);
                      }
                      Navigator.of(sheetContext).pop();
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettingsProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(settings.t('sign_in_title')),
        actions: [
          IconButton(
            icon: const Icon(Icons.language),
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
                child: ListView(
                  children: [
                    Text(
                      _isRegisterMode
                          ? settings.t('auth_create_account_prompt')
                          : settings.t('auth_sign_in_title'),
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 16),
                    if (_isRegisterMode)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          children: [
                            TextFormField(
                              controller: _displayNameController,
                              decoration: InputDecoration(
                                labelText: settings.t('auth_display_name'),
                                hintText: settings.t('auth_display_name'),
                                border: OutlineInputBorder(),
                              ),
                              validator: (value) {
                                if (_isRegisterMode &&
                                    (value == null || value.trim().isEmpty)) {
                                  return settings.t('auth_enter_display_name');
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _phoneController,
                              keyboardType: TextInputType.phone,
                              decoration: InputDecoration(
                                labelText: settings.t('auth_phone_number'),
                                hintText: settings.t('auth_phone_number'),
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    TextFormField(
                      controller: _emailController,
                      decoration: InputDecoration(
                        labelText: settings.t('auth_email'),
                        hintText: settings.t('auth_email'),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return settings.t('auth_enter_email');
                        }
                        if (!value.contains('@')) {
                          return settings.t('auth_enter_valid_email');
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _passwordController,
                      decoration: InputDecoration(
                        labelText: settings.t('auth_password'),
                        hintText: settings.t('auth_password'),
                        border: OutlineInputBorder(),
                      ),
                      obscureText: true,
                      validator: (value) {
                        if (value == null || value.length < 6) {
                          return settings.t('auth_password_min_length');
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        onPressed: authProvider.isLoading ? null : _submit,
                        child: authProvider.isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(_isRegisterMode
                                ? settings.t('create_account')
                                : settings.t('sign_in')),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: authProvider.isLoading
                          ? null
                          : () {
                              setState(() {
                                _isRegisterMode = !_isRegisterMode;
                              });
                            },
                      child: Text(
                        _isRegisterMode
                            ? settings.t('auth_already_have_account')
                            : settings.t('auth_need_account'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      settings.t('auth_phone_otp_disabled'),
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.grey[700]),
                    ),
                    const Divider(height: 24),
                    if (widget.showGuestButton)
                      OutlinedButton.icon(
                        onPressed: authProvider.isLoading
                            ? null
                            : () async {
                                final success =
                                    await authProvider.ensureAuthenticated();
                                if (!success && mounted && authProvider.error != null) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(authProvider.error!)),
                                  );
                                }
                              },
                        icon: const Icon(Icons.person_outline),
                        label: Text(settings.t('continue_guest')),
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
}
