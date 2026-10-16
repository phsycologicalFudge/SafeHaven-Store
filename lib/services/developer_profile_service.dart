import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'device_identity_service.dart';

class DeveloperProfileService extends ChangeNotifier {
  DeveloperProfileService._();
  static final DeveloperProfileService instance = DeveloperProfileService._();

  static const _nameKey = 'dev_profile_display_name';
  static const _avatarKey = 'dev_profile_avatar_file';
  static const _legacyAvatar = 'dev_profile_avatar.png';

  String? _displayName;
  String? _nickname;
  File? _avatarFile;
  Future<void>? _loading;

  String? get displayName => _displayName;
  String? get nickname => _nickname;
  String get name => _displayName ?? _nickname ?? '';
  File? get avatarFile => _avatarFile;

  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _displayName = prefs.getString(_nameKey);
    _nickname = await DeviceIdentityService.instance.getNickname();
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/${prefs.getString(_avatarKey) ?? _legacyAvatar}');
    if (await file.exists()) _avatarFile = file;
    notifyListeners();
  }

  Future<void> refreshNickname() async {
    _nickname = await DeviceIdentityService.instance.getNickname();
    notifyListeners();
  }

  Future<void> setDisplayName(String? name) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty) {
      await prefs.remove(_nameKey);
      _displayName = null;
    } else {
      await prefs.setString(_nameKey, trimmed);
      _displayName = trimmed;
    }
    notifyListeners();
  }

  Future<void> setAvatarBytes(Uint8List bytes) async {
    final dir = await getApplicationDocumentsDirectory();
    final fileName = 'profile_avatar_${DateTime.now().millisecondsSinceEpoch}.png';
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_avatarKey, fileName);
    await _discard(_avatarFile);
    _avatarFile = file;
    notifyListeners();
  }

  Future<void> clearAvatar() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_avatarKey);
    await _discard(_avatarFile);
    _avatarFile = null;
    notifyListeners();
  }

  Future<void> _discard(File? file) async {
    if (file == null) return;
    await FileImage(file).evict();
    try {
      await file.delete();
    } catch (_) {}
  }
}
