import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import 'geo.dart';

/// Every photo the app sends goes through here, so they all stay small enough
/// for a weak network (and for the offline queue on the phone): about
/// 1024 px on the long side at JPEG quality 55 - usually 80-200 KB, still
/// sharp enough to read a label, a receipt or an expiry date.
const _maxSide = 1024.0;
const _quality = 55;

/// Selfies only need a face: smaller again.
const _selfieSide = 640.0;

/// Takes the photo and writes where and when it was taken across the bottom.
///
/// The stamp is burnt into the picture, so the proof travels with the photo
/// wherever it is opened later - Odoo, a download or a forwarded message.
/// [stamp] is off for pictures that are not evidence, such as a profile photo.
Future<Uint8List?> takePhoto(ImageSource source, {bool selfie = false, bool stamp = true}) async {
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

/// Adds the time and the GPS position to the foot of a picture.
/// Returns the picture untouched if anything goes wrong - a photo without a
/// stamp is better than no photo at all.
Future<Uint8List> stampPhoto(Uint8List bytes) async {
  String where = 'Location not available';
  try {
    final pos = await currentPosition(recentOk: true);
    where = '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}'
        '  ±${pos.accuracy.round()} m';
  } catch (_) {
    // No permission, no fix, or a fake-GPS warning: stamp the time alone.
  }
  try {
    final picture = img.decodeImage(bytes);
    if (picture == null) return bytes;
    final now = DateTime.now();
    final when = '${now.day.toString().padLeft(2, '0')}-${now.month.toString().padLeft(2, '0')}-${now.year} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final big = picture.width >= 900;
    final font = big ? img.arial24 : img.arial14;
    final line = font.lineHeight;
    final pad = (picture.width * 0.02).round().clamp(6, 20);
    final height = line * 2 + pad * 2;
    final top = picture.height - height;
    img.fillRect(
      picture,
      x1: 0,
      y1: top,
      x2: picture.width,
      y2: picture.height,
      color: img.ColorRgba8(0, 0, 0, 140),
    );
    img.drawString(picture, when, font: font, x: pad, y: top + pad, color: img.ColorRgb8(255, 255, 255));
    img.drawString(picture, where, font: font, x: pad, y: top + pad + line,
        color: img.ColorRgb8(255, 255, 255));
    return Uint8List.fromList(img.encodeJpg(picture, quality: _quality));
  } catch (_) {
    return bytes;
  }
}
