import 'package:flutter/material.dart';
import '../../services/theme/theme_manager.dart';

class TopBanner {
  static PreferredSizeWidget home() {
    return const _SafeHavenTopBanner(
      title: 'SafeHaven',
      showHomeDecoration: true,
      large: true,
      actions: [],
    );
  }

  static PreferredSizeWidget defaultScreen({
    required String title,
    List<Widget> actions = const [],
  }) {
    return _SafeHavenTopBanner(
      title: title,
      showHomeDecoration: false,
      large: true,
      actions: actions,
    );
  }
}

class _SafeHavenTopBanner extends StatelessWidget
    implements PreferredSizeWidget {
  const _SafeHavenTopBanner({
    required this.title,
    required this.showHomeDecoration,
    required this.large,
    required this.actions,
  });

  final String title;
  final bool showHomeDecoration;
  final bool large;
  final List<Widget> actions;

  @override
  Size get preferredSize => Size.fromHeight(large ? 62 : kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AppBar(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: colors.backgroundFrost,
      foregroundColor: colors.text,
      surfaceTintColor: Colors.transparent,
      titleSpacing: large ? 16 : 0,
      toolbarHeight: large ? 62 : kToolbarHeight,
      title: Row(
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (showHomeDecoration) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/icons/icon.png',
                width: 28,
                height: 28,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 9),
          ],
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShaderMask(
                  shaderCallback: (bounds) =>
                      colors.accentGradient.createShader(bounds),
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: large ? 20 : 19,
                      fontWeight: large ? FontWeight.w600 : FontWeight.w700,
                      letterSpacing: large ? -0.8 : -0.3,
                      height: 1,
                      color: Colors.white,
                    ),
                  ),
                ),
                if (showHomeDecoration)
                  Text(
                    'store',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.4,
                      height: 1.4,
                      color: isDark
                          ? Colors.white.withOpacity(0.28)
                          : Colors.black.withOpacity(0.28),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      actions: actions,
    );
  }
}