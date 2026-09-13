import 'dart:convert';

import 'package:dio/dio.dart';

import 'map_usage.dart';
import 'services.dart';
import 'storage.dart';

/// Google's Map Tiles API, driven by the key the office pastes into Odoo.
///
/// The key alone is not enough to fetch tiles: Google first hands out a session
/// token that the tile URLs carry. The token is good for two weeks, so it is
/// kept on the device and only renewed when it expires or the key changes.
class GoogleTiles {
  GoogleTiles(this._storage);

  static const _createSession = 'https://tile.googleapis.com/v1/createSession';
  static const _tile = 'https://tile.googleapis.com/v1/2dtiles/{z}/{x}/{y}';
  static const _sessionKey = 'gmaps_session';

  final AppStorage _storage;
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
  ));

  String? _token;
  String? _forKey;
  DateTime? _expiry;
  Future<String?>? _pending;

  /// The tile URL template for [flutter_map], or null when Google cannot be used.
  Future<String?> urlTemplate({String mapType = 'roadmap', bool highDpi = true}) async {
    if (!available) return null;
    final key = Services.auth.profile?.googleMapsKey ?? '';
    final session = await _session(key, mapType, highDpi);
    if (session == null) return null;
    return '$_tile?session=$session&key=${Uri.encodeQueryComponent(key)}';
  }

  /// Google only when the office chose it and gave a key; otherwise the free tiles are used.
  bool get available =>
      Services.auth.profile?.mapProvider == 'google' && (Services.auth.profile?.googleMapsKey ?? '').isNotEmpty;

  Future<String?> _session(String key, String mapType, bool highDpi) {
    final cached = _token;
    if (cached != null && _forKey == key && (_expiry?.isAfter(DateTime.now()) ?? false)) {
      return Future.value(cached);
    }
    return _pending ??= _createOrRestore(key, mapType, highDpi).whenComplete(() => _pending = null);
  }

  Future<String?> _createOrRestore(String key, String mapType, bool highDpi) async {
    final stored = await _storage.read(_sessionKey);
    if (stored != null) {
      try {
        final saved = jsonDecode(stored) as Map<String, dynamic>;
        final expiry = DateTime.tryParse('${saved['expiry']}');
        if (saved['key'] == key &&
            saved['map_type'] == mapType &&
            expiry != null &&
            expiry.isAfter(DateTime.now())) {
          _token = '${saved['session']}';
          _forKey = key;
          _expiry = expiry;
          return _token;
        }
      } catch (_) {
        // Unreadable cache: ask Google for a fresh session below.
      }
    }
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '$_createSession?key=${Uri.encodeQueryComponent(key)}',
        data: {
          'mapType': mapType,
          'language': 'en-US',
          'region': 'IN',
          'scale': highDpi ? 'scaleFactor2x' : 'scaleFactor1x',
          'highDpi': highDpi,
        },
      );
      final session = res.data?['session'] as String?;
      if (session == null) return null;
      // Google returns the expiry as epoch seconds in a string; keep a day of margin.
      final epoch = int.tryParse('${res.data?['expiry']}');
      final expiry = epoch != null
          ? DateTime.fromMillisecondsSinceEpoch(epoch * 1000).subtract(const Duration(days: 1))
          : DateTime.now().add(const Duration(days: 6));
      _token = session;
      _forKey = key;
      _expiry = expiry;
      MapUsage.session();
      await _storage.write(
        _sessionKey,
        jsonEncode({
          'session': session,
          'key': key,
          'map_type': mapType,
          'expiry': expiry.toIso8601String(),
        }),
      );
      return session;
    } on DioException {
      return null; // No network, bad key, or Map Tiles API not enabled: use the free basemap.
    }
  }

  /// Forget the session — after a key change or a sign-out.
  Future<void> clear() async {
    _token = null;
    _forKey = null;
    _expiry = null;
    await _storage.write(_sessionKey, null);
  }
}
