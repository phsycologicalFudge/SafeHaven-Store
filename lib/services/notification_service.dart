import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum NotificationKind { updated, updateFailed, selfUpdate }

class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.packageName,
    required this.appName,
    required this.detail,
    required this.at,
    required this.read,
  });

  final String id;
  final NotificationKind kind;
  final String packageName;
  final String appName;
  final String detail;
  final DateTime at;
  final bool read;

  String get key => '${kind.name}|$packageName|$detail';

  AppNotification copyWith({bool? read}) => AppNotification(
        id: id,
        kind: kind,
        packageName: packageName,
        appName: appName,
        detail: detail,
        at: at,
        read: read ?? this.read,
      );

  Map<String, Object> toJson() => {
        'id': id,
        'kind': kind.name,
        'packageName': packageName,
        'appName': appName,
        'detail': detail,
        'at': at.millisecondsSinceEpoch,
        'read': read,
      };

  static AppNotification? fromJson(Map<String, dynamic> json) {
    final kind = NotificationKind.values.where((k) => k.name == json['kind']).firstOrNull;
    final at = json['at'];
    if (kind == null || at is! int) return null;
    final packageName = json['packageName']?.toString() ?? '';
    return AppNotification(
      id: json['id']?.toString() ?? '$at|${kind.name}|$packageName',
      kind: kind,
      packageName: packageName,
      appName: json['appName']?.toString() ?? packageName,
      detail: json['detail']?.toString() ?? '',
      at: DateTime.fromMillisecondsSinceEpoch(at),
      read: json['read'] == true,
    );
  }
}

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static const _prefsKey = 'safehaven_notifications';
  static const _nativeInbox = 'inbox_native.jsonl';
  static const _maxItems = 200;
  static const _nativeKinds = {'updated': 'updated', 'update_failed': 'updateFailed'};

  final ValueNotifier<int> unread = ValueNotifier(0);
  List<AppNotification> _items = const [];
  bool _loaded = false;

  List<AppNotification> get items => _items;

  Future<List<AppNotification>> load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!_loaded) {
      _loaded = true;
      final raw = prefs.getString(_prefsKey);
      if (raw != null) {
        try {
          _items = _dedupe([
            for (final item in jsonDecode(raw) as List<dynamic>)
              if (AppNotification.fromJson(item as Map<String, dynamic>) case final n?) n,
          ]);
        } catch (_) {
          _items = const [];
        }
      }
    }
    final ingested = await _ingestNative();
    if (ingested.isNotEmpty) await _save([...ingested, ..._items]);
    _publish();
    return _items;
  }

  Future<void> add(
    NotificationKind kind, {
    required String packageName,
    required String appName,
    String detail = '',
  }) async {
    await load();
    final at = DateTime.now();
    final item = AppNotification(
      id: '${at.millisecondsSinceEpoch}|${kind.name}|$packageName',
      kind: kind,
      packageName: packageName,
      appName: appName,
      detail: detail,
      at: at,
      read: false,
    );
    await _save([item, ..._items]);
  }

  Future<void> delete(String id) => _save(_items.where((n) => n.id != id).toList());

  Future<void> markAllRead() async {
    if (!_items.any((n) => !n.read)) return;
    await _save([for (final n in _items) n.read ? n : n.copyWith(read: true)]);
  }

  Future<void> _save(List<AppNotification> items) async {
    _items = _dedupe(items).take(_maxItems).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode([for (final n in _items) n.toJson()]));
    _publish();
  }

  List<AppNotification> _dedupe(List<AppNotification> items) {
    items.sort((a, b) => b.at.compareTo(a.at));
    final latest = <String, AppNotification>{};
    for (final n in items) {
      final kept = latest[n.key];
      latest[n.key] = kept == null ? n : kept.copyWith(read: kept.read || n.read);
    }
    return latest.values.toList();
  }

  void _publish() {
    unread.value = _items.where((n) => !n.read).length;
  }

  Future<List<AppNotification>> _ingestNative() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final inbox = File('${dir.path}/$_nativeInbox');
      if (!await inbox.exists()) return const [];
      final claimed = await inbox.rename('${inbox.path}.reading');
      final lines = await claimed.readAsLines();
      await claimed.delete();
      return [
        for (final line in lines)
          if (_fromNative(line) case final n?) n,
      ];
    } catch (_) {
      return const [];
    }
  }

  AppNotification? _fromNative(String line) {
    try {
      final json = jsonDecode(line) as Map<String, dynamic>;
      final kind = _nativeKinds[json['kind']];
      if (kind == null) return null;
      return AppNotification.fromJson({...json, 'kind': kind, 'read': false});
    } catch (_) {
      return null;
    }
  }
}