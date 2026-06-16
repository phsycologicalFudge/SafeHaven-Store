import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../services/store_service.dart';
import '../../../../services/theme/theme_manager.dart';

const List<List<Color>> _chipPalettes = [
  [Color(0xFF3B71E8), Color(0xFFD6E4FF)],
  [Color(0xFF0F766E), Color(0xFFCCFBF1)],
  [Color(0xFF7C3AED), Color(0xFFEDE9FE)],
  [Color(0xFFDB2777), Color(0xFFFCE7F3)],
  [Color(0xFFD97706), Color(0xFFFEF3C7)],
  [Color(0xFF059669), Color(0xFFD1FAE5)],
  [Color(0xFFDC2626), Color(0xFFFEE2E2)],
  [Color(0xFF0284C7), Color(0xFFE0F2FE)],
];

List<Color> _paletteFor(String seed) {
  final hash = seed.codeUnits.fold<int>(
    0,
        (value, code) => ((value * 31) + code) & 0x7fffffff,
  );
  return _chipPalettes[hash % _chipPalettes.length];
}

class _AppIconFallback extends StatelessWidget {
  const _AppIconFallback({
    required this.app,
    required this.size,
    required this.radius,
  });

  final PublicStoreApp app;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = _paletteFor(app.packageName);
    final bg = isDark ? palette[0].withOpacity(0.22) : palette[1];
    final fg = isDark ? palette[1] : palette[0];
    final letter = app.name.trim().isNotEmpty
        ? app.name.trim()[0].toUpperCase()
        : '?';

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Center(
        child: Text(
          letter,
          style: TextStyle(
            fontSize: size * 0.42,
            fontWeight: FontWeight.w800,
            color: fg,
            height: 1,
          ),
        ),
      ),
    );
  }
}

class CatalogueAppIcon extends StatelessWidget {
  const CatalogueAppIcon({required this.app, required this.size});

  final PublicStoreApp app;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);
    final iconUrl = app.iconUrl?.trim();
    final hasIcon = iconUrl != null && iconUrl.isNotEmpty;

    if (!hasIcon) {
      return _AppIconFallback(
        app: app,
        size: size,
        radius: size * 0.22,
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(size * 0.22),
      ),
      clipBehavior: Clip.antiAlias,
      child: CachedNetworkImage(
        imageUrl: iconUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        memCacheWidth: (size * 2).toInt(),
        memCacheHeight: (size * 2).toInt(),
        fadeInDuration: const Duration(milliseconds: 120),
        filterQuality: FilterQuality.medium,
        placeholder: (_, __) => const SizedBox.shrink(),
        errorWidget: (_, __, ___) => _AppIconFallback(
          app: app,
          size: size,
          radius: size * 0.22,
        ),
      ),
    );
  }
}

class CatalogueRawAppIcon extends StatelessWidget {
  const CatalogueRawAppIcon({
    required this.app,
    required this.size,
    required this.radius,
  });

  final PublicStoreApp app;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);
    final iconUrl = app.iconUrl?.trim();
    final hasIcon = iconUrl != null && iconUrl.isNotEmpty;

    if (!hasIcon) {
      return _AppIconFallback(app: app, size: size, radius: radius);
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(radius),
      ),
      clipBehavior: Clip.antiAlias,
      child: CachedNetworkImage(
        imageUrl: iconUrl,
        fit: BoxFit.cover,
        memCacheWidth: (size * 2).toInt(),
        memCacheHeight: (size * 2).toInt(),
        fadeInDuration: const Duration(milliseconds: 120),
        filterQuality: FilterQuality.medium,
        placeholder: (_, __) => const SizedBox.shrink(),
        errorWidget: (_, __, ___) =>
            _AppIconFallback(app: app, size: size, radius: radius),
      ),
    );
  }
}