import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../services/store_service.dart';
import '../../../../services/theme/theme_manager.dart';


class AppScreenHeader extends StatelessWidget {
  const AppScreenHeader({super.key, required this.app});

  final PublicStoreApp app;

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppScreenLargeIcon(iconUrl: app.iconUrl),
          const SizedBox(width: 18),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    app.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 27,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                      height: 1.08,
                      color: colors.text,
                    ),
                  ),
                  if (app.developerName.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      app.developerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: colors.accentEnd,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AppScreenLargeIcon extends StatelessWidget {
  const AppScreenLargeIcon({super.key, required this.iconUrl});

  final String? iconUrl;

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);
    final url = iconUrl?.trim();

    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        color: colors.iconBackground,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: url == null || url.isEmpty
          ? null
          : CachedNetworkImage(
        imageUrl: url,
        fadeInDuration: const Duration(milliseconds: 150),
        fit: BoxFit.cover,
        memCacheWidth: 240,
        memCacheHeight: 240,
        filterQuality: FilterQuality.medium,
        placeholder: (_, __) => const SizedBox.shrink(),
        errorWidget: (_, __, ___) => const SizedBox.shrink(),
      ),
    );
  }
}

class AppScreenMetadataRow extends StatelessWidget {
  const AppScreenMetadataRow({super.key, required this.app});

  final PublicStoreApp app;

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);
    final version = app.latestVersion;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
      child: Row(
        children: [
          Expanded(
            child: _MetaItem(
              top: app.ratingCount > 0 ? '${app.displayRating} ★' : '—',
              bottom: 'Rating',
            ),
          ),
          const _DividerLine(),
          Expanded(
            child: _MetaItem(
              top: version?.versionName ?? 'None',
              bottom: 'Version',
            ),
          ),
          const _DividerLine(),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: app.repoUrl.isEmpty
                  ? null
                  : () async {
                final uri = Uri.tryParse(app.repoUrl);
                if (uri == null) return;
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              },
              child: SizedBox(
                height: 56,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.code_rounded,
                      size: 24,
                      color: colors.text,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Repo',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textMuted,
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
}

class _MetaItem extends StatelessWidget {
  const _MetaItem({required this.top, required this.bottom});

  final String top;
  final String bottom;

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);
    final hasRating = top.contains('★');
    final ratingNumber = hasRating ? top.replaceAll(' ★', '') : top;

    return SizedBox(
      height: 56,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (hasRating)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  ratingNumber,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: colors.text,
                  ),
                ),
                Transform.translate(
                  offset: const Offset(0, -2),
                  child: Text(
                    '★',
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.text,
                    ),
                  ),
                ),
              ],
            )
          else
            Text(
              ratingNumber,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: colors.text,
              ),
            ),
          const SizedBox(height: 4),
          Text(
            bottom,
            style: TextStyle(
              fontSize: 12,
              color: colors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _DividerLine extends StatelessWidget {
  const _DividerLine();

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);

    return Container(
      width: 1,
      height: 30,
      color: colors.border,
    );
  }
}