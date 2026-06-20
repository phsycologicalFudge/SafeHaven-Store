import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../services/logs/debug_log_service.dart';
import '../../services/index_service.dart';
import '../../services/installer/install_sync.dart';
import '../../services/installer/store_update_service.dart';
import '../../services/installer/unattended_update_service.dart';
import '../../services/store_service.dart';
import '../../services/theme/theme_manager.dart';
import '../../widgets/animated_tap.dart';
import '../../widgets/dialogs/update_results_dialog.dart';
import '../../widgets/refresh/pull_to_refresh.dart';
import 'app_screen/app_screen.dart';
import 'catalogue_screen/catalogue_navigation.dart';
import 'catalogue_screen/widgets/catalogue_download_button.dart';

class _UpdateOutcome {
  const _UpdateOutcome({required this.started, required this.failed});

  final int started;
  final List<UpdateFailure> failed;
}

class MyAppsScreen extends StatefulWidget {
  const MyAppsScreen({super.key});

  @override
  State<MyAppsScreen> createState() => _MyAppsScreenState();
}

class _MyAppsScreenState extends State<MyAppsScreen>
    with WidgetsBindingObserver {
  late Future<List<StoreUpdateCheck>> _future;
  bool _triggering = false;
  bool _autoTriggered = false;
  DateTime? _lastLifecycleLoad;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _future = _loadInstalledStoreApps();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final now = DateTime.now();
      if (_lastLifecycleLoad != null &&
          now.difference(_lastLifecycleLoad!) < const Duration(minutes: 5)) {
        return;
      }
      _lastLifecycleLoad = now;
      setState(() {
        _autoTriggered = false;
        _future = _loadInstalledStoreApps();
      });
    }
  }

  Future<List<StoreUpdateCheck>> _loadInstalledStoreApps({bool forceRefresh = false}) async {
    final index = await IndexService.instance.fetchIndex(forceRefresh: forceRefresh);
    final checks = await StoreUpdateService.instance.checkApps(index.apps, forceRefresh: forceRefresh);
    final installed = checks.where((c) => c.installed).toList()
      ..sort((a, b) => a.app.name.toLowerCase().compareTo(b.app.name.toLowerCase()));

    if (!_autoTriggered) {
      _autoTriggered = true;
      final updatable = installed.where((c) => c.canUpdate && c.latestVersion != null).toList();
      if (updatable.isNotEmpty) {
        _autoTriggerUpdates(updatable);
      }
    }

    return installed;
  }

  Future<_UpdateOutcome> _autoTriggerUpdates(List<StoreUpdateCheck> checks) async {
    final failed = <UpdateFailure>[];

    try {
      final eligible = <StoreUpdateCheck>[];
      for (final check in checks) {
        if (!check.installedState.isInstalledBySafeHaven) {
          failed.add(UpdateFailure(
            appName: check.app.name,
            reason: 'App cannot be updated by SafeHaven',
            blockedBySafeHaven: true,
          ));
          continue;
        }
        eligible.add(check);
      }

      if (eligible.isEmpty) {
        return _UpdateOutcome(started: 0, failed: failed);
      }

      final urlResults = await Future.wait(
        eligible.map((c) async {
          try {
            return await StoreService.instance.getDownloadUrl(
              packageName: c.app.packageName,
              versionCode: c.latestVersion!.versionCode,
            );
          } catch (e, s) {
            DebugLog.e('MyApps', 'getDownloadUrl failed: ${c.app.packageName}', e, s);
            return null;
          }
        }),
      );

      final updates = <Map<String, dynamic>>[];
      for (var i = 0; i < eligible.length; i++) {
        final url = urlResults[i];
        if (url != null) {
          updates.add({'packageName': eligible[i].app.packageName, 'downloadUrl': url});
        } else {
          failed.add(UpdateFailure(
            appName: eligible[i].app.name,
            reason: 'Could not get download link',
          ));
        }
      }

      if (updates.isEmpty) {
        return _UpdateOutcome(started: 0, failed: failed);
      }

      await UnattendedUpdateService.triggerManualBatchUpdate(updates);
      return _UpdateOutcome(started: updates.length, failed: failed);
    } catch (e, s) {
      DebugLog.e('MyApps', 'autoTriggerUpdates failed', e, s);
      return _UpdateOutcome(
        started: 0,
        failed: failed.isNotEmpty
            ? failed
            : [
          for (final c in checks)
            UpdateFailure(appName: c.app.name, reason: 'Could not start update'),
        ],
      );
    }
  }

  Future<void> _reload() async {
    setState(() {
      _autoTriggered = false;
      _future = _loadInstalledStoreApps(forceRefresh: true);
    });
    await _future;
  }

  Future<void> _triggerUpdateAll(List<StoreUpdateCheck> checks) async {
    if (_triggering) return;
    final updatable = checks.where((c) {
      final live = InstallSync.cachedCheck[c.app.packageName];
      return (live ?? c).canUpdate && (live ?? c).latestVersion != null;
    }).toList();
    if (updatable.isEmpty) return;
    setState(() => _triggering = true);
    try {
      final outcome = await _autoTriggerUpdates(updatable);
      if (mounted && outcome.failed.isNotEmpty) {
        UpdateResultsDialog.show(context, started: outcome.started, failed: outcome.failed);
      }
    } finally {
      if (mounted) setState(() => _triggering = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);

    return FutureBuilder<List<StoreUpdateCheck>>(
      future: _future,
      builder: (context, snapshot) {
        final loading = snapshot.connectionState == ConnectionState.waiting;
        final checks = snapshot.data ?? const <StoreUpdateCheck>[];
        return PullRefresh(
          onRefresh: _reload,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              if (loading)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 54, 18, 54),
                    child: Center(child: CircularProgressIndicator(color: colors.accentEnd)),
                  ),
                ),
              if (snapshot.hasError)
                SliverToBoxAdapter(
                  child: _ErrorBlock(message: snapshot.error.toString(), onRetry: _reload),
                ),
              if (!loading && !snapshot.hasError && checks.isEmpty)
                const SliverToBoxAdapter(child: _EmptyBlock()),
              if (!loading && !snapshot.hasError && checks.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: _UpdateBanner(
                    checks: checks,
                    triggering: _triggering,
                    onUpdateAll: () => _triggerUpdateAll(checks),
                  ),
                ),
                SliverToBoxAdapter(child: _InstalledSection(checks: checks)),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 18)),
            ],
          ),
        );
      },
    );
  }
}

