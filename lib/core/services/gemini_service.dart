import 'dart:convert';

import 'package:google_generative_ai/google_generative_ai.dart';

class CrisisAnalysis {
  final String category;
  final String severity;
  final String summary;
  final String recommendedSkill;
  final List<String> suggestedActions;
  final bool offlineMode;

  const CrisisAnalysis({
    required this.category,
    required this.severity,
    required this.summary,
    required this.recommendedSkill,
    required this.suggestedActions,
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
category, severity, summary, recommendedSkill, suggestedActions

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
        suggestedActions: (parsed['suggestedActions'] as List?)
                ?.whereType<String>()
                .toList() ??
            const <String>[],
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
        recommendedSkill: 'Fire & Rescue',
        suggestedActions: <String>[
          'Move away from smoke and flames immediately.',
          'Call fire and off-duty authority responders.',
        ],
        offlineMode: true,
      );
    }
    if (text.contains('injury') ||
        text.contains('bleeding') ||
        text.contains('medical') ||
        text.contains('insulin') ||
        text.contains('fainted') ||
        text.contains('fall')) {
      return const CrisisAnalysis(
        category: 'Medical Emergency',
        severity: 'high',
        summary: 'Possible medical emergency reported.',
        recommendedSkill: 'Medical Emergency',
        suggestedActions: <String>[
          'Keep the person safe and breathing.',
          'Request medical responders and emergency transport.',
        ],
        offlineMode: true,
      );
    }
    if (text.contains('flood') || text.contains('storm') || text.contains('earthquake')) {
      return const CrisisAnalysis(
        category: 'Disaster Evacuation',
        severity: 'critical',
        summary: 'Large-scale disaster context detected. Evacuation support needed.',
        recommendedSkill: 'Shelter & Evacuation',
        suggestedActions: <String>[
          'Move to higher ground or a safer zone.',
          'Notify shelter, logistics, and civil defense responders.',
        ],
        offlineMode: true,
      );
    }
    if (text.contains('hungry') || text.contains('food') || text.contains('water')) {
      return const CrisisAnalysis(
        category: 'Essential Supply Need',
        severity: 'medium',
        summary: 'Immediate food or water support likely needed.',
        recommendedSkill: 'Food & Water Supply',
        suggestedActions: <String>[
          'Arrange food, water, or medicines urgently.',
          'Notify logistics and supply responders.',
        ],
        offlineMode: true,
      );
    }
    if (text.contains('elderly') || text.contains('old person')) {
      return const CrisisAnalysis(
        category: 'Elderly Assistance',
        severity: 'medium',
        summary: 'Elderly assistance request detected.',
        recommendedSkill: 'Elderly Assist',
        suggestedActions: <String>[
          'Use calm verbal guidance and gentle support.',
          'Request mobility support or medical check if needed.',
        ],
        offlineMode: true,
      );
    }
    if (text.contains('woman') || text.contains('women') || text.contains('harassment')) {
      return const CrisisAnalysis(
        category: 'Women Safety',
        severity: 'high',
        summary: 'Potential women safety incident detected.',
        recommendedSkill: 'Women Safety',
        suggestedActions: <String>[
          'Move to a safer visible location if possible.',
          'Notify police and safety responders immediately.',
        ],
        offlineMode: true,
      );
    }
    if (text.contains('child') || text.contains('kid')) {
      return const CrisisAnalysis(
        category: 'Child Safety',
        severity: 'high',
        summary: 'Potential child safety emergency detected.',
        recommendedSkill: 'Child Safety',
        suggestedActions: <String>[
          'Keep the child with a trusted adult if possible.',
          'Notify child safety and police responders.',
        ],
        offlineMode: true,
      );
    }
    if (text.contains('missing') || text.contains('trapped') || text.contains('rescue')) {
      return const CrisisAnalysis(
        category: 'Search & Rescue',
        severity: 'critical',
        summary: 'Possible rescue operation needed.',
        recommendedSkill: 'Search & Rescue',
        suggestedActions: <String>[
          'Keep the area clear and preserve landmarks.',
          'Request search and rescue plus off-duty authority responders.',
        ],
        offlineMode: true,
      );
    }

    return const CrisisAnalysis(
      category: 'General Emergency',
      severity: 'medium',
      summary: 'SOS emergency triggered by user.',
      recommendedSkill: 'General Support',
      suggestedActions: <String>[
        'Stay visible and share exact location details.',
        'Use responder chat, call, or emergency SMS as needed.',
      ],
      offlineMode: true,
    );
  }
}
