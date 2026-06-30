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

  int? _memoTimestamp;
  String? _memoCategory;
  List<PublicStoreApp> _memoAllApps = const [];
  List<PublicStoreApp> _memoFiltered = const [];
  List<PublicStoreApp> _memoTopCharts = const [];
  List<PublicStoreApp> _memoNewArrivals = const [];
  List<PublicStoreApp> _memoTopInA = const [];
  List<PublicStoreApp> _memoTopInB = const [];
  String? _memoCatKeyA;
  String? _memoCatKeyB;
  String? _memoCatLabelA;
  String? _memoCatLabelB;

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
      _memoTimestamp = null;
      _memoCategory = null;
      _loadFuture(forceRefresh: true);
    });

    await _future;
  }

  void _recompute(StoreIndex index) {
    final ts = index.timestamp;
    final cat = _selectedCategory;
    if (ts == _memoTimestamp && cat == _memoCategory) return;

    _memoTimestamp = ts;
    _memoCategory = cat;
    _memoAllApps = index.apps;
    _memoFiltered = IndexService.instance.filterByCategory(_memoAllApps, cat);
    _memoTopCharts = IndexService.instance.topCharts(_memoFiltered);
    _memoNewArrivals = IndexService.instance.newArrivals(_memoFiltered);

    final showCatRows = cat == null && _shuffledCategoryKeys.length >= 2;
    _memoCatKeyA = showCatRows ? _shuffledCategoryKeys[0] : null;
    _memoCatKeyB = showCatRows ? _shuffledCategoryKeys[1] : null;
    _memoCatLabelA = _memoCatKeyA != null
        ? (index.categories[_memoCatKeyA] ?? _memoCatKeyA)
        : null;
    _memoCatLabelB = _memoCatKeyB != null
        ? (index.categories[_memoCatKeyB] ?? _memoCatKeyB)
        : null;
    _memoTopInA = _memoCatKeyA != null
        ? IndexService.instance.topInCategory(_memoAllApps, _memoCatKeyA!)
        : const [];
    _memoTopInB = _memoCatKeyB != null
        ? IndexService.instance.topInCategory(_memoAllApps, _memoCatKeyB!)
        : const [];
  }

  Future<List<PublicStoreApp>> _recommendedFor(
      List<PublicStoreApp> apps,
      List<PublicStoreApp> topCharts,
      ) {
    final key = '${_memoTimestamp ?? 0}|${_selectedCategory ?? ''}';

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

        if (index != null) {
          _recompute(index);
        }

        final showCategoryRows = _memoCatKeyA != null;

        final Future<List<PublicStoreApp>>? recommendedFuture =
        _memoFiltered.isEmpty ? null : _recommendedFor(_memoFiltered, _memoTopCharts);
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
                        _memoCategory = null;
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
              if (!loading && !snapshot.hasError && _memoFiltered.isEmpty)
                const SliverToBoxAdapter(child: CatalogueEmptyBlock()),
              if (!loading && !snapshot.hasError && _memoFiltered.isNotEmpty) ...[
                if (recommendedSection != null)
                  SliverToBoxAdapter(child: recommendedSection),
                if (_memoTopCharts.isNotEmpty)
                  SliverToBoxAdapter(
                    child: CatalogueTopChartsSection(
                      apps: _memoTopCharts.take(10).toList(),
                      onAllApps: () => _openAllApps(_memoAllApps),
                    ),
                  ),
                if (showCategoryRows && _memoTopInA.isNotEmpty)
                  SliverToBoxAdapter(
                    child: CatalogueTopInCategorySection(
                      categoryLabel: _memoCatLabelA!,
                      apps: _memoTopInA.take(10).toList(),
                    ),
                  ),
                if (showCategoryRows && _memoTopInB.isNotEmpty)
                  SliverToBoxAdapter(
                    child: CatalogueTopInCategorySection(
                      categoryLabel: _memoCatLabelB!,
                      apps: _memoTopInB.take(10).toList(),
                    ),
                  ),
                if (_memoNewArrivals.isNotEmpty)
                  SliverToBoxAdapter(
                    child: CatalogueNewArrivalsSection(apps: _memoNewArrivals),
                  ),
                SliverToBoxAdapter(
                  child: CatalogueSeeAllBlock(
                    count: _memoAllApps.length,
                    onTap: () => _openAllApps(_memoAllApps),
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
