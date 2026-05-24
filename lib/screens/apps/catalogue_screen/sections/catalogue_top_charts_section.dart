import 'package:flutter/material.dart';
import '../../../../services/store_service.dart';
import '../../../../services/theme/theme_manager.dart';
import '../../../../widgets/animated_tap.dart';
import '../../app_screen/app_screen.dart';
import '../catalogue_navigation.dart';
import '../widgets/catalogue_app_icons.dart';
import '../widgets/catalogue_download_button.dart';
import '../widgets/catalogue_shared_widgets.dart';

class CatalogueTopChartsSection extends StatelessWidget {
  const CatalogueTopChartsSection({
    required this.apps,
    required this.onAllApps,
  });

  final List<PublicStoreApp> apps;
  final VoidCallback onAllApps;

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.sizeOf(context).width;
    final double cardWidth = (screenWidth - 56) / 3;

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        children: [
          const CatalogueSectionHeader(title: 'Top charts'),
          const SizedBox(height: 10),
          SizedBox(
            height: 186,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: apps.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                return _TopChartGalleryCard(app: apps[index], cardWidth: cardWidth);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TopChartGalleryCard extends StatelessWidget {
  const _TopChartGalleryCard({required this.app, required this.cardWidth});

  final PublicStoreApp app;
  final double cardWidth;

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);

    return AnimatedTap(
      borderRadius: 18,
      onTap: () {
        Navigator.of(context).push(pushRoute(AppScreen(app: app)));
      },
      child: Container(
        width: cardWidth,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: colors.surfaceSoft,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CatalogueRawAppIcon(app: app, size: 64, radius: 16),
            const SizedBox(height: 8),
            Text(
              app.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.2,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
                color: colors.text,
              ),
            ),
            if (app.ratingCount > 0) ...[
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    app.displayRating,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: colors.textMuted,
                    ),
                  ),
                  Transform.translate(
                    offset: const Offset(0, -1),
                    child: Text(
                      '★',
                      style: TextStyle(
                        fontSize: 9,
                        color: colors.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const Spacer(),
            _PillDownloadButton(app: app),
          ],
        ),
      ),
    );
  }
}

class _PillDownloadButton extends StatelessWidget {
  const _PillDownloadButton({required this.app});

  final PublicStoreApp app;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      height: 26,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: CatalogueDownloadButton(app: app),
      ),
    );
  }
}