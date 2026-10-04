import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

/// Picks who will supply a pile of demands.
///
/// The distributor is asked for once, at the moment of sending: the field
/// collects demand shop by shop without knowing yet which warehouse will fill
/// it, and the same demands may well be split differently next week.
Future<Map<String, dynamic>?> pickDistributor(BuildContext context, {required int demandCount}) async {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheet) => _DistributorSheet(demandCount: demandCount),
  );
}

class _DistributorSheet extends StatefulWidget {
  const _DistributorSheet({required this.demandCount});

  final int demandCount;

  @override
  State<_DistributorSheet> createState() => _DistributorSheetState();
}

class _DistributorSheetState extends State<_DistributorSheet> {
  List<Map<String, dynamic>> _all = [];
  String _query = '';
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = (await Services.api.get('/api/v1/distributors') as List).cast<Map<String, dynamic>>();
      if (mounted) setState(() => _all = list);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final shown = q.isEmpty
        ? _all
        : _all.where((d) => '${d['name']} ${d['city'] ?? ''}'.toLowerCase().contains(q)).toList();
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.8,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Send to distributor',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                  Text(
                      '${widget.demandCount} ${widget.demandCount == 1 ? 'demand' : 'demands'} '
                      'become one order for whoever supplies them.',
                      style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
                  const SizedBox(height: 10),
                  TextField(
                    onChanged: (value) => setState(() => _query = value),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search_rounded),
                      hintText: 'Search distributor or city',
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ),
            if (_loading) const LinearProgressIndicator(),
            Expanded(
              child: _error != null
                  ? ErrorView(message: _error!, onRetry: _load)
                  : shown.isEmpty && !_loading
                      ? const EmptyView(icon: Icons.local_shipping_outlined, text: 'No distributors')
                      : ListView.builder(
                          itemCount: shown.length,
                          itemBuilder: (_, i) {
                            final d = shown[i];
                            return ListTile(
                              leading: const CircleAvatar(
                                backgroundColor: Color(0xFFE8EFFF),
                                child: Icon(Icons.local_shipping_rounded, color: AppColors.primary),
                              ),
                              title: Text('${d['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                              subtitle: Text([
                                if (d['city'] != null) '${d['city']}',
                                if (d['gst'] != null) 'GST ${d['gst']}',
                              ].join(' · ')),
                              trailing: const Icon(Icons.chevron_right_rounded),
                              onTap: () => Navigator.pop(context, d),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fetches the outlet summary PDF and hands it to the phone's share sheet.
///
/// The share sheet is what puts it into WhatsApp: the distributor is messaged
/// the same file the office would print, and nothing has to be typed out again.
Future<void> shareOrderSummary(BuildContext context, int orderId, String orderName) async {
  showSnack(context, 'Preparing the summary…');
  try {
    final url = await Services.api.url('/api/v1/orders/$orderId/summary.pdf');
    final headers = await Services.api.authHeaders();
    final response = await http.get(Uri.parse(url), headers: headers);
    if (response.statusCode != 200) {
      throw Exception('The summary could not be prepared (${response.statusCode}).');
    }
    final dir = await getTemporaryDirectory();
    final safe = orderName.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final file = File('${dir.path}/Order_Summary_$safe.pdf');
    await file.writeAsBytes(response.bodyBytes);
    if (!context.mounted) return;
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'application/pdf')],
      subject: 'Order summary $orderName',
      text: 'Order summary $orderName',
    ));
  } catch (e) {
    if (context.mounted) showProblem(context, e.toString());
  }
}

/// Shown once the demands have become an order: what it is, and how to send it on.
Future<void> showSubmittedSheet(BuildContext context, Map<String, dynamic> result) {
  final order = result['order'] as Map<String, dynamic>;
  final distributor = result['distributor'] as Map?;
  final count = ((result['demands'] as List?) ?? []).length;
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: const Icon(Icons.check_rounded, color: AppColors.success, size: 30),
          ),
          const SizedBox(height: 12),
          Text('${order['name']} created',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          const SizedBox(height: 4),
          Text(
            '$count ${count == 1 ? 'demand' : 'demands'} sent to ${distributor?['name'] ?? 'the distributor'}.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: AppColors.muted),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: GradientButton(
              label: 'Share the summary',
              icon: Icons.ios_share_rounded,
              onPressed: () => shareOrderSummary(sheet, order['id'] as int, '${order['name']}'),
            ),
          ),
          if (order['portal_link'] != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: '${order['portal_link']}'));
                  if (sheet.mounted) showSnack(sheet, 'Link copied - the distributor confirms it there');
                },
                icon: const Icon(Icons.link_rounded, size: 18),
                label: const Text('Copy the distributor link'),
              ),
            ),
          ],
          const SizedBox(height: 8),
          TextButton(onPressed: () => Navigator.pop(sheet), child: const Text('Later')),
        ],
      ),
    ),
  );
}
