import 'dart:convert';
import 'package:http/http.dart' as http;
import 'store_exceptions.dart';

Map<String, String> storeAuthHeaders(String token) {
  return {
    'authorization': 'Bearer $token',
    'content-type': 'application/json; charset=utf-8',
  };
}

Map<String, dynamic> storeDecodeMap(String body) {
  final decoded = jsonDecode(body);
  if (decoded is Map<String, dynamic>) return decoded;
  throw const StoreApiException('invalid_response');
}

void storeThrowIfBad(http.Response res) {
  if (res.statusCode >= 200 && res.statusCode < 300) return;

  try {
    final decoded = jsonDecode(res.body);
    if (decoded is Map<String, dynamic>) {
      throw StoreApiException(
        decoded['error']?.toString() ??
            decoded['reason']?.toString() ??
            'http_${res.statusCode}',
      );
    }
  } catch (e) {
    if (e is StoreApiException) rethrow;
  }

  throw StoreApiException('http_${res.statusCode}');
}