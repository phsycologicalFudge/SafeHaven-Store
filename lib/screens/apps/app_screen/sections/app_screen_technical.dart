import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../services/store_service.dart';
import '../../../../services/theme/theme_manager.dart';
import '../app_screen_helpers.dart';
import 'app_screen_layout.dart';
import 'package:safehaven/translations/app_localizations.dart';

const _vttiIconAsset = 'assets/icons/vtti_logo.svg';

Future<void> _openVttiSample(String sha256) async {
  final uri = Uri.parse('https://platform.colourswift.com/sample/$sha256');
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

String _breakLastWord(String text) {
  final lastSpace = text.lastIndexOf(' ');
  if (lastSpace == -1) return text;
  return '${text.substring(0, lastSpace)}\n${text.substring(lastSpace + 1)}';
}

class AppScreenTrustSection extends StatelessWidget {
  const AppScreenTrustSection({super.key, required this.app});

  final PublicStoreApp app;

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);
    final version = app.latestVersion;

    return AppScreenSection(
      title: AppLocalizations.of(context)!.securitySignals,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Column(
          children: [
            _SignalRow(
              icon: app.hasTrustBadge
                  ? Icons.verified_rounded
                  : Icons.info_outline_rounded,
              title: app.trustLabel,
              body: app.trustDescription,
              color: app.hasTrustBadge ? colors.accentEnd : colors.textMuted,
            ),
            _SignalRow(
              icon: Icons.fingerprint_rounded,
              title: AppLocalizations.of(context)!.securityVerifiedSig,
              body: _breakLastWord(AppLocalizations.of(context)!.securityVerifiedSigBody),
              color: null,
            ),
            _SignalRow(
              icon: Icons.manage_search_rounded,
              title: AppLocalizations.of(context)!.securityLatestScan,
              body: version == null || version.scannedAt == 0
                  ? AppLocalizations.of(context)!.securityNoScanTimestamp
                  : AppLocalizations.of(context)!.securityNoThreats(formatScannedAt(version.scannedAt)),
              color: null,
              onTrailingTap: version == null || version.sha256.isEmpty
                  ? null
                  : () => _openVttiSample(version.sha256),
            ),
          ],
        ),
      ),
    );
  }
}

class AppScreenTechnicalSection extends StatelessWidget {
  const AppScreenTechnicalSection({super.key, required this.app});

  final PublicStoreApp app;

  void _showShaDialog(BuildContext context, String sha256) {
    final colors = SafeHavenTheme.of(context);

    showDialog(
      context: context,
      builder: (_) => AppAccentDialog(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppLocalizations.of(context)!.technicalSha256,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: colors.text,
                ),
              ),
              const SizedBox(height: 16),
              _ShaCopyItem(sha256: sha256),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final version = app.latestVersion;
    final sha256 = version?.sha256 ?? '';

    return AppScreenExpandableSection(
      title: AppLocalizations.of(context)!.technicalAppInfo,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Column(
          children: [
            _InfoRow(label: AppLocalizations.of(context)!.technicalPackage, value: app.packageName),
            _InfoRow(
              label: AppLocalizations.of(context)!.technicalRepository,
              value: app.repoUrl.isEmpty ? AppLocalizations.of(context)!.technicalNotProvided : app.repoUrl,
            ),
            if (sha256.isEmpty)
              _InfoRow(
                label: AppLocalizations.of(context)!.technicalSha256,
                value: AppLocalizations.of(context)!.technicalNotAvailable,
              )
            else
              _TapToCopyInfoRow(
                label: AppLocalizations.of(context)!.technicalSha256,
                onTap: () => _showShaDialog(context, sha256),
              ),
            _InfoRow(
              label: AppLocalizations.of(context)!.technicalApkSize,
              value: version == null || version.apkSize == 0
                  ? AppLocalizations.of(context)!.technicalNotAvailable
                  : formatBytes(version.apkSize),
            ),
            _InfoRow(
              label: AppLocalizations.of(context)!.technicalLastScanned,
              value: version == null || version.scannedAt == 0
                  ? AppLocalizations.of(context)!.technicalNotAvailable
                  : formatScannedAt(version.scannedAt),
            ),
          ],
        ),
      ),
    );
  }
}

class _SignalRow extends StatelessWidget {
  const _SignalRow({
    required this.icon,
    required this.title,
    required this.body,
    required this.color,
    this.onTrailingTap,
  });

  final IconData icon;
  final String title;
  final String body;
  final Color? color;
  final VoidCallback? onTrailingTap;

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: color ?? colors.textMuted),
          const SizedBox(width: 13),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: _SignalText(title: title, body: body),
                ),
                if (onTrailingTap != null) ...[
                  const SizedBox(width: 10),
                  Container(
                    width: 1,
                    height: 18,
                    color: colors.textMuted.withOpacity(0.25),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: onTrailingTap,
                    behavior: HitTestBehavior.opaque,
                    child: SvgPicture.asset(
                      _vttiIconAsset,
                      width: 18,
                      height: 18,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SignalText extends StatelessWidget {
  const _SignalText({super.key, required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: colors.text,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          body,
          style: TextStyle(
            fontSize: 12.5,
            height: 1.35,
            color: colors.textSoft,
          ),
        ),
      ],
    );
  }
}

class _TapToCopyInfoRow extends StatelessWidget {
  const _TapToCopyInfoRow({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                color: colors.textMuted,
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: onTap,
              behavior: HitTestBehavior.opaque,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    AppLocalizations.of(context)!.devSigningKeyTapToCopy,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: colors.textSoft,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.copy_rounded,
                    size: 13,
                    color: colors.textMuted,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShaCopyItem extends StatefulWidget {
  const _ShaCopyItem({required this.sha256});

  final String sha256;

  @override
  State<_ShaCopyItem> createState() => _ShaCopyItemState();
}

class _ShaCopyItemState extends State<_ShaCopyItem> {
  bool _copied = false;
  Timer? _resetTimer;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.sha256));
    if (!mounted) return;
    setState(() => _copied = true);
    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _copy,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                _copied ? Icons.check_rounded : Icons.content_copy_rounded,
                color: _copied ? colors.accentEnd : colors.textMuted,
                size: 22,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  widget.sha256,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                    color: colors.text,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                color: colors.textMuted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: colors.textSoft,
              ),
            ),
          ),
        ],
      ),
    );
  }
}