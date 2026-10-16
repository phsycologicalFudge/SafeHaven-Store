import 'dart:math';
import 'package:safehaven/services/engine/bridge.dart';
import 'package:safehaven/services/history_service.dart';
import 'store_service.dart';

StoreIndex _decodeIndex(dynamic value) {
  return StoreIndex.fromJson(value as Map<String, dynamic>);
}

List<PublicStoreApp> _decodeApps(dynamic raw) {
  return [
    for (final item in raw as List<dynamic>)
      PublicStoreApp.fromJson(item as Map<String, dynamic>),
  ];
}

class IndexService {
  IndexService._();
  static final IndexService instance = IndexService._();

  final EngineBridge _bridge = EngineBridge.instance;

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

    final fetch = _bridge
        .call<StoreIndex>(
          'index.get',
          args: {'force': forceRefresh},
          decode: _decodeIndex,
        )
        .then((index) {
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

  Future<void> sync({bool force = false}) async {
    final result = await _bridge.call<Map<String, dynamic>>(
      'index.sync',
      args: {'force': force},
      decode: asMap,
    );
    if (result['timestamp'] != _cache?.timestamp) _cache = null;
  }

  PublicStoreApp full(PublicStoreApp app) {
    try {
      final raw = _bridge.callSync('index.app', {'package': app.packageName, 'cached': true});
      return PublicStoreApp.fromJson(raw as Map<String, dynamic>);
    } catch (_) {
      return app;
    }
  }

  List<String> shuffledCategoryKeys(Map<String, String> categories) {
    final keys = categories.keys.toList();
    keys.shuffle(Random());
    return keys;
  }

  Future<List<PublicStoreApp>> query({
    String query = '',
    String? category,
    double minRating = 0,
  }) {
    return _bridge.call<List<PublicStoreApp>>(
      'index.query',
      args: {'query': query, 'category': category ?? '', 'minRating': minRating},
      decode: _decodeApps,
    );
  }

  Future<List<PublicStoreApp>> apps(List<String> packages) {
    return _bridge.call<List<PublicStoreApp>>(
      'index.apps',
      args: {'packages': packages},
      decode: _decodeApps,
    );
  }

  List<PublicStoreApp> newArrivals({String? category, int limit = 10}) {
    return _list('index.new_arrivals', {'category': category ?? '', 'limit': limit});
  }

  List<PublicStoreApp> topInCategory(String categoryKey, {int limit = 8}) {
    return _list('index.top_in_category', {'category': categoryKey, 'limit': limit});
  }

  List<PublicStoreApp> topCharts({String? category}) {
    return _list('rank.top_charts', {'category': category ?? ''});
  }

  Future<List<PublicStoreApp>> recommended({
    Iterable<PublicStoreApp> exclude = const [],
    int? limit,
  }) async {
    final dominant = await HistoryService.instance.getDominantCategory();
    return _list('rank.recommended', {
      'exclude': [for (final app in exclude) app.packageName],
      'dominantCategory': dominant,
      'limit': limit,
    });
  }

  List<PublicStoreApp> _list(String method, Map<String, Object?> args) {
    return _decodeApps(_bridge.callSync(method, args));
  }
}
