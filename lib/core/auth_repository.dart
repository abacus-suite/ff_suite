import 'dart:convert';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'api_client.dart';
import 'models.dart';
import 'storage.dart';

class AuthRepository {
  AuthRepository(this._api, this._storage);

  final ApiClient _api;
  final AppStorage _storage;
  Profile? profile;

  /// Restore the cached session at app start (works offline).
  Future<void> restore() async {
    final token = await _storage.token();
    final cached = await _storage.read('profile');
    if (token == null || cached == null) return;
    try {
      profile = Profile.fromJson(jsonDecode(cached) as Map<String, dynamic>);
    } catch (_) {
      profile = null;
    }
  }

  Future<Profile> login(String baseUrl, String login, String password) async {
    await _storage.saveBaseUrl(baseUrl);
    final device = await _deviceMeta();
    final data = await _api.post('/api/v1/auth/login', {
      'login': login.trim(),
      'password': password,
      ...device,
    }) as Map<String, dynamic>;
    await _storage.saveToken(data['token'] as String);
    return _setProfile(data['profile'] as Map<String, dynamic>);
  }

  Future<Profile> refreshProfile() async {
    final data = await _api.get('/api/v1/me') as Map<String, dynamic>;
    return _setProfile(data);
  }

  Future<void> logout() async {
    try {
      await _api.post('/api/v1/auth/logout', {'device_uid': await _storage.deviceUid()});
    } catch (_) {
      // Token is dropped locally anyway.
    }
    await clearLocal();
  }

  Future<void> clearLocal() async {
    profile = null;
    await _storage.saveToken(null);
    await _storage.write('profile', null);
    // The next person may work under a different Google key.
    await _storage.write('gmaps_session', null);
  }

  Future<Profile> _setProfile(Map<String, dynamic> json) async {
    final parsed = Profile.fromJson(json);
    profile = parsed;
    await _storage.write('profile', jsonEncode(json));
    return parsed;
  }

  Future<Map<String, dynamic>> _deviceMeta() async {
    var name = 'Android device';
    var os = '';
    var appVersion = '';
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      name = '${info.manufacturer} ${info.model}';
      os = 'Android ${info.version.release}';
    } catch (_) {}
    try {
      final pkg = await PackageInfo.fromPlatform();
      appVersion = '${pkg.version}+${pkg.buildNumber}';
    } catch (_) {}
    return {
      'device_uid': await _storage.deviceUid(),
      'device_name': name,
      'os_version': os,
      'app_version': appVersion,
    };
  }
}
