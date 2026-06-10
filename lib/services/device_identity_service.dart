import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

class DeviceIdentityService {
  DeviceIdentityService._();
  static final DeviceIdentityService instance = DeviceIdentityService._();

  static const _tokenKey = 'sh_device_token';
  static const _nicknameKey = 'sh_device_nickname';

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  Future<String?> getNickname() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_nicknameKey);
  }

  Future<bool> isSetUp() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  Future<String> setupIdentity(String nickname) async {
    final clean = nickname.trim();
    if (clean.isEmpty) throw ArgumentError('nickname_empty');

    final suffix = _randomHex(8);
    final token = '${clean}_$suffix';

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_nicknameKey, clean);
    await prefs.setString(_tokenKey, token);

    return token;
  }

  String _randomHex(int length) {
    final rng = Random.secure();
    final bytes = List.generate(length ~/ 2, (_) => rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
