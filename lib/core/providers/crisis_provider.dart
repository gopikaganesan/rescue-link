import 'package:flutter/foundation.dart';

import '../services/gemini_service.dart';

class CrisisProvider extends ChangeNotifier {
  final GeminiService _geminiService;

  CrisisProvider({GeminiService? geminiService})
      : _geminiService = geminiService ?? GeminiService();

  CrisisAnalysis? _latestAnalysis;
  bool _isLoading = false;
  String? _error;

  CrisisAnalysis? get latestAnalysis => _latestAnalysis;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> classifyCrisis(
    String input, {
    List<String> availableSkills = const <String>[],
    bool forceOffline = false,
    Uint8List? imageBytes,
    String? imageMimeType,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _latestAnalysis = await _geminiService.analyze(
        input,
        availableSkills: availableSkills,
        forceOffline: forceOffline,
        imageBytes: imageBytes,
        imageMimeType: imageMimeType,
      );
    } catch (e) {
      _error = 'Classification failed: ${e.toString()}';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void clearAnalysis() {
    _latestAnalysis = null;
    _error = null;
    notifyListeners();
  }
}
