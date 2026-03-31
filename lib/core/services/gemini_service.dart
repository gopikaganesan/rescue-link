import 'dart:convert';

import 'package:google_generative_ai/google_generative_ai.dart';

class CrisisAnalysis {
  final String category;
  final String severity;
  final String summary;
  final String recommendedSkill;
  final bool offlineMode;

  const CrisisAnalysis({
    required this.category,
    required this.severity,
    required this.summary,
    required this.recommendedSkill,
    required this.offlineMode,
  });
}

class GeminiService {
  static const String _fallbackSkill = 'General Support';
  final String _apiKey;

  GeminiService({String? apiKey})
      : _apiKey = apiKey ?? const String.fromEnvironment('GEMINI_API_KEY');

  Future<CrisisAnalysis> analyze(
    String userInput, {
    List<String> availableSkills = const <String>[],
  }) async {
    if (_apiKey.isEmpty) {
      return _offlineHeuristic(userInput);
    }

    try {
      final model = GenerativeModel(model: 'gemini-1.5-flash', apiKey: _apiKey);
      final prompt = '''
You classify emergency text for rapid response.
Return strict JSON only with keys:
category, severity, summary, recommendedSkill

Allowed severity values: low, medium, high, critical.
recommendedSkill should prefer one from: ${availableSkills.join(', ')}
If no skill matches, use $_fallbackSkill.

Input:
$userInput
''';

      final response = await model.generateContent(<Content>[Content.text(prompt)]);
      final text = response.text;
      if (text == null || text.trim().isEmpty) {
        return _offlineHeuristic(userInput);
      }

      final cleaned = text.trim().replaceAll('```json', '').replaceAll('```', '');
      final parsed = jsonDecode(cleaned) as Map<String, dynamic>;

      return CrisisAnalysis(
        category: (parsed['category'] as String?) ?? 'Unknown',
        severity: (parsed['severity'] as String?) ?? 'medium',
        summary: (parsed['summary'] as String?) ?? userInput,
        recommendedSkill: (parsed['recommendedSkill'] as String?) ?? _fallbackSkill,
        offlineMode: false,
      );
    } catch (_) {
      return _offlineHeuristic(userInput);
    }
  }

  CrisisAnalysis _offlineHeuristic(String input) {
    final text = input.toLowerCase();
    if (text.contains('fire') || text.contains('smoke') || text.contains('burn')) {
      return const CrisisAnalysis(
        category: 'Fire Emergency',
        severity: 'high',
        summary: 'Possible fire-related incident reported.',
        recommendedSkill: 'Fire',
        offlineMode: true,
      );
    }
    if (text.contains('injury') || text.contains('bleeding') || text.contains('medical')) {
      return const CrisisAnalysis(
        category: 'Medical Emergency',
        severity: 'high',
        summary: 'Possible medical emergency reported.',
        recommendedSkill: 'Medical',
        offlineMode: true,
      );
    }
    if (text.contains('missing') || text.contains('trapped') || text.contains('rescue')) {
      return const CrisisAnalysis(
        category: 'Search & Rescue',
        severity: 'critical',
        summary: 'Possible rescue operation needed.',
        recommendedSkill: 'Search & Rescue',
        offlineMode: true,
      );
    }

    return const CrisisAnalysis(
      category: 'General Emergency',
      severity: 'medium',
      summary: 'SOS emergency triggered by user.',
      recommendedSkill: 'General Support',
      offlineMode: true,
    );
  }
}
