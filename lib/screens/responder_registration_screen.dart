import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/models/responder_model.dart';
import '../core/providers/app_settings_provider.dart';
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

  static const Map<String, String> _skillTranslationKeys = {
    'Medical Emergency': 'responder_skill_medical_emergency',
    'Fire & Rescue': 'responder_skill_fire_and_rescue',
    'Search & Rescue': 'responder_skill_search_and_rescue',
    'Elderly Assist': 'responder_skill_elderly_assist',
    'Women Safety': 'responder_skill_women_safety',
    'Child Safety': 'responder_skill_child_safety',
    'Shelter & Evacuation': 'responder_skill_shelter_and_evacuation',
    'Food & Water Supply': 'responder_skill_food_and_water_supply',
    'Essential Medicines': 'responder_skill_essential_medicines',
    'Mobility Support': 'responder_skill_mobility_support',
    'Communication Relay': 'responder_skill_communication_relay',
    'Logistics & Transport': 'responder_skill_logistics_and_transport',
    'General Support': 'responder_skill_general_support',
  };

  static const Map<String, String> _typeTranslationKeys = {
    'Community Volunteer': 'responder_type_community_volunteer',
    'Medical Professional': 'responder_type_medical_professional',
    'Firefighter': 'responder_type_firefighter',
    'Police': 'responder_type_police',
    'Off-duty Authority': 'responder_type_off_duty_authority',
    'Civil Defense': 'responder_type_civil_defense',
    'NGO Worker': 'responder_type_ngo_worker',
    'Logistics Provider': 'responder_type_logistics_provider',
    'Shelter Host': 'responder_type_shelter_host',
  };

  String _skillLabel(BuildContext context, String skill) {
    return context.read<AppSettingsProvider>().t(_skillTranslationKeys[skill] ?? skill);
  }

  String _responderTypeLabel(BuildContext context, String type) {
    return context.read<AppSettingsProvider>().t(_typeTranslationKeys[type] ?? type);
  }

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
    final settings = context.read<AppSettingsProvider>();

    if (_selectedFile == null) {
      _showMessage(settings.t('prompt_select_document_first'));
      return;
    }

    final authProvider = context.read<AuthProvider>();
    final user = authProvider.currentUser;
    if (user == null) {
      _showMessage(settings.t('prompt_sign_in_first'));
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
        _showMessage(settings.t('document_uploaded_successfully'));
      }
    } catch (e) {
      if (mounted) {
        final errorText = settings.t('error_document_upload_failed').replaceAll('{error}', e.toString());
        _showMessage(errorText);
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

    final settings = context.read<AppSettingsProvider>();
    final authProvider = context.read<AuthProvider>();
    final locationProvider = context.read<LocationProvider>();
    final responderProvider = context.read<ResponderProvider>();

    setState(() {
      _isSubmitting = true;
    });

    try {
      final currentUser = authProvider.currentUser;
      if (currentUser == null) {
        _showMessage(settings.t('prompt_sign_in_first'));
        return;
      }

      if (!locationProvider.hasLocation) {
        _showMessage(settings.t('prompt_getting_location'));
        await locationProvider.getCurrentLocation();
      }

      if (!locationProvider.hasLocation) {
        _showMessage(settings.t('prompt_location_required'));
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

      _showMessage(context.read<AppSettingsProvider>().t('snackbar_responder_registered'));
      Navigator.pop(context);
    } catch (e) {
      final errorText = context.read<AppSettingsProvider>().t('error_registration').replaceAll('{error}', e.toString());
      _showMessage(errorText);
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
    final settings = context.read<AppSettingsProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(settings.t('title_responder_registration')),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: ListView(
              children: [
                Text(
                  settings.t('responder_registration_headline'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  settings.t('responder_registration_description'),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  settings.t('responder_registration_profile_help'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Text(
                  settings.t('responder_registration_verification_note'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey[700],
                      ),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: settings.t('label_full_name'),
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return settings.t('error_please_enter_name');
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: settings.t('label_phone_number'),
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return settings.t('error_please_enter_phone');
                    }
                    if (value.trim().length < 8) {
                      return settings.t('error_valid_phone_number');
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _selectedSkill,
                  decoration: InputDecoration(
                    labelText: settings.t('label_primary_skill'),
                    border: const OutlineInputBorder(),
                  ),
                  items: _skills
                      .map(
                        (skill) => DropdownMenuItem<String>(
                          value: skill,
                          child: Text(_skillLabel(context, skill)),
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
                  decoration: InputDecoration(
                    labelText: settings.t('label_responder_type'),
                    border: const OutlineInputBorder(),
                  ),
                  items: _responderTypes
                      .map(
                        (type) => DropdownMenuItem<String>(
                          value: type,
                          child: Text(_responderTypeLabel(context, type)),
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
                  settings.t('label_id_upload'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  settings.t('responder_registration_id_description'),
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
                              Text(settings.t('document_uploaded_successfully')),
                              Text(
                                _selectedFile?.name ?? settings.t('label_document_name'),
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
                              _isUploadingDocument
                                  ? settings.t('status_uploading')
                                  : settings.t('button_upload'),
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
                      label: Text(settings.t('button_select_document')),
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
                        : Text(settings.t('button_responder_register')),
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
