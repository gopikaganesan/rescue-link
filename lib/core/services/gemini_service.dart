import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

import 'text_translation_service.dart';

class CrisisAnalysis {
  final String category;
  final String severity;
  final String summary;
  final String recommendedSkill;
  final List<String> suggestedActions;
  final bool offlineMode;
  final String aiSource;
  final String aiStatus;
  final double confidence;
  final bool humanReviewRecommended;

  const CrisisAnalysis({
    required this.category,
    required this.severity,
    required this.summary,
    required this.recommendedSkill,
    required this.suggestedActions,
    required this.offlineMode,
    this.aiSource = 'offline',
    this.aiStatus = 'offline_heuristic',
    this.confidence = 0.65,
    this.humanReviewRecommended = false,
  });
}

class GeminiService {
  static const String _fallbackSkill = 'General Support';
  static const List<String> _defaultModelCandidates = <String>[
    'gemini-1.5-flash',
    'gemini-1.5-pro',
    'gemini-2.5-flash',
    'gemini-2.5-flash-lite',
    'gemini-2.5-pro',
    'gemini-2.0-flash',
    'gemini-2.0-flash-001',
    'gemini-2.0-flash-lite-001',
    'gemini-2.0-flash-lite',
    'gemini-1.5-flash-latest',
    'gemini-1.5-pro-latest',
    'gemini-flash-latest',
    'gemini-pro',
  ];
  static const Duration _geminiTimeout = Duration(seconds: 12);
  final String _apiKey;
  final List<String> _modelCandidates;
  final TextTranslationService _textTranslationService =
      TextTranslationService();

  static const Map<String, String> _emojiKeywords = <String, String>{
    '🚨': ' emergency alert ',
    '🆘': ' sos emergency help ',
    '🔥': ' fire smoke burn ',
    '💥': ' explosion emergency ',
    '🧯': ' fire rescue ',
    '💧': ' water flood ',
    '🌊': ' flood disaster ',
    '🏥': ' medical hospital ',
    '🚑': ' ambulance medical ',
    '⛑️': ' medical first aid ',
    '🩺': ' medical doctor ',
    '🩸': ' bleeding injury ',
    '👩': ' woman female ',
    '👮': ' police safety ',
    '👮‍♂️': ' police safety ',
    '👮‍♀️': ' police safety ',
    '🛡️': ' safety protection ',
    '👧': ' child kid ',
    '👦': ' child kid ',
    '👴': ' elderly old person ',
    '🧓': ' elderly old person ',
    '⚠️': ' warning emergency ',
    '☎️': ' call phone help ',
    '📞': ' call phone help ',
    '😨': ' panic fear help ',
    '😭': ' distress crying help ',
    '💔': ' distress injury help ',
    '🍞': ' food supply ',
    '🥤': ' water supply ',
    '🔍': ' missing rescue ',
    '🧑‍🚒': ' fire rescue ',
    '🧑‍⚕️': ' medical help ',
  };

  static const Map<String, String> _textAliases = <String, String>{
    'nerupu': ' fire ',
    'neruppu': ' fire ',
    'aag': ' fire ',
    'aagni': ' fire ',
    'agni': ' fire ',
    'pani': ' water ',
    'jal': ' water ',
    'rakta': ' bleeding ',
    'bachcha': ' child ',
    'baccha': ' child ',
    'ladki': ' woman ',
    'ladkiyon': ' women ',
    'mahila': ' woman ',
    'missing person': ' missing person rescue ',
    'trapped': ' trapped rescue ',
  };

  GeminiService({String? apiKey, List<String>? modelCandidates})
      : _apiKey = apiKey ?? const String.fromEnvironment('GEMINI_API_KEY'),
        _modelCandidates = modelCandidates ?? _resolveModelCandidates();

