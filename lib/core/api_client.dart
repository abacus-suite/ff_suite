import 'package:dio/dio.dart';

import 'storage.dart';

class ApiException implements Exception {
  ApiException(this.status, this.code, this.message);

  final int? status;
  final String code;
  final String message;

  @override
  String toString() => message;
}

/// Thin client for the Odoo /api/v1 endpoints.
/// Unwraps {"ok": true, "data": ...} and turns errors into [ApiException].
class ApiClient {
  ApiClient(this._storage);

  final AppStorage _storage;
  Future<void> Function()? onUnauthorized;

  /// Absolute URL for [path] on the configured server (e.g. for images).
  Future<String> url(String path) async => '${await _storage.baseUrl()}$path';

  /// Bearer header for requests made outside this client (Image.network).
  Future<Map<String, String>> authHeaders() async {
    final token = await _storage.token();
    return {if (token != null) 'Authorization': 'Bearer $token'};
  }

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 45),
    contentType: Headers.jsonContentType,
    responseType: ResponseType.json,
    validateStatus: (_) => true,
  ));

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) => _send('GET', path, query: query);

  Future<dynamic> post(String path, [Map<String, dynamic>? body]) =>
      _send('POST', path, body: body ?? <String, dynamic>{});

  Future<dynamic> _send(String method, String path, {Object? body, Map<String, dynamic>? query}) async {
    final base = await _storage.baseUrl();
    final token = await _storage.token();
    final Response<dynamic> res;
    try {
      res = await _dio.request<dynamic>(
        '$base$path',
        data: body,
        queryParameters: query,
        options: Options(method: method, headers: {
          if (token != null) 'Authorization': 'Bearer $token',
        }),
      );
    } on DioException {
      throw ApiException(null, 'network', 'Cannot reach the server. Check your internet connection.');
    }

    final data = res.data;
    if (data is Map && data['ok'] == true) return data['data'];
    if (res.statusCode == 401 && token != null && !path.endsWith('/auth/login')) {
      await onUnauthorized?.call();
    }
    if (data is Map && data['error'] is Map) {
      final error = data['error'] as Map;
      throw ApiException(res.statusCode, '${error['code'] ?? 'error'}', '${error['message'] ?? 'Error'}');
    }
    throw ApiException(res.statusCode, 'http_${res.statusCode}', 'Unexpected server response (${res.statusCode}).');
  }
}
