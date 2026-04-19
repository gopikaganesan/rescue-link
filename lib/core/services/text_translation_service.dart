import 'package:translator/translator.dart';

class TextTranslationService {
  final GoogleTranslator _translator = GoogleTranslator();

  Future<String> translate({
    required String text,
    required String targetLanguageCode,
  }) async {
    final safeText = text.trim();
    final target = targetLanguageCode.trim().toLowerCase();

    if (safeText.isEmpty || target.isEmpty) {
      return text;
    }

    try {
      final translated = await _translator.translate(safeText, to: target);
      final result = translated.text.trim();
      return result.isEmpty ? text : result;
    } catch (_) {
      return text;
    }
  }
}