  static List<String> _resolveModelCandidates() {
    final raw = const String.fromEnvironment(
      'GEMINI_MODEL_CANDIDATES',
      defaultValue: '',
    ).trim();
    final aliasRaw = const String.fromEnvironment(
      'GEMINI_MODELS',
      defaultValue: '',
    ).trim();

    final source = raw.isNotEmpty ? raw : aliasRaw;
    if (source.isEmpty) {
      return _defaultModelCandidates;
    }

    final parsed = source
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    if (parsed.isEmpty) {
      return _defaultModelCandidates;
    }

    final unique = <String>[];
    final seen = <String>{};
    for (final item in parsed) {
      if (seen.add(item)) {
        unique.add(item);
      }
    }

    return unique;
  }

  Future<CrisisAnalysis> analyze(
    String userInput, {
    List<String> availableSkills = const <String>[],
    bool forceOffline = false,
    Uint8List? imageBytes,
    String? imageMimeType,
  }) async {
    final normalizedInput = await _normalizeInput(userInput);

    if (forceOffline) {
      _logAiStatus('forced_offline');
      return _withAiDiagnostics(
        _offlineHeuristic(normalizedInput),
        aiStatus: 'forced_offline',
      );
    }

    if (_apiKey.isEmpty) {
      _logAiStatus('missing_api_key');
      return _withAiDiagnostics(
        _offlineHeuristic(normalizedInput),
        aiStatus: 'missing_api_key',
      );
    }

    _GeminiFailure bestFailure = const _GeminiFailure(
      code: 'gemini_error',
      userMessage: 'Gemini is temporarily unavailable.',
    );

    final prompt = '''
    You classify emergency text and optional incident image for rapid response.
Return strict JSON only with keys:
category, severity, summary, recommendedSkill, suggestedActions, confidence, humanReviewRecommended

Allowed severity values: low, medium, high, critical.
recommendedSkill should prefer one from: ${availableSkills.join(', ')}
If no skill matches, use $_fallbackSkill.

    Treat these as HIGH or CRITICAL by default:
    - Drowning / person in water / unable to breathe in water
    - Rail-track hazard / train approaching / person stuck near track
    - Limb trapped in pit, machinery, grate, or debris
    - Animal swarm attack (bees, hornets, wasps) with breathing risk

    Input may include Tanglish or mixed Indian languages; infer urgency from meaning, not grammar.
    If image is present, use visual evidence to override weak text and choose safer severity.

Input:
$normalizedInput
''';

    final content = (imageBytes != null && (imageMimeType ?? '').isNotEmpty)
        ? Content.multi(<Part>[
            TextPart(prompt),
            DataPart(imageMimeType!, imageBytes),
          ])
        : Content.text(prompt);

    for (final modelName in _modelCandidates) {
      try {
        final model = GenerativeModel(model: modelName, apiKey: _apiKey);
        final response = await model
            .generateContent(<Content>[content])
            .timeout(_geminiTimeout);
        final text = response.text;
        if (text == null || text.trim().isEmpty) {
          bestFailure = _pickMoreUsefulFailure(
            bestFailure,
            const _GeminiFailure(
              code: 'gemini_empty_response',
              userMessage: 'Gemini returned an empty response.',
            ),
          );
          _logAiStatus('gemini_empty_response', model: modelName);
          continue;
        }

        final cleaned =
            text.trim().replaceAll('```json', '').replaceAll('```', '');
        final parsed = jsonDecode(cleaned) as Map<String, dynamic>;

        final parsedAnalysis = CrisisAnalysis(
          category: (parsed['category'] as String?) ?? 'Unknown',
          severity: (parsed['severity'] as String?) ?? 'medium',
          summary: (parsed['summary'] as String?) ?? userInput,
          recommendedSkill:
              (parsed['recommendedSkill'] as String?) ?? _fallbackSkill,
          suggestedActions: (parsed['suggestedActions'] as List?)
                  ?.whereType<String>()
                  .toList() ??
              const <String>[],
          offlineMode: false,
          aiSource: 'gemini',
          aiStatus: 'gemini_success',
          confidence: _parseConfidence(parsed['confidence']),
          humanReviewRecommended: parsed['humanReviewRecommended'] == true,
        );
        _logAiStatus('gemini_success', model: modelName);
        return _applySafetyEscalation(
          normalizedInput,
          parsedAnalysis,
          hasImageEvidence: imageBytes != null,
        );
      } on TimeoutException catch (e) {
        bestFailure = _pickMoreUsefulFailure(
          bestFailure,
          const _GeminiFailure(
            code: 'gemini_timeout',
            userMessage: 'Gemini request timed out.',
          ),
        );
        _logAiStatus('gemini_timeout', model: modelName, error: e);
      } catch (e) {
        final mapped = _classifyGeminiFailure(e);
        bestFailure = _pickMoreUsefulFailure(bestFailure, mapped);
        _logAiStatus(mapped.code, model: modelName, error: e);
      }
    }

    return _withAiDiagnostics(
      _offlineHeuristic(normalizedInput),
      aiStatus: bestFailure.code,
    );
  }

