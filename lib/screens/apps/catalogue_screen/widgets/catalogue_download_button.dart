import 'package:flutter/material.dart';
import '../../../../services/store_service.dart';
import '../../../../services/theme/theme_manager.dart';
import '../../../../services/installer/apk_install_service.dart';
import '../../../../services/installer/install_sync.dart';
import '../../../../services/installer/store_update_service.dart';
import '../../../../widgets/animated_tap.dart';

class CatalogueDownloadButton extends StatefulWidget {
  const CatalogueDownloadButton({
    required this.app,
    super.key,
    this.compact = false,
    this.borderRadius = 10.0,
  });

  final PublicStoreApp app;
  final bool compact;
  final double borderRadius;

  @override
  State<CatalogueDownloadButton> createState() => _CatalogueDownloadButtonState();
}

class _CatalogueDownloadButtonState extends State<CatalogueDownloadButton>
    with WidgetsBindingObserver {
  String get _pkg => widget.app.packageName;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    InstallSync.register(_pkg);
    _checkInstalled();
  }

  @override
  void didUpdateWidget(covariant CatalogueDownloadButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.app.packageName != widget.app.packageName) {
      InstallSync.register(_pkg);
      _checkInstalled();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        !(InstallSync.active[_pkg]?.value ?? false)) {
      Future.delayed(
        const Duration(milliseconds: 600),
            () {
          if (mounted) _checkInstalled(invalidate: true);
        },
      );
    }
  }

  Future<void> _checkInstalled({bool invalidate = false}) async {
    if (widget.app.latestVersion == null) {
      InstallSync.isChecking[_pkg]?.value = false;
      return;
    }

    if (invalidate) {
      InstallSync.cachedCheck[_pkg] = null;
    } else if (InstallSync.cachedCheck[_pkg] != null) {
      InstallSync.isChecking[_pkg]?.value = false;
      return;
    }

    try {
      final check = await StoreUpdateService.instance.checkAppCached(
        widget.app,
        forceRefresh: invalidate,
      );
      if (!mounted) return;
      InstallSync.cachedCheck[_pkg] = check;
      InstallSync.bumpCheck();
    } catch (_) {
    } finally {
      if (mounted) {
        InstallSync.isChecking[_pkg]?.value = false;
      }
    }
  }

  Future<void> _startDownload() async {
    if (InstallSync.active[_pkg]?.value ?? false) return;

    InstallSync.active[_pkg]!.value = true;
    InstallSync.progress[_pkg]!.value = 0.0;

    try {
      await ApkInstallService.instance.downloadAndInstall(
        app: widget.app,
        onProgress: (p) {
          if (!mounted) return;
          InstallSync.progress[_pkg]?.value = p.clamp(0.0, 1.0);
        },
      );
    } catch (_) {
    } finally {
      if (mounted) {
        InstallSync.isChecking[_pkg]!.value = true;
        InstallSync.active[_pkg]!.value = false;
        InstallSync.progress[_pkg]!.value = 0.0;
        await Future<void>.delayed(const Duration(milliseconds: 800));
        if (mounted) _checkInstalled(invalidate: true);
      }
    }
  }

  Future<void> _cancelDownload() async {
    await ApkInstallService.instance.cancelDownload(packageName: _pkg);
  }

  Future<void> _open() async {
    try {
      await ApkInstallService.instance.openApp(packageName: widget.app.packageName);
    } catch (_) {}
  }

  Widget _buildButtonText(String text, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);

    final double w = widget.compact ? 58.0 : 64.0;
    final double h = widget.compact ? 28.0 : 32.0;

    return ListenableBuilder(
      listenable: Listenable.merge([
        InstallSync.active[_pkg]!,
        InstallSync.progress[_pkg]!,
        InstallSync.isChecking[_pkg]!,
        InstallSync.checkVersion,
      ]),
      builder: (context, _) {
        final isChecking = InstallSync.isChecking[_pkg]?.value ?? true;
        final isDownloading = InstallSync.active[_pkg]?.value ?? false;
        final progress = InstallSync.progress[_pkg]?.value ?? 0.0;

        if (isChecking) {
          return SizedBox(width: w, height: h);
        }

        final cached = InstallSync.cachedCheck[_pkg];
        final installed = cached?.installed ?? false;
        final canUpdate = cached?.canUpdate ?? false;

        Widget inner;
        VoidCallback? onTap;
        String stateKey;

        if (isDownloading) {
          stateKey = 'downloading';
          inner = SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              value: progress > 0 ? progress : null,
              strokeWidth: 2.2,
              color: colors.text,
            ),
          );
          onTap = _cancelDownload;
        } else if (!installed) {
          stateKey = 'get';
          inner = _buildButtonText('Get', colors.text);
          onTap = _startDownload;
        } else if (canUpdate) {
          stateKey = 'update';
          inner = _buildButtonText('Update', colors.text);
          onTap = _startDownload;
        } else {
          stateKey = 'open';
          inner = _buildButtonText('Open', colors.text);
          onTap = _open;
        }

        return AnimatedTap(
          borderRadius: widget.borderRadius,
          scale: 0.94,
          onTap: onTap,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.8, end: 1.0).animate(
                  CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
                ),
                child: child,
              ),
            ),
            child: Container(
              key: ValueKey(stateKey),
              width: w,
              height: h,
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(widget.borderRadius),
                border: Border.all(color: colors.border, width: 1.5),
              ),
              child: Center(child: inner),
            ),
          ),
        );
      },
    );
  }
}

class CataloguePillDownloadButton extends StatelessWidget {
  const CataloguePillDownloadButton({required this.app, super.key});

  final PublicStoreApp app;

  @override
  Widget build(BuildContext context) {
    return CatalogueDownloadButton(
      app: app,
      compact: true,
    );
  }
}