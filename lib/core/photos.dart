import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

/// Every photo the app sends goes through here, so they all stay small enough
/// for a weak network (and for the offline queue on the phone): about
/// 1024 px on the long side at JPEG quality 55 - usually 80-200 KB, still
/// sharp enough to read a label, a receipt or an expiry date.
const _maxSide = 1024.0;
const _quality = 55;

/// Selfies only need a face: smaller again.
const _selfieSide = 640.0;

Future<Uint8List?> takePhoto(ImageSource source, {bool selfie = false}) async {
  final image = await ImagePicker().pickImage(
    source: source,
    maxWidth: selfie ? _selfieSide : _maxSide,
    maxHeight: selfie ? _selfieSide : _maxSide,
    imageQuality: _quality,
    preferredCameraDevice: selfie ? CameraDevice.front : CameraDevice.rear,
    requestFullMetadata: false,
  );
  return image?.readAsBytes();
}