  Future<String> _normalizeInput(String input) async {
    var normalized = input;
    for (final entry in _emojiKeywords.entries) {
      normalized = normalized.replaceAll(entry.key, entry.value);
    }

    for (final entry in _textAliases.entries) {
      normalized = normalized.replaceAll(
        RegExp(r'\b' + RegExp.escape(entry.key) + r'\b', caseSensitive: false),
        entry.value,
      );
    }

    if (_containsNonEnglishScript(normalized)) {
      final translated = await _textTranslationService.translate(
        text: normalized,
        targetLanguageCode: 'en',
      );
      if (translated.trim().isNotEmpty) {
        normalized = translated;
      }
    }

    normalized = normalized.replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized.isEmpty ? input : normalized;
  }

  bool _containsNonEnglishScript(String input) {
    return RegExp(
      r'[\u0900-\u097F\u0B80-\u0BFF\u0C00-\u0C7F\u0C80-\u0CFF\u0D00-\u0D7F\u3040-\u30FF\uAC00-\uD7AF\u4E00-\u9FFF]',
    ).hasMatch(input);
  }

  CrisisAnalysis _offlineHeuristic(String input) {
    final text = input.toLowerCase();

    if (_matchesAny(
      text,
      <String>[
        'drown',
        'drowning',
        'underwater',
        'sinking',
        'can\'t breathe',
        'cannot breathe',
        'water rescue',
        'river',
        'lake',
        'sea',
      ],
    )) {
      return const CrisisAnalysis(
        category: 'Water Rescue Emergency',
        severity: 'critical',
        summary:
            'Possible drowning or severe water-distress incident detected.',
        recommendedSkill: 'Search & Rescue',
        suggestedActions: <String>[
          'Call emergency services immediately and request water rescue.',
          'Do not jump in unless trained; use a rope, pole, or floating object.',
        ],
        offlineMode: true,
      );
    }

    if (_matchesAny(
      text,
      <String>[
        'rail track',
        'railway',
        'train',
        'track',
        'stuck on track',
        'level crossing',
      ],
    )) {
      return const CrisisAnalysis(
        category: 'Railway Hazard Emergency',
        severity: 'critical',
        summary:
            'Person appears at immediate risk near an active railway line.',
        recommendedSkill: 'Search & Rescue',
        suggestedActions: <String>[
          'Move everyone away from tracks immediately if safe to do so.',
          'Alert railway control and emergency responders without delay.',
        ],
        offlineMode: true,
      );
    }

    if (_matchesAny(
      text,
      <String>[
        'stuck in pit',
        'leg stuck',
        'trapped leg',
        'trapped in pit',
        'stuck in drain',
        'stuck in grate',
      ],
    )) {
      return const CrisisAnalysis(
        category: 'Entrapment Rescue',
        severity: 'high',
        summary: 'Possible limb/body entrapment incident detected.',
        recommendedSkill: 'Search & Rescue',
        suggestedActions: <String>[
          'Avoid forceful pulling if fracture risk exists.',
          'Stabilize the person and request rescue plus medical responders.',
        ],
        offlineMode: true,
      );
    }

    if (_matchesAny(
      text,
      <String>[
        'bee',
        'bees',
        'hornet',
        'wasp',
        'swarm',
        'stings',
      ],
    )) {
      return const CrisisAnalysis(
        category: 'Animal/Insect Attack',
        severity: 'high',
        summary: 'Possible dangerous insect swarm or multiple stings reported.',
        recommendedSkill: 'Medical Emergency',
        suggestedActions: <String>[
          'Move to enclosed shelter and reduce further exposure.',
          'Watch for breathing difficulty and request urgent medical support.',
        ],
        offlineMode: true,
      );
    }

    if (text.contains('fire') ||
        text.contains('smoke') ||
        text.contains('burn')) {
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
    if (text.contains('flood') ||
        text.contains('tsunami') ||
        text.contains('tidal wave') ||
        text.contains('sea surge') ||
        text.contains('storm') ||
        text.contains('earthquake')) {
      return const CrisisAnalysis(
        category: 'Disaster Evacuation',
        severity: 'critical',
        summary:
            'Large-scale disaster context detected. Evacuation support needed.',
        recommendedSkill: 'Shelter & Evacuation',
        suggestedActions: <String>[
          'Move to higher ground or a safer zone.',
          'Notify shelter, logistics, and civil defense responders.',
        ],
        offlineMode: true,
      );
    }
    if (text.contains('hungry') ||
        text.contains('food') ||
        text.contains('water')) {
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
    if (text.contains('woman') ||
        text.contains('women') ||
        text.contains('harassment')) {
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
    if (text.contains('missing') ||
        text.contains('trapped') ||
        text.contains('rescue')) {
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

  CrisisAnalysis _withAiDiagnostics(
    CrisisAnalysis analysis, {
    required String aiStatus,
  }) {
    return CrisisAnalysis(
      category: analysis.category,
      severity: analysis.severity,
      summary: analysis.summary,
      recommendedSkill: analysis.recommendedSkill,
      suggestedActions: analysis.suggestedActions,
      offlineMode: true,
      aiSource: 'offline',
      aiStatus: aiStatus,
      confidence: analysis.confidence,
      humanReviewRecommended: analysis.humanReviewRecommended,
    );
  }

  bool _matchesAny(String text, List<String> keywords) {
    for (final keyword in keywords) {
      if (text.contains(keyword)) {
        return true;
      }
    }
    return false;
  }

  CrisisAnalysis _applySafetyEscalation(
    String input,
    CrisisAnalysis analysis, {
    required bool hasImageEvidence,
  }) {
    final text = input.toLowerCase();
    final hasCriticalCue = _matchesAny(
      text,
      <String>[
        'drown',
        'drowning',
        'underwater',
        'train',
        'rail',
        'track',
        'stuck in pit',
        'leg stuck',
        'trapped',
      ],
    );
    final hasHighCue = _matchesAny(
      text,
      <String>['bee', 'bees', 'hornet', 'wasp', 'swarm'],
    );

    if (!hasCriticalCue && !hasHighCue) {
      return analysis;
    }

    // Safety-first hard rule: when image evidence is present with hazard cues,
    // force critical to avoid under-triage in ambiguous descriptions.
    final targetSeverity = (hasImageEvidence && (hasCriticalCue || hasHighCue))
        ? 'critical'
        : (hasCriticalCue ? 'critical' : 'high');
    final escalatedSeverity = _maxSeverity(analysis.severity, targetSeverity);
    final category = analysis.category.toLowerCase() == 'general emergency'
        ? ((hasCriticalCue || hasImageEvidence)
            ? 'Rescue Emergency'
            : 'Medical Safety Emergency')
        : analysis.category;
    final reviewRecommended =
        analysis.humanReviewRecommended || hasImageEvidence;

    return CrisisAnalysis(
      category: category,
      severity: escalatedSeverity,
      summary: analysis.summary,
      recommendedSkill: analysis.recommendedSkill,
      suggestedActions: analysis.suggestedActions,
      offlineMode: analysis.offlineMode,
      aiSource: analysis.aiSource,
      aiStatus: analysis.aiStatus,
      confidence: analysis.confidence,
      humanReviewRecommended: reviewRecommended,
    );
  }

  _GeminiFailure _classifyGeminiFailure(Object error) {
    final message = error.toString().toLowerCase();

    if (message.contains('api key not valid') ||
        message.contains('invalid api key') ||
        message.contains('permission denied') ||
        message.contains('403')) {
      return const _GeminiFailure(
        code: 'gemini_auth_error',
        userMessage: 'Gemini key is invalid or lacks permissions.',
      );
    }

    if (message.contains('429') ||
        message.contains('quota') ||
        message.contains('rate limit') ||
        message.contains('resource_exhausted')) {
      return const _GeminiFailure(
        code: 'gemini_quota_exceeded',
        userMessage: 'Gemini quota/rate limit reached.',
      );
    }

    if (message.contains('404') ||
        (message.contains('model') && message.contains('not found'))) {
      return const _GeminiFailure(
        code: 'gemini_model_unavailable',
        userMessage: 'Requested Gemini model is unavailable for this key.',
      );
    }

    if (message.contains('socketexception') ||
        message.contains('failed host lookup') ||
        message.contains('network') ||
        message.contains('connection')) {
      return const _GeminiFailure(
        code: 'gemini_offline',
        userMessage: 'Network appears offline or unstable.',
      );
    }

    return const _GeminiFailure(
      code: 'gemini_error',
      userMessage: 'Gemini is temporarily unavailable.',
    );
  }

  _GeminiFailure _pickMoreUsefulFailure(
    _GeminiFailure current,
    _GeminiFailure candidate,
  ) {
    final currentPriority = _failurePriority(current.code);
    final candidatePriority = _failurePriority(candidate.code);
    return candidatePriority > currentPriority ? candidate : current;
  }

  int _failurePriority(String code) {
    switch (code) {
      case 'missing_api_key':
      case 'gemini_auth_error':
      case 'gemini_quota_exceeded':
      case 'gemini_offline':
      case 'gemini_timeout':
        return 5;
      case 'gemini_model_unavailable':
        return 3;
      case 'gemini_empty_response':
        return 2;
      case 'gemini_error':
      default:
        return 1;
    }
  }

  void _logAiStatus(String status, {String? model, Object? error}) {
    final modelSuffix = model == null ? '' : ' | model=$model';
    final errorSuffix = error == null ? '' : ' | error=$error';
    debugPrint('[GeminiService] $status$modelSuffix$errorSuffix');
  }

  String _maxSeverity(String a, String b) {
    const rank = <String, int>{
      'low': 0,
      'medium': 1,
      'high': 2,
      'critical': 3,
    };
    final left = rank[a.toLowerCase()] ?? 1;
    final right = rank[b.toLowerCase()] ?? 1;
    return left >= right ? a.toLowerCase() : b.toLowerCase();
  }

  double _parseConfidence(dynamic value) {
    if (value is num) {
      final clamped = value.toDouble().clamp(0.0, 1.0);
      return clamped;
    }
    if (value is String) {
      final parsed = double.tryParse(value.trim());
      if (parsed != null) {
        return parsed.clamp(0.0, 1.0);
      }
    }
    return 0.6;
  }
}

class _GeminiFailure {
  final String code;
  final String userMessage;

  const _GeminiFailure({
    required this.code,
    required this.userMessage,
  });
}
