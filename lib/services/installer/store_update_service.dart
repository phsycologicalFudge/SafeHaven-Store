import '../engine/bridge.dart';
import '../index_service.dart';
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
  bool get updateBlocked => canUpdate && hasConfirmedSignatureMismatch;
  bool get updatable => canUpdate && !hasConfirmedSignatureMismatch;
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

  final EngineBridge _bridge = EngineBridge.instance;

  static const _absent = InstalledPackageState(installed: false, versionCode: 0);

  Future<void> syncAndTriggerAutoUpdates() async {
    await IndexService.instance.sync(force: true);
    final states = await ApkInstallService.instance.getAllPackageStates();

    final plan = await _bridge.call<List<dynamic>>(
      'updates.plan',
      args: {'states': ApkInstallService.wire(states)},
      decode: asList,
    );

    if (plan.isEmpty) return;

    await UnattendedUpdateService.triggerManualBatchUpdate([
      for (final entry in plan)
        {
          'packageName': (entry as Map<String, dynamic>)['packageName'],
          'downloadUrl': entry['downloadUrl'],
        },
    ]);
  }

  Future<StoreUpdateCheck> checkApp(PublicStoreApp app) async {
    await _bridge.ensureReady();
    final state = await ApkInstallService.instance.getPackageState(
      packageName: app.packageName,
    );
    return _evaluate([app], {app.packageName: state}).single;
  }

  Future<StoreUpdateCheck> checkAppCached(PublicStoreApp app, {bool forceRefresh = false}) async {
    final checks = await checkApps([app], forceRefresh: forceRefresh);
    return checks.single;
  }

  Future<List<StoreUpdateCheck>> checkApps(List<PublicStoreApp> apps, {bool forceRefresh = false}) async {
    await _bridge.ensureReady();
    final states = await ApkInstallService.instance.getAllPackageStates(forceRefresh: forceRefresh);
    return _evaluate(apps, states);
  }

  Future<List<StoreUpdateCheck>> installedChecks({bool forceRefresh = false}) async {
    await _bridge.ensureReady();
    final states = await ApkInstallService.instance.getAllPackageStates(forceRefresh: forceRefresh);
    final results = _bridge.callSync('updates.installed', {
      'states': ApkInstallService.wire(states),
    }) as List<dynamic>;
    return [
      for (final raw in results.cast<Map<String, dynamic>>())
        _check(PublicStoreApp.fromJson(raw['app'] as Map<String, dynamic>), states, raw),
    ];
  }

  List<StoreUpdateCheck> _evaluate(
    List<PublicStoreApp> apps,
    Map<String, InstalledPackageState> states,
  ) {
    final results = _bridge.callSync('updates.check', {
      'states': ApkInstallService.wire(states),
      'items': [
        for (final app in apps)
          {
            'packageName': app.packageName,
            'latestVersionCode': app.latestVersion?.versionCode,
            'signingKeyHash': app.signingKeyHash,
          },
      ],
    }) as List<dynamic>;

    return [
      for (var i = 0; i < apps.length; i++)
        _check(apps[i], states, results[i] as Map<String, dynamic>),
    ];
  }

  StoreUpdateCheck _check(
    PublicStoreApp app,
    Map<String, InstalledPackageState> states,
    Map<String, dynamic> result,
  ) {
    return StoreUpdateCheck(
      app: app,
      installedState: states[app.packageName] ?? _absent,
      latestVersion: app.latestVersion,
      status: _statusOf(result['status'] as String),
      signatureMismatch: result['signatureMismatch'] as bool?,
    );
  }

  StoreUpdateStatus _statusOf(String wire) {
    return switch (wire) {
      'notInstalled' => StoreUpdateStatus.notInstalled,
      'missingStoreVersion' => StoreUpdateStatus.missingStoreVersion,
      'current' => StoreUpdateStatus.current,
      'updateAvailable' => StoreUpdateStatus.updateAvailable,
      _ => StoreUpdateStatus.installedNewerThanStore,
    };
  }
}
