import 'package:flutter/material.dart';
import '../../../../services/store_service.dart';
import '../../../../services/theme/theme_manager.dart';
import '../app_screen_helpers.dart';
import 'app_screen_layout.dart';
import 'package:safehaven/translations/app_localizations.dart';

class AppScreenTrustSection extends StatelessWidget {
  const AppScreenTrustSection({super.key, required this.app});

  final PublicStoreApp app;

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);

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
              body: AppLocalizations.of(context)!.securityVerifiedSigBody,
              color: null,
            ),
            _SignalRow(
              icon: Icons.manage_search_rounded,
              title: AppLocalizations.of(context)!.securityLatestScan,
              body: app.latestVersion == null || app.latestVersion!.scannedAt == 0
                  ? AppLocalizations.of(context)!.securityNoScanTimestamp
                  : AppLocalizations.of(context)!.securityNoThreats(formatScannedAt(app.latestVersion!.scannedAt)),
              color: null,
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

  @override
  Widget build(BuildContext context) {
    final version = app.latestVersion;

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
            _InfoRow(
              label: AppLocalizations.of(context)!.technicalSha256,
              value: version == null || version.sha256.isEmpty
                  ? AppLocalizations.of(context)!.technicalNotAvailable
                  : version.sha256,
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
  });

  final IconData icon;
  final String title;
  final String body;
  final Color? color;

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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
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
            ),
          ),
        ],
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