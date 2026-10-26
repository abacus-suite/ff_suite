import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Half-filled forms kept on the phone, so going back or minimising never loses what was typed.
///
/// One small JSON file holds every draft by name. Dates and photos are turned into plain text on
/// the way in and back on the way out; a draft that cannot be read is simply treated as absent.
class DraftStore {
  DraftStore._();

  static Map<String, dynamic>? _all;

  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/drafts.json');
  }

  static Future<Map<String, dynamic>> _load() async {
    final cached = _all;
    if (cached != null) return cached;
    try {
      final file = await _file();
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map<String, dynamic>) return _all = decoded;
      }
    } catch (_) {
      // Unreadable: start clean.
    }
    return _all = <String, dynamic>{};
  }

  static Future<void> _flush() async {
    try {
      final file = await _file();
      await file.writeAsString(jsonEncode(_all ?? const {}), flush: true);
    } catch (_) {
      // A draft that cannot be written is lost, never an error on screen.
    }
  }

  static Future<Map<String, dynamic>?> read(String key) async {
    final all = await _load();
    final value = all[key];
    if (value == null) return null;
    try {
      return unpack(value) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(String key, Map<String, dynamic> data) async {
    final all = await _load();
    all[key] = pack(data);
    await _flush();
  }

  static Future<void> remove(String key) async {
    final all = await _load();
    if (all.remove(key) != null) await _flush();
  }

  /// Anything into something JSON can hold.
  static dynamic pack(dynamic v) {
    if (v == null || v is num || v is bool || v is String) return v;
    if (v is DateTime) return {'__dt': v.toIso8601String()};
    if (v is Uint8List) return {'__b64': base64Encode(v)};
    if (v is Map) return {'__map': [for (final e in v.entries) [pack(e.key), pack(e.value)]]};
    if (v is Iterable) return [for (final e in v) pack(e)];
    return '$v';
  }

  static dynamic unpack(dynamic v) {
    if (v is Map) {
      if (v.containsKey('__dt')) return DateTime.parse('${v['__dt']}');
      if (v.containsKey('__b64')) return base64Decode('${v['__b64']}');
      if (v.containsKey('__map')) {
        return {for (final pair in (v['__map'] as List)) unpack((pair as List)[0]): unpack(pair[1])};
      }
      return {for (final e in v.entries) '${e.key}': unpack(e.value)};
    }
    if (v is List) return [for (final e in v) unpack(e)];
    return v;
  }
}
