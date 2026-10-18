import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../../services/theme/theme_manager.dart';
import '../../../../widgets/animated_tap.dart';
import '../../../../widgets/shimmer.dart';
import 'package:safehaven/translations/app_localizations.dart';


String compactAppName(String name) {
  final trimmed = name.trim();
  if (trimmed.length <= 12) return trimmed;
  return '${trimmed.substring(0, 12)}...';
}

class CatalogueSectionHeader extends StatelessWidget {
  const CatalogueSectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                color: colors.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CatalogueAllAppsTextButton extends StatelessWidget {
  const CatalogueAllAppsTextButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);

    return AnimatedTap(
      borderRadius: 14,
      scale: 0.96,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 4),
        child: Row(
          children: [
            Text(
              AppLocalizations.of(context)!.allApps,
              style: TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
                color: colors.accentStart,
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.arrow_forward_rounded,
              size: 18,
              color: colors.accentStart,
            ),
          ],
        ),
      ),
    );
  }
}

class CatalogueSeeAllBlock extends StatelessWidget {
  const CatalogueSeeAllBlock({
    required this.count,
    required this.onTap,
  });

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 20, 14, 4),
      child: AnimatedTap(
        borderRadius: 99,
        scale: 0.975,
        onTap: onTap,
        child: Shimmer(
          borderRadius: 99,
          child: Container(
            height: 56,
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: colors.border),
            ),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    AppLocalizations.of(context)!.catalogueBrowseAll,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                      color: colors.text,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: colors.accentStart.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: colors.accentStart,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 17,
                    color: colors.textMuted,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CatalogueLoadingBlock extends StatelessWidget {
  const CatalogueLoadingBlock();

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 44, 18, 44),
      child: Center(child: CircularProgressIndicator(color: colors.accentEnd)),
    );
  }
}

class CatalogueErrorBlock extends StatelessWidget {
  const CatalogueErrorBlock({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 44, 18, 44),
      child: Column(
        children: [
          Icon(
            Icons.cloud_off_rounded,
            color: colors.textMuted,
            size: 34,
          ),
          const SizedBox(height: 14),
          Text(
            AppLocalizations.of(context)!.catalogueCouldNotLoad,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: colors.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              color: colors.textSoft,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 42,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: colors.accentGradient,
                borderRadius: BorderRadius.circular(10),
              ),
              child: AnimatedTap(
                borderRadius: 10,
                onTap: onRetry,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Center(
                    child: Text(
                      AppLocalizations.of(context)!.retry,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: colors.buttonText,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CatalogueEmptyBlock extends StatelessWidget {
  const CatalogueEmptyBlock();

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 54, 18, 54),
      child: Center(
        child: Text(
          AppLocalizations.of(context)!.catalogueNoApps,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: colors.textSoft,
            height: 1.45,
          ),
        ),
      ),
    );
  }
}