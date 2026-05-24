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

    if (!forceRefresh) {
      final pending = _inFlightFetch;
      if (pending != null) return pending;
    }

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

  Future<List<PublicStoreApp>> recommended(
      List<PublicStoreApp> apps, {
        Iterable<PublicStoreApp> exclude = const [],
      }) {
    return RankingService.instance.recommended(apps, exclude: exclude);
  }

  List<PublicStoreApp> topCharts(List<PublicStoreApp> apps) {
    return RankingService.instance.topCharts(apps);
  }

  List<PublicStoreApp> filterByCategory(
      List<PublicStoreApp> apps,
      String? category,
      ) {
    if (category == null || category.isEmpty) return apps;
    return apps.where((a) => a.category == category).toList();
  }

  List<String> shuffledCategoryKeys(Map<String, String> categories) {
    final keys = categories.keys.toList()..shuffle();
    return keys;
  }

  List<PublicStoreApp> newArrivals(List<PublicStoreApp> apps, {int limit = 12}) {
    final withAdded = apps.where((a) => a.versions.isNotEmpty).map((a) {
      final resolvedAdded = a.versions.map((v) => v.added).reduce((x, y) => x < y ? x : y);
      return MapEntry(a, resolvedAdded);
    }).toList();

    withAdded.sort((a, b) => b.value.compareTo(a.value));

    return withAdded.take(limit).map((e) => e.key).toList();
  }

  List<PublicStoreApp> topInCategory(
      List<PublicStoreApp> apps,
      String categoryKey,
      ) {
    final filtered = filterByCategory(apps, categoryKey);
    return topCharts(filtered);
  }
}