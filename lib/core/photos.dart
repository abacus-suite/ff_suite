import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import 'geo_camera.dart';
import 'geo.dart';
import 'services.dart';
import 'tile_cache.dart';

/// Every photo the app sends goes through here, so they all stay small enough
/// for a weak network (and for the offline queue on the phone): about
/// 1024 px on the long side at JPEG quality 55 - usually 80-200 KB, still
/// sharp enough to read a label, a receipt or an expiry date.
const _maxSide = 1024.0;
const _quality = 55;

/// Selfies only need a face: smaller again.
const _selfieSide = 640.0;

/// Where and when a photo was taken, ready to be written on it.
class PhotoPlace {
  const PhotoPlace({this.latitude, this.longitude, this.accuracy, this.address = '', required this.at});

  final double? latitude;
  final double? longitude;
  final double? accuracy;
  final String address;
  final DateTime at;

  bool get located => latitude != null && longitude != null;

  String get coordinates => located
      ? 'Lat ${latitude!.toStringAsFixed(6)}   Long ${longitude!.toStringAsFixed(6)}'
      : 'Location not available';

  String get stampedAt {
    final t = at;
    String two(int v) => v.toString().padLeft(2, '0');
    final offset = t.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final zone = 'GMT $sign${two(offset.inHours.abs())}:${two(offset.inMinutes.abs() % 60)}';
    final hour12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
    return '${two(t.day)}/${two(t.month)}/${t.year % 100} '
        '${two(hour12)}:${two(t.minute)} ${t.hour < 12 ? 'AM' : 'PM'} $zone';
  }
}

/// The place of the last stamp, reused for a couple of minutes so a burst of
/// photos does not ask the GPS and the server again for every shot.
PhotoPlace? _recent;
DateTime? _recentAt;

Future<PhotoPlace> currentPlace({bool fresh = false}) async {
  final cached = _recent;
  final cachedAt = _recentAt;
  if (!fresh && cached != null && cachedAt != null && DateTime.now().difference(cachedAt).inMinutes < 2) {
    return PhotoPlace(
      latitude: cached.latitude,
      longitude: cached.longitude,
      accuracy: cached.accuracy,
      address: cached.address,
      at: DateTime.now(),
    );
  }
  double? lat, lng, accuracy;
  try {
    final pos = await currentPosition(recentOk: true);
    lat = pos.latitude;
    lng = pos.longitude;
    accuracy = pos.accuracy;
  } catch (_) {
    // No permission, no fix, or a fake-GPS warning: the photo is stamped with the time alone.
  }
  var address = '';
  if (lat != null) {
    try {
      final res = await Services.api.get('/api/v1/geo/address', query: {'lat': lat, 'lng': lng});
      if (res is Map) address = '${res['address'] ?? ''}';
    } catch (_) {
      // Offline or the lookup is unavailable: coordinates alone still prove the place.
    }
  }
  final place = PhotoPlace(latitude: lat, longitude: lng, accuracy: accuracy, address: address, at: DateTime.now());
  _recent = place;
  _recentAt = DateTime.now();
  return place;
}

/// Takes the photo and writes where and when it was taken across the bottom.
///
/// The stamp is burnt into the picture, so the proof travels with the photo
/// wherever it is opened later - Odoo, a download or a forwarded message.
/// [stamp] is off for pictures that are not evidence, such as a profile photo.
Future<Uint8List?> takePhoto(ImageSource source, {bool selfie = false, bool stamp = true}) async {
  // Photos meant as evidence are taken in the app's own camera, which shows the
  // place and time on the viewfinder before the shot. Pictures chosen from the
  // gallery, and photos that carry no stamp, still use the phone's picker.
  if (stamp && source == ImageSource.camera) {
    try {
      final shot = await openGeoCamera(selfie: selfie);
      if (shot != null) return shot;
    } catch (_) {
      // The phone's camera would not open through the app: fall back to its own
      // camera below, and the place and time are still written on the picture.
    }
  }
  final image = await ImagePicker().pickImage(
    source: source,
    maxWidth: selfie ? _selfieSide : _maxSide,
    maxHeight: selfie ? _selfieSide : _maxSide,
    imageQuality: _quality,
    preferredCameraDevice: selfie ? CameraDevice.front : CameraDevice.rear,
    requestFullMetadata: false,
  );
  final bytes = await image?.readAsBytes();
  if (bytes == null || !stamp) return bytes;
  return stampPhoto(bytes);
}

/// Writes the place, the coordinates and the time across the foot of a photo,
/// with a small map of the spot beside them.
///
/// Returns the picture untouched if anything goes wrong - a photo without a
/// stamp is better than no photo at all.
Future<Uint8List> stampPhoto(Uint8List bytes, {PhotoPlace? place}) async {
  final where = place ?? await currentPlace();
  final map = where.located ? await _mapThumb(where.latitude!, where.longitude!) : null;
  try {
    final picture = img.decodeImage(bytes);
    if (picture == null) return bytes;
    final wide = picture.width >= 700;
    final font = wide ? img.arial24 : img.arial14;
    final line = font.lineHeight;
    final pad = (picture.width * 0.018).round().clamp(5, 16);
    final lines = <String>[
      if (where.address.isNotEmpty) where.address,
      where.coordinates,
      where.stampedAt,
    ];
    final panel = line * lines.length + pad * 2;
    final top = math.max(picture.height - panel, 0);
    img.fillRect(picture, x1: 0, y1: top, x2: picture.width, y2: picture.height,
        color: img.ColorRgba8(0, 0, 0, 150));
    var textLeft = pad;
    if (map != null) {
      final side = math.min(panel - pad, (picture.width * 0.28).round());
      if (side > 24) {
        final thumb = img.copyResize(map, width: side, height: side);
        img.compositeImage(picture, thumb, dstX: pad, dstY: top + (panel - side) ~/ 2);
        textLeft = pad * 2 + side;
      }
    }
    for (final (i, text) in lines.indexed) {
      img.drawString(picture, text,
          font: font, x: textLeft, y: top + pad + line * i, color: img.ColorRgb8(255, 255, 255));
    }
    return Uint8List.fromList(img.encodeJpg(picture, quality: _quality));
  } catch (_) {
    return bytes;
  }
}

/// One free map tile around the point, for the corner of the stamp.
Future<img.Image?> _mapThumb(double lat, double lng) async {
  try {
    const zoom = 15;
    final n = 1 << zoom;
    final x = ((lng + 180.0) / 360.0 * n).floor();
    final latRad = lat * math.pi / 180.0;
    final y = ((1 - (math.log(math.tan(latRad) + 1 / math.cos(latRad)) / math.pi)) / 2 * n).floor();
    final bytes = await TileCache.get(
      'https://a.basemaps.cartocdn.com/rastertiles/voyager/$zoom/$x/$y.png',
      paid: false,
    );
    return img.decodeImage(bytes);
  } catch (_) {
    return null; // The stamp still carries the address, the coordinates and the time.
  }
}
