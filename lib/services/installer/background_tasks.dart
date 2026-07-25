import 'package:safehaven/services/installer/unattended_update_service.dart';
import 'package:safehaven/services/installer/update_mode_service.dart';
import 'package:safehaven/services/logs/debug_log_service.dart';
import 'package:workmanager/workmanager.dart';

const updateCheckTaskName = 'safehaven.updateCheck';

@pragma('vm:entry-point')
void callbackDispatcher() {
  DebugLog.installCrashHandlers();
  Workmanager().executeTask((taskName, inputData) async {
    await DebugLog.init();
    try {
      switch (taskName) {
        case updateCheckTaskName:
          await UnattendedUpdateService.performBackgroundCheck();
          return true;
        default:
          return false;
      }
    } catch (e, s) {
      DebugLog.e('Background', 'task failed: $taskName', e, s);
      return false;
    }
  });
}

Future<void> initBackgroundTasks() async {
  await Workmanager().initialize(callbackDispatcher);
  final mode = await UpdateModeService.getMode();
  if (mode == UpdateMode.none) {
    await Workmanager().cancelByUniqueName(updateCheckTaskName);
    return;
  }
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
