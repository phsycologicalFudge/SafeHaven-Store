import '../logs/debug_log_service.dart';
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
    required this.signatureMismatch,
  });

  final PublicStoreApp app;
  final InstalledPackageState installedState;
  final StoreVersion? latestVersion;
  final StoreUpdateStatus status;
  final bool? signatureMismatch;

  bool get hasConfirmedSignatureMismatch => signatureMismatch == true;

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
    final installedStates = await ApkInstallService.instance.getAllPackageStates();

    final eligible = <({PublicStoreApp app, int versionCode})>[];
    for (final app in apps) {
      final state = installedStates[app.packageName];
      if (state == null || !state.installed) continue;
      if (!state.canUpdateTo(app.latestVersion)) continue;
      if (state.signatureMismatchWith(app.signingKeyHash) == true) continue;
      eligible.add((app: app, versionCode: app.latestVersion!.versionCode));
    }

    if (eligible.isEmpty) return;

    final urlResults = await Future.wait(
      eligible.map((e) async {
        try {
          return await StoreService.instance.getDownloadUrl(
            packageName: e.app.packageName,
            versionCode: e.versionCode,
          );
        } catch (err, s) {
          DebugLog.e('StoreUpdate', 'getDownloadUrl failed: ${e.app.packageName}', err, s);
          return null;
        }
      }),
    );

    final updates = <Map<String, dynamic>>[];
    for (var i = 0; i < eligible.length; i++) {
      final url = urlResults[i];
      if (url != null) {
        updates.add({'packageName': eligible[i].app.packageName, 'downloadUrl': url});
      }
    }

    if (updates.isEmpty) return;
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
      signatureMismatch: installedState.signatureMismatchWith(app.signingKeyHash),
    );
  }

  Future<StoreUpdateCheck> checkAppCached(PublicStoreApp app, {bool forceRefresh = false}) async {
    final installedStates = await ApkInstallService.instance.getAllPackageStates(forceRefresh: forceRefresh);
    final installedState = installedStates[app.packageName] ??
        const InstalledPackageState(installed: false, versionCode: 0);

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
      signatureMismatch: installedState.signatureMismatchWith(app.signingKeyHash),
    );
  }

  Future<List<StoreUpdateCheck>> checkApps(List<PublicStoreApp> apps, {bool forceRefresh = false}) async {
    final installedStates = await ApkInstallService.instance.getAllPackageStates(forceRefresh: forceRefresh);
    return apps.map((app) {
      final state = installedStates[app.packageName] ??
          const InstalledPackageState(installed: false, versionCode: 0);
      final latestVersion = app.latestVersion;
      return StoreUpdateCheck(
        app: app,
        installedState: state,
        latestVersion: latestVersion,
        status: _resolveStatus(installedState: state, latestVersion: latestVersion),
        signatureMismatch: state.signatureMismatchWith(app.signingKeyHash),
      );
    }).toList();
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