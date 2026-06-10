import 'package:safehaven/services/installer/unattended_update_service.dart';
import 'package:workmanager/workmanager.dart';

const _updateCheckTask = 'safehaven.updateCheck';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    switch (taskName) {
      case _updateCheckTask:
        await UnattendedUpdateService.performBackgroundCheck();
        return true;
      default:
        return false;
    }
  });
}

Future<void> initBackgroundTasks() async {
  await Workmanager().initialize(callbackDispatcher);
  await Workmanager().registerPeriodicTask(
    _updateCheckTask,
    _updateCheckTask,
    frequency: const Duration(hours: 6),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    constraints: Constraints(
      networkType: NetworkType.connected,
    ),
  );
}
