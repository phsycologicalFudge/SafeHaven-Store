import 'package:flutter/material.dart';
import 'package:safehaven/screens/apps/catalogue_screen/sections/catalogue_top_charts_section.dart';
import 'package:safehaven/screens/apps/catalogue_screen/widgets/catalogue_shared_widgets.dart';
import '../../../services/index_service.dart';
import '../../../services/store_service.dart';
import '../../../widgets/identity_setup_dialog.dart';
import '../../../widgets/refresh/pull_to_refresh.dart';
import 'catalogue_navigation.dart';
import 'sections/catalogue_category_tabs.dart';
import 'sections/catalogue_recommended_section.dart';
import 'sections/catalogue_extra_sections.dart';
import 'sections/see_more_apps_screen.dart';
import 'package:safehaven/translations/app_localizations.dart';

class CatalogueScreen extends StatefulWidget {
  const CatalogueScreen({super.key});

  @override
  State<CatalogueScreen> createState() => _CatalogueScreenState();
}

class _CatalogueScreenState extends State<CatalogueScreen> {
  static const int _bannersPerCarousel = 6;
  late Future<StoreIndex> _future;
  StoreIndex? _lastIndex;
  String? _selectedCategory;
  List<String> _shuffledCategoryKeys = [];
  Future<List<PublicStoreApp>>? _bannersTop;
  Future<List<PublicStoreApp>>? _bannersMid;
  int? _recommendedTimestamp;

  int? _memoTimestamp;
  String? _memoCategory;
  bool _memoCatsReady = false;
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
      _lastIndex = index;
      final keys = index.categories.keys.toSet();
      final same = _shuffledCategoryKeys.length == keys.length &&
          _shuffledCategoryKeys.every(keys.contains);
      if (same) return;
      setState(() {
        _shuffledCategoryKeys =
            IndexService.instance.shuffledCategoryKeys(index.categories);
        if (_selectedCategory != null && !keys.contains(_selectedCategory)) {
          _selectedCategory = null;
        }
      });
    }, onError: (_) {});
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
    final hadData = _lastIndex != null;
    setState(() {
      _bannersTop = null;
      _bannersMid = null;
      _recommendedTimestamp = null;
      _loadFuture(forceRefresh: true);
    });

    try {
      await _future;
    } catch (_) {
      if (!mounted || !hadData) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.catalogueCouldNotLoad)),
      );
    }
  }

  void _recompute(StoreIndex index) {
    final ts = index.timestamp;
    final cat = _selectedCategory;
    final catsReady = _shuffledCategoryKeys.isNotEmpty;
    if (ts == _memoTimestamp && cat == _memoCategory && catsReady == _memoCatsReady) return;

    _memoTimestamp = ts;
    _memoCategory = cat;
    _memoCatsReady = catsReady;
    _memoTopCharts = IndexService.instance.topCharts(category: cat);
    _memoNewArrivals = IndexService.instance.newArrivals(category: cat);

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
        ? IndexService.instance.topInCategory(_memoCatKeyA!)
        : const [];
    _memoTopInB = _memoCatKeyB != null
        ? IndexService.instance.topInCategory(_memoCatKeyB!)
        : const [];
  }

  void _loadBanners(List<PublicStoreApp> topCharts, int timestamp) {
    if (_recommendedTimestamp == timestamp && _bannersTop != null) return;
    _recommendedTimestamp = timestamp;
    final picks = IndexService.instance.recommended(exclude: topCharts, limit: _bannersPerCarousel * 2);
    _bannersTop = picks.then((apps) => apps.take(_bannersPerCarousel).toList());
    _bannersMid = picks.then((apps) => apps.skip(_bannersPerCarousel).toList());
  }

  void _openAllApps() {
    Navigator.of(context).push(
      pushRoute(SeeMoreAppsScreen(title: AppLocalizations.of(context)!.allApps)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<StoreIndex>(
      future: _future,
      builder: (context, snapshot) {
        final index = snapshot.data ?? _lastIndex;
        final loading =
            snapshot.connectionState == ConnectionState.waiting && index == null;
        final failed = snapshot.hasError && index == null;

        if (index != null) {
          _recompute(index);
        }

        final showCategoryRows = _memoCatKeyA != null;

        if ((index?.count ?? 0) > 0) {
          _loadBanners(_memoTopCharts, _memoTimestamp ?? 0);
        }
        final top = _bannersTop;
        final mid = _bannersMid;

        return PullRefresh(
          onRefresh: _reload,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              if (top != null && !failed)
                SliverToBoxAdapter(
                  child: CatalogueRecommendedSection(future: top, storageId: 'catalogue_banner_top'),
                ),
              if (index != null && index.categories.isNotEmpty)
                SliverToBoxAdapter(
                  child: CatalogueCategoryTabs(
                    categoryKeys: _shuffledCategoryKeys,
                    categories: index.categories,
                    selected: _selectedCategory,
                    onSelected: (key) {
                      if (key == _selectedCategory) return;
                      setState(() => _selectedCategory = key);
                    },
                  ),
                ),
              if (loading)
                const SliverToBoxAdapter(child: CatalogueLoadingBlock()),
              if (failed)
                SliverToBoxAdapter(
                  child: CatalogueErrorBlock(
                    message: snapshot.error.toString(),
                    onRetry: _reload,
                  ),
                ),
              if (!loading && !failed && _memoTopCharts.isEmpty)
                const SliverToBoxAdapter(child: CatalogueEmptyBlock()),
              if (!loading && !failed && _memoTopCharts.isNotEmpty) ...[
                if (_memoTopCharts.isNotEmpty)
                  SliverToBoxAdapter(
                    child: CatalogueTopChartsSection(
                      apps: _memoTopCharts.take(10).toList(),
                      onAllApps: _openAllApps,
                    ),
                  ),
                if (mid != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: CatalogueRecommendedSection(
                        future: mid,
                        storageId: 'catalogue_banner_mid',
                        speed: 1.35,
                      ),
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
                    count: index?.count ?? 0,
                    onTap: _openAllApps,
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