import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'format.dart';
import 'services.dart';
import 'theme.dart';

/// Opens an in-app PDF preview screen that displays the document using the platform's
/// native PDF viewer. The user can view/zoom/read the PDF and optionally download
/// or share it directly from the preview screen.
Future<void> openPdfPreview(
  BuildContext context, {
  required String title,
  required String endpoint,
  required String filename,
}) async {
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => PdfPreviewScreen(
        title: title,
        endpoint: endpoint,
        filename: filename,
      ),
    ),
  );
}

class PdfPreviewScreen extends StatefulWidget {
  final String title;
  final String endpoint;
  final String filename;

  const PdfPreviewScreen({
    super.key,
    required this.title,
    required this.endpoint,
    required this.filename,
  });

  @override
  State<PdfPreviewScreen> createState() => _PdfPreviewScreenState();
}

class _PdfPreviewScreenState extends State<PdfPreviewScreen> {
  bool _loading = true;
  String? _error;
  File? _file;
  Uint8List? _bytes;
  int _totalPages = 0;
  int _currentPage = 0;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadPdf();
  }

  String get _normalizedFilename {
    final safeName = widget.filename
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), '_');
    return safeName.endsWith('.pdf') ? safeName : '$safeName.pdf';
  }

  Future<void> _loadPdf() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final name = _normalizedFilename;
      final url = await Services.api.url(widget.endpoint);
      final headers = await Services.api.authHeaders();
      final response = await http.get(Uri.parse(url), headers: headers);

      if (response.statusCode != 200) {
        throw Exception('Server returned status ${response.statusCode}');
      }

      final bytes = response.bodyBytes;
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/$name');
      await tempFile.writeAsBytes(bytes, flush: true);

      if (mounted) {
        setState(() {
          _bytes = bytes;
          _file = tempFile;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _saveToDownloads() async {
    if (_bytes == null || _file == null) return;
    setState(() => _saving = true);

    final name = _normalizedFilename;

    try {
      if (Platform.isAndroid) {
        // 1. Android MediaStore insertion (official Android way)
        try {
          await const MethodChannel('ff/whatsapp').invokeMethod<bool>('saveToDownloads', {
            'name': name,
            'bytes': _bytes,
          });
        } catch (_) {}

        // 2. Direct write to public Download directory
        try {
          final publicDownload = Directory('/storage/emulated/0/Download');
          if (await publicDownload.exists()) {
            final file = File('${publicDownload.path}/$name');
            await file.writeAsBytes(_bytes!);
          }
        } catch (_) {}
      }

      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
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
                    'Saved $name to Downloads',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            action: SnackBarAction(
              label: 'Share',
              textColor: AppColors.primary,
              onPressed: _share,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        showProblem(context, 'Failed to save PDF: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  void _share() {
    if (_file == null) return;
    final name = _normalizedFilename;
    SharePlus.instance.share(
      ShareParams(
        files: [XFile(_file!.path, mimeType: 'application/pdf')],
        subject: name,
        text: name,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              overflow: TextOverflow.ellipsis,
            ),
            if (_totalPages > 0)
              Text(
                'Page ${_currentPage + 1} of $_totalPages',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal, color: AppColors.muted),
              ),
          ],
        ),
        actions: [
          if (_file != null) ...[
            IconButton(
              icon: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                    )
                  : const Icon(Icons.download_rounded),
              tooltip: 'Download to phone',
              onPressed: _saving ? null : _saveToDownloads,
            ),
            IconButton(
              icon: const Icon(Icons.share_rounded),
              tooltip: 'Share PDF',
              onPressed: _share,
            ),
          ],
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Loading PDF preview…',
              style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.muted),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 48),
              const SizedBox(height: 12),
              const Text(
                'Could not load PDF',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted, fontSize: 13),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _loadPdf,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_file == null) {
      return const Center(child: Text('No document available'));
    }

    return PDFView(
      filePath: _file!.path,
      enableSwipe: true,
      swipeHorizontal: false,
      autoSpacing: true,
      pageFling: true,
      pageSnap: true,
      fitPolicy: FitPolicy.WIDTH,
      backgroundColor: Colors.grey.shade200,
      onRender: (pages) {
        if (mounted) {
          setState(() {
            _totalPages = pages ?? 0;
          });
        }
      },
      onPageChanged: (page, total) {
        if (mounted) {
          setState(() {
            _currentPage = page ?? 0;
            _totalPages = total ?? _totalPages;
          });
        }
      },
      onError: (err) {
        if (mounted) {
          setState(() {
            _error = err.toString();
          });
        }
      },
    );
  }
}
