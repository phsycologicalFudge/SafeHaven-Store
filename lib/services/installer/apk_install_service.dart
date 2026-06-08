/*
APK install service. Handles downloading, pausing, resuming, and cancelling APK
installations via a MethodChannel to the Kotlin side. Also exposes package state
queries (installed version, signing hash, installer attribution) used for update checks.
*/
import 'dart:async';
import 'dart:io';
import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../store_service.dart';

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

  HttpClient? _client;
  StreamSubscription<List<int>>? _subscription;
  Completer<void>? _downloadCompleter;
  Timer? _cleanupTimer;
  File? _activeFile;
  bool _cancelled = false;
  bool _paused = false;

  bool get isPaused => _paused;

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

    return InstalledPackageState(
      installed: result['installed'] == true,
      versionCode: _asInt(result['versionCode']),
      versionName: _asString(result['versionName']),
      signingCertificateSha256: _asString(result['signingCertificateSha256']),
      installer: _asString(result['installer']),
    );
  }

  Future<void> openApp({required String packageName}) async {
    await _channel.invokeMethod('openApp', {'packageName': packageName});
  }

  Future<void> uninstallApp({required String packageName}) async {
    await _channel.invokeMethod('uninstallApp', {'packageName': packageName});
  }

  Future<void> pauseDownload() async {
    final subscription = _subscription;
    if (subscription == null || _paused) return;
    subscription.pause();
    _paused = true;
  }

  Future<void> resumeDownload() async {
    final subscription = _subscription;
    if (subscription == null || !_paused) return;
    subscription.resume();
    _paused = false;
  }

  Future<void> cancelDownload() async {
    _cancelled = true;
    _paused = false;

    try {
      await _subscription?.cancel();
    } catch (_) {}
    _subscription = null;

    _client?.close(force: true);
    _client = null;

    await _deleteFile(_activeFile);
    _activeFile = null;

    final completer = _downloadCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(const StoreApiException('download_cancelled'));
    }
  }

  Future<void> downloadAndInstall({
    required PublicStoreApp app,
    required void Function(double progress) onProgress,
  }) async {
    final version = app.latestVersion;
    if (version == null) {
      throw const StoreApiException('missing_version');
    }

    await cancelDownload();
    _cancelled = false;
    _paused = false;

    final downloadUrl = await StoreService.instance.getDownloadUrl(
      packageName: app.packageName,
      versionCode: version.versionCode,
    );

    final installDir = await _installCacheDirectory();
    await _clearInstallCache(installDir);

    final file = File(
      '${installDir.path}/${app.packageName}-${version.versionCode}.apk',
    );
    _activeFile = file;

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);
    _client = client;

    final request = await client.getUrl(Uri.parse(downloadUrl));
    final response = await request.close();

    if (response.statusCode < 200 || response.statusCode >= 300) {
      client.close(force: true);
      _client = null;
      throw StoreApiException('download_http_${response.statusCode}');
    }

    final total = response.contentLength;
    var received = 0;

    final digestOutput = AccumulatorSink<Digest>();
    final digestInput = sha256.startChunkedConversion(digestOutput);
    final sink = file.openWrite();
    final completer = Completer<void>();
    _downloadCompleter = completer;

    _subscription = response.listen(
          (chunk) {
        if (_cancelled) return;

        received += chunk.length;
        digestInput.add(chunk);
        sink.add(chunk);

        if (total > 0) {
          onProgress(received / total);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      },
      onDone: () {
        if (!completer.isCompleted) {
          completer.complete();
        }
      },
      cancelOnError: true,
    );

    try {
      await completer.future;
    } finally {
      await sink.close();
      digestInput.close();
      client.close(force: true);

      _subscription = null;
      _downloadCompleter = null;
      _client = null;
      _paused = false;
    }

    if (_cancelled) {
      await _deleteFile(file);
      _activeFile = null;
      throw const StoreApiException('download_cancelled');
    }

    final actualSha256 = digestOutput.events.single.toString().toLowerCase();
    final expectedSha256 = version.sha256.trim().toLowerCase();

    if (expectedSha256.isNotEmpty && actualSha256 != expectedSha256) {
      await _deleteFile(file);
      _activeFile = null;
      throw const StoreApiException('sha256_mismatch');
    }

    onProgress(1);

    await _channel.invokeMethod('installApk', {
      'path': file.path,
      'packageName': app.packageName,
    });

    _scheduleInstallCacheCleanup(installDir, file);
  }

  Future<Directory> _installCacheDirectory() async {
    final dir = await getApplicationSupportDirectory();
    final installDir = Directory('${dir.path}/install_cache');

    if (!await installDir.exists()) {
      await installDir.create(recursive: true);
    }

    return installDir;
  }

  Future<void> _clearInstallCache(Directory installDir) async {
    if (!await installDir.exists()) return;

    final active = _activeFile;
    await for (final entity in installDir.list()) {
      if (active != null && entity.path == active.path) continue;
      await _deleteEntity(entity);
    }
  }

  void _scheduleInstallCacheCleanup(Directory installDir, File installedFile) {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer(_installCacheTtl, () async {
      await _deleteFile(installedFile);
    });
  }

  Future<void> _deleteFile(File? file) async {
    if (file == null) return;

    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  Future<void> _deleteEntity(FileSystemEntity entity) async {
    try {
      await entity.delete(recursive: true);
    } catch (_) {}
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