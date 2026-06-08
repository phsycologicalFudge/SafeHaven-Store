/*
Store update service. Compares installed package versions against the store index to
produce StoreUpdateCheck results. Also coordinates triggering unattended updates for
packages installed by SafeHaven that have a newer version available.
*/
import '../store_service.dart';
import 'apk_install_service.dart';
import 'unattended_update_service.dart';

enum StoreUpdateStatus {
  notInstalled,
  missingStoreVersion,
  current,
  updateAvailable,
  installedNewerThanStore,
}

class StoreUpdateCheck {
  const StoreUpdateCheck({
    required this.app,
    required this.installedState,
    required this.latestVersion,
    required this.status,
  });

  final PublicStoreApp app;
  final InstalledPackageState installedState;
  final StoreVersion? latestVersion;
  final StoreUpdateStatus status;

  bool get installed => installedState.installed;
  bool get canUpdate => status == StoreUpdateStatus.updateAvailable;
  bool get isCurrent => status == StoreUpdateStatus.current;
  bool get isInstalledNewerThanStore => status == StoreUpdateStatus.installedNewerThanStore;
  int get installedVersionCode => installedState.versionCode;
  String? get installedVersionName => installedState.versionName;
  String? get installedSigningCertificateSha256 => installedState.signingCertificateSha256;
  int? get latestVersionCode => latestVersion?.versionCode;
  String? get latestVersionName => latestVersion?.versionName;
}

class StoreUpdateService {
  StoreUpdateService._();
  static final StoreUpdateService instance = StoreUpdateService._();

  Future<void> syncAndTriggerAutoUpdates(List<PublicStoreApp> apps) async {
    final states = await Future.wait(
      apps.map((app) => ApkInstallService.instance.getPackageState(packageName: app.packageName)),
    );

    final eligible = <({PublicStoreApp app})>[];
    for (var i = 0; i < apps.length; i++) {
      final app = apps[i];
      final state = states[i];
      if (!state.installed || !state.isInstalledBySafeHaven) continue;
      if (!state.canUpdateTo(app.latestVersion)) continue;
      eligible.add((app: app,));
    }

    if (eligible.isEmpty) return;

    final downloadUrls = await Future.wait(
      eligible.map((e) => StoreService.instance.getDownloadUrl(
        packageName: e.app.packageName,
        versionCode: e.app.latestVersion!.versionCode,
      )),
    );

    final updates = <Map<String, dynamic>>[
      for (var i = 0; i < eligible.length; i++)
        {'packageName': eligible[i].app.packageName, 'downloadUrl': downloadUrls[i]},
    ];

    await UnattendedUpdateService.triggerManualBatchUpdate(updates);
  }

  Future<StoreUpdateCheck> checkApp(PublicStoreApp app) async {
    final installedState = await ApkInstallService.instance.getPackageState(
      packageName: app.packageName,
    );

    final latestVersion = app.latestVersion;
    final status = _resolveStatus(
      installedState: installedState,
      latestVersion: latestVersion,
    );

    return StoreUpdateCheck(
      app: app,
      installedState: installedState,
      latestVersion: latestVersion,
      status: status,
    );
  }

  Future<List<StoreUpdateCheck>> checkApps(List<PublicStoreApp> apps) async {
    return Future.wait(apps.map(checkApp));
  }

  Future<List<StoreUpdateCheck>> availableUpdates(List<PublicStoreApp> apps) async {
    final checks = await checkApps(apps);
    return checks.where((check) => check.canUpdate).toList();
  }

  StoreUpdateStatus _resolveStatus({
    required InstalledPackageState installedState,
    required StoreVersion? latestVersion,
  }) {
    if (!installedState.installed) return StoreUpdateStatus.notInstalled;
    if (latestVersion == null) return StoreUpdateStatus.missingStoreVersion;
    if (latestVersion.versionCode > installedState.versionCode) return StoreUpdateStatus.updateAvailable;
    if (latestVersion.versionCode == installedState.versionCode) return StoreUpdateStatus.current;
    return StoreUpdateStatus.installedNewerThanStore;
  }
}