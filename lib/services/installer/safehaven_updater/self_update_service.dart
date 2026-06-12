import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../../store_service.dart';

class SelfUpdateInfo {
  const SelfUpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.versionCode,
    required this.parsedNotes,
    required this.releaseUrl,
  });

  final String currentVersion;
  final String latestVersion;
  final int versionCode;
  final List<ReleaseNoteBlock> parsedNotes;
  final String releaseUrl;
}

enum ReleaseNoteLineKind { header, bullet, commitBullet, blank }

class ReleaseNoteLine {
  const ReleaseNoteLine({
    required this.kind,
    required this.text,
    this.commitHash,
    this.commitUrl,
  });

  final ReleaseNoteLineKind kind;
  final String text;
  final String? commitHash;
  final String? commitUrl;
}

class ReleaseNoteBlock {
  const ReleaseNoteBlock({required this.header, required this.lines});

  final String header;
  final List<ReleaseNoteLine> lines;
}

class SelfUpdateService {
  SelfUpdateService._();
  static final SelfUpdateService instance = SelfUpdateService._();

  static const _selfPackage = 'com.colourswift.safehaven';
  static const _repo = 'phsycologicalFudge/SafeHaven-Store';
  static const _apiBase = 'https://api.github.com/repos/$_repo';
  static const MethodChannel _channel = MethodChannel('safehaven/installer');

  static bool forceUpdate = true;

  static final _tagPrefix = RegExp(r'^v', caseSensitive: false);
  static final _tagPostfix = RegExp(r'[-+].*$');
  static final _commitLine = RegExp(
    r'^[-*]\s+([0-9a-f]{40,64}):\s*(.+)$',
    caseSensitive: false,
  );
  static final _discordCut = RegExp(r'_To keep up with.*$', dotAll: true);
  static final _trailingHr = RegExp(r'\n---\s*$');
  static final _headerLine = RegExp(r'^#{1,4}\s+(.+)$');
  static final _bulletLine = RegExp(r'^[-*]\s+(.+)$');

  Future<SelfUpdateInfo?> check() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final currentVersion = info.version;

      final index = await StoreService.instance.fetchIndex();
      final storeApp = index.apps.firstWhere(
            (a) => a.packageName == _selfPackage,
        orElse: () => throw StateError('not_in_index'),
      );

      final latest = storeApp.latestVersion;
      if (latest == null) return null;

      final latestVersion = _cleanTag(latest.versionName);
      if (latestVersion.isEmpty) return null;
      if (!forceUpdate && !_isNewer(currentVersion, latestVersion)) return null;

      final githubRes = await http.get(
        Uri.parse('$_apiBase/releases/latest'),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      );

      List<ReleaseNoteBlock> parsedNotes = const [];
      String releaseUrl = '';

      if (githubRes.statusCode == 200) {
        final body = jsonDecode(githubRes.body) as Map<String, dynamic>;
        parsedNotes = _parseReleaseNotes((body['body'] as String?) ?? '');
        releaseUrl = (body['html_url'] as String?) ?? '';
      }

      return SelfUpdateInfo(
        currentVersion: currentVersion,
        latestVersion: latestVersion,
        versionCode: latest.versionCode,
        parsedNotes: parsedNotes,
        releaseUrl: releaseUrl,
      );
    } catch (_) {
      return null;
    }
  }

  Future<String?> downloadApk(
      int versionCode, {
        required void Function(double progress) onProgress,
      }) async {
    final dir = await getApplicationSupportDirectory();
    final updateDir = Directory('${dir.path}/install_cache');
    if (!await updateDir.exists()) {
      await updateDir.create(recursive: true);
    }

    await for (final entity in updateDir.list()) {
      try {
        await entity.delete(recursive: true);
      } catch (_) {}
    }

    final file = File('${updateDir.path}/safehaven_self_update.apk');

    String url;
    try {
      url = await StoreService.instance.getDownloadUrl(
        packageName: _selfPackage,
        versionCode: versionCode,
      );
    } catch (_) {
      return null;
    }

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);

    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }

      final total = response.contentLength;
      var received = 0;
      final sink = file.openWrite();

      await for (final chunk in response) {
        received += chunk.length;
        sink.add(chunk);
        if (total > 0) {
          onProgress((received / total).clamp(0.0, 1.0));
        }
      }

      await sink.close();
      return file.path;
    } catch (_) {
      try {
        await file.delete();
      } catch (_) {}
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> installApk(String path) async {
    await _channel.invokeMethod('installApk', {
      'path': path,
      'packageName': _selfPackage,
    });
  }

  String _cleanTag(String tag) {
    return tag
        .replaceFirst(_tagPrefix, '')
        .trim()
        .replaceFirst(_tagPostfix, '')
        .trim();
  }

  bool _isNewer(String current, String latest) {
    final c = current.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final l = latest.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final len = c.length > l.length ? c.length : l.length;

    for (var i = 0; i < len; i++) {
      final cv = i < c.length ? c[i] : 0;
      final lv = i < l.length ? l[i] : 0;
      if (lv > cv) return true;
      if (lv < cv) return false;
    }

    return false;
  }

  List<ReleaseNoteBlock> _parseReleaseNotes(String raw) {
    var cleaned = raw.replaceFirst(_discordCut, '').trim();
    cleaned = cleaned.replaceFirst(_trailingHr, '').trim();

    final lines = cleaned.split('\n');
    final blocks = <ReleaseNoteBlock>[];
    String currentHeader = '';
    var currentLines = <ReleaseNoteLine>[];

    for (final line in lines) {
      final trimmed = line.trim();

      final headerMatch = _headerLine.firstMatch(trimmed);
      if (headerMatch != null) {
        if (currentHeader.isNotEmpty || currentLines.isNotEmpty) {
          blocks.add(ReleaseNoteBlock(header: currentHeader, lines: currentLines));
        }
        currentHeader = headerMatch.group(1)!.trim();
        currentLines = [];
        continue;
      }

      if (trimmed.isEmpty) continue;

      final commitMatch = _commitLine.firstMatch(trimmed);
      if (commitMatch != null) {
        final hash = commitMatch.group(1)!;
        final desc = commitMatch.group(2)!.trim();
        currentLines.add(ReleaseNoteLine(
          kind: ReleaseNoteLineKind.commitBullet,
          text: desc,
          commitHash: hash.substring(0, 7),
          commitUrl: 'https://github.com/$_repo/commit/$hash',
        ));
        continue;
      }

      final bulletMatch = _bulletLine.firstMatch(trimmed);
      if (bulletMatch != null) {
        currentLines.add(ReleaseNoteLine(
          kind: ReleaseNoteLineKind.bullet,
          text: bulletMatch.group(1)!.trim(),
        ));
        continue;
      }

      currentLines.add(ReleaseNoteLine(
        kind: ReleaseNoteLineKind.bullet,
        text: trimmed,
      ));
    }

    if (currentHeader.isNotEmpty || currentLines.isNotEmpty) {
      blocks.add(ReleaseNoteBlock(header: currentHeader, lines: currentLines));
    }

    return blocks;
  }
}