import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../services/history_service.dart';
import '../../services/index_service.dart';
import '../../services/store_service.dart';
import '../../services/theme/theme_manager.dart';
import '../../widgets/animated_tap.dart';
import '../../widgets/refresh/pull_to_refresh.dart';
import 'app_screen/app_screen.dart';
import 'catalogue_screen/catalogue_navigation.dart';
import 'package:safehaven/translations/app_localizations.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<PublicStoreApp>? _apps;
  Object? _error;
  bool _visible = true;
  bool _stale = false;
  int _loadId = 0;

  @override
  void initState() {
    super.initState();
    _reload();
    HistoryService.instance.changes.addListener(_onHistoryChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = TickerMode.of(context);
    if (visible == _visible) return;
    _visible = visible;
    if (visible && _stale) {
      _stale = false;
      _reload();
    }
  }

  @override
  void dispose() {
    HistoryService.instance.changes.removeListener(_onHistoryChanged);
    super.dispose();
  }

  void _onHistoryChanged() {
    if (!mounted) return;
    if (_visible) {
      _reload();
    } else {
      _stale = true;
    }
  }

  Future<List<PublicStoreApp>> _load() async {
    return IndexService.instance.apps(await HistoryService.instance.getViewed());
  }

  Future<void> _reload() async {
    final id = ++_loadId;
    if (_apps == null && _error != null) setState(() => _error = null);
    try {
      final apps = await _load();
      if (!mounted || id != _loadId) return;
      setState(() {
        _apps = apps;
        _error = null;
      });
    } catch (e) {
      if (!mounted || id != _loadId) return;
      setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);
    final apps = _apps;

    if (apps == null && _error == null) {
      return Center(
        child: CircularProgressIndicator(color: colors.accentEnd),
      );
    }

    if (apps == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off_rounded,
                color: colors.textMuted,
                size: 34,
              ),
              const SizedBox(height: 14),
              Text(
                _error.toString(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: colors.textMuted,
                ),
              ),
              const SizedBox(height: 14),
              OutlinedButton(
                onPressed: _reload,
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.text,
                  side: BorderSide(color: colors.border),
                ),
                child: Text(AppLocalizations.of(context)!.retry),
              ),
            ],
          ),
        ),
      );
    }

    if (apps.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(
            AppLocalizations.of(context)!.historyEmpty,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.45,
              color: colors.textMuted,
            ),
          ),
        ),
      );
    }

    return PullRefresh(
      onRefresh: _reload,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 18),
        itemCount: apps.length + 1,
        itemBuilder: (context, i) => i == 0
            ? _SectionHeader(title: AppLocalizations.of(context)!.titleRecentlyViewed)
            : _AppRow(key: ValueKey(apps[i - 1].packageName), app: apps[i - 1]),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 6),
      child: SizedBox(
        height: 26,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
              color: colors.text,
            ),
          ),
        ),
      ),
    );
  }
}

class _AppRow extends StatelessWidget {
  const _AppRow({super.key, required this.app});

  final PublicStoreApp app;

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);

    return AnimatedTap(
      borderRadius: 18,
      onTap: () {
        Navigator.of(context).push(pushRoute(AppScreen(app: app)));
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
        child: Row(
          children: [
            _AppIcon(app: app, size: 48),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 52,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    app.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                      color: colors.text,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppIcon extends StatelessWidget {
  const _AppIcon({required this.app, required this.size});

  final PublicStoreApp app;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);
    final iconUrl = app.iconUrl;

    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.22),
      child: SizedBox(
        width: size,
        height: size,
        child: iconUrl == null
            ? Container(
          color: colors.surfaceSoft,
          child: Icon(
            Icons.apps_rounded,
            size: size * 0.48,
            color: colors.textMuted,
          ),
        )
            : CachedNetworkImage(
          imageUrl: iconUrl,
          width: size,
          height: size,
          fit: BoxFit.cover,
          memCacheWidth: (size * 2).toInt(),
          memCacheHeight: (size * 2).toInt(),
          fadeInDuration: const Duration(milliseconds: 120),
          filterQuality: FilterQuality.medium,
          placeholder: (_, __) => Container(
            color: colors.surfaceSoft,
            child: Icon(
              Icons.apps_rounded,
              size: size * 0.48,
              color: colors.textMuted,
            ),
          ),
          errorWidget: (_, __, ___) => Container(
            color: colors.surfaceSoft,
            child: Icon(
              Icons.apps_rounded,
              size: size * 0.48,
              color: colors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}