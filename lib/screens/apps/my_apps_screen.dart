import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../services/logs/debug_log_service.dart';
import '../../services/index_service.dart';
import '../../services/installer/apk_install_service.dart';
import '../../services/installer/install_sync.dart';
import '../../services/installer/store_update_service.dart';
import '../../services/store_service.dart';
import '../../services/theme/theme_manager.dart';
import '../../widgets/animated_tap.dart';
import '../../widgets/dialogs/update_results_dialog.dart';
import '../../widgets/refresh/pull_to_refresh.dart';
import 'app_screen/app_screen.dart';
import 'catalogue_screen/catalogue_navigation.dart';
import 'catalogue_screen/widgets/catalogue_download_button.dart';
import 'package:safehaven/translations/app_localizations.dart';

const Color _danger = Color(0xFFE85D75);
final RegExp _leadingV = RegExp(r'^v', caseSensitive: false);

int _byName(StoreUpdateCheck a, StoreUpdateCheck b) =>
    a.app.name.toLowerCase().compareTo(b.app.name.toLowerCase());

class MyAppsScreen extends StatefulWidget {
  const MyAppsScreen({super.key});

  @override
  State<MyAppsScreen> createState() => _MyAppsScreenState();
}

class _MyAppsScreenState extends State<MyAppsScreen>
    with WidgetsBindingObserver {
  List<StoreUpdateCheck> _checks = const [];
  bool _initialLoading = true;
  bool _refreshing = false;
  Object? _error;
  bool _visible = true;
  int _loadId = 0;
  int _batchTotal = 0;
  int _batchDone = 0;
  bool _batchCancelled = false;
  String? _batchCurrent;

  bool get _batchRunning => _batchTotal > 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = TickerMode.of(context);
    if (visible == _visible) return;
    _visible = visible;
    if (visible && !_initialLoading) _load(refreshStates: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_initialLoading) {
      _load(refreshStates: true);
    }
  }

  Future<void> _load({bool refreshIndex = false, bool refreshStates = false}) async {
    final id = ++_loadId;
    if (refreshIndex && !_initialLoading) setState(() => _refreshing = true);
    try {
      if (refreshIndex) await IndexService.instance.sync(force: true);
      final installed = await StoreUpdateService.instance.installedChecks(
        forceRefresh: refreshIndex || refreshStates,
      );
      if (!mounted || id != _loadId) return;
      installed.sort(_byName);
      for (final c in installed) {
        if (!(InstallSync.active[c.app.packageName]?.value ?? false)) {
          InstallSync.cachedCheck[c.app.packageName] = c;
        }
      }
      InstallSync.bumpCheck();
      setState(() {
        _checks = installed;
        _error = null;
      });
    } catch (e) {
      if (!mounted || id != _loadId) return;
      setState(() => _error = e);
    }
    if (!mounted || id != _loadId) return;
    setState(() {
      _initialLoading = false;
      _refreshing = false;
    });
  }

  Future<void> _reload() => _load(refreshIndex: true);

  StoreUpdateCheck _live(StoreUpdateCheck c) =>
      InstallSync.cachedCheck[c.app.packageName] ?? c;

  bool _isQueueable(StoreUpdateCheck c) => c.updatable && c.latestVersion != null;

  Future<Object?> _updateApp(PublicStoreApp app) async {
    final pkg = app.packageName;
    InstallSync.register(pkg);
    if (InstallSync.active[pkg]!.value) return null;
    InstallSync.active[pkg]!.value = true;
    InstallSync.progress[pkg]!.value = 0.0;
    try {
      await ApkInstallService.instance.downloadAndInstall(
        app: app,
        onProgress: (p) => InstallSync.progress[pkg]!.value = p.clamp(0.0, 1.0),
      );
      return null;
    } catch (e, s) {
      if (e.toString() != 'download_cancelled') {
        DebugLog.e('MyApps', 'update failed: $pkg', e, s);
      }
      return e;
    } finally {
      InstallSync.active[pkg]!.value = false;
      InstallSync.progress[pkg]!.value = 0.0;
    }
  }

  Future<void> _updateAll() async {
    if (_batchRunning) return;
    final queue = _checks.map(_live).where(_isQueueable).toList();
    if (queue.isEmpty) return;

    final l = AppLocalizations.of(context)!;
    final failed = <UpdateFailure>[];

    setState(() {
      _batchCancelled = false;
      _batchTotal = queue.length;
      _batchDone = 0;
    });

    for (final check in queue) {
      if (_batchCancelled || !mounted) break;
      _batchCurrent = check.app.packageName;
      final error = await _updateApp(check.app);
      if (error != null && error.toString() != 'download_cancelled') {
        failed.add(UpdateFailure(
          appName: check.app.name,
          reason: ApkInstallService.failureMessage(error, l),
        ));
      }
      if (mounted) setState(() => _batchDone++);
    }

    _batchCurrent = null;
    if (!mounted) return;
    final started = _batchDone - failed.length;
    setState(() {
      _batchTotal = 0;
      _batchDone = 0;
    });

    _load(refreshStates: true);
    for (final delay in const [Duration(seconds: 8), Duration(seconds: 20)]) {
      Future.delayed(delay, () {
        if (mounted) _load(refreshStates: true);
      });
    }

    if (failed.isNotEmpty) {
      UpdateResultsDialog.show(context, started: started, failed: failed);
    }
  }

  Future<void> _cancelAll() async {
    if (!_batchRunning) return;
    setState(() => _batchCancelled = true);
    final pkg = _batchCurrent;
    if (pkg != null) {
      await ApkInstallService.instance.cancelDownload(packageName: pkg);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);

    return PullRefresh(
      onRefresh: _reload,
      child: ListenableBuilder(
        listenable: InstallSync.checkVersion,
        builder: (context, _) {
          final live = _checks.map(_live).where((c) => c.installed).toList();
          final updates = live.where((c) => c.canUpdate).toList()
            ..sort((a, b) {
              final byMismatch = (a.hasConfirmedSignatureMismatch ? 1 : 0)
                  .compareTo(b.hasConfirmedSignatureMismatch ? 1 : 0);
              return byMismatch != 0 ? byMismatch : _byName(a, b);
            });
          final rest = live.where((c) => !c.canUpdate).toList();
          final queueable = updates.where(_isQueueable).length;

          return CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              if (_initialLoading)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 54, 18, 54),
                    child: Center(child: CircularProgressIndicator(color: colors.accentEnd)),
                  ),
                ),
              if (_refreshing && !_initialLoading)
                SliverToBoxAdapter(
                  child: LinearProgressIndicator(
                    minHeight: 2,
                    color: colors.accentEnd,
                    backgroundColor: Colors.transparent,
                  ),
                ),
              if (!_initialLoading && _error != null && live.isEmpty)
                SliverToBoxAdapter(
                  child: _ErrorBlock(message: _error.toString(), onRetry: _reload),
                ),
              if (!_initialLoading && _error == null && live.isEmpty)
                const SliverToBoxAdapter(child: _EmptyBlock()),
              if (!_initialLoading && (queueable > 0 || _batchRunning))
                SliverToBoxAdapter(
                  child: _UpdateBanner(
                    count: queueable,
                    batchTotal: _batchTotal,
                    batchDone: _batchDone,
                    cancelling: _batchCancelled,
                    onUpdateAll: _updateAll,
                    onCancel: _cancelAll,
                  ),
                ),
              if (!_initialLoading && updates.isNotEmpty)
                SliverList.builder(
                  itemCount: updates.length,
                  itemBuilder: (context, i) => _InstalledAppRow(
                    key: ValueKey('u:${updates[i].app.packageName}'),
                    check: updates[i],
                  ),
                ),
              if (!_initialLoading && rest.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: _SectionHeader(
                    title: AppLocalizations.of(context)!.myAppsInstalledSection,
                    count: rest.length,
                  ),
                ),
                SliverList.builder(
                  itemCount: rest.length,
                  itemBuilder: (context, i) => _InstalledAppRow(
                    key: ValueKey('i:${rest[i].app.packageName}'),
                    check: rest[i],
                  ),
                ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 18)),
            ],
          );
        },
      ),
    );
  }
}

