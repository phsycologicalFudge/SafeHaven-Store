import 'package:flutter/material.dart';
import '../../../../services/catalogue_service.dart';
import '../../../../services/store_service.dart';
import '../../../../services/theme/theme_manager.dart';
import '../../../../widgets/animated_tap.dart';
import '../../app_screen/app_screen.dart';
import 'catalogue_app_icons.dart';
import 'catalogue_download_button.dart';
import '../catalogue_navigation.dart';
import 'catalogue_shared_widgets.dart';

class CatalogueAppSmallTile extends StatelessWidget {
  const CatalogueAppSmallTile({required this.app, required this.width});

  final PublicStoreApp app;
  final double width;

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);
    final double iconSize = width > 76 ? 76.0 : width - 6;

    return SizedBox(
      width: width,
      child: AnimatedTap(
        borderRadius: 14,
        onTap: () {
          Navigator.of(context).push(pushRoute(AppScreen(app: app)));
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CatalogueRawAppIcon(app: app, size: iconSize, radius: 18),
            const SizedBox(height: 8),
            Text(
              compactAppName(app.name),
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: TextStyle(
                fontSize: 13,
                height: 1.15,
                fontWeight: FontWeight.w900,
                color: colors.text,
              ),
            ),
            if (app.ratingCount > 0) ...[
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    app.displayRating,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: colors.textMuted,
                    ),
                  ),
                  Transform.translate(
                    offset: const Offset(0, -1.5),
                    child: Text(
                      '★',
                      style: TextStyle(
                        fontSize: 10,
                        color: colors.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class CatalogueSeeMoreTile extends StatelessWidget {
  const CatalogueSeeMoreTile({required this.onTap, required this.width});

  final VoidCallback onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);

    return SizedBox(
      width: width,
      child: AnimatedTap(
        borderRadius: 12,
        scale: 0.96,
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 68,
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'See more',
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.0,
                        fontWeight: FontWeight.w700,
                        color: colors.accentStart.withOpacity(0.9),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 16,
                      color: colors.accentStart.withOpacity(0.9),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 7),
            const SizedBox(height: 18),
          ],
        ),
      ),
    );
  }
}

class CatalogueAppWideRow extends StatelessWidget {
  const CatalogueAppWideRow({required this.app});

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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            CatalogueRawAppIcon(app: app, size: 48, radius: 12),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    app.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16.5,
                      height: 1.12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.4,
                      color: colors.text,
                    ),
                  ),
                  const SizedBox(height: 5),
                  if (app.ratingCount > 0)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          app.displayRating,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: colors.textMuted,
                          ),
                        ),
                        Transform.translate(
                          offset: const Offset(0, -2),
                          child: Text(
                            '★',
                            style: TextStyle(
                              fontSize: 11,
                              color: colors.textMuted,
                            ),
                          ),
                        ),
                      ],
                    )
                  else
                    Text(
                      app.developerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: colors.textMuted,
                      ),
                    ),
                ],
              ),
            ),
            CatalogueDownloadButton(app: app),
          ],
        ),
      ),
    );
  }
}

class CatalogueHorizontalSection extends StatelessWidget {
  const CatalogueHorizontalSection({
    required this.title,
    required this.apps,
    this.limit = 10,
    this.onSeeMore,
  });

  final String title;
  final List<PublicStoreApp> apps;
  final int limit;
  final VoidCallback? onSeeMore;

  @override
  Widget build(BuildContext context) {
    final visibleApps = apps.take(limit).toList();
    final showSeeMore = onSeeMore != null && apps.length > visibleApps.length;
    final double screenWidth = MediaQuery.sizeOf(context).width;
    final double cardWidth = (screenWidth - 68) / 4;

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        children: [
          CatalogueSectionHeader(title: title),
          const SizedBox(height: 8),
          SizedBox(
            height: 136,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: visibleApps.length + (showSeeMore ? 1 : 0),
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                if (index < visibleApps.length) {
                  return CatalogueAppSmallTile(app: visibleApps[index], width: cardWidth);
                }
                return CatalogueSeeMoreTile(onTap: onSeeMore!, width: cardWidth);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class CatalogueVerticalSection extends StatelessWidget {
  const CatalogueVerticalSection({required this.title, required this.apps});

  final String title;
  final List<PublicStoreApp> apps;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        children: [
          CatalogueSectionHeader(title: title),
          const SizedBox(height: 4),
          ...apps.map((app) => CatalogueAppWideRow(app: app)),
        ],
      ),
    );
  }
}