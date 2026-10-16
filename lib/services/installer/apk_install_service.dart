import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import '../engine/bridge.dart';
import '../logs/debug_log_service.dart';
import '../store_service.dart';
import 'package:safehaven/translations/app_localizations.dart';

class InstalledPackageState {
  const InstalledPackageState({
    required this.installed,
    required this.versionCode,
    this.versionName,
    this.signingCertificateSha256,
    this.installer,
  });

  final bool installed;
  final int versionCode;
  final String? versionName;
  final String? signingCertificateSha256;
  final String? installer;

  bool get isInstalledBySafeHaven => installer == 'com.colourswift.safehaven';

  Map<String, Object?> toJson() {
    return {
      'installed': installed,
      'versionCode': versionCode,
      'signingCertificateSha256': signingCertificateSha256,
    };
  }

  bool? signatureMismatchWith(String? storeSigningKeyHash) {
    final installedHash = signingCertificateSha256?.trim().toLowerCase();
    final storeHash = storeSigningKeyHash?.trim().toLowerCase();
    if (installedHash == null || installedHash.isEmpty) return null;
    if (storeHash == null || storeHash.isEmpty) return null;
    return installedHash != storeHash;
  }

  bool canUpdateTo(StoreVersion? version) {
    if (!installed || version == null) return false;
    return version.versionCode > versionCode;
  }

  bool isSameVersionAs(StoreVersion? version) {
    if (!installed || version == null) return false;
    return version.versionCode == versionCode;
  }

  bool isNewerThan(StoreVersion? version) {
    if (!installed || version == null) return false;
    return versionCode > version.versionCode;
  }
}

class ApkInstallService {
  ApkInstallService._();

  static final ApkInstallService instance = ApkInstallService._();

  static const MethodChannel _channel = MethodChannel('safehaven/installer');
  static const Duration _installCacheTtl = Duration(seconds: 30);
  static const Duration _pollInterval = Duration(milliseconds: 120);

  final EngineBridge _bridge = EngineBridge.instance;
  final _cancelledPackages = <String>{};
  final _jobs = <String, int>{};
  Map<String, InstalledPackageState>? _stateCache;
  Future<Map<String, InstalledPackageState>>? _inFlightStates;

  int? _runningJob;
  bool _paused = false;

  bool get isPaused => _paused;

  static Map<String, Object?> wire(Map<String, InstalledPackageState> states) {
    return {for (final e in states.entries) e.key: e.value.toJson()};
  }

  static String failureMessage(Object error, AppLocalizations l) {
    if (error is PlatformException) {
      return error.code == 'install_permission_required'
          ? l.installPermissionRequired
          : l.installCouldNotStart;
    }
    return l.installFailedGeneric(error.toString());
  }

  Future<InstalledPackageState> getPackageState({
    required String packageName,
  }) async {
    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'getPackageState',
      {'packageName': packageName},
    );

    if (result == null) {
      return const InstalledPackageState(installed: false, versionCode: 0);
    }

    return _stateFrom(result);
  }

  Future<Map<String, InstalledPackageState>> getAllPackageStates({bool forceRefresh = false}) {
    if (!forceRefresh) {
      final cached = _stateCache;
      if (cached != null) return Future.value(cached);
    }

    final pending = _inFlightStates;
    if (pending != null) return pending;

    final fetch = _fetchAllPackageStates();
    _inFlightStates = fetch;

    return fetch.whenComplete(() {
      if (identical(_inFlightStates, fetch)) {
        _inFlightStates = null;
      }
    });
  }

  Future<Map<String, InstalledPackageState>> _fetchAllPackageStates() async {
    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('getAllPackageStates');
    if (result == null) {
      _stateCache = {};
      return _stateCache!;
    }

    final map = <String, InstalledPackageState>{};
    for (final entry in result.entries) {
      map[entry.key as String] = _stateFrom(entry.value as Map<dynamic, dynamic>);
    }

    _stateCache = map;
    return _stateCache!;
  }

  InstalledPackageState _stateFrom(Map<dynamic, dynamic> data) {
    return InstalledPackageState(
      installed: data['installed'] == true,
      versionCode: _asInt(data['versionCode']),
      versionName: _asString(data['versionName']),
      signingCertificateSha256: _asString(data['signingCertificateSha256']),
      installer: _asString(data['installer']),
    );
  }

  void invalidateStateCache() {
    _stateCache = null;
  }

  Future<void> openApp({required String packageName}) async {
    await _channel.invokeMethod('openApp', {'packageName': packageName});
  }

  Future<void> uninstallApp({required String packageName}) async {
    await _channel.invokeMethod('uninstallApp', {'packageName': packageName});
  }

  Future<void> pauseDownload() async {
    final job = _runningJob;
    if (job == null || _paused) return;
    _bridge.callSync('download.pause', {'id': job});
    _paused = true;
  }

  Future<void> resumeDownload() async {
    final job = _runningJob;
    if (job == null || !_paused) return;
    _bridge.callSync('download.resume', {'id': job});
    _paused = false;
  }

  Future<void> cancelDownload({String? packageName}) async {
    if (packageName != null) {
      final job = _jobs[packageName];
      if (job == null) {
        _cancelledPackages.add(packageName);
        return;
      }
      _bridge.callSync('download.cancel', {'id': job});
    } else {
      _bridge.callSync('download.cancel');
    }
    _paused = false;
  }

  Future<void> downloadAndInstall({
    required PublicStoreApp app,
    required void Function(double progress) onProgress,
    void Function()? onStarted,
  }) async {
    final version = app.latestVersion;
    if (version == null) {
      throw const StoreApiException('missing_version');
    }

    final path = await downloadApk(
      packageName: app.packageName,
      version: version,
      onProgress: onProgress,
      onStarted: onStarted,
    );

    try {
      await _channel.invokeMethod('installApk', {
        'path': path,
        'packageName': app.packageName,
      });
    } catch (e, s) {
      DebugLog.e('ApkInstall', 'install failed: ${app.packageName}', e, s);
      rethrow;
    }
    invalidateStateCache();

    _scheduleInstallCacheCleanup(File(path));
  }

  Future<String> downloadApk({
    required String packageName,
    required StoreVersion version,
    required void Function(double progress) onProgress,
    void Function()? onStarted,
  }) async {
    await _bridge.ensureReady();

    if (_cancelledPackages.remove(packageName)) {
      throw const StoreApiException('download_cancelled');
    }

    _paused = false;

    final job = await _bridge.call<int>(
      'download.start',
      args: {
        'packageName': packageName,
        'versionCode': version.versionCode,
        'apkSize': version.apkSize,
      },
      decode: _asJobId,
    );
    _jobs[packageName] = job;

    try {
      if (_cancelledPackages.remove(packageName)) {
        _bridge.callSync('download.cancel', {'id': job});
      }

      final path = await _awaitJob(job, packageName, onProgress, onStarted);
      onProgress(1);
      return path;
    } finally {
      _jobs.remove(packageName);
      _cancelledPackages.remove(packageName);
      if (_runningJob == job) _runningJob = null;
      _paused = false;
    }
  }

  Future<String> _awaitJob(
    int job,
    String packageName,
    void Function(double progress) onProgress,
    void Function()? onStarted,
  ) async {
    var started = false;
    var lastProgress = -1.0;

    while (true) {
      final status = _bridge.callSync('download.status', {'id': job}) as Map<String, dynamic>;
      final state = status['state'] as String;

      if (!started && state != 'queued') {
        started = true;
        _runningJob = job;
        onStarted?.call();
      }

      if (state == 'done') return status['path'] as String;

      if (state == 'failed') {
        final error = status['error'] as String? ?? 'download_failed';
        if (error != 'download_cancelled') {
          DebugLog.e('ApkInstall', 'download failed: $packageName $error');
        }
        throw StoreApiException(error);
      }

      final total = _asInt(status['total']);
      if (total > 0) {
        final progress = _asInt(status['received']) / total;
        if (progress != lastProgress) {
          lastProgress = progress;
          onProgress(progress);
        }
      }

      await Future<void>.delayed(_pollInterval);
    }
  }

  void _scheduleInstallCacheCleanup(File installedFile) {
    Timer(_installCacheTtl, () async {
      try {
        if (await installedFile.exists()) {
          await installedFile.delete();
        }
      } catch (e, s) {
        DebugLog.e('ApkInstall', 'delete file failed: ${installedFile.path}', e, s);
      }
    });
  }

  String? _asString(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;
    return text;
  }

  int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

int _asJobId(dynamic value) => (value as num).toInt();