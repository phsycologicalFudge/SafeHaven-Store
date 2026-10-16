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

class CatalogueRecommendedSection extends StatefulWidget {
  const CatalogueRecommendedSection({
    super.key,
    required this.future,
    required this.storageId,
    this.speed = 1,
  });

  final Future<List<PublicStoreApp>> future;
  final String storageId;
  final double speed;

  @override
  State<CatalogueRecommendedSection> createState() => _CatalogueRecommendedSectionState();
}

class _CatalogueRecommendedSectionState extends State<CatalogueRecommendedSection>
    with WidgetsBindingObserver {
  static final Expando<List<CatalogueBannerItem>> _memo = Expando();

  static const Duration _bannerHoldDuration = Duration(seconds: 5);
  static const Duration _bannerMoveDuration = Duration(milliseconds: 520);
  static const Curve _bannerMoveCurve = Curves.easeOutCubic;

  static const double _bannerHeight = 176;

  PageController? _controller;
  Timer? _timer;
  List<CatalogueBannerItem>? _banners;
  int _page = 0;
  int _loadId = 0;
  bool _visible = true;
  bool _foreground = true;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final memo = _memo[widget.future];
    if (memo != null) {
      _banners = memo;
    } else {
      _load();
    }
  }

  @override
  void didUpdateWidget(covariant CatalogueRecommendedSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.future, widget.future)) _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final storage = PageStorage.maybeOf(context);
    if (_controller == null) {
      _page = storage?.readState(context, identifier: widget.storageId) as int? ?? 0;
    }

    final double screenWidth = MediaQuery.sizeOf(context).width;
    final double fraction = (screenWidth - 20.0) / screenWidth;
    final old = _controller;

    if (old == null) {
      _controller = PageController(viewportFraction: fraction, initialPage: _page);
    } else if ((old.viewportFraction - fraction).abs() > 0.001) {
      _controller = PageController(viewportFraction: fraction, initialPage: _page);
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }

    final visible = TickerMode.of(context);
    if (visible != _visible) {
      _visible = visible;
      if (visible) {
        _schedule();
      } else {
        _cancel();
        _settle();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      _schedule();
    } else {
      _cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancel();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final id = ++_loadId;
    final source = widget.future;
    try {
      final apps = await source;
      final banners = await CatalogueService.instance.bannersFor(apps);
      if (!mounted || id != _loadId) return;
      _memo[source] = banners;
      setState(() => _banners = banners);
      _schedule();
    } catch (_) {
      if (!mounted || id != _loadId) return;
      setState(() => _banners ??= const []);
    }
  }

  void _cancel() {
    _timer?.cancel();
    _timer = null;
  }

  void _schedule() {
    _cancel();
    if ((_banners?.length ?? 0) <= 1 || !_visible || !_foreground || _dragging) return;
    _timer = Timer(_bannerHoldDuration * (1 / widget.speed), _advance);
  }

  void _advance() {
    _timer = null;
    if (!mounted) return;
    final c = _controller;
    if (c == null || !c.hasClients) {
      _schedule();
      return;
    }
    c
        .animateToPage(_page + 1, duration: _bannerMoveDuration * (1 / widget.speed), curve: _bannerMoveCurve)
        .whenComplete(() {
      if (mounted && _timer == null) _schedule();
    });
  }

  void _settle() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = _controller;
      if (!mounted || c == null || !c.hasClients) return;
      final p = c.page;
      if (p != null && p != p.roundToDouble()) c.jumpToPage(p.round());
    });
  }

  void _onPageChanged(int i) {
    _page = i;
    PageStorage.maybeOf(context)?.writeState(context, i, identifier: widget.storageId);
    _schedule();
  }

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0) return false;
    if (n is ScrollStartNotification && n.dragDetails != null) {
      _dragging = true;
      _cancel();
    } else if (n is ScrollEndNotification && _dragging) {
      _dragging = false;
      _schedule();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final banners = _banners;
    final Widget content;

    if (banners == null) {
      content = const _RecommendedPlaceholder(key: ValueKey('placeholder'));
    } else if (banners.isEmpty) {
      content = const SizedBox.shrink(key: ValueKey('empty'));
    } else {
      content = Padding(
        key: const ValueKey('carousel'),
        padding: const EdgeInsets.only(top: 12),
        child: SizedBox(
          height: _bannerHeight,
          child: NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: PageView.builder(
              controller: _controller,
              clipBehavior: Clip.none,
              onPageChanged: _onPageChanged,
              itemBuilder: (context, index) {
                final banner = banners[index % banners.length];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6.0),
                  child: _RecommendedCard(item: banner),
                );
              },
            ),
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
  }
}

class _RecommendedPlaceholder extends StatelessWidget {
  const _RecommendedPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SizedBox(
        height: _CatalogueRecommendedSectionState._bannerHeight,
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

class _RecommendedCard extends StatelessWidget {
  const _RecommendedCard({required this.item});

  final CatalogueBannerItem item;

  @override
  Widget build(BuildContext context) {
    final app = item.app;

    return AnimatedTap(
      borderRadius: 20,
      scale: 0.985,
      onTap: () => Navigator.of(context).push(pushRoute(AppScreen(app: app))),
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
            Positioned(
              top: 14,
              right: 16,
              child: _BannerForegroundIcon(app: app),
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 18,
              child: Text(
                app.displaySummary,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15.5,
                  height: 1.25,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                  color: Colors.white,
                ),
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