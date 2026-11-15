import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/pdf_preview_screen.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

/// The documents of one finished task (credit notes, demands, orders). Tapping one opens its preview, where it can be
/// downloaded or shared.
class TaskDocsScreen extends StatefulWidget {
  const TaskDocsScreen({super.key, required this.taskId, required this.title, this.onOpenCustomer});

  final int taskId;
  final String title;
  final VoidCallback? onOpenCustomer;

  @override
  State<TaskDocsScreen> createState() => _TaskDocsScreenState();
}

class _TaskDocsScreenState extends State<TaskDocsScreen> {
  List<Map<String, dynamic>>? _docs;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await Services.api.get('/api/v1/field-tasks/${widget.taskId}/docs') as Map<String, dynamic>;
      if (mounted) setState(() => _docs = ((d['docs'] as List?) ?? const []).cast<Map<String, dynamic>>());
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  IconData _icon(String? kind) => switch (kind) {
        'credit_note' || 'debit_note' => Icons.receipt_long_rounded,
        'order' => Icons.shopping_cart_rounded,
        _ => Icons.inventory_2_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final docs = _docs;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title), actions: [
        if (widget.onOpenCustomer != null)
          IconButton(tooltip: 'Open customer', icon: const Icon(Icons.storefront_rounded), onPressed: widget.onOpenCustomer),
      ]),
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
          : docs == null
              ? const Center(child: CircularProgressIndicator())
              : docs.isEmpty
                  ? const EmptyView(icon: Icons.description_outlined, text: 'No documents for this task.')
                  : ListView(padding: const EdgeInsets.all(16), children: [
                      const Text('Documents', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                      const SizedBox(height: 4),
                      const Text('Tap one to preview, download or share it.',
                          style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
                      const SizedBox(height: 10),
                      for (final d in docs)
                        Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                              child: Icon(_icon(asText(d['kind'])), color: AppColors.primary),
                            ),
                            title: Text('${d['title']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                            subtitle: asText(d['subtitle']) == null ? null : Text('${d['subtitle']}'),
                            trailing: const Icon(Icons.picture_as_pdf_rounded, color: AppColors.primary),
                            onTap: () => openPdfPreview(
                              context,
                              title: '${d['title']}',
                              endpoint: '${d['endpoint']}',
                              filename: '${d['filename']}',
                            ),
                          ),
                        ),
                    ]),
    );
  }
}