class _UpdateBanner extends StatelessWidget {
  const _UpdateBanner({required this.checks, required this.triggering, required this.onUpdateAll});

  final List<StoreUpdateCheck> checks;
  final bool triggering;
  final VoidCallback onUpdateAll;

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);

    return ListenableBuilder(
      listenable: InstallSync.checkVersion,
      builder: (context, _) {
        final liveCount = checks.where((c) {
          final live = InstallSync.cachedCheck[c.app.packageName];
          return (live ?? c).canUpdate;
        }).length;

        if (liveCount == 0) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: colors.accentGradient,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '$liveCount update${liveCount == 1 ? '' : 's'} available',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: colors.buttonText),
                    ),
                  ),
                  AnimatedTap(
                    borderRadius: 8,
                    onTap: triggering ? null : onUpdateAll,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: colors.buttonText.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: triggering
                          ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(colors.buttonText),
                        ),
                      )
                          : Text(
                        'Update All',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: colors.buttonText),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _InstalledSection extends StatelessWidget {
  const _InstalledSection({required this.checks});

  final List<StoreUpdateCheck> checks;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: checks.map((c) => _InstalledAppRow(check: c)).toList(),
    );
  }
}

class _InstalledAppRow extends StatelessWidget {
  const _InstalledAppRow({required this.check});

  final StoreUpdateCheck check;

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);

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
                    if (check.app.developerName.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        check.app.developerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: colors.textMuted),
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
      padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.apps_rounded, size: 38, color: colors.textMuted),
            const SizedBox(height: 14),
            Text(
              'No installed store apps found.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: colors.text),
            ),
            const SizedBox(height: 6),
            Text(
              'Apps only appear here when their package name matches an app in the catalogue.',
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
              'Could not load your apps',
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
                      child: Text('Retry', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: colors.buttonText)),
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