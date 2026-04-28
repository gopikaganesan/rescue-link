import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/providers/app_settings_provider.dart';
import '../core/services/text_translation_service.dart';

class TranslatedText extends StatefulWidget {
  const TranslatedText(
    this.text, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow,
    this.fallback,
  });

  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final String? fallback;

  @override
  State<TranslatedText> createState() => _TranslatedTextState();
}

class _TranslatedTextState extends State<TranslatedText> {
  static final Map<String, String> _cache = <String, String>{};
  final TextTranslationService _translationService = TextTranslationService();

  String _displayText = '';
  String _lastKey = '';

  @override
  void initState() {
    super.initState();
    _initDisplayText();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshTranslation());
  }

  void _initDisplayText() {
    final source = widget.text.trim().isEmpty ? (widget.fallback ?? widget.text) : widget.text;
    try {
      final languageCode = context.read<AppSettingsProvider>().languageCode.trim().toLowerCase();
      if (languageCode.isEmpty || languageCode == 'en') {
        _displayText = source;
      } else {
        final key = '$languageCode|$source';
        if (_cache.containsKey(key)) {
          _displayText = _cache[key]!;
        } else {
          _displayText = source;
        }
      }
    } catch (_) {
      _displayText = source;
    }
  }

  @override
  void didUpdateWidget(covariant TranslatedText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.fallback != widget.fallback) {
      _initDisplayText();
      _refreshTranslation();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refreshTranslation();
  }

  Future<void> _refreshTranslation() async {
    if (!mounted) {
      return;
    }

    final languageCode =
        context.read<AppSettingsProvider>().languageCode.trim().toLowerCase();
    final source = widget.text.trim().isEmpty
        ? (widget.fallback ?? widget.text)
        : widget.text;

    if (source.trim().isEmpty || languageCode.isEmpty || languageCode == 'en') {
      if (_displayText != source) {
        setState(() {
          _displayText = source;
        });
      }
      return;
    }

    final key = '$languageCode|$source';
    _lastKey = key;

    final cached = _cache[key];
    if (cached != null) {
      if (_displayText != cached) {
        setState(() {
          _displayText = cached;
        });
      }
      return;
    }

    final translated = await _translationService.translate(
      text: source,
      targetLanguageCode: languageCode,
    );

    if (!mounted || _lastKey != key) {
      return;
    }

    _cache[key] = translated;
    if (_displayText != translated) {
      setState(() {
        _displayText = translated;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _displayText,
      style: widget.style,
      maxLines: widget.maxLines,
      overflow: widget.overflow,
    );
  }
}
