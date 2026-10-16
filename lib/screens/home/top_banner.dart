import 'package:flutter/material.dart';
import '../../services/developer_profile_service.dart';
import '../../services/notification_service.dart';
import '../../services/theme/theme_manager.dart';
import '../../widgets/animated_tap.dart';
import '../account/developer_account_screen.dart';
import '../apps/catalogue_screen/catalogue_navigation.dart';
import '../notifications/notifications_screen.dart';

class TopBanner {
  static PreferredSizeWidget home() {
    return const _SafeHavenTopBanner(
      title: 'SafeHaven',
      showHomeDecoration: true,
      large: true,
      actions: [_NotificationsButton(), _AccountButton()],
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

class _AccountButton extends StatelessWidget {
  const _AccountButton();

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);
    final profile = DeveloperProfileService.instance..ensureLoaded();
    final placeholder = Icon(Icons.account_circle_rounded, size: 32, color: colors.textMuted);

    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: AnimatedTap(
        borderRadius: 99,
        scale: 0.92,
        onTap: () => Navigator.of(context).push(pushRoute(const DeveloperAccountScreen())),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Center(
            child: ListenableBuilder(
              listenable: profile,
              builder: (context, _) {
                final avatar = profile.avatarFile;
                if (avatar == null) return placeholder;
                return ClipOval(
                  child: Image.file(
                    avatar,
                    width: 30,
                    height: 30,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => placeholder,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationsButton extends StatelessWidget {
  const _NotificationsButton();

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);

    return AnimatedTap(
      borderRadius: 99,
      scale: 0.92,
      onTap: () => Navigator.of(context).push(pushRoute(const NotificationsScreen())),
      child: SizedBox(
        width: 40,
        height: 40,
        child: ValueListenableBuilder<int>(
          valueListenable: NotificationService.instance.unread,
          builder: (context, unread, _) => Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                unread > 0 ? Icons.notifications_rounded : Icons.notifications_none_rounded,
                size: 27,
                color: colors.textMuted,
              ),
              if (unread > 0)
                Positioned(
                  top: 8,
                  right: 9,
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: colors.accentStart,
                      shape: BoxShape.circle,
                      border: Border.all(color: colors.backgroundFrost, width: 1.5),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
