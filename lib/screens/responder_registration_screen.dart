import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../core/models/responder_model.dart';
import '../core/providers/auth_provider.dart';
import '../core/providers/location_provider.dart';
import '../core/providers/responder_provider.dart';

class ResponderRegistrationScreen extends StatefulWidget {
  const ResponderRegistrationScreen({super.key});

  @override
  State<ResponderRegistrationScreen> createState() =>
      _ResponderRegistrationScreenState();
}

class _ResponderRegistrationScreenState
    extends State<ResponderRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  String _selectedSkill = 'Medical';
  bool _isSubmitting = false;

  static const List<String> _skills = <String>[
    'Medical',
    'Fire',
    'Search & Rescue',
    'Logistics',
    'General Support',
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _submitRegistration() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final authProvider = context.read<AuthProvider>();
    final locationProvider = context.read<LocationProvider>();
    final responderProvider = context.read<ResponderProvider>();

    final currentUser = authProvider.currentUser;
    if (currentUser == null) {
      _showMessage('Please sign in first.');
      return;
    }

    if (!locationProvider.hasLocation) {
      await locationProvider.getCurrentLocation();
    }

    if (!locationProvider.hasLocation) {
      _showMessage('Location is required to register as responder.');
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    final responder = ResponderModel(
      id: const Uuid().v4(),
      userId: currentUser.id,
      name: _nameController.text.trim(),
      phoneNumber: _phoneController.text.trim(),
      skillsArea: _selectedSkill,
      latitude: locationProvider.latitude!,
      longitude: locationProvider.longitude!,
      registeredAt: DateTime.now(),
    );

    await responderProvider.addResponder(responder);
    authProvider.registerAsResponder();

    if (!mounted) {
      return;
    }

    setState(() {
      _isSubmitting = false;
    });

    _showMessage('You are now registered as a responder.');
    Navigator.pop(context);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Responder Registration'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: ListView(
              children: [
                Text(
                  'Join local emergency response',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'Your profile helps RescueLink find and match you during SOS events.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Full Name',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter your name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone Number',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter your phone number';
                    }
                    if (value.trim().length < 8) {
                      return 'Please enter a valid phone number';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _selectedSkill,
                  decoration: const InputDecoration(
                    labelText: 'Primary Skill',
                    border: OutlineInputBorder(),
                  ),
                  items: _skills
                      .map(
                        (skill) => DropdownMenuItem<String>(
                          value: skill,
                          child: Text(skill),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _selectedSkill = value;
                      });
                    }
                  },
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _submitRegistration,
                    child: _isSubmitting
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Register As Responder'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
