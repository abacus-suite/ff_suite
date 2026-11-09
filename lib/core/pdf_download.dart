import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'format.dart';
import 'services.dart';
import 'theme.dart';

/// Downloads a PDF from an authenticated backend API endpoint and registers it
/// directly into the device's public Downloads directory via Android MediaStore,
/// so it immediately appears in the phone's native Downloads & Files apps.
Future<File?> downloadAndSavePdf(
  BuildContext context, {
  required String endpoint,
  required String filename,
}) async {
  final safeName = filename
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
      .replaceAll(RegExp(r'\s+'), '_');
  final normalizedName = safeName.endsWith('.pdf') ? safeName : '$safeName.pdf';

  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      duration: const Duration(seconds: 40),
      content: Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text('Downloading $normalizedName…')),
        ],
      ),
    ),
  );

  try {
    final url = await Services.api.url(endpoint);
    final headers = await Services.api.authHeaders();
    final response = await http.get(Uri.parse(url), headers: headers);

    if (response.statusCode != 200) {
      throw Exception('Server returned ${response.statusCode}');
    }

    final bytes = response.bodyBytes;

    // 1. Android MediaStore insertion (official Android way to register in system Downloads)
    if (Platform.isAndroid) {
      try {
        await const MethodChannel('ff/whatsapp').invokeMethod<bool>('saveToDownloads', {
          'name': normalizedName,
          'bytes': bytes,
        });
      } catch (_) {
        // Fallback to POSIX write below
      }
    }

    // 2. Direct write to public Download directory (for older Android / direct file explorers)
    if (Platform.isAndroid) {
      try {
        final publicDownload = Directory('/storage/emulated/0/Download');
        if (await publicDownload.exists()) {
          final file = File('${publicDownload.path}/$normalizedName');
          await file.writeAsBytes(bytes);
        }
      } catch (_) {}
    }

    // 3. Cache in temp directory for SharePlus
    final tempDir = await getTemporaryDirectory();
    final tempFile = File('${tempDir.path}/$normalizedName');
    await tempFile.writeAsBytes(bytes);

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 6),
        behavior: SnackBarBehavior.floating,
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.greenAccent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Saved $normalizedName to Downloads',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        action: SnackBarAction(
          label: 'Share',
          textColor: AppColors.primary,
          onPressed: () {
            SharePlus.instance.share(
              ShareParams(
                files: [XFile(tempFile.path, mimeType: 'application/pdf')],
                subject: normalizedName,
                text: normalizedName,
              ),
            );
          },
        ),
      ),
    );
    return tempFile;
  } catch (e) {
    messenger.hideCurrentSnackBar();
    if (context.mounted) {
      showProblem(context, 'PDF download failed: $e');
    }
    return null;
  }
}
