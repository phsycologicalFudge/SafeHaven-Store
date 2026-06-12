import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../services/installer/apk_install_service.dart';
import '../../../../services/installer/install_sync.dart';
import '../../../../services/installer/store_update_service.dart';
import '../../../../services/store_service.dart';
import '../../../../services/theme/theme_manager.dart';

class AppScreenInstallButton extends StatefulWidget {
  const AppScreenInstallButton({
    super.key,
    required this.app,
    this.compact = false,
  });

  final PublicStoreApp app;
  final bool compact;

  @override
  State<AppScreenInstallButton> createState() => _AppScreenInstallButtonState();
}

class _AppScreenInstallButtonState extends State<AppScreenInstallButton>
    with WidgetsBindingObserver {
  double _lastPaintedProgress = -1;

  String get _pkg => widget.app.packageName;
  bool get _hasVersion => widget.app.versions.isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    InstallSync.register(_pkg);
    _loadPackageState(showChecking: true);
  }

  @override
  void didUpdateWidget(covariant AppScreenInstallButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.app.packageName != widget.app.packageName) {
      InstallSync.register(_pkg);
    }
    if (oldWidget.app.packageName != widget.app.packageName ||
        oldWidget.app.latestVersion?.versionCode !=
            widget.app.latestVersion?.versionCode) {
      _loadPackageState();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadPackageState();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _loadPackageState({bool showChecking = false}) async {
    if (InstallSync.cachedCheck[_pkg] != null && showChecking) {
      showChecking = false;
    }

    if (showChecking && mounted) {
      InstallSync.isChecking[_pkg]!.value = true;
    }

    try {
      final check = await StoreUpdateService.instance.checkApp(widget.app);
      if (!mounted) return;

      InstallSync.cachedCheck[_pkg] = check;
      InstallSync.isChecking[_pkg]!.value = false;
      InstallSync.bumpCheck();
    } catch (_) {
      if (mounted) {
        InstallSync.isChecking[_pkg]!.value = false;
      }
    }
  }

  Future<void> _primaryAction() async {
    final isInstalling = InstallSync.active[_pkg]!.value;
    final isChecking = InstallSync.isChecking[_pkg]!.value;

    if (!_hasVersion || isInstalling || isChecking) return;

    final check = InstallSync.cachedCheck[_pkg];
    final status = check?.status;

    if (status == StoreUpdateStatus.current ||
        status == StoreUpdateStatus.installedNewerThanStore) {
      await _openInstalledApp();
      return;
    }

    if (status == StoreUpdateStatus.notInstalled ||
        status == StoreUpdateStatus.updateAvailable) {
      await _install();
    }
  }

  Future<void> _openInstalledApp() async {
    try {
      await ApkInstallService.instance.openApp(packageName: _pkg);
    } on PlatformException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open this app.')),
      );
    }
  }

  Future<void> _uninstall() async {
    try {
      await ApkInstallService.instance.uninstallApp(packageName: _pkg);

      Future<void>.delayed(const Duration(milliseconds: 700), () {
        if (!mounted) return;
        _loadPackageState();
      });

      Future<void>.delayed(const Duration(milliseconds: 1600), () {
        if (!mounted) return;
        _loadPackageState();
      });
    } catch (_) {}
  }

  Future<void> _install() async {
    final check = InstallSync.cachedCheck[_pkg];
    final version = check?.latestVersion ?? widget.app.latestVersion;
    if (version == null) return;

    InstallSync.active[_pkg]!.value = true;
    InstallSync.paused[_pkg]!.value = false;
    InstallSync.progress[_pkg]!.value = 0.0;
    InstallSync.preparing[_pkg]!.value = true;
    _lastPaintedProgress = -1;

    final downloadFuture = ApkInstallService.instance.downloadAndInstall(
      app: widget.app,
      onProgress: (value) {
        final nextProgress = value.clamp(0, 1).toDouble();
        final changedEnough =
            (nextProgress - _lastPaintedProgress).abs() >= 0.01 ||
                nextProgress == 0 ||
                nextProgress == 1;

        if (!changedEnough) return;

        _lastPaintedProgress = nextProgress;
        InstallSync.progress[_pkg]!.value = nextProgress;
      },
      onStarted: () {
        if (mounted) {
          InstallSync.preparing[_pkg]!.value = false;
        }
      },
    );

    try {
      await downloadFuture;
    } on PlatformException catch (e) {
      if (!mounted) return;
      InstallSync.preparing[_pkg]!.value = false;
      final message = e.code == 'install_permission_required'
          ? 'Allow SafeHaven to install apps, then tap Install again.'
          : 'Could not start the installer.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (!mounted) return;
      InstallSync.preparing[_pkg]!.value = false;
      final msg = e.toString();
      if (msg != 'download_cancelled') {
        final text = switch (msg) {
          'sha256_mismatch' || 'sha256_missing' => 'APK integrity check failed.',
          'apk_size_mismatch' => 'APK download appears incomplete.',
          _ => 'Install failed: $e',
        };
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
      }
    } finally {
      InstallSync.active[_pkg]!.value = false;
      InstallSync.paused[_pkg]!.value = false;
      InstallSync.progress[_pkg]!.value = 0.0;
      InstallSync.preparing[_pkg]!.value = false;

      await Future<void>.delayed(const Duration(milliseconds: 800));
      if (mounted) {
        await _loadPackageState();
      }
    }
  }

  Future<void> _togglePause() async {
    if (!InstallSync.active[_pkg]!.value) return;

    if (InstallSync.paused[_pkg]!.value) {
      await ApkInstallService.instance.resumeDownload();
      InstallSync.paused[_pkg]!.value = false;
    } else {
      await ApkInstallService.instance.pauseDownload();
      InstallSync.paused[_pkg]!.value = true;
    }
  }

  Future<void> _cancelDownload() async {
    if (!InstallSync.active[_pkg]!.value) return;

    InstallSync.active[_pkg]!.value = false;
    InstallSync.paused[_pkg]!.value = false;
    InstallSync.progress[_pkg]!.value = 0.0;
    InstallSync.preparing[_pkg]!.value = false;

    try {
      await ApkInstallService.instance.cancelDownload(packageName: _pkg);
    } catch (_) {}
  }

  String _getLabelText(bool isInstalling, bool isPaused, double fillProgress, bool isChecking, StoreUpdateCheck? check) {
    if (!_hasVersion) return 'No live APK yet';

    if (isInstalling) {
      final percent = (fillProgress * 100).clamp(0, 100).round();
      return isPaused ? 'Paused' : 'Downloading $percent%';
    }

    if (isChecking) return 'Checking';

    switch (check?.status) {
      case StoreUpdateStatus.notInstalled:
        return 'Install';
      case StoreUpdateStatus.updateAvailable:
        return 'Update';
      case StoreUpdateStatus.current:
      case StoreUpdateStatus.installedNewerThanStore:
        return 'Open';
      case StoreUpdateStatus.missingStoreVersion:
      case null:
        return 'Unavailable';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);
    final isDark = SafeHavenThemeManager.instance.isDark;

    return ListenableBuilder(
      listenable: Listenable.merge([
        InstallSync.active[_pkg]!,
        InstallSync.paused[_pkg]!,
        InstallSync.progress[_pkg]!,
        InstallSync.preparing[_pkg]!,
        InstallSync.isChecking[_pkg]!,
      ]),
      builder: (context, _) {
        final isInstalling = InstallSync.active[_pkg]!.value;
        final isPaused = InstallSync.paused[_pkg]!.value;
        final fillProgress = InstallSync.progress[_pkg]!.value;
        final isPreparing = InstallSync.preparing[_pkg]!.value;
        final isChecking = InstallSync.isChecking[_pkg]!.value;
        final check = InstallSync.cachedCheck[_pkg];
        final isInstalled = check?.installed ?? false;

        final primaryEnabled = _hasVersion && !isInstalling && !isChecking;
        final height = widget.compact ? 36.0 : 52.0;
        final radius = BorderRadius.circular(widget.compact ? 8 : 12);

        final hasBorder = (!_hasVersion || isInstalling);
        final labelText = _getLabelText(isInstalling, isPaused, fillProgress, isChecking, check);

        final buttonRow = Row(
          children: [
            Expanded(
              child: SizedBox(
                height: height,
                child: Opacity(
                  opacity: isDark && _hasVersion && !isInstalling ? 0.82 : 1.0,
                  child: ClipRRect(
                    borderRadius: radius,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: (_hasVersion && !isInstalling) ? colors.accentGradient : null,
                              color: hasBorder ? colors.surfaceSoft : null,
                              borderRadius: radius,
                              border: Border.all(
                                color: hasBorder ? colors.border : Colors.transparent,
                              ),
                            ),
                          ),
                        ),
                        if (isInstalling)
                          Positioned.fill(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: FractionallySizedBox(
                                widthFactor: fillProgress,
                                heightFactor: 1.0,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: colors.accentGradient,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        Positioned.fill(
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: radius,
                              onTap: primaryEnabled ? _primaryAction : null,
                              child: Center(
                                child: isInstalling && isPreparing
                                    ? SizedBox(
                                  width: widget.compact ? 18 : 22,
                                  height: widget.compact ? 18 : 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      colors.text,
                                    ),
                                  ),
                                )
                                    : Text(
                                  labelText,
                                  style: TextStyle(
                                    fontSize: widget.compact ? 13.5 : 14,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.2,
                                    color: _hasVersion && !isInstalling
                                        ? colors.buttonText
                                        : (isInstalling ? colors.text : colors.textMuted),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (isInstalling && !isPreparing)
                          Positioned(
                            right: widget.compact ? 4 : 6,
                            top: 0,
                            bottom: 0,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _InstallInnerAction(
                                  icon: isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                                  compact: widget.compact,
                                  onTap: _togglePause,
                                ),
                                const SizedBox(width: 4),
                                _InstallInnerAction(
                                  icon: Icons.close_rounded,
                                  compact: widget.compact,
                                  onTap: _cancelDownload,
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (isInstalled && !isInstalling && !widget.compact) ...[
              const SizedBox(width: 10),
              _InstallIconButton(
                icon: Icons.delete_outline_rounded,
                tooltip: 'Uninstall',
                onTap: _uninstall,
              ),
            ],
          ],
        );

        if (widget.compact) {
          return buttonRow;
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 22),
          child: buttonRow,
        );
      },
    );
  }
}

class _InstallInnerAction extends StatelessWidget {
  const _InstallInnerAction({
    required this.icon,
    required this.compact,
    required this.onTap,
  });

  final IconData icon;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);
    final isDark = SafeHavenThemeManager.instance.isDark;

    final size = compact ? 28.0 : 36.0;
    final iconSize = compact ? 16.0 : 20.0;

    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              child: Container(
                width: size,
                height: size,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isDark
                      ? colors.surface.withOpacity(0.5)
                      : colors.text.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  size: iconSize,
                  color: colors.text,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InstallIconButton extends StatelessWidget {
  const _InstallIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = SafeHavenThemeManager.instance.isDark;
    const danger = Color(0xFFE85D75);

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 52,
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isDark ? Colors.transparent : danger.withOpacity(0.09),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: danger.withOpacity(isDark ? 0.15 : 0.18),
            ),
            boxShadow: [
              if (!isDark)
                BoxShadow(
                  color: danger.withOpacity(0.08),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
            ],
          ),
          child: Icon(
            icon,
            size: 22,
            color: danger.withOpacity(isDark ? 0.75 : 0.92),
          ),
        ),
      ),
    );
  }
}