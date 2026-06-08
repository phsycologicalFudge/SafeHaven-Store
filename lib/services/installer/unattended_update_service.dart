/*
Unattended update service. Triggers background APK updates via a MethodChannel
without requiring user interaction, gated on SafeHaven being the recorded installer.
Also runs as a periodic WorkManager task to catch updates while the app is closed.
*/
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

    final candidates = index.apps.where((app) {
      final latestVersionCode = app.latestVersion?.versionCode;
      if (latestVersionCode == null) return false;
      return triggered[app.packageName] != latestVersionCode;
    }).toList();

    final states = await Future.wait(
      candidates.map((app) => ApkInstallService.instance.getPackageState(packageName: app.packageName)),
    );

    final eligible = <({PublicStoreApp app, int versionCode})>[];
    for (var i = 0; i < candidates.length; i++) {
      final app = candidates[i];
      final state = states[i];
      if (!state.installed || !state.isInstalledBySafeHaven) continue;
      if (!state.canUpdateTo(app.latestVersion)) continue;
      eligible.add((app: app, versionCode: app.latestVersion!.versionCode));
    }

    if (eligible.isEmpty) return;

    final downloadUrls = await Future.wait(
      eligible.map((e) => StoreService.instance.getDownloadUrl(
        packageName: e.app.packageName,
        versionCode: e.versionCode,
      )),
    );

    final updates = <Map<String, dynamic>>[];
    for (var i = 0; i < eligible.length; i++) {
      final e = eligible[i];
      updates.add({'packageName': e.app.packageName, 'downloadUrl': downloadUrls[i]});
      triggered[e.app.packageName] = e.versionCode;
    }

    await triggerManualBatchUpdate(updates);
    await _saveTriggeredUpdates(triggered);
  }
}