import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models/responder_model.dart';
import '../core/providers/auth_provider.dart';
import '../core/providers/location_provider.dart';
import '../core/providers/responder_provider.dart';
import '../core/services/notification_service.dart';

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

  String _selectedSkill = 'Medical Emergency';
  String _responderType = 'Community Volunteer';
  bool _isSubmitting = false;
  PlatformFile? _selectedFile;
  String? _uploadedDocumentUrl;
  bool _isUploadingDocument = false;

  static const List<String> _skills = <String>[
    'Medical Emergency',
    'Fire & Rescue',
    'Search & Rescue',
    'Elderly Assist',
    'Women Safety',
    'Child Safety',
    'Shelter & Evacuation',
    'Food & Water Supply',
    'Essential Medicines',
    'Mobility Support',
    'Communication Relay',
    'Logistics & Transport',
    'General Support',
  ];

  static const List<String> _responderTypes = <String>[
    'Community Volunteer',
    'Medical Professional',
    'Firefighter',
    'Police',
    'Off-duty Authority',
    'Civil Defense',
    'NGO Worker',
    'Logistics Provider',
    'Shelter Host',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _prefillProfile();
    });
  }

  void _prefillProfile() {
    final authProvider = context.read<AuthProvider>();
    final responderProvider = context.read<ResponderProvider>();
    final user = authProvider.currentUser;

    if (user == null) {
      return;
    }

    if (_nameController.text.trim().isEmpty && user.displayName.trim().isNotEmpty) {
      _nameController.text = user.displayName;
    }

    final phoneCandidate = user.phoneNumber ?? '';
    if (_phoneController.text.trim().isEmpty && phoneCandidate.trim().isNotEmpty) {
      _phoneController.text = phoneCandidate;
    }

    final existingResponder = responderProvider.responders
        .where((responder) => responder.userId == user.id)
        .toList();
    if (existingResponder.isNotEmpty) {
      final profile = existingResponder.first;
      if (_nameController.text.trim().isEmpty) {
        _nameController.text = profile.name;
      }
      if (_phoneController.text.trim().isEmpty) {
        _phoneController.text = profile.phoneNumber;
      }
      if (_skills.contains(profile.skillsArea)) {
        _selectedSkill = profile.skillsArea;
      }
      if (_responderTypes.contains(profile.responderType)) {
        _responderType = profile.responderType;
      }
      setState(() {});
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _pickIdDocument() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      lockParentWindow: true,
    );

    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _selectedFile = result.files.first;
      });
    }
  }

  Future<void> _uploadIdDocument() async {
    if (_selectedFile == null) {
      _showMessage('Please select a document first');
      return;
    }

    final authProvider = context.read<AuthProvider>();
    final user = authProvider.currentUser;
    if (user == null) {
      _showMessage('Please sign in first');
      return;
    }

    setState(() {
      _isUploadingDocument = true;
    });

    try {
      final file = File(_selectedFile!.path!);
      final fileExtension = _selectedFile!.name.split('.').last;
      final fileName = '${user.id}_id_document_${DateTime.now().millisecondsSinceEpoch}.$fileExtension';
      final storageRef = FirebaseStorage.instance.ref().child('responder_documents/$fileName');

      await storageRef.putFile(file);
      final url = await storageRef.getDownloadURL();

      setState(() {
        _uploadedDocumentUrl = url;
        _selectedFile = null;
      });

      if (mounted) {
        _showMessage('Document uploaded successfully');
      }
    } catch (e) {
      if (mounted) {
        _showMessage('Failed to upload document: ${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingDocument = false;
        });
      }
    }
  }

  void _clearDocument() {
    setState(() {
      _selectedFile = null;
      _uploadedDocumentUrl = null;
    });
  }

  Future<void> _submitRegistration() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final authProvider = context.read<AuthProvider>();
      final locationProvider = context.read<LocationProvider>();
      final responderProvider = context.read<ResponderProvider>();

      final currentUser = authProvider.currentUser;
      if (currentUser == null) {
        _showMessage('Please sign in first.');
        return;
      }

      if (!locationProvider.hasLocation) {
        _showMessage('Getting your location...');
        await locationProvider.getCurrentLocation();
      }

      if (!locationProvider.hasLocation) {
        _showMessage('Location is required to register as responder.');
        return;
      }

      final responder = ResponderModel(
        id: currentUser.id,
        userId: currentUser.id,
        name: _nameController.text.trim(),
        phoneNumber: _phoneController.text.trim(),
        skillsArea: _selectedSkill,
        responderType: _responderType,
        verificationLevel: 'Self-declared',
        latitude: locationProvider.latitude!,
        longitude: locationProvider.longitude!,
        registeredAt: DateTime.now(),
        idDocumentUrl: _uploadedDocumentUrl,
        idDocumentFileName: _selectedFile?.name,
      );

      await responderProvider.addResponder(responder);
      authProvider.registerAsResponder();
      await NotificationService.syncDeviceProfile(
        userId: currentUser.id,
        isResponder: true,
        isAvailable: true,
        skill: responder.skillsArea,
        responderType: responder.responderType,
      );

      if (!mounted) {
        return;
      }

      _showMessage('You are now registered as a responder.');
      Navigator.pop(context);
    } catch (e) {
      _showMessage('Registration error: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
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
                const SizedBox(height: 8),
                Text(
                  'Name and phone are prefilled from your login profile. Add your responder profile so AI can route requests better during crisis and daily care.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'Verification is self-declared for now. Admin review can be added later without slowing down registration.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey[700],
                      ),
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
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _responderType,
                  decoration: const InputDecoration(
                    labelText: 'Responder Type',
                    border: OutlineInputBorder(),
                  ),
                  items: _responderTypes
                      .map(
                        (type) => DropdownMenuItem<String>(
                          value: type,
                          child: Text(type),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _responderType = value;
                      });
                    }
                  },
                ),
                const SizedBox(height: 20),
                // ID Document Upload Section
                Text(
                  'ID Document Upload (Optional)',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Upload your official ID (Passport, Driver License, or National ID) for verification. Accepted formats: PDF, JPG, PNG',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey[600],
                      ),
                ),
                const SizedBox(height: 12),
                if (_uploadedDocumentUrl != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      border: Border.all(color: Colors.green),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle, color: Colors.green),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Document uploaded successfully'),
                              Text(
                                _selectedFile?.name ?? 'ID Document',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: _clearDocument,
                        ),
                      ],
                    ),
                  ),
                ] else if (_selectedFile != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      border: Border.all(color: Colors.blue),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.description, color: Colors.blue),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _selectedFile!.name,
                                style: Theme.of(context).textTheme.bodyMedium,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed:
                                _isUploadingDocument ? null : _uploadIdDocument,
                            icon: _isUploadingDocument
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(Icons.cloud_upload),
                            label: Text(
                              _isUploadingDocument ? 'Uploading...' : 'Upload',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _pickIdDocument,
                      icon: const Icon(Icons.attach_file),
                      label: const Text('Select ID Document'),
                    ),
                  ),
                ],
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
