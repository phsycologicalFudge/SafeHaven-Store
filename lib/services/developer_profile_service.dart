import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeveloperProfileService extends ChangeNotifier {
  DeveloperProfileService._();
  static final DeveloperProfileService instance = DeveloperProfileService._();

  static const _nameKey = 'dev_profile_display_name';
  static const _avatarFileName = 'dev_profile_avatar.png';

  String? _displayName;
  File? _avatarFile;
  bool _loaded = false;

  String? get displayName => _displayName;
  File? get avatarFile => _avatarFile;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;

    final prefs = await SharedPreferences.getInstance();
    _displayName = prefs.getString(_nameKey);

    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$_avatarFileName');
    if (await file.exists()) {
      _avatarFile = file;
    }

    notifyListeners();
  }

  Future<void> setDisplayName(String? name) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = name?.trim();

    if (trimmed == null || trimmed.isEmpty) {
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
    final file = File('${dir.path}/$_avatarFileName');
    await file.writeAsBytes(bytes, flush: true);
    _avatarFile = file;
    notifyListeners();
  }

  Future<void> clearAvatar() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$_avatarFileName');
    if (await file.exists()) {
      await file.delete();
    }
    _avatarFile = null;
    notifyListeners();
  }
}