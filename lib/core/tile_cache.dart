import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:path_provider/path_provider.dart';

import 'map_usage.dart';

/// Map tiles kept on the phone, so an area already seen is not downloaded (or
/// paid for) again. Field staff cover the same streets every day, which makes
/// this the biggest saving on Google's tile bill.
class TileCache {
  static const keepFor = Duration(days: 14);
  static const _maxFiles = 6000;

  static Directory? _dir;
  static Future<Directory>? _opening;
  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 20),
    responseType: ResponseType.bytes,
    headers: {'User-Agent': 'com.abs.fieldforce'},
  ));

  static Future<Directory> _folder() async {
    if (_dir != null) return _dir!;
    return _opening ??= () async {
      final base = await getApplicationSupportDirectory();
      final dir = Directory('${base.path}/map_tiles');
      await dir.create(recursive: true);
      _dir = dir;
      _prune(dir);
      return dir;
    }();
  }

  /// The file name for a tile: its address without the key or session, which change.
  static String _name(String url) {
    final uri = Uri.parse(url);
    return '${uri.host}${uri.path}'.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_');
  }

  /// The tile's bytes, from the phone when fresh, otherwise from the network.
  /// [paid] tiles are counted for the Maps cost page when they are downloaded.
  static Future<Uint8List> get(String url, {required bool paid}) async {
    final dir = await _folder();
    final file = File('${dir.path}/${_name(url)}');
    try {
      if (await file.exists()) {
        final age = DateTime.now().difference(await file.lastModified());
        if (age < keepFor) return await file.readAsBytes();
      }
    } catch (_) {
      // Unreadable file: download it again below.
    }
    final res = await _dio.get<List<int>>(url);
    final bytes = Uint8List.fromList(res.data ?? const []);
    if (paid) MapUsage.tile();
    if (bytes.isNotEmpty) {
      file.writeAsBytes(bytes, flush: false).ignore();
    }
    return bytes;
  }

  /// Drop old tiles, and the oldest ones when the folder grows too big.
  static Future<void> _prune(Directory dir) async {
    try {
      final files = <File, DateTime>{};
      await for (final entry in dir.list()) {
        if (entry is File) files[entry] = await entry.lastModified();
      }
      final now = DateTime.now();
      final sorted = files.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
      var left = sorted.length;
      for (final e in sorted) {
        if (now.difference(e.value) > keepFor || left > _maxFiles) {
          await e.key.delete().catchError((_) => e.key);
          left--;
        }
      }
    } catch (_) {
      // Housekeeping only.
    }
  }

  /// Forget every stored tile, for example after changing the map provider.
  static Future<void> clear() async {
    final dir = await _folder();
    try {
      await for (final entry in dir.list()) {
        if (entry is File) await entry.delete();
      }
    } catch (_) {}
  }
}

/// Serves tiles through [TileCache]; [paid] marks Google tiles for counting.
class CachedTileProvider extends TileProvider {
  CachedTileProvider({this.paid = false});

  final bool paid;

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      _CachedTileImage(getTileUrl(coordinates, options), paid);
}

class _CachedTileImage extends ImageProvider<_CachedTileImage> {
  const _CachedTileImage(this.url, this.paid);

  final String url;
  final bool paid;

  @override
  Future<_CachedTileImage> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(_CachedTileImage key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(codec: _load(decode), scale: 1);

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final bytes = await TileCache.get(url, paid: paid);
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  @override
  bool operator ==(Object other) => other is _CachedTileImage && other.url == url;

  @override
  int get hashCode => url.hashCode;
}
