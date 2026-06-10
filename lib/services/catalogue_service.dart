import 'dart:collection';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';
import 'store_service.dart';

class CatalogueService {
  CatalogueService._();

  static final CatalogueService instance = CatalogueService._();

  static const int _maxGradientCacheEntries = 160;

  static final double _log80 = math.log(80);

  static const List<List<Color>> _fallbackPalettes = [
    [Color(0xFF135DFF), Color(0xFF8A32F4)],
    [Color(0xFF0F766E), Color(0xFF2563EB)],
    [Color(0xFF7C3AED), Color(0xFFDB2777)],
    [Color(0xFF0891B2), Color(0xFF4F46E5)],
  ];

  final LinkedHashMap<String, LinearGradient> _gradientCache =
  LinkedHashMap<String, LinearGradient>();

  final Map<String, Future<LinearGradient>> _gradientFutureCache = {};

  Future<List<CatalogueBannerItem>> bannersFor(
      List<PublicStoreApp> apps, {
        int limit = 6,
      }) async {
    if (apps.isEmpty || limit <= 0) {
      return const [];
    }

    final ranked = apps
        .map(
          (app) => _RankedCatalogueApp(
        app: app,
        score: _score(app),
        sortName: app.name.toLowerCase(),
      ),
    )
        .toList();

    ranked.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return a.sortName.compareTo(b.sortName);
    });

    final selected = ranked.take(limit).map((item) => item.app).toList();

    return Future.wait(
      selected.map((app) async {
        return CatalogueBannerItem(
          app: app,
          gradient: await _gradientFor(app),
        );
      }),
    );
  }

  int _score(PublicStoreApp app) {
    var score = 0;

    final ratingAvg = app.ratingAvg.isFinite ? app.ratingAvg : 0.0;
    final ratingCount = math.max(app.ratingCount, 0);

    if (ratingCount > 0) score += 30;
    score += math.min(ratingCount, 50);
    score += (ratingAvg.clamp(0.0, 5.0) * 8).round();

    if (app.verifiedSource) score += 20;
    if (app.iconUrl != null && app.iconUrl!.trim().isNotEmpty) score += 8;
    if (app.screenshots.isNotEmpty) score += 12;
    if (app.summary.trim().isNotEmpty) score += 6;

    return score;
  }

  Future<LinearGradient> _gradientFor(PublicStoreApp app) {
    final iconUrl = app.iconUrl?.trim();
    final cacheKey = '${app.packageName}|${iconUrl ?? ''}';

    final cached = _gradientCache[cacheKey];
    if (cached != null) {
      _gradientCache.remove(cacheKey);
      _gradientCache[cacheKey] = cached;
      return Future.value(cached);
    }

    final pending = _gradientFutureCache[cacheKey];
    if (pending != null) {
      return pending;
    }

    final future = _buildGradientFor(app, iconUrl, cacheKey);
    _gradientFutureCache[cacheKey] = future;

    return future.whenComplete(() {
      _gradientFutureCache.remove(cacheKey);
    });
  }

  Future<LinearGradient> _buildGradientFor(
      PublicStoreApp app,
      String? iconUrl,
      String cacheKey,
      ) async {
    Color? seed;

    if (iconUrl != null && iconUrl.isNotEmpty) {
      seed = await _dominantIconColor(iconUrl);
    }

    final gradient = seed == null
        ? _fallbackGradient(app.packageName)
        : _gradientFromColor(seed);

    if (seed != null) {
      _putGradientCache(cacheKey, gradient);
    }

    return gradient;
  }

  Future<Color?> _dominantIconColor(String iconUrl) async {
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        NetworkImage(iconUrl),
        maximumColorCount: 18,
        size: const Size(96, 96),
      );

      final candidates = <PaletteColor?>[
        palette.vibrantColor,
        palette.lightVibrantColor,
        palette.darkVibrantColor,
        palette.dominantColor,
        palette.mutedColor,
        palette.lightMutedColor,
        palette.darkMutedColor,
      ];

      PaletteColor? best;
      double bestScore = 0;

      for (final candidate in candidates) {
        if (candidate == null) continue;

        final score = _bannerColorScore(
          candidate.color,
          candidate.population,
        );

        if (score <= bestScore) continue;

        best = candidate;
        bestScore = score;
      }

      if (best == null || bestScore < 0.22) {
        return null;
      }

      return best.color;
    } catch (_) {
      return null;
    }
  }

  double _bannerColorScore(Color color, int population) {
    final hsl = HSLColor.fromColor(color);
    final hue = hsl.hue;
    final saturation = hsl.saturation;
    final lightness = hsl.lightness;

    if (lightness < 0.10 || lightness > 0.88) return 0;
    if (saturation < 0.16) return 0;

    final isMuddyBrown =
        hue >= 18 && hue <= 48 && saturation < 0.52 && lightness < 0.58;

    if (isMuddyBrown) return 0;

    final isWeakWarmNeutral =
        hue >= 12 && hue <= 62 && saturation < 0.34;

    if (isWeakWarmNeutral) return 0;

    final vividness = saturation * (1 - (lightness - 0.48).abs());
    final populationWeight = math.log(population + 1) / _log80;

    return vividness * populationWeight.clamp(0.35, 1.4);
  }

  LinearGradient _gradientFromColor(Color color) {
    final hsl = HSLColor.fromColor(color);

    final baseHue = hsl.hue;
    final first = HSLColor.fromAHSL(
      1,
      baseHue,
      hsl.saturation.clamp(0.52, 0.78),
      0.34,
    ).toColor();

    final second = HSLColor.fromAHSL(
      1,
      (baseHue + 22) % 360,
      hsl.saturation.clamp(0.48, 0.72),
      0.42,
    ).toColor();

    return LinearGradient(
      begin: Alignment.bottomLeft,
      end: Alignment.topRight,
      colors: [first, second],
    );
  }

  void _putGradientCache(String key, LinearGradient gradient) {
    _gradientCache[key] = gradient;

    while (_gradientCache.length > _maxGradientCacheEntries) {
      _gradientCache.remove(_gradientCache.keys.first);
    }
  }

  LinearGradient _fallbackGradient(String seed) {
    final hash = seed.codeUnits.fold<int>(
      0,
          (value, code) => ((value * 31) + code) & 0x7fffffff,
    );

    final colors = _fallbackPalettes[hash % _fallbackPalettes.length];

    return LinearGradient(
      begin: Alignment.bottomLeft,
      end: Alignment.topRight,
      colors: colors,
    );
  }
}

class _RankedCatalogueApp {
  const _RankedCatalogueApp({
    required this.app,
    required this.score,
    required this.sortName,
  });

  final PublicStoreApp app;
  final int score;
  final String sortName;
}

class CatalogueBannerItem {
  const CatalogueBannerItem({
    required this.app,
    required this.gradient,
  });

  final PublicStoreApp app;
  final LinearGradient gradient;
}