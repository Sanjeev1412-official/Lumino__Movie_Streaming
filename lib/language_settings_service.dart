import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LanguageOption {
  final String code;
  final String name;
  final String nativeName;

  const LanguageOption({
    required this.code,
    required this.name,
    required this.nativeName,
  });
}

class LanguageSettingsService {
  static final LanguageSettingsService _instance =
      LanguageSettingsService._internal();
  factory LanguageSettingsService() => _instance;

  LanguageSettingsService._internal() {
    _loadLanguage();
  }

  static const String _keyLanguageCode = 'lumino_app_language_code';

  static const List<LanguageOption> supportedLanguages = [
    LanguageOption(code: 'en-US', name: 'English (US)', nativeName: 'English (United States)'),
    LanguageOption(code: 'en-GB', name: 'English (UK)', nativeName: 'English (United Kingdom)'),
    LanguageOption(code: 'es-ES', name: 'Spanish', nativeName: 'Español'),
    LanguageOption(code: 'fr-FR', name: 'French', nativeName: 'Français'),
    LanguageOption(code: 'de-DE', name: 'German', nativeName: 'Deutsch'),
    LanguageOption(code: 'it-IT', name: 'Italian', nativeName: 'Italiano'),
    LanguageOption(code: 'pt-BR', name: 'Portuguese (Brazil)', nativeName: 'Português (Brasil)'),
    LanguageOption(code: 'ru-RU', name: 'Russian', nativeName: 'Русский'),
    LanguageOption(code: 'hi-IN', name: 'Hindi', nativeName: 'हिन्दी'),
    LanguageOption(code: 'ml-IN', name: 'Malayalam', nativeName: 'മലയാളം'),
    LanguageOption(code: 'ta-IN', name: 'Tamil', nativeName: 'தமிழ்'),
    LanguageOption(code: 'te-IN', name: 'Telugu', nativeName: 'తెలుగు'),
    LanguageOption(code: 'kn-IN', name: 'Kannada', nativeName: 'ಕನ್ನಡ'),
    LanguageOption(code: 'bn-IN', name: 'Bengali', nativeName: 'বাংলা'),
    LanguageOption(code: 'ja-JP', name: 'Japanese', nativeName: '日本語'),
    LanguageOption(code: 'ko-KR', name: 'Korean', nativeName: '한국어'),
    LanguageOption(code: 'zh-CN', name: 'Chinese (Simplified)', nativeName: '简体中文'),
    LanguageOption(code: 'ar-SA', name: 'Arabic', nativeName: 'العربية'),
  ];

  static const LanguageOption defaultLanguage = LanguageOption(
    code: 'en-US',
    name: 'English (US)',
    nativeName: 'English (United States)',
  );

  final ValueNotifier<LanguageOption> currentLanguageNotifier =
      ValueNotifier<LanguageOption>(defaultLanguage);

  LanguageOption get current => currentLanguageNotifier.value;
  String get currentCode => currentLanguageNotifier.value.code;
  String get currentName => currentLanguageNotifier.value.name;

  Future<void> _loadLanguage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final code = prefs.getString(_keyLanguageCode) ?? defaultLanguage.code;
      final match = supportedLanguages.firstWhere(
        (l) => l.code.toLowerCase() == code.toLowerCase(),
        orElse: () => defaultLanguage,
      );
      currentLanguageNotifier.value = match;
    } catch (e) {
      debugPrint('[LanguageSettingsService] Failed to load language: $e');
    }
  }

  Future<void> setLanguage(LanguageOption option) async {
    currentLanguageNotifier.value = option;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyLanguageCode, option.code);
    } catch (e) {
      debugPrint('[LanguageSettingsService] Failed to save language: $e');
    }
  }
}
