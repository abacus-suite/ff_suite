import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';

import '../../core/format.dart';
import '../../core/geo.dart';
import '../../core/services.dart';

class OrderReviewScreen extends StatefulWidget {
  const OrderReviewScreen({super.key, required this.client, required this.lines});

  final Map<String, dynamic> client;
  final List<Map<String, dynamic>> lines;

  @override
  State<OrderReviewScreen> createState() => _OrderReviewScreenState();
}

class _OrderReviewScreenState extends State<OrderReviewScreen> {
  bool get demandFlow => Services.auth.profile?.isDemandFlow ?? false;

  final _note = TextEditingController();
  // One id per review screen: retrying after a network error cannot create a duplicate order.
  final String _uuid = const Uuid().v4();
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  double get _total => widget.lines
      .fold(0.0, (sum, l) => sum + ((l['price'] as num?) ?? 0) * ((l['qty'] as num?) ?? 0));

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      Position? pos;
      try {
        pos = await currentPosition();
      } catch (_) {
        // Orders are accepted without a fresh GPS fix.
      }
      final order = await Services.api.post('/api/v1/orders', {
        'partner_id': widget.client['id'],
        'lines': [
          for (final l in widget.lines) {'product_id': l['id'], 'qty': l['qty']},
        ],
        'note': _note.text.trim(),
        'lat': pos?.latitude,
        'lng': pos?.longitude,
        'uuid': _uuid,
      }) as Map<String, dynamic>;
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.check_circle, color: Colors.green, size: 48),
          title: Text(demandFlow
              ? 'Demand ${order['name']} recorded'
              : 'Order ${order['name']} placed'),
          content: Text(demandFlow
              ? '${fmtMoney(order['amount_total'] as num?, order['currency'] as String?)} at PTR. '
                  'The office will send it to the distributor.'
              : 'Total ${fmtMoney(order['amount_total'] as num?, order['currency'] as String?)} incl. tax'),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(demandFlow ? 'Review Demand' : 'Review Order')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.store),
            title: Text(widget.client['name'] as String, style: theme.textTheme.titleMedium),
          ),
          const Divider(),
          for (final l in widget.lines)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l['name'] as String),
              subtitle: Text('${fmtQty(l['qty'] as num)} × ${fmtMoney(l['price'] as num?)}'),
              trailing: Text(fmtMoney(((l['price'] as num?) ?? 0) * (l['qty'] as num))),
            ),
          const Divider(),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(demandFlow ? 'Value at PTR' : 'Estimated total'),
            trailing: Text(fmtMoney(_total), style: theme.textTheme.titleMedium),
          ),
          Text("Taxes and the client's price list are applied by the server.", style: theme.textTheme.bodySmall),
          const SizedBox(height: 16),
          TextField(
            controller: _note,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Note for the office (optional)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy ? null : _submit,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send),
            label: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(demandFlow ? 'Record demand' : 'Place order'),
            ),
          ),
        ],
      ),
    );
  }
}
