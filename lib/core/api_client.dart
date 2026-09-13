import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'offline_queue.dart';
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

  /// Where answers are kept for offline use (set once services are up).
  OfflineQueue? store;

  /// Runs before a read, so queued work reaches the server before we ask it what is true.
  Future<void> Function()? beforeRead;

  /// Whether the last request reached the server.
  final ValueNotifier<bool> online = ValueNotifier(true);

  static String cacheKey(String path, Map<String, dynamic>? query) {
    if (query == null || query.isEmpty) return path;
    final keys = query.keys.toList()..sort();
    return '$path?${jsonEncode({for (final k in keys) k: '${query[k]}'})}';
  }

  /// Absolute URL for [path] on the configured server (e.g. for images).
  Future<String> url(String path) async => '${await _storage.baseUrl()}$path';

  /// Bearer header for requests made outside this client (Image.network).
  Future<Map<String, String>> authHeaders() async {
    final token = await _storage.token();
    return {if (token != null) 'Authorization': 'Bearer $token'};
  }

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 45),
    contentType: Headers.jsonContentType,
    responseType: ResponseType.json,
    validateStatus: (_) => true,
  ));

  /// A read. Online, the answer is also kept on the phone; offline, the last
  /// kept answer is returned instead, so screens still open in a dead zone.
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async {
    final key = cacheKey(path, query);
    try {
      if (online.value && beforeRead != null) {
        await beforeRead!().timeout(const Duration(seconds: 10), onTimeout: () {});
      }
      final data = await _send('GET', path, query: query);
      await store?.saveCache(key, data);
      return data;
    } on ApiException catch (e) {
      if (e.code != 'network' || store == null) rethrow;
      final cached = await store!.readCache(key);
      if (cached == null) {
        throw ApiException(null, 'network', 'You are offline, and this screen was not opened online before.');
      }
      return cached.$1;
    }
  }

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
      online.value = false;
      throw ApiException(null, 'network', 'Cannot reach the server. Check your internet connection.');
    }
    online.value = true;

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
