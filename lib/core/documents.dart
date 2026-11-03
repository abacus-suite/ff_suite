import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// A document chosen from the phone (a PDF, Word or Excel file, or any picture), with its name and type, so it can be
/// sent with a request like a photo.
class PickedDoc {
  const PickedDoc({required this.bytes, required this.name, required this.mime});

  final Uint8List bytes;
  final String name;
  final String mime;

  bool get isImage => mime.startsWith('image/');

  /// "data:application/pdf;name=invoice.pdf;base64,...": the way the server learns the name and the type.
  String get dataUrl => 'data:$mime;name=${Uri.encodeComponent(name)};base64,${base64Encode(bytes)}';
}

const _mimes = {
  'pdf': 'application/pdf',
  'doc': 'application/msword',
  'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'xls': 'application/vnd.ms-excel',
  'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'csv': 'text/csv',
  'txt': 'text/plain',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
};

String mimeOfName(String name) => _mimes[name.split('.').last.toLowerCase()] ?? 'application/octet-stream';

/// The phone's file chooser: a PDF, a Word or Excel file, or a picture. Null when nothing was chosen or the file is
/// over 10 MB.
Future<PickedDoc?> pickDocument() async {
  final picked = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'csv', 'txt', 'jpg', 'jpeg', 'png'],
  );
  final file = picked.firstOrNull;
  if (file == null) return null;
  final bytes = await file.readAsBytes();
  if (bytes.length > 10 * 1024 * 1024) return null;
  return PickedDoc(bytes: bytes, name: file.name, mime: mimeOfName(file.name));
}

/// Hands a downloaded file to the phone's share sheet, where it can be saved to the device or sent on.
Future<void> shareFile(Uint8List bytes, String name, String mime) async {
  final dir = await getTemporaryDirectory();
  final safe = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  final file = File('${dir.path}/$safe');
  await file.writeAsBytes(bytes);
  await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: mime)], subject: name));
}
