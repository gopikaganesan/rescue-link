import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:google_phone_number_hint/google_phone_number_hint.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:intl_phone_field/phone_number.dart';
import '../core/services/media_upload_service.dart';
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

  String _selectedSkill = 'General Support';
  String _responderType = 'Community Volunteer';
  bool _isSubmitting = false;
  PlatformFile? _selectedFile;
  XFile? _selectedXFile;
  String? _uploadedDocumentUrl;
  bool _isUploadingDocument = false;
  bool _isInfoExpanded = false;

  static const List<String> _skills = <String>[
    
    'Food & Water Supply',
    'Essential Medicines',
    'General Support',
    'Medical Emergency',
    'Fire & Rescue',
    'Search & Rescue',
    'Elderly Assist',
    'Women Safety',
    'Child Safety',
    'Shelter & Evacuation',
    'Mobility Support',
    'Communication Relay',
    'Logistics & Transport',
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

  String _stripCountryCode(String number) {
    var clean = number.trim().replaceAll(' ', '').replaceAll('-', '');
    if (clean.startsWith('+91')) {
      return clean.substring(3);
    }
    if (clean.startsWith('0')) {
      return clean.substring(1);
    }
    return clean;
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
      _phoneController.text = _stripCountryCode(phoneCandidate);
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
        _phoneController.text = _stripCountryCode(profile.phoneNumber);
      }
      if (_skills.contains(profile.skillsArea)) {
        _selectedSkill = profile.skillsArea;
      }
      if (_responderTypes.contains(profile.responderType)) {
        _responderType = profile.responderType;
      }
    }

    if (_phoneController.text.trim().isEmpty) {
      _requestPhoneNumberHint();
    }
    setState(() {});
  }

  Future<void> _requestPhoneNumberHint() async {
    if (!mounted) return;
    try {
      final number = await GooglePhoneNumberHint().getMobileNumber();
      if (number != null && mounted && _phoneController.text.trim().isEmpty) {
        setState(() {
          _phoneController.text = _stripCountryCode(number);
        });
      }
    } catch (e) {
      debugPrint('Failed to get phone number hint: $e');
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
      withData: true,
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _selectedFile = result.files.first;
        if (_selectedFile != null && _selectedFile!.extension != 'pdf') {
          _selectedXFile = XFile.fromData(_selectedFile!.bytes!, name: _selectedFile!.name);
        } else {
          _selectedXFile = null;
        }
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
      String? url;
      if (_selectedXFile != null) {
        // Use MediaUploadService for images
        final mediaService = MediaUploadService.fromEnvironment();
        url = await mediaService.uploadEmergencyImage(image: _selectedXFile!, userId: user.id);
      } else if (_selectedFile != null && _selectedFile!.extension == 'pdf') {
        // For PDFs, fallback to Firebase Storage
        final file = File(_selectedFile!.path!);
        final fileExtension = _selectedFile!.name.split('.').last;
        final fileName = '${user.id}_id_document_${DateTime.now().millisecondsSinceEpoch}.$fileExtension';
        final storageRef = FirebaseStorage.instance.ref().child('responder_documents/$fileName');
        await storageRef.putFile(file);
        url = await storageRef.getDownloadURL();
      }
      setState(() {
        _uploadedDocumentUrl = url;
        _selectedFile = null;
        _selectedXFile = null;
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
      _selectedXFile = null;
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
    padding: const EdgeInsets.all(16),
    children: [

      Container(
  decoration: BoxDecoration(
    color: Colors.red.shade50,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: Colors.red.shade100),
  ),
  child: Column(
    children: [

      InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          setState(() {
            _isInfoExpanded = !_isInfoExpanded;
          });
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [

              // 🔹 Info Icon
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade100,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.info_outline,
                  size: 20,
                  color: Colors.red,
                ),
              ),

              const SizedBox(width: 12),

              // 🔹 Title
              Expanded(
                child: Text(
                  settings.t('responder_registration_headline'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),

              // 🔹 Arrow
              AnimatedRotation(
                turns: _isInfoExpanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 200),
                child: const Icon(Icons.keyboard_arrow_down),
              ),
            ],
          ),
        ),
      ),

      // 🔽 Expandable Content
      AnimatedCrossFade(
        duration: const Duration(milliseconds: 250),
        crossFadeState: _isInfoExpanded
            ? CrossFadeState.showFirst
            : CrossFadeState.showSecond,
        firstChild: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(settings.t('responder_registration_description')),
              const SizedBox(height: 6),
              Text(
                settings.t('responder_registration_profile_help'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 6),
              Text(
                settings.t('responder_registration_verification_note'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey[700],
                    ),
              ),
            ],
          ),
        ),
        secondChild: const SizedBox.shrink(),
      ),
    ],
  ),
),


      const SizedBox(height: 24),

      // 🔹 Name Field
      Padding(
        padding:EdgeInsets.only(bottom: 2,left: 10),
        child:Text(settings.t('label_full_name'),style: TextStyle(fontWeight: FontWeight.bold,color: Colors.red[300]),)
      ),
      TextFormField(
        controller: _nameController,
        decoration: InputDecoration(
          filled: true,
          fillColor: Colors.grey.shade100,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return settings.t('error_please_enter_name');
          }
          return null;
        },
      ),

      const SizedBox(height: 16),
      Padding(
        padding:EdgeInsets.only(bottom: 2,left: 10),
        child:Text(settings.t('label_phone_number'),style: TextStyle(fontWeight: FontWeight.bold,color: Colors.red[300]),)
      ),
      // 🔹 Phone Field
      Row(
        children: [
          Expanded(
            child: IntlPhoneField(
              controller: _phoneController,
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
              initialCountryCode: 'IN', // Default to India or handle via location
              onChanged: (PhoneNumber phone) {
                // _phoneController.text handles the rest, but you can capture phone.completeNumber if needed
              },
              validator: (value) {
                if (value == null || _phoneController.text.trim().isEmpty) {
                  return settings.t('error_please_enter_phone');
                }
                if (_phoneController.text.trim().length < 8) {
                  return settings.t('error_valid_phone_number');
                }
                return null;
              },
            ),
          ),
        ],
      ),

      const SizedBox(height: 16),
      Padding(
        padding:EdgeInsets.only(bottom: 2,left: 10),
        child:Text(settings.t('label_primary_skill'),style: TextStyle(fontWeight: FontWeight.bold,color: Colors.red[300]),)
      ),
      // 🔹 Skill Dropdown
      DropdownButtonFormField<String>(
  isExpanded: true,
  value: _selectedSkill,
  decoration: InputDecoration(
    filled: true,
    fillColor: Colors.grey.shade100,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide.none,
    ),
  ),
  items: _skills.map((skill) {
    return DropdownMenuItem<String>(
      value: skill,
      child: Text(
        _skillLabel(context, skill),
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      ),
    );
  }).toList(),
  onChanged: (value) {
    if (value != null) {
      setState(() => _selectedSkill = value);
    }
  },
),

      const SizedBox(height: 16),
      Padding(
        padding:EdgeInsets.only(bottom: 2,left: 10),
        child:Text(settings.t('label_responder_type'),style: TextStyle(fontWeight: FontWeight.bold,color: Colors.red[300]),)
      ),
      // 🔹 Responder Type
     DropdownButtonFormField<String>(
  isExpanded: true, 
  value: _responderType,
  decoration: InputDecoration(
    filled: true,
    fillColor: Colors.grey.shade100,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide.none,
    ),
  ),
  items: _responderTypes.map((type) {
    return DropdownMenuItem<String>(
      value: type,
      child: Text(
        _responderTypeLabel(context, type),
        overflow: TextOverflow.ellipsis, // ✅ prevents overflow
        maxLines: 1,
      ),
    );
  }).toList(),
  onChanged: (value) {
    if (value != null) {
      setState(() => _responderType = value);
    }
  },
),

      const SizedBox(height: 24),

      // 🔹 Upload Section (Modern Card)
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Colors.grey.shade50,
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              settings.t('label_id_upload'),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              settings.t('responder_registration_id_description'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),

            if (_uploadedDocumentUrl != null)
              Row(
                children: [
                  const Icon(Icons.verified, color: Colors.green),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _selectedFile?.name ?? settings.t('label_document_name'),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _clearDocument,
                  )
                ],
              )
            else if (_selectedFile != null)
              Row(
                children: [
                  if (_selectedXFile != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: Image.memory(
                        _selectedFile!.bytes!,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                      ),
                    )
                  else
                    const Icon(Icons.picture_as_pdf, size: 40, color: Colors.red),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _selectedFile?.name ?? settings.t('label_document_name'),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _clearDocument,
                  )
                ],
              )
            else
              Column(
                children: [
                  OutlinedButton.icon(
                    onPressed: _pickIdDocument,
                    icon: const Icon(Icons.attach_file),
                    label: Text(settings.t('button_select_document')),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: _isUploadingDocument ? null : _uploadIdDocument,
                    icon: _isUploadingDocument
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cloud_upload),
                    label: Text(
                      _isUploadingDocument
                          ? settings.t('status_uploading')
                          : settings.t('button_upload'),
                    ),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),

      const SizedBox(height: 28),

      // 🔹 Submit Button
      SizedBox(
        height: 54,
        child: ElevatedButton(
          onPressed: _isSubmitting ? null : _submitRegistration,
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: _isSubmitting
              ? const CircularProgressIndicator(strokeWidth: 2)
              : Text(
                  settings.t('button_responder_register'),
                  style: const TextStyle(fontSize: 16),
                ),
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
