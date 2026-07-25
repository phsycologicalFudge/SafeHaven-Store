import 'package:flutter/services.dart';
import 'package:workmanager/workmanager.dart';
import 'background_tasks.dart';

enum UpdateMode { none, light, full }

extension UpdateModeWire on UpdateMode {
  String get wireValue => switch (this) {
    UpdateMode.none => 'none',
    UpdateMode.light => 'light',
    UpdateMode.full => 'full',
  };

  static UpdateMode fromWire(String? value) => switch (value) {
    'none' => UpdateMode.none,
    'full' => UpdateMode.full,
    _ => UpdateMode.light,
  };
}

class UpdateModeService {
  UpdateModeService._();

  static const MethodChannel _channel = MethodChannel('safehaven/installer');

  static Future<UpdateMode> getMode() async {
    try {
      final value = await _channel.invokeMethod<String>('getUpdateMode');
      return UpdateModeWire.fromWire(value);
    } catch (_) {
      return UpdateMode.light;
    }
  }

  static Future<void> setMode(UpdateMode mode) async {
    try {
      await _channel.invokeMethod('setUpdateMode', {'mode': mode.wireValue});
    } catch (_) {}

    if (mode == UpdateMode.none) {
      await Workmanager().cancelByUniqueName(updateCheckTaskName);
    } else {
      await Workmanager().registerPeriodicTask(
        updateCheckTaskName,
        updateCheckTaskName,
        frequency: const Duration(hours: 6),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
        constraints: Constraints(
          networkType: NetworkType.connected,
        ),
      );
    }
  }
}
