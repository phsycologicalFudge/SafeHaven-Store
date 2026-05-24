import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum SafeHavenThemeMode {
  light,
  dark,
}

class SafeHavenThemeManager extends ChangeNotifier {
  SafeHavenThemeManager._();

  static final SafeHavenThemeManager instance = SafeHavenThemeManager._();

  SafeHavenThemeMode _mode = SafeHavenThemeMode.light;
  bool _initialized = false;

  SafeHavenThemeMode get mode => _mode;

  bool get isDark => _mode == SafeHavenThemeMode.dark;

  Future<void> init() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    final isDarkPref = prefs.getBool('safehaven_is_dark') ?? false;
    _mode = isDarkPref ? SafeHavenThemeMode.dark : SafeHavenThemeMode.light;
    _initialized = true;
    notifyListeners();
  }

  Future<void> setMode(SafeHavenThemeMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('safehaven_is_dark', isDark);
  }

  Future<void> toggle() async {
    await setMode(isDark ? SafeHavenThemeMode.light : SafeHavenThemeMode.dark);
  }
}

class SafeHavenColors {
  const SafeHavenColors({
    required this.background,
    required this.backgroundFrost,
    required this.surface,
    required this.surfaceSoft,
    required this.border,
    required this.text,
    required this.textSoft,
    required this.textMuted,
    required this.navBackground,
    required this.navBorder,
    required this.accentStart,
    required this.accentEnd,
    required this.iconBackground,
    required this.buttonText,
  });

  final Color background;
  final Color backgroundFrost;
  final Color surface;
  final Color surfaceSoft;
  final Color border;
  final Color text;
  final Color textSoft;
  final Color textMuted;
  final Color navBackground;
  final Color navBorder;
  final Color accentStart;
  final Color accentEnd;
  final Color iconBackground;
  final Color buttonText;

  LinearGradient get accentGradient {
    return LinearGradient(
      begin: Alignment.bottomLeft,
      end: Alignment.topRight,
      colors: [accentStart, accentEnd],
    );
  }

  BoxDecoration get gradientPill {
    return BoxDecoration(
      gradient: accentGradient,
      borderRadius: BorderRadius.circular(99),
    );
  }
}

class SafeHavenTheme {
  static const light = SafeHavenColors(
    background: Color(0xFFFFFFFF),
    backgroundFrost: Color(0xFFF2F2F6),
    surface: Color(0xFFFFFFFF),
    surfaceSoft: Color(0xFFF7F7FA),
    border: Color(0xFFE7E8EE),
    text: Color(0xFF18181C),
    textSoft: Color(0xFF4D515C),
    textMuted: Color(0xFF8E929E),
    navBackground: Color(0xFFF2F2F6),
    navBorder: Color(0xFFE7E8EE),
    accentStart: Color(0xFF5A92FF),
    accentEnd: Color(0xFF8EBCFF),
    iconBackground: Color(0xFFF4F5F8),
    buttonText: Color(0xFFFFFFFF),
  );

  static const dark = SafeHavenColors(
    background: Color(0xFF0B0B10),
    backgroundFrost: Color(0xFF111118),
    surface: Color(0xFF12131A),
    surfaceSoft: Color(0xFF191B24),
    border: Color(0xFF272A34),
    text: Color(0xFFF6F7FB),
    textSoft: Color(0xFFD8DBE3),
    textMuted: Color(0xFF9BA0AD),
    navBackground: Color(0xFF111118),
    navBorder: Color(0xFF232632),
    accentStart: Color(0xFF3B71E8),
    accentEnd: Color(0xFF6A97FF),
    iconBackground: Color(0xFF1B1E27),
    buttonText: Color(0xFFFFFFFF),
  );

  static SafeHavenColors of(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? dark : light;
  }
}