import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

/// Encrypted key/value storage for the token, server URL and device id.
class AppStorage {
  /// Override at build time: flutter run --dart-define=BASE_URL=https://...
  static const defaultBaseUrl = String.fromEnvironment(
    'BASE_URL',
    defaultValue: 'https://kumbayah-live.odoo.com',
  );

  // flutter_secure_storage 11 encrypts on Android by default.
  final FlutterSecureStorage _store = const FlutterSecureStorage();

  String? _token;
  String? _baseUrl;

  Future<String?> token() async => _token ??= await _store.read(key: 'token');

  Future<void> saveToken(String? value) async {
    _token = value;
    await write('token', value);
  }

  Future<String> baseUrl() async => _baseUrl ??= (await _store.read(key: 'base_url')) ?? defaultBaseUrl;

  Future<void> saveBaseUrl(String value) async {
    final cleaned = value.trim().replaceAll(RegExp(r'/+$'), '');
    _baseUrl = cleaned;
    await write('base_url', cleaned);
  }

  String? _db;
  bool _dbRead = false;

  /// The database chosen at login, for servers that host more than one (null: the server decides).
  Future<String?> db() async {
    if (!_dbRead) {
      _db = await _store.read(key: 'db_name');
      _dbRead = true;
    }
    return _db;
  }

  Future<void> saveDb(String? value) async {
    _db = (value == null || value.trim().isEmpty) ? null : value.trim();
    _dbRead = true;
    await write('db_name', _db);
  }

  Future<String> deviceUid() async {
    var id = await _store.read(key: 'device_uid');
    if (id == null) {
      id = const Uuid().v4();
      await _store.write(key: 'device_uid', value: id);
    }
    return id;
  }

  Future<String?> read(String key) => _store.read(key: key);

  Future<void> write(String key, String? value) =>
      value == null ? _store.delete(key: key) : _store.write(key: key, value: value);
}