class _UpdateBanner extends StatelessWidget {
  const _UpdateBanner({
    required this.count,
    required this.batchTotal,
    required this.batchDone,
    required this.cancelling,
    required this.onUpdateAll,
    required this.onCancel,
  });

  final int count;
  final int batchTotal;
  final int batchDone;
  final bool cancelling;
  final VoidCallback onUpdateAll;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);
    final l = AppLocalizations.of(context)!;
    final running = batchTotal > 0;
    final step = batchDone < batchTotal ? batchDone + 1 : batchTotal;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: colors.accentGradient,
          borderRadius: BorderRadius.circular(14),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            children: [
              if (running)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: batchDone / batchTotal),
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    builder: (context, v, _) => LinearProgressIndicator(
                      value: v,
                      minHeight: 3,
                      color: colors.buttonText.withOpacity(0.85),
                      backgroundColor: colors.buttonText.withOpacity(0.18),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        layoutBuilder: (top, previous) => Stack(
                          alignment: Alignment.centerLeft,
                          children: [...previous, if (top != null) top],
                        ),
                        child: Text(
                          running
                              ? l.myAppsUpdatingProgress(step, batchTotal)
                              : l.myAppsUpdatesAvailable(count),
                          key: ValueKey(running ? 'p$step' : 'c$count'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: colors.buttonText,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    AnimatedTap(
                      borderRadius: 8,
                      onTap: running ? (cancelling ? null : onCancel) : onUpdateAll,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 84),
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: colors.buttonText.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: cancelling
                            ? SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(colors.buttonText),
                                ),
                              )
                            : Text(
                                running ? l.commonCancel : l.myAppsUpdateAll,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: colors.buttonText,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
              color: colors.text,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: colors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _InstalledAppRow extends StatelessWidget {
  const _InstalledAppRow({super.key, required this.check});

  final StoreUpdateCheck check;

  String? _subtitle(BuildContext context) {
    if (check.updateBlocked) {
      return AppLocalizations.of(context)!.updateFailureCannotUpdate;
    }
    if (check.canUpdate) {
      final name = (check.latestVersionName ?? '').replaceFirst(_leadingV, '');
      return AppLocalizations.of(context)!
          .myAppsVersionAvailable(name.isEmpty ? '${check.latestVersionCode}' : name);
    }
    if (check.app.developerName.isNotEmpty) return check.app.developerName;
    return check.installedVersionName;
  }

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);
    final subtitle = _subtitle(context);

    return AnimatedTap(
      borderRadius: 18,
      onTap: () {
        Navigator.of(context).push(pushRoute(AppScreen(app: check.app)));
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
        child: Row(
          children: [
            _AppIcon(app: check.app, size: 48),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 56,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      check.app.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                        color: colors.text,
                      ),
                    ),
                    if (subtitle != null && subtitle.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: check.updateBlocked ? _danger : colors.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            CatalogueDownloadButton(
              app: check.app,
              compact: true,
              key: ValueKey(check.app.packageName),
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
            ? Container(color: colors.surfaceSoft, child: Icon(Icons.apps_rounded, size: size * 0.48, color: colors.textMuted))
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
            child: Icon(Icons.apps_rounded, size: size * 0.48, color: colors.textMuted),
          ),
          errorWidget: (_, __, ___) => Container(
            color: colors.surfaceSoft,
            child: Icon(Icons.apps_rounded, size: size * 0.48, color: colors.textMuted),
          ),
        ),
      ),
    );
  }
}

class _EmptyBlock extends StatelessWidget {
  const _EmptyBlock();

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 54, 24, 54),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.apps_rounded, size: 38, color: colors.textMuted),
            const SizedBox(height: 14),
            Text(
              AppLocalizations.of(context)!.myAppsEmptyTitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: colors.text),
            ),
            const SizedBox(height: 6),
            Text(
              AppLocalizations.of(context)!.myAppsEmptyBody,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, height: 1.4, color: colors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBlock extends StatelessWidget {
  const _ErrorBlock({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 54, 24, 54),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.error_outline_rounded, size: 36, color: colors.textMuted),
            const SizedBox(height: 14),
            Text(
              AppLocalizations.of(context)!.myAppsErrorTitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: colors.text),
            ),
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, height: 1.35, color: colors.textSoft)),
            const SizedBox(height: 20),
            SizedBox(
              height: 42,
              child: DecoratedBox(
                decoration: BoxDecoration(gradient: colors.accentGradient, borderRadius: BorderRadius.circular(12)),
                child: AnimatedTap(
                  borderRadius: 12,
                  onTap: onRetry,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Center(
                      child: Text(AppLocalizations.of(context)!.retry, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: colors.buttonText)),
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