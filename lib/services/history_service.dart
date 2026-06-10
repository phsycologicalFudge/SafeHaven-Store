import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HistoryService {
  HistoryService._();
  static final HistoryService instance = HistoryService._();

  static const _viewedKey = 'sh_viewed_apps';
  static const _categoryViewsKey = 'sh_category_views';
  static const _maxViewed = 50;
  static const _categoryWindow = Duration(days: 30);

  final ValueNotifier<int> changes = ValueNotifier<int>(0);

  Future<void> recordView(String packageName) async {
    final normalized = packageName.trim();
    if (normalized.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final list = _cleanPackageList(prefs.getStringList(_viewedKey) ?? []);

    list.remove(normalized);
    list.insert(0, normalized);

    while (list.length > _maxViewed) {
      list.removeLast();
    }

    await prefs.setStringList(_viewedKey, list);
    changes.value++;
  }

  Future<void> recordCategoryView(String category) async {
    final normalized = _normalizeCategory(category);
    if (normalized == null) return;

    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final list = _prunedCategoryViews(
      prefs.getStringList(_categoryViewsKey) ?? [],
      now,
    );

    list.add('$normalized|$now');
    await prefs.setStringList(_categoryViewsKey, list);
  }

  Future<List<String>> getViewed() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _cleanPackageList(prefs.getStringList(_viewedKey) ?? []);

    if (list.length != (prefs.getStringList(_viewedKey) ?? []).length) {
      await prefs.setStringList(_viewedKey, list);
    }

    return list;
  }

  Future<String?> getDominantCategory() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final list = _prunedCategoryViews(
      prefs.getStringList(_categoryViewsKey) ?? [],
      now,
    );

    await prefs.setStringList(_categoryViewsKey, list);
    if (list.isEmpty) return null;

    final counts = <String, int>{};
    for (final entry in list) {
      final category = _normalizeCategory(entry.split('|').first);
      if (category == null) continue;
      counts[category] = (counts[category] ?? 0) + 1;
    }

    if (counts.isEmpty) return null;

    final sorted = counts.entries.toList()
      ..sort((a, b) {
        final countCompare = b.value.compareTo(a.value);
        if (countCompare != 0) return countCompare;
        return a.key.compareTo(b.key);
      });

    return sorted.first.key;
  }

  List<String> _cleanPackageList(List<String> entries) {
    final seen = <String>{};
    final cleaned = <String>[];

    for (final entry in entries) {
      final packageName = entry.trim();
      if (packageName.isEmpty || seen.contains(packageName)) continue;

      seen.add(packageName);
      cleaned.add(packageName);

      if (cleaned.length >= _maxViewed) break;
    }

    return cleaned;
  }

  List<String> _prunedCategoryViews(List<String> entries, int nowSeconds) {
    final cutoff = nowSeconds - _categoryWindow.inSeconds;

    return entries.where((entry) {
      final parts = entry.split('|');
      if (parts.length != 2) return false;

      final category = _normalizeCategory(parts[0]);
      final timestamp = int.tryParse(parts[1]);

      if (category == null || timestamp == null) return false;
      return timestamp >= cutoff;
    }).toList();
  }

  String? _normalizeCategory(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) return null;
    return normalized;
  }
}