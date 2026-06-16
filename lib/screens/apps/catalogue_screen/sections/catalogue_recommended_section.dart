import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:math' as math;
import 'dart:async';
import '../../../../services/catalogue_service.dart';
import '../../../../services/store_service.dart';
import '../../../../services/theme/theme_manager.dart';
import '../../../../widgets/animated_tap.dart';
import '../../app_screen/app_screen.dart';
import '../catalogue_navigation.dart';
import '../widgets/catalogue_shared_widgets.dart';

class CatalogueRecommendedSection extends StatefulWidget {
  const CatalogueRecommendedSection({required this.future});

  final Future<List<PublicStoreApp>> future;

  @override
  State<CatalogueRecommendedSection> createState() => _CatalogueRecommendedSectionState();
}

class _CatalogueRecommendedSectionState extends State<CatalogueRecommendedSection> {
  PageController? _controller;
  Timer? _timer;
  int _page = 0;
  Future<List<CatalogueBannerItem>>? _bannerFuture;
  List<PublicStoreApp>? _lastApps;

  static const Duration _bannerHoldDuration = Duration(seconds: 5);
  static const Duration _bannerMoveDuration = Duration(milliseconds: 520);
  static const Curve _bannerMoveCurve = Curves.easeOutCubic;

  static const double _bannerHeight = 200;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final double screenWidth = MediaQuery.sizeOf(context).width;
    final double cardWidth = screenWidth - 32.0;
    final double slotWidth = cardWidth + 12.0;
    final double fraction = slotWidth / screenWidth;

    if (_controller == null) {
      _controller = PageController(viewportFraction: fraction, initialPage: _page);
    } else if ((_controller!.viewportFraction - fraction).abs() > 0.001) {
      _controller!.dispose();
      _controller = PageController(viewportFraction: fraction, initialPage: _page);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  Future<List<CatalogueBannerItem>> _bannersFor(List<PublicStoreApp> apps) {
    if (_bannerFuture == null || !identical(_lastApps, apps)) {
      _lastApps = apps;
      _bannerFuture = CatalogueService.instance.bannersFor(apps).then((banners) {
        _startTimer(banners.length);
        return banners;
      });
    }
    return _bannerFuture!;
  }

  void _startTimer(int count) {
    if (count <= 1 || _timer != null || !mounted) return;

    _timer = Timer.periodic(_bannerHoldDuration, (_) {
      if (!mounted || _controller == null || !_controller!.hasClients) return;
      _page += 1;
      _controller!.animateToPage(
        _page,
        duration: _bannerMoveDuration,
        curve: _bannerMoveCurve,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<PublicStoreApp>>(
      future: widget.future,
      builder: (context, snapshot) {
        final isAppsLoading = snapshot.connectionState == ConnectionState.waiting;
        final apps = snapshot.data ?? const <PublicStoreApp>[];

        if (!isAppsLoading && apps.isEmpty) {
          return const SizedBox.shrink();
        }

        return FutureBuilder<List<CatalogueBannerItem>>(
          future: isAppsLoading ? null : _bannersFor(apps),
          builder: (context, bannerSnapshot) {
            final isBannersLoading =
                bannerSnapshot.connectionState == ConnectionState.waiting ||
                    isAppsLoading;
            final banners = bannerSnapshot.data ?? const <CatalogueBannerItem>[];

            Widget content;

            if (isBannersLoading) {
              content = const _RecommendedPlaceholder(key: ValueKey('placeholder'));
            } else if (banners.isEmpty) {
              content = const SizedBox.shrink(key: ValueKey('empty'));
            } else {
              content = Padding(
                key: const ValueKey('carousel'),
                padding: const EdgeInsets.only(top: 12),
                child: SizedBox(
                  height: _bannerHeight,
                  child: PageView.builder(
                    controller: _controller,
                    clipBehavior: Clip.none,
                    onPageChanged: (i) => _page = i,
                    itemBuilder: (context, index) {
                      final banner = banners[index % banners.length];
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6.0),
                        child: _RecommendedBannerCard(item: banner),
                      );
                    },
                  ),
                ),
              );
            }

            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: content,
            );
          },
        );
      },
    );
  }
}

class _RecommendedPlaceholder extends StatelessWidget {
  const _RecommendedPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SizedBox(
        height: 160,
        child: Center(child: _LoadingDots()),
      ),
    );
  }
}

class _LoadingDots extends StatefulWidget {
  const _LoadingDots({super.key});

  @override
  State<_LoadingDots> createState() => _LoadingDotsState();
}

class _LoadingDotsState extends State<_LoadingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  static const double _piOverZeroPointSix = math.pi / 0.6;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        final delay = index * 0.18;

        return AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            double t = (_controller.value - delay) % 1.0;
            if (t < 0) t += 1.0;

            double pulse = 0.0;
            if (t < 0.6) {
              pulse = math.sin(t * _piOverZeroPointSix);
            }

            final scale = 0.8 + (0.35 * pulse);
            final opacity = 0.3 + (0.7 * pulse);

            return Transform.scale(
              scale: scale,
              child: Opacity(
                opacity: opacity,
                child: child,
              ),
            );
          },
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 6),
            width: 11,
            height: 11,
            decoration: BoxDecoration(
              color: colors.textMuted,
              shape: BoxShape.circle,
            ),
          ),
        );
      }),
    );
  }
}

class _RecommendedBannerCard extends StatelessWidget {
  const _RecommendedBannerCard({required this.item});

  final CatalogueBannerItem item;

  @override
  Widget build(BuildContext context) {
    final app = item.app;

    return AnimatedTap(
      borderRadius: 20,
      onTap: () {
        Navigator.of(context).push(pushRoute(AppScreen(app: app)));
      },
      child: Container(
        decoration: BoxDecoration(
          gradient: item.gradient,
          borderRadius: BorderRadius.circular(20),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned(
              right: -24,
              bottom: -22,
              child: Opacity(
                opacity: 0.13,
                child: _BannerLargeIcon(app: app),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          app.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 19,
                            height: 1.05,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      _BannerForegroundIcon(app: app),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.only(right: 78),
                    child: Text(
                      app.displaySummary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.25,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withOpacity(0.86),
                      ),
                    ),
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      if (app.ratingCount > 0)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              app.displayRating,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: Colors.white.withOpacity(0.9),
                              ),
                            ),
                            Transform.translate(
                              offset: const Offset(0, -1.5),
                              child: Text(
                                '★',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.white.withOpacity(0.9),
                                ),
                              ),
                            ),
                          ],
                        ),
                      if (app.ratingCount > 0 && app.developerName.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Container(
                            width: 3,
                            height: 3,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.65),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      if (app.developerName.isNotEmpty)
                        Expanded(
                          child: Text(
                            app.developerName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.white.withOpacity(0.82),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BannerForegroundIcon extends StatelessWidget {
  const _BannerForegroundIcon({required this.app});

  final PublicStoreApp app;

  @override
  Widget build(BuildContext context) {
    final iconUrl = app.iconUrl?.trim();
    final hasIcon = iconUrl != null && iconUrl.isNotEmpty;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: 58,
        height: 58,
        child: !hasIcon
            ? Container(
          color: Colors.white.withOpacity(0.16),
          child: const Icon(
            Icons.apps_rounded,
            size: 28,
            color: Colors.white,
          ),
        )
            : CachedNetworkImage(
          imageUrl: iconUrl,
          fit: BoxFit.cover,
          memCacheWidth: 116,
          memCacheHeight: 116,
          fadeInDuration: const Duration(milliseconds: 120),
          placeholder: (_, __) => const SizedBox.shrink(),
          errorWidget: (_, __, ___) => Container(
            color: Colors.white.withOpacity(0.16),
            child: const Icon(
              Icons.apps_rounded,
              size: 28,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _BannerLargeIcon extends StatelessWidget {
  const _BannerLargeIcon({required this.app});

  final PublicStoreApp app;

  @override
  Widget build(BuildContext context) {
    final iconUrl = app.iconUrl?.trim();
    final hasIcon = iconUrl != null && iconUrl.isNotEmpty;

    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: SizedBox(
        width: 148,
        height: 148,
        child: !hasIcon
            ? Container(
          color: Colors.white.withOpacity(0.16),
          child: const Icon(
            Icons.apps_rounded,
            size: 96,
            color: Colors.white,
          ),
        )
            : CachedNetworkImage(
          imageUrl: iconUrl,
          fit: BoxFit.cover,
          memCacheWidth: 296,
          memCacheHeight: 296,
          fadeInDuration: const Duration(milliseconds: 120),
          placeholder: (_, __) => const SizedBox.shrink(),
          errorWidget: (_, __, ___) => Container(
            color: Colors.white.withOpacity(0.16),
            child: const Icon(
              Icons.apps_rounded,
              size: 96,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}