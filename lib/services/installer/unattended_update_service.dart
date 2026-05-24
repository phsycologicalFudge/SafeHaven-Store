import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../index_service.dart';
import '../store_service.dart';
import 'apk_install_service.dart';

class UnattendedUpdateService {
  static const _channel = MethodChannel('safehaven/installer');
  static const _triggeredUpdatesKey = 'safehaven_triggered_update_versions';

  static Future<void> triggerManualBatchUpdate(List<Map<String, dynamic>> updates) async {
    await _channel.invokeMethod('startUnattendedUpdates', {'updates': updates});
  }

  static Future<Map<String, int>> _loadTriggeredUpdates() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_triggeredUpdatesKey);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, (v as num).toInt()));
    } catch (_) {
      return {};
    }
  }

  static Future<void> _saveTriggeredUpdates(Map<String, int> updates) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_triggeredUpdatesKey, jsonEncode(updates));
  }

  @pragma('vm:entry-point')
  static Future<void> performBackgroundCheck() async {
    final index = await IndexService.instance.fetchIndex(forceRefresh: true);
    final triggered = await _loadTriggeredUpdates();
    final updates = <Map<String, dynamic>>[];

    for (final app in index.apps) {
      final latestVersionCode = app.latestVersion?.versionCode;
      if (latestVersionCode == null) continue;

      if (triggered[app.packageName] == latestVersionCode) continue;

      final state = await ApkInstallService.instance.getPackageState(
        packageName: app.packageName,
      );

      if (!state.installed || !state.isInstalledBySafeHaven) continue;
      if (!state.canUpdateTo(app.latestVersion)) continue;

      final downloadUrl = await StoreService.instance.getDownloadUrl(
        packageName: app.packageName,
        versionCode: latestVersionCode,
      );

      updates.add({
        'packageName': app.packageName,
        'downloadUrl': downloadUrl,
      });

      triggered[app.packageName] = latestVersionCode;
    }

    if (updates.isNotEmpty) {
      await triggerManualBatchUpdate(updates);
      await _saveTriggeredUpdates(triggered);
    }
  }
}