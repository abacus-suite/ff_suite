import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../core/services.dart';
import '../core/theme.dart';

/// The pictures uploaded with a request, for the person who decides on it: small thumbnails that open full screen.
/// Nothing is drawn when the request has none (or the server does not send documents yet).
class DocumentGallery extends StatefulWidget {
  const DocumentGallery({super.key, required this.model, required this.id});

  /// The Odoo model of the request, for example 'ff.expense.claim'.
  final String model;
  final int id;

  @override
  State<DocumentGallery> createState() => _DocumentGalleryState();
}

class _DocumentGalleryState extends State<DocumentGallery> {
  List<Map<String, dynamic>> _files = [];
  final Map<int, Future<Uint8List?>> _bytes = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await Services.api.get('/api/v1/documents', query: {'model': widget.model, 'id': widget.id});
      if (mounted) setState(() => _files = ((data as List?) ?? []).cast<Map<String, dynamic>>());
    } catch (_) {
      // An older server or no access: no documents are shown.
    }
  }

  Future<Uint8List?> _fetch(int id) => _bytes.putIfAbsent(id, () async {
        try {
          final response = await http.get(Uri.parse(await Services.api.url('/api/v1/documents/$id/file')),
              headers: await Services.api.authHeaders());
          return response.statusCode == 200 ? response.bodyBytes : null;
        } catch (_) {
          return null;
        }
      });

  void _open(int id, String name) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
            backgroundColor: Colors.black, foregroundColor: Colors.white, title: Text(name, style: const TextStyle(fontSize: 14))),
        body: FutureBuilder<Uint8List?>(
          future: _fetch(id),
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
            final bytes = snap.data;
            if (bytes == null) return const Center(child: Text('Could not open it', style: TextStyle(color: Colors.white)));
            return InteractiveViewer(maxScale: 6, child: Center(child: Image.memory(bytes)));
          },
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_files.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: const Color(0xFF1B3A7A).withValues(alpha: 0.07), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Documents (${_files.length})',
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Color(0xFF0F172A))),
        const SizedBox(height: 10),
        Wrap(spacing: 10, runSpacing: 10, children: [
          for (final f in _files)
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: f['image'] == true ? () => _open(f['id'] as int, '${f['name']}') : null,
              child: Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                clipBehavior: Clip.antiAlias,
                child: f['image'] == true
                    ? FutureBuilder<Uint8List?>(
                        future: _fetch(f['id'] as int),
                        builder: (context, snap) {
                          if (snap.connectionState != ConnectionState.done) {
                            return const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)));
                          }
                          final bytes = snap.data;
                          return bytes == null
                              ? const Icon(Icons.broken_image_rounded, color: AppColors.muted)
                              : Image.memory(bytes, fit: BoxFit.cover);
                        },
                      )
                    : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const Icon(Icons.description_rounded, color: AppColors.primary),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text('${f['name']}',
                              maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10)),
                        ),
                      ]),
              ),
            ),
        ]),
      ]),
    );
  }
}
