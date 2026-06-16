import 'package:flutter/material.dart';
import 'package:safehaven/services/installer/safehaven_updater/self_update_service.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../widgets/animated_tap.dart';
import '../../theme/theme_manager.dart';

class SelfUpdateDialog extends StatefulWidget {
  const SelfUpdateDialog({super.key, required this.info});

  final SelfUpdateInfo info;

  static Future<void> show(BuildContext context, SelfUpdateInfo info) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.55),
      builder: (_) => SelfUpdateDialog(info: info),
    );
  }

  @override
  State<SelfUpdateDialog> createState() => _SelfUpdateDialogState();
}

enum _UpdatePhase { idle, downloading, installing, failed }

class _SelfUpdateDialogState extends State<SelfUpdateDialog> {
  _UpdatePhase _phase = _UpdatePhase.idle;
  double _progress = 0;
  String? _error;

  Future<void> _startUpdate() async {
    setState(() {
      _phase = _UpdatePhase.downloading;
      _progress = 0;
      _error = null;
    });

    final path = await SelfUpdateService.instance.downloadApk(
      widget.info.apkDownloadUrl,
      onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      },
    );

    if (!mounted) return;

    if (path == null) {
      setState(() {
        _phase = _UpdatePhase.failed;
        _error = 'Download failed. Check your connection and try again.';
      });
      return;
    }

    setState(() => _phase = _UpdatePhase.installing);

    try {
      await SelfUpdateService.instance.installApk(path);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _phase = _UpdatePhase.failed;
        _error = 'Could not start the installer.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);
    final isDark = SafeHavenThemeManager.instance.isDark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Material(
          color: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 380),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: colors.border),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(colors),
                Container(height: 0.5, color: colors.border),
                _buildNotes(colors, isDark),
                if (_error != null) _buildError(colors),
                Container(height: 0.5, color: colors.border),
                _buildActions(colors, isDark),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(SafeHavenColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Update available',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: colors.textMuted,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                widget.info.currentVersion,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                  color: colors.text,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  size: 18,
                  color: colors.textMuted,
                ),
              ),
              ShaderMask(
                shaderCallback: (bounds) =>
                    colors.accentGradient.createShader(bounds),
                child: Text(
                  widget.info.latestVersion,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNotes(SafeHavenColors colors, bool isDark) {
    final blocks = widget.info.parsedNotes;
    if (blocks.isEmpty) return const SizedBox.shrink();

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 280),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < blocks.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              _buildBlock(blocks[i], colors, isDark),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBlock(
      ReleaseNoteBlock block,
      SafeHavenColors colors,
      bool isDark,
      ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (block.header.isNotEmpty) ...[
          Text(
            block.header,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.15,
              color: colors.text,
            ),
          ),
          const SizedBox(height: 6),
        ],
        for (final line in block.lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: _buildLine(line, colors, isDark),
          ),
      ],
    );
  }

  Widget _buildLine(
      ReleaseNoteLine line,
      SafeHavenColors colors,
      bool isDark,
      ) {
    if (line.kind == ReleaseNoteLineKind.commitBullet) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: colors.textMuted,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: line.text,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: colors.textSoft,
                      height: 1.45,
                    ),
                  ),
                  const TextSpan(text: ' '),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.baseline,
                    baseline: TextBaseline.alphabetic,
                    child: GestureDetector(
                      onTap: line.commitUrl != null
                          ? () => _openUrl(line.commitUrl!)
                          : null,
                      child: Text(
                        line.commitHash ?? '',
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w500,
                          color: colors.accentStart,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Container(
            width: 4,
            height: 4,
            decoration: BoxDecoration(
              color: colors.textMuted,
              shape: BoxShape.circle,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            line.text,
            style: TextStyle(
              fontSize: 12.5,
              color: colors.textSoft,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildError(SafeHavenColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Text(
        _error!,
        style: TextStyle(
          fontSize: 12,
          color: colors.textMuted,
          height: 1.3,
        ),
      ),
    );
  }

  Widget _buildActions(SafeHavenColors colors, bool isDark) {
    final downloading = _phase == _UpdatePhase.downloading;
    final installing = _phase == _UpdatePhase.installing;
    final busy = downloading || installing;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 46,
              child: AnimatedTap(
                borderRadius: 12,
                scale: 0.97,
                onTap: busy ? null : () => Navigator.of(context).pop(),
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: colors.border),
                  ),
                  child: Text(
                    'Dismiss',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: colors.textMuted,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 46,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: busy ? null : colors.accentGradient,
                          color: busy ? colors.surfaceSoft : null,
                          borderRadius: BorderRadius.circular(12),
                          border: busy
                              ? Border.all(color: colors.border)
                              : null,
                        ),
                      ),
                    ),
                    if (downloading)
                      Positioned.fill(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: _progress,
                            heightFactor: 1,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: colors.accentGradient,
                              ),
                            ),
                          ),
                        ),
                      ),
                    Positioned.fill(
                      child: AnimatedTap(
                        borderRadius: 12,
                        scale: 0.97,
                        onTap: busy ? null : _startUpdate,
                        child: Center(
                          child: installing
                              ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                colors.text,
                              ),
                            ),
                          )
                              : Text(
                            downloading
                                ? '${(_progress * 100).round()}%'
                                : (_phase == _UpdatePhase.failed
                                ? 'Retry'
                                : 'Update'),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.2,
                              color: (downloading && _progress < 0.5)
                                  ? colors.text
                                  : colors.buttonText,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }
}