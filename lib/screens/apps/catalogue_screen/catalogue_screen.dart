import 'package:flutter/material.dart';
import 'package:safehaven/screens/apps/catalogue_screen/sections/catalogue_top_charts_section.dart';
import 'package:safehaven/screens/apps/catalogue_screen/widgets/catalogue_shared_widgets.dart';
import '../../../services/index_service.dart';
import '../../../services/store_service.dart';
import '../../../services/installer/store_update_service.dart';
import '../../../widgets/identity_setup_dialog.dart';
import '../../../widgets/refresh/pull_to_refresh.dart';
import 'catalogue_navigation.dart';
import 'sections/catalogue_category_tabs.dart';
import 'sections/catalogue_recommended_section.dart';
import 'sections/catalogue_extra_sections.dart';
import 'sections/see_more_apps_screen.dart';

class CatalogueScreen extends StatefulWidget {
  const CatalogueScreen({super.key});

  @override
  State<CatalogueScreen> createState() => _CatalogueScreenState();
}

class _CatalogueScreenState extends State<CatalogueScreen> {
  late Future<StoreIndex> _future;
  String? _selectedCategory;
  List<String> _shuffledCategoryKeys = [];
  Future<List<PublicStoreApp>>? _recommendedFuture;
  String? _recommendedKey;

  void _loadFuture({bool forceRefresh = false}) {
    _future = IndexService.instance.fetchIndex(forceRefresh: forceRefresh);

    _future.then((index) {
      if (!mounted) return;

      StoreUpdateService.instance.syncAndTriggerAutoUpdates(index.apps);

      if (_shuffledCategoryKeys.isEmpty) {
        setState(() {
          _shuffledCategoryKeys =
              IndexService.instance.shuffledCategoryKeys(index.categories);
        });
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _loadFuture();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      IdentitySetupDialog.showIfNeeded(context);
    });
  }

  Future<void> _reload() async {
    setState(() {
      _shuffledCategoryKeys = [];
      _recommendedFuture = null;
      _recommendedKey = null;
      _loadFuture(forceRefresh: true);
    });

    await _future;
  }

  Future<List<PublicStoreApp>> _recommendedFor(
      List<PublicStoreApp> apps,
      List<PublicStoreApp> topCharts,
      ) {
    final key = [
      _selectedCategory ?? '',
      apps.map((app) => app.packageName).join('|'),
      topCharts.map((app) => app.packageName).join('|'),
    ].join('::');

    if (_recommendedKey != key || _recommendedFuture == null) {
      _recommendedKey = key;
      _recommendedFuture = IndexService.instance.recommended(
        apps,
        exclude: topCharts,
      );
    }

    return _recommendedFuture!;
  }

  void _openAllApps(List<PublicStoreApp> allApps) {
    Navigator.of(context).push(
      pushRoute(
        SeeMoreAppsScreen(
          title: 'All apps',
          apps: allApps,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<StoreIndex>(
      future: _future,
      builder: (context, snapshot) {
        final loading = snapshot.connectionState == ConnectionState.waiting;
        final index = snapshot.data;

        final allApps = index?.apps ?? const [];
        final filtered = IndexService.instance.filterByCategory(
          allApps,
          _selectedCategory,
        );
        final topCharts = IndexService.instance.topCharts(filtered);
        final newArrivals = IndexService.instance.newArrivals(filtered);

        final showCategoryRows = _selectedCategory == null &&
            _shuffledCategoryKeys.length >= 2;
        final catKeyA = showCategoryRows ? _shuffledCategoryKeys[0] : null;
        final catKeyB = showCategoryRows ? _shuffledCategoryKeys[1] : null;
        final catLabelA = catKeyA != null ? (index?.categories[catKeyA] ?? catKeyA) : null;
        final catLabelB = catKeyB != null ? (index?.categories[catKeyB] ?? catKeyB) : null;
        final topInA = catKeyA != null
            ? IndexService.instance.topInCategory(allApps, catKeyA)
            : const <PublicStoreApp>[];
        final topInB = catKeyB != null
            ? IndexService.instance.topInCategory(allApps, catKeyB)
            : const <PublicStoreApp>[];

        final Future<List<PublicStoreApp>>? recommendedFuture =
        filtered.isEmpty ? null : _recommendedFor(filtered, topCharts);
        final Widget? recommendedSection = recommendedFuture == null
            ? null
            : CatalogueRecommendedSection(future: recommendedFuture);

        return PullRefresh(
          onRefresh: _reload,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              if (index != null && index.categories.isNotEmpty)
                SliverToBoxAdapter(
                  child: CatalogueCategoryTabs(
                    categoryKeys: _shuffledCategoryKeys,
                    categories: index.categories,
                    selected: _selectedCategory,
                    onSelected: (key) {
                      setState(() {
                        _selectedCategory = key;
                      });
                    },
                  ),
                ),
              if (loading)
                const SliverToBoxAdapter(child: CatalogueLoadingBlock()),
              if (snapshot.hasError)
                SliverToBoxAdapter(
                  child: CatalogueErrorBlock(
                    message: snapshot.error.toString(),
                    onRetry: _reload,
                  ),
                ),
              if (!loading && !snapshot.hasError && filtered.isEmpty)
                const SliverToBoxAdapter(child: CatalogueEmptyBlock()),
              if (!loading && !snapshot.hasError && filtered.isNotEmpty) ...[
                if (recommendedSection != null)
                  SliverToBoxAdapter(child: recommendedSection),
                if (topCharts.isNotEmpty)
                  SliverToBoxAdapter(
                    child: CatalogueTopChartsSection(
                      apps: topCharts.take(10).toList(),
                      onAllApps: () => _openAllApps(allApps),
                    ),
                  ),
                if (showCategoryRows && topInA.isNotEmpty)
                  SliverToBoxAdapter(
                    child: CatalogueTopInCategorySection(
                      categoryLabel: catLabelA!,
                      apps: topInA.take(10).toList(),
                    ),
                  ),
                if (showCategoryRows && topInB.isNotEmpty)
                  SliverToBoxAdapter(
                    child: CatalogueTopInCategorySection(
                      categoryLabel: catLabelB!,
                      apps: topInB.take(10).toList(),
                    ),
                  ),
                if (newArrivals.isNotEmpty)
                  SliverToBoxAdapter(
                    child: CatalogueNewArrivalsSection(apps: newArrivals),
                  ),
                SliverToBoxAdapter(
                  child: CatalogueSeeAllBlock(
                    count: allApps.length,
                    onTap: () => _openAllApps(allApps),
                  ),
                ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 18)),
            ],
          ),
        );
      },
    );
  }
}