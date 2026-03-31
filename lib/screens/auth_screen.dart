import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/providers/auth_provider.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _displayNameController = TextEditingController();

  bool _isRegisterMode = false;

  @override
  void dispose() {
    _emailController.dispose();
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

    if (!success && authProvider.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(authProvider.error!)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('RescueLink Sign In')),
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
                          ? 'Create account'
                          : 'Sign in to RescueLink',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 16),
                    if (_isRegisterMode)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: TextFormField(
                          controller: _displayNameController,
                          decoration: const InputDecoration(
                            labelText: 'Display Name',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (_isRegisterMode &&
                                (value == null || value.trim().isEmpty)) {
                              return 'Enter your display name';
                            }
                            return null;
                          },
                        ),
                      ),
                    TextFormField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Enter your email';
                        }
                        if (!value.contains('@')) {
                          return 'Enter a valid email';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _passwordController,
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        border: OutlineInputBorder(),
                      ),
                      obscureText: true,
                      validator: (value) {
                        if (value == null || value.length < 6) {
                          return 'Password must be at least 6 characters';
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
                            : Text(_isRegisterMode ? 'Create Account' : 'Sign In'),
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
                            ? 'Already have an account? Sign in'
                            : 'Need an account? Create one',
                      ),
                    ),
                    const Divider(height: 24),
                    OutlinedButton.icon(
                      onPressed: authProvider.isLoading
                          ? null
                          : () => authProvider.ensureAuthenticated(),
                      icon: const Icon(Icons.person_outline),
                      label: const Text('Continue as Guest (Anonymous)'),
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
