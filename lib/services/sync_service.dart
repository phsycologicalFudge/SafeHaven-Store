import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'store_service.dart';

class SyncService {
  SyncService._();
  static final SyncService instance = SyncService._();

  static const String _localIndexKey = 'safehaven_local_index_raw';

  StoreIndex? _liveIndex;

  Future<StoreIndex> syncStore() async {
    final baseline = await _loadBaseline();
    final since = baseline?.timestamp ?? 0;

    final uri = Uri.parse('${StoreService.defaultBaseUrl}/store/sync?since=$since');
    final res = await http.get(uri);

    if (res.statusCode < 200 || res.statusCode >= 300) {
      if (baseline != null) return baseline;
      throw const StoreApiException('sync_failed');
    }

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final action = body['action'] as String?;

    if (action == 'full') {
      final fullUri = Uri.parse('${StoreService.defaultBaseUrl}/store/index.json');
      final fullRes = await http.get(fullUri);

      if (fullRes.statusCode < 200 || fullRes.statusCode >= 300) {
        if (baseline != null) return baseline;
        throw const StoreApiException('full_fetch_failed');
      }

      final index = await compute(_parseIndex, fullRes.body);
      _liveIndex = index;
      unawaited(_persist(index));
      return index;
    }

    if (action == 'patch' && baseline != null) {
      final newTimestamp = body['timestamp'] as int;
      final updates = (body['updates'] as List? ?? [])
          .map((e) => e as Map<String, dynamic>)
          .toList();
      final removes = (body['removes'] as List? ?? [])
          .map((e) => e as String)
          .toList();

      final merged = _applyPatch(baseline, newTimestamp, updates, removes);
      _liveIndex = merged;
      unawaited(_persist(merged));
      return merged;
    }

    if (baseline != null) return baseline;
    throw const StoreApiException('sync_invalid_state');
  }

  Future<StoreIndex?> _loadBaseline() async {
    final cached = _liveIndex;
    if (cached != null) return cached;

    final prefs = await SharedPreferences.getInstance();
    final localRaw = prefs.getString(_localIndexKey);
    if (localRaw == null) return null;

    try {
      final index = await compute(_parseIndex, localRaw);
      _liveIndex = index;
      return index;
    } catch (_) {
      return null;
    }
  }

  StoreIndex _applyPatch(
      StoreIndex baseline,
      int newTimestamp,
      List<Map<String, dynamic>> updates,
      List<String> removes,
      ) {
    final appMap = {for (final a in baseline.apps) a.packageName: a};

    for (final packageName in removes) {
      appMap.remove(packageName);
    }

    for (final update in updates) {
      final app = PublicStoreApp.fromJson(update);
      appMap[app.packageName] = app;
    }

    return StoreIndex(
      timestamp: newTimestamp,
      categories: baseline.categories,
      apps: appMap.values.toList(),
    );
  }

  Future<void> _persist(StoreIndex index) async {
    final raw = await compute(_encodeIndex, index);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_localIndexKey, raw);
  }
}

StoreIndex _parseIndex(String raw) {
  return StoreIndex.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}

String _encodeIndex(StoreIndex index) {
  return jsonEncode(index.toJson());
}