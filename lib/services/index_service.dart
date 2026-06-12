import 'dart:math';
import 'package:safehaven/services/ratings/ranking_service.dart';
import 'store_service.dart';
import 'sync_service.dart';

class IndexService {
  IndexService._();
  static final IndexService instance = IndexService._();

  StoreIndex? _cache;
  DateTime? _cacheTime;
  Future<StoreIndex>? _inFlightFetch;

  static const _ttl = Duration(minutes: 5);

  bool get _isCacheValid =>
      _cache != null &&
      _cacheTime != null &&
      DateTime.now().difference(_cacheTime!) < _ttl;

  Future<StoreIndex> fetchIndex({bool forceRefresh = false}) {
    if (!forceRefresh && _isCacheValid) return Future.value(_cache!);

    final pending = _inFlightFetch;
    if (pending != null) return pending;

    final fetch = SyncService.instance.syncStore().then((index) {
      _cache = index;
      _cacheTime = DateTime.now();
      return index;
    });

    _inFlightFetch = fetch;

    return fetch.whenComplete(() {
      if (identical(_inFlightFetch, fetch)) {
        _inFlightFetch = null;
      }
    });
  }

  StoreIndex? get cached => _cache;

  List<String> shuffledCategoryKeys(Map<String, String> categories) {
    final keys = categories.keys.toList();
    keys.shuffle(Random());
    return keys;
  }

  List<PublicStoreApp> filterByCategory(
    List<PublicStoreApp> apps,
    String? category,
  ) {
    if (category == null) return apps;
    final normalized = category.trim().toLowerCase();
    return apps
        .where((app) => app.category.trim().toLowerCase() == normalized)
        .toList();
  }

  List<PublicStoreApp> newArrivals(List<PublicStoreApp> apps, {int limit = 10}) {
    final sorted = [...apps];
    sorted.sort((a, b) {
      final addedA = a.latestVersion?.added ?? 0;
      final addedB = b.latestVersion?.added ?? 0;
      return addedB.compareTo(addedA);
    });
    return sorted.take(limit).toList();
  }

  List<PublicStoreApp> topInCategory(
    List<PublicStoreApp> apps,
    String categoryKey, {
    int limit = 8,
  }) {
    final normalized = categoryKey.trim().toLowerCase();
    final inCategory = apps
        .where((app) => app.category.trim().toLowerCase() == normalized)
        .toList();

    inCategory.sort((a, b) {
      final scoreA = _ratingScore(a);
      final scoreB = _ratingScore(b);
      return scoreB.compareTo(scoreA);
    });

    return inCategory.take(limit).toList();
  }

  double _ratingScore(PublicStoreApp app) {
    if (app.ratingCount <= 0 || app.ratingAvg <= 0) return 0.0;
    return app.ratingAvg * (log(app.ratingCount + 1) / ln10);
  }

  Future<List<PublicStoreApp>> recommended(
    List<PublicStoreApp> apps, {
    Iterable<PublicStoreApp> exclude = const [],
  }) {
    return RankingService.instance.recommended(apps, exclude: exclude);
  }

  List<PublicStoreApp> topCharts(List<PublicStoreApp> apps) {
    return RankingService.instance.topCharts(apps);
  }
}
