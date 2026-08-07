import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:safehaven/translations/app_localizations.dart';

class LocaleManager extends ChangeNotifier {
  static final instance = LocaleManager._();
  LocaleManager._();

  Locale? _locale;
  Locale? get locale => _locale;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString('locale');
    if (code != null) _locale = Locale(code);
  }

  Future<void> setLocale(Locale? locale) async {
    _locale = locale;
    final prefs = await SharedPreferences.getInstance();
    if (locale == null) {
      await prefs.remove('locale');
    } else {
      await prefs.setString('locale', locale.languageCode);
    }
    notifyListeners();
  }

  String displayName(String code) {
    const names = {
      'en': 'English',
      'fr': 'Français',
      'de': 'Deutsch',
      'es': 'Español',
      'it': 'Italiano',
      'pt': 'Português',
      'nl': 'Nederlands',
      'pl': 'Polski',
      'ru': 'Русский',
      'ja': '日本語',
      'ko': '한국어',
      'zh': '中文',
      'ar': 'العربية',
      'hi': 'हिन्दी',
      'tr': 'Türkçe',
      'uk': 'Українська',
      'sv': 'Svenska',
      'da': 'Dansk',
      'fi': 'Suomi',
      'nb': 'Norsk',
      'cs': 'Čeština',
      'ro': 'Română',
      'hu': 'Magyar',
      'el': 'Ελληνικά',
      'th': 'ไทย',
      'vi': 'Tiếng Việt',
      'id': 'Bahasa Indonesia',
      'ms': 'Bahasa Melayu',
      // alr thats enough
    };
    return names[code] ?? code;
  }

  List<Locale> get supportedLocales => AppLocalizations.supportedLocales;
}