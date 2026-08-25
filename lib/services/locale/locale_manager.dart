import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocaleManager extends ChangeNotifier {
  static final instance = LocaleManager._();
  LocaleManager._();

  static const List<Locale> curatedLocales = [
    Locale('en'),
    Locale('de'),
    Locale('es'),
    // Locale('fr'),
    // Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
  ];

  Locale? _locale;
  Locale? get locale => _locale;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final language = prefs.getString('locale_language');
    final script = prefs.getString('locale_script');
    final country = prefs.getString('locale_country');
    if (language != null) {
      _locale = Locale.fromSubtags(
        languageCode: language,
        scriptCode: script,
        countryCode: country,
      );
    }
  }

  Future<void> setLocale(Locale? locale) async {
    _locale = locale;
    final prefs = await SharedPreferences.getInstance();
    if (locale == null) {
      await prefs.remove('locale_language');
      await prefs.remove('locale_script');
      await prefs.remove('locale_country');
    } else {
      await prefs.setString('locale_language', locale.languageCode);
      if (locale.scriptCode != null) {
        await prefs.setString('locale_script', locale.scriptCode!);
      } else {
        await prefs.remove('locale_script');
      }
      if (locale.countryCode != null) {
        await prefs.setString('locale_country', locale.countryCode!);
      } else {
        await prefs.remove('locale_country');
      }
    }
    notifyListeners();
  }

  String displayName(Locale locale) {
    const names = {
      'en': 'English',
      'de': 'Deutsch',
      'es': 'Español',
      //'zh_Hans': '简体中文',
    };

    final variant = locale.scriptCode ?? locale.countryCode;
    final key = variant != null
        ? '${locale.languageCode}_$variant'
        : locale.languageCode;

    return names[key] ?? key;
  }

  List<Locale> get supportedLocales => curatedLocales;
}