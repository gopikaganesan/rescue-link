import 'dart:ui';

import 'package:flutter/foundation.dart';

class AppSettingsProvider extends ChangeNotifier {
  AppSettingsProvider() {
    configureForLocale(PlatformDispatcher.instance.locale);
  }

  String _languageCode = 'en';
  List<String> _availableLanguageCodes = <String>['en', 'hi', 'ta'];
  double _textScaleFactor = 1.0;
  bool _hapticsEnabled = true;
  bool _sosFlashEnabled = false;
  bool _highContrastEnabled = false;
  bool _notificationsEnabled = false;

  static const Map<String, List<String>> _regionLanguagePresets = <String, List<String>>{
    'IN:hi': <String>['hi', 'en', 'ta', 'te', 'kn'],
    'IN:ta': <String>['ta', 'en', 'hi', 'ml', 'te'],
    'IN:te': <String>['te', 'en', 'hi', 'ta', 'kn'],
    'IN:kn': <String>['kn', 'en', 'hi', 'ta', 'ml'],
    'IN:ml': <String>['ml', 'en', 'ta', 'hi', 'kn'],
    'IN:mr': <String>['mr', 'en', 'hi', 'gu'],
    'IN:bn': <String>['bn', 'en', 'hi', 'or'],
    'IN:gu': <String>['gu', 'en', 'hi', 'mr'],
    'IN:pa': <String>['pa', 'en', 'hi', 'or'],
    'IN:or': <String>['or', 'en', 'hi', 'bn'],
    'CN:zh': <String>['zh', 'en'],
    'JP:ja': <String>['ja', 'en'],
    'KR:ko': <String>['ko', 'en'],
  };

  static const Map<String, String> _languageLabels = {
    'en': 'English',
    'hi': 'Hindi',
    'bn': 'Bengali',
    'gu': 'Gujarati',
    'kn': 'Kannada',
    'mr': 'Marathi',
    'or': 'Odia',
    'pa': 'Punjabi',
    'ta': 'Tamil',
    'te': 'Telugu',
    'ml': 'Malayalam',
    'zh': 'Chinese',
    'ja': 'Japanese',
    'ko': 'Korean',
  };

  static const Map<String, String> _nativeLanguageLabels = {
    'en': 'English',
    'hi': 'हिंदी',
    'bn': 'বাংলা',
    'gu': 'ગુજરાતી',
    'kn': 'ಕನ್ನಡ',
    'mr': 'मराठी',
    'or': 'ଓଡ଼ିଆ',
    'pa': 'ਪੰਜਾਬੀ',
    'ta': 'தமிழ்',
    'te': 'తెలుగు',
    'ml': 'മലയാളം',
    'zh': '中文',
    'ja': '日本語',
    'ko': '한국어',
  };

  String get languageCode => _languageCode;
  List<String> get availableLanguageCodes =>
      List<String>.unmodifiable(_availableLanguageCodes);
  String get selectedLanguageLabel =>
      _languageLabels[_languageCode] ?? _languageCode;
  double get textScaleFactor => _textScaleFactor;
  bool get hapticsEnabled => _hapticsEnabled;
  bool get sosFlashEnabled => _sosFlashEnabled;
  bool get highContrastEnabled => _highContrastEnabled;
  bool get notificationsEnabled => _notificationsEnabled;

  String languageLabel(String code) {
    final native = _nativeLanguageLabels[code] ?? code;
    final english = _languageLabels[code];
    if (english == null || english == native) {
      return native;
    }
    return '$native ($english)';
  }

  static const Map<String, Map<String, String>> _strings = {
    'en': {
      'app_title': 'RescueLink',
      'emergency_prompt': 'In an Emergency?',
      'emergency_subtitle': 'Press the SOS button below to alert nearby responders',
      'become_responder': 'Become A Responder',
      'location_ready': 'Location: Ready',
      'location_not_ready': 'Location: Not Ready',
      'user_info': 'User Info',
      'total_responders': 'Total Responders',
      'nearby_5km': 'Nearby (5km)',
      'sign_in_title': 'RescueLink Sign In',
      'sign_in': 'Sign In',
      'create_account': 'Create Account',
      'continue_guest': 'Continue as Guest (Anonymous)',
      'language': 'Language',
    },
    'hi': {
      'app_title': 'रेस्क्यूलिंक',
      'emergency_prompt': 'क्या आप आपात स्थिति में हैं?',
      'emergency_subtitle': 'नीचे SOS बटन दबाकर नज़दीकी रिस्पॉन्डर्स को अलर्ट करें',
      'become_responder': 'रिस्पॉन्डर बनें',
      'location_ready': 'लोकेशन: तैयार',
      'location_not_ready': 'लोकेशन: तैयार नहीं',
      'user_info': 'उपयोगकर्ता जानकारी',
      'total_responders': 'कुल रिस्पॉन्डर्स',
      'nearby_5km': 'नज़दीक (5 किमी)',
      'sign_in_title': 'रेस्क्यूलिंक साइन इन',
      'sign_in': 'साइन इन',
      'create_account': 'खाता बनाएं',
      'continue_guest': 'गेस्ट के रूप में जारी रखें',
      'language': 'भाषा',
    },
    'ta': {
      'app_title': 'மீட்பு இணைப்பு',
      'emergency_prompt': 'அவசரநிலையா?',
      'emergency_subtitle': 'அருகிலுள்ள பதிலளிப்போருக்கு எச்சரிக்க கீழே உள்ள SOS பொத்தானை அழுத்தவும்',
      'become_responder': 'பதிலளிப்பவராக சேரவும்',
      'location_ready': 'இடம்: தயாராக உள்ளது',
      'location_not_ready': 'இடம்: தயாரில்லை',
      'user_info': 'பயனர் தகவல்',
      'total_responders': 'மொத்த பதிலளிப்பவர்கள்',
      'nearby_5km': 'அருகில் (5 கிமீ)',
      'sign_in_title': 'RescueLink உள்நுழைவு',
      'sign_in': 'உள்நுழை',
      'create_account': 'கணக்கு உருவாக்கு',
      'language': 'மொழி',
      'continue_guest': 'விருந்தினராக தொடரவும்',
    },
    'te': {
      'app_title': 'RescueLink',
      'sign_in_title': 'RescueLink సైన్ ఇన్',
      'language': 'భాష',
      'continue_guest': 'గెస్ట్‌గా కొనసాగండి',
    },
    'kn': {
      'app_title': 'RescueLink',
      'sign_in_title': 'RescueLink ಸೈನ್ ಇನ್',
      'language': 'ಭಾಷೆ',
      'continue_guest': 'ಅತಿಥಿಯಾಗಿ ಮುಂದುವರಿಯಿರಿ',
    },
    'bn': {
      'app_title': 'RescueLink',
      'sign_in_title': 'RescueLink সাইন ইন',
      'language': 'ভাষা',
      'continue_guest': 'অতিথি হিসেবে চালিয়ে যান',
    },
    'mr': {
      'app_title': 'RescueLink',
      'sign_in_title': 'RescueLink साइन इन',
      'language': 'भाषा',
      'continue_guest': 'अतिथी म्हणून सुरू ठेवा',
    },
    'gu': {
      'app_title': 'RescueLink',
      'sign_in_title': 'RescueLink સાઇન ઇન',
      'language': 'ભાષા',
      'continue_guest': 'અતિથિ તરીકે ચાલુ રાખો',
    },
    'pa': {
      'app_title': 'RescueLink',
      'sign_in_title': 'RescueLink ਸਾਇਨ ਇਨ',
      'language': 'ਭਾਸ਼ਾ',
      'continue_guest': 'ਮਹਿਮਾਨ ਵਜੋਂ ਜਾਰੀ ਰੱਖੋ',
    },
    'or': {
      'app_title': 'RescueLink',
      'sign_in_title': 'RescueLink ସାଇନ ଇନ',
      'language': 'ଭାଷା',
      'continue_guest': 'ଅତିଥି ଭାବରେ ଜାରି ରଖନ୍ତୁ',
    },
    'ml': {
      'app_title': 'RescueLink',
      'sign_in_title': 'RescueLink സൈൻ ഇൻ',
      'language': 'ഭാഷ',
      'continue_guest': 'അതിഥിയായി തുടരുക',
    },
    'zh': {
      'app_title': 'RescueLink',
      'sign_in_title': 'RescueLink 登录',
      'language': '语言',
      'continue_guest': '以访客身份继续',
    },
    'ja': {
      'app_title': 'RescueLink',
      'sign_in_title': 'RescueLink サインイン',
      'language': '言語',
      'continue_guest': 'ゲストとして続行',
    },
    'ko': {
      'app_title': 'RescueLink',
      'sign_in_title': 'RescueLink 로그인',
      'language': '언어',
      'continue_guest': '게스트로 계속',
    },
  };

  String t(String key) {
    return _strings[_languageCode]?[key] ?? _strings['en']?[key] ?? key;
  }

  void configureForLocale(Locale locale) {
    final country = (locale.countryCode ?? '').toUpperCase();
    final language = locale.languageCode.toLowerCase();

    final preset = _regionLanguagePresets['$country:$language'] ??
        _regionLanguagePresets['$country:en'] ??
        <String>[language, 'en'];

    // Always include core languages (en, hi, ta) for better user experience
    final options = <String>{...preset, language, 'en', 'hi', 'ta'};
    _availableLanguageCodes = options.toList();

    if (_availableLanguageCodes.contains(language)) {
      _languageCode = language;
    } else if (!_availableLanguageCodes.contains(_languageCode)) {
      _languageCode = _availableLanguageCodes.first;
    }

    notifyListeners();
  }

  void setLanguage(String languageCode) {
    if (!_availableLanguageCodes.contains(languageCode)) {
      return;
    }
    if (_languageCode == languageCode) {
      return;
    }
    _languageCode = languageCode;
    notifyListeners();
  }

  void setTextScaleFactor(double value) {
    final next = value.clamp(0.85, 1.6);
    if (_textScaleFactor == next) {
      return;
    }
    _textScaleFactor = next;
    notifyListeners();
  }

  void setHapticsEnabled(bool enabled) {
    if (_hapticsEnabled == enabled) {
      return;
    }
    _hapticsEnabled = enabled;
    notifyListeners();
  }

  void setSosFlashEnabled(bool enabled) {
    if (_sosFlashEnabled == enabled) {
      return;
    }
    _sosFlashEnabled = enabled;
    notifyListeners();
  }

  void setHighContrastEnabled(bool enabled) {
    if (_highContrastEnabled == enabled) {
      return;
    }
    _highContrastEnabled = enabled;
    notifyListeners();
  }

  void setNotificationsEnabled(bool enabled) {
    if (_notificationsEnabled == enabled) {
      return;
    }
    _notificationsEnabled = enabled;
    notifyListeners();
  }
}
