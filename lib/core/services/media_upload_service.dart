import 'dart:convert';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

class MediaUploadService {
  final String _provider;
  final String _cloudinaryCloudName;
  final String _cloudinaryUploadPreset;

  MediaUploadService._(
    this._provider,
    this._cloudinaryCloudName,
    this._cloudinaryUploadPreset,
  );

  factory MediaUploadService.fromEnvironment() {
    return MediaUploadService._(
      const String.fromEnvironment('MEDIA_UPLOAD_PROVIDER', defaultValue: 'firebase')
          .trim()
          .toLowerCase(),
      const String.fromEnvironment('CLOUDINARY_CLOUD_NAME', defaultValue: '').trim(),
      const String.fromEnvironment('CLOUDINARY_UPLOAD_PRESET', defaultValue: '').trim(),
    );
  }

  Future<String?> uploadEmergencyImage({
    required XFile image,
    required String userId,
  }) async {
    switch (_provider) {
      case 'cloudinary':
        return _uploadToCloudinary(
          file: image,
          folder: 'emergency_attachments/$userId',
          fallbackPublicIdPrefix: userId,
        );
      case 'firebase':
      default:
        return _uploadImageToFirebase(image: image, userId: userId);
    }
  }

  Future<String?> uploadEmergencyVoice({
    required String localPath,
    required String userId,
  }) async {
    final audioFile = XFile(localPath);
    switch (_provider) {
      case 'cloudinary':
        return _uploadToCloudinary(
          file: audioFile,
          folder: 'emergency_voice/$userId',
          fallbackPublicIdPrefix: userId,
        );
      case 'firebase':
      default:
        return _uploadVoiceToFirebase(localPath: localPath, userId: userId);
    }
  }

  Future<String?> _uploadImageToFirebase({
    required XFile image,
    required String userId,
  }) async {
    final bytes = await image.readAsBytes();
    final safeName = image.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final fileName = '${userId}_${DateTime.now().millisecondsSinceEpoch}_$safeName';
    final storageRef = FirebaseStorage.instance.ref().child('emergency_attachments/$userId/$fileName');
    final metadata = SettableMetadata(contentType: _contentTypeForName(image.name));

    await storageRef.putData(bytes, metadata);
    return storageRef.getDownloadURL();
  }

  Future<String?> _uploadVoiceToFirebase({
    required String localPath,
    required String userId,
  }) async {
    final storageRef = FirebaseStorage.instance
        .ref()
        .child('emergency_voice/$userId/${DateTime.now().millisecondsSinceEpoch}.wav');
    final metadata = SettableMetadata(contentType: 'audio/wav');

    final bytes = await XFile(localPath).readAsBytes();
    await storageRef.putData(bytes, metadata);
    return storageRef.getDownloadURL();
  }

  Future<String?> _uploadToCloudinary({
    required XFile file,
    required String folder,
    required String fallbackPublicIdPrefix,
  }) async {
    if (_cloudinaryCloudName.isEmpty || _cloudinaryUploadPreset.isEmpty) {
      throw Exception(
        'Cloudinary is selected but CLOUDINARY_CLOUD_NAME or CLOUDINARY_UPLOAD_PRESET is missing.',
      );
    }

    final uri = Uri.parse('https://api.cloudinary.com/v1_1/$_cloudinaryCloudName/auto/upload');
    final request = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = _cloudinaryUploadPreset
      ..fields['folder'] = folder
      ..fields['public_id_prefix'] = fallbackPublicIdPrefix
      ..files.add(await http.MultipartFile.fromPath('file', file.path));

    final streamed = await request.send();
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      throw Exception('Cloudinary upload failed (${streamed.statusCode}): $body');
    }

    final json = jsonDecode(body) as Map<String, dynamic>;
    final secureUrl = (json['secure_url'] as String?)?.trim();
    if (secureUrl == null || secureUrl.isEmpty) {
      throw Exception('Cloudinary upload succeeded but secure_url is missing.');
    }
    return secureUrl;
  }

  String _contentTypeForName(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) {
      return 'image/png';
    }
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    return 'image/jpeg';
  }
}
