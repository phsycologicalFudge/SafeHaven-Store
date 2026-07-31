import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'store_config.dart';
import 'store_exceptions.dart';
import 'store_http_utils.dart';

class StoreAuthService {
  StoreAuthService._();

  static final StoreAuthService instance = StoreAuthService._();

  static const String _tokenKey = 'safehaven_developer_token';

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

  Uri loginUri() {
    return Uri.parse('$storeDefaultBaseUrl/login?app=store');
  }

  Future<Uri> dashboardUri() async {
    final token = await requireToken();
    return Uri.parse(
      '$storeDefaultBaseUrl/account?token=${Uri.encodeComponent(token)}',
    );
  }

  Future<void> saveTokenFromAuthUri(Uri uri) async {
    final token = uri.queryParameters['token']?.trim();
    if (token == null || token.isEmpty) {
      throw const StoreApiException('missing_token');
    }
    await saveToken(token);
  }

  Future<StoreAccount> fetchMe() async {
    final token = await requireToken();
    final res = await http.get(
      Uri.parse('$storeDefaultBaseUrl/me'),
      headers: storeAuthHeaders(token),
    );

    storeThrowIfBad(res);

    final body = storeDecodeMap(res.body);
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