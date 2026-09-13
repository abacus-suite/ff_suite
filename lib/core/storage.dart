import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

/// Encrypted key/value storage for the token, server URL and device id.
class AppStorage {
  /// Override at build time: flutter run --dart-define=BASE_URL=https://...
  static const defaultBaseUrl = String.fromEnvironment(
    'BASE_URL',
    defaultValue: 'https://bharathi17656-beauty-salon-demo-staging-37854326.dev.odoo.com',
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
