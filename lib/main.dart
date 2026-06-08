import 'package:flutter/material.dart';
import 'package:safehaven/services/installer/background_tasks.dart';
import 'screens/boot_screen/boot.dart';
import 'services/theme/theme_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initBackgroundTasks();
  await SafeHavenThemeManager.instance.init();
  runApp(const SafeHavenApp());
}

class SafeHavenApp extends StatelessWidget {
  const SafeHavenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SafeHavenThemeManager.instance,
      builder: (context, child) {
        final isDark = SafeHavenThemeManager.instance.isDark;
        final currentColors = isDark ? SafeHavenTheme.dark : SafeHavenTheme.light;

        return MaterialApp(
          title: 'SafeHaven',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            brightness: isDark ? Brightness.dark : Brightness.light,
            scaffoldBackgroundColor: currentColors.background,
            colorScheme: ColorScheme.fromSeed(
              seedColor: currentColors.accentStart,
              brightness: isDark ? Brightness.dark : Brightness.light,
            ),
            fontFamily: 'Roboto',
            useMaterial3: true,
          ),
          home: const BootScreen(),
        );
      },
    );
  }
}