import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';

class TranscriptionResult {
  final String transcript;
  final double confidence;
  final String provider;

  const TranscriptionResult({
    required this.transcript,
    required this.confidence,
    required this.provider,
  });
}

class TranscriptionService {
  final FirebaseFunctions _functions;
  final bool _cloudEnabled =
      const String.fromEnvironment('USE_CLOUD_TRANSCRIPTION', defaultValue: 'false') ==
          'true';

  TranscriptionService({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  Future<TranscriptionResult?> transcribeWithCloud({
    required Uint8List audioBytes,
    required String languageCode,
    List<String> alternativeLanguageCodes = const <String>[],
  }) async {
    if (!_cloudEnabled) {
      return null;
    }

    try {
      final callable = _functions.httpsCallable('transcribeEmergencyAudio');
      final response = await callable.call(<String, dynamic>{
        'audioBase64': base64Encode(audioBytes),
        'languageCode': languageCode,
        'alternativeLanguageCodes': alternativeLanguageCodes,
      });

      final data = Map<String, dynamic>.from(response.data as Map);
      final transcript = (data['transcript'] ?? '').toString().trim();
      final confidenceRaw = data['confidence'];
      final confidence = confidenceRaw is num
          ? confidenceRaw.toDouble().clamp(0.0, 1.0)
          : 0.0;

      if (transcript.isEmpty) {
        return null;
      }

      return TranscriptionResult(
        transcript: transcript,
        confidence: confidence,
        provider: 'Google Cloud Speech',
      );
    } catch (_) {
      return null;
    }
  }
}
