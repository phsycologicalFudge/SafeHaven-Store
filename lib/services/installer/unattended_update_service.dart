import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../engine/bridge.dart';
import '../logs/debug_log_service.dart';
import 'apk_install_service.dart';
import 'update_mode_service.dart';

class UnattendedUpdateService {
  static const _channel = MethodChannel('safehaven/installer');
  static const _triggeredUpdatesKey = 'safehaven_triggered_update_versions';

  static Future<void> triggerManualBatchUpdate(List<Map<String, dynamic>> updates) async {
    final mode = await UpdateModeService.getMode();
    if (mode == UpdateMode.none) {
      DebugLog.d('Unattended', 'skipped batch update, mode is none');
      return;
    }
    await _channel.invokeMethod('startUnattendedUpdates', {'updates': updates});
  }

  static Future<Map<String, int>> _loadTriggeredUpdates() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_triggeredUpdatesKey);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, (v as num).toInt()));
    } catch (e, s) {
      DebugLog.e('Unattended', 'loadTriggeredUpdates decode failed', e, s);
      return {};
    }
  }

  static Future<void> _saveTriggeredUpdates(Map<String, int> updates) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_triggeredUpdatesKey, jsonEncode(updates));
  }

  @pragma('vm:entry-point')
  static Future<void> performBackgroundCheck() async {
    final bridge = EngineBridge.instance;
    await bridge.call<dynamic>('index.sync', args: {'force': true}, decode: asIs);

    final triggered = await _loadTriggeredUpdates();
    final states = await ApkInstallService.instance.getAllPackageStates(forceRefresh: true);

    final plan = await bridge.call<List<dynamic>>(
      'updates.plan',
      args: {
        'states': ApkInstallService.wire(states),
        'triggered': triggered,
      },
      decode: asList,
    );

    if (plan.isEmpty) return;

    final updates = <Map<String, dynamic>>[];
    for (final entry in plan) {
      final item = entry as Map<String, dynamic>;
      final packageName = item['packageName'] as String;
      updates.add({'packageName': packageName, 'downloadUrl': item['downloadUrl']});
      triggered[packageName] = (item['versionCode'] as num).toInt();
    }

    await triggerManualBatchUpdate(updates);
    await _saveTriggeredUpdates(triggered);
  }
}
