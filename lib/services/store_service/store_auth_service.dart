import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:safehaven/services/engine/bridge.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'store_config.dart';
import 'store_exceptions.dart';

class StoreAuthService {
  StoreAuthService._();

  static final StoreAuthService instance = StoreAuthService._();

  static const String _tokenKey = 'safehaven_developer_token';
  static const String _verifierKey = 'safehaven_auth_pkce_verifier';
  static const String _startedAtKey = 'safehaven_auth_pkce_started_at';
  static const String _appLinkHost = 'account.colourswift.com';
  static const String _appLinkPath = '/app/auth/store';
  static const Duration _pendingTtl = Duration(minutes: 10);

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey)?.trim();
    if (token == null || token.isEmpty) return null;
    return token;
  }

  Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token.trim());
  }

  Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }

  Future<String> requireToken() async {
    final token = await getToken();
    if (token == null) throw const StoreApiException('missing_token');
    return token;
  }

  Future<Uri> startLoginUri() async {
    final rnd = Random.secure();
    final verifier = _b64url(List<int>.generate(32, (_) => rnd.nextInt(256)));
    final challenge = _b64url(sha256.convert(ascii.encode(verifier)).bytes);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_verifierKey, verifier);
    await prefs.setInt(_startedAtKey, DateTime.now().millisecondsSinceEpoch);

    return Uri.parse('$storeDefaultBaseUrl/login').replace(queryParameters: {
      'app': 'store',
      'flow': 'v2',
      'applink': '1',
      'code_challenge': challenge,
    });
  }

  bool isAuthUri(Uri uri) =>
      (uri.scheme == 'https' && uri.host == _appLinkHost && uri.path == _appLinkPath) ||
      (uri.scheme == 'safehaven' && uri.host == 'auth');

  Future<void> completeLoginFromUri(Uri uri) async {
    if (!isAuthUri(uri)) return;
    final code = (uri.queryParameters['code'] ?? '').trim();
    if (code.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final verifier = prefs.getString(_verifierKey) ?? '';
    final startedAt = prefs.getInt(_startedAtKey) ?? 0;
    await prefs.remove(_verifierKey);
    await prefs.remove(_startedAtKey);

    if (verifier.isEmpty) return;
    final age = DateTime.now().millisecondsSinceEpoch - startedAt;
    if (age < 0 || age > _pendingTtl.inMilliseconds) return;

    final body = await EngineBridge.instance.call<Map<String, dynamic>>(
      'api.request',
      args: {
        'method': 'POST',
        'path': '/auth/exchange',
        'token': null,
        'body': {'code': code, 'codeVerifier': verifier},
      },
      decode: asMap,
    );
    final token = (body['token'] ?? '').toString().trim();
    if (token.isEmpty) throw const StoreApiException('missing_token');
    await saveToken(token);
  }

  Future<Uri> dashboardUri() async {
    final token = await requireToken();
    final target = Uri.parse('$storeDefaultBaseUrl/account');
    try {
      final body = await EngineBridge.instance.call<Map<String, dynamic>>(
        'api.request',
        args: {'method': 'POST', 'path': '/auth/web-handoff', 'token': token},
        decode: asMap,
      );
      final code = (body['code'] ?? '').toString().trim();
      if (code.isNotEmpty) return target.replace(queryParameters: {'handoff': code});
    } catch (_) {}
    return target;
  }

  static String _b64url(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');

  Future<StoreAccount> fetchMe() async {
    final token = await requireToken();
    final body = await EngineBridge.instance.call<Map<String, dynamic>>(
      'api.request',
      args: {'method': 'GET', 'path': '/me', 'token': token},
      decode: asMap,
    );

    final user = body['user'];
    if (user is! Map<String, dynamic>) {
      throw const StoreApiException('user_missing');
    }

    return StoreAccount.fromJson(user);
  }
}

class StoreAccount {
  const StoreAccount({
    required this.id,
    required this.email,
    required this.displayName,
    required this.developerEnabled,
  });

  final String id;
  final String email;
  final String displayName;
  final bool developerEnabled;

  factory StoreAccount.fromJson(Map<String, dynamic> json) {
    return StoreAccount(
      id: _asString(json['id']),
      email: _asString(json['email']),
      displayName: _asString(json['display_name'], fallback: 'User'),
      developerEnabled: _asBool(json['developer_enabled']) ||
          _asBool(json['developerEnabled']) ||
          _asBool(json['is_developer']) ||
          _asBool(json['isDeveloper']),
    );
  }
}

String _asString(dynamic value, {String fallback = ''}) {
  if (value == null) return fallback;
  return value.toString();
}

bool _asBool(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final clean = value?.toString().toLowerCase().trim();
  return clean == 'true' || clean == '1' || clean == 'yes';
}