import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import 'distributor_submit.dart';

/// The orders raised from demand: one per send, addressed to a distributor.
///
/// This is where the summary is fetched from afterwards - a distributor asks
/// for it again, or the first message never arrived - so every order keeps its
/// share button for as long as it exists.
class DistributorOrdersScreen extends StatefulWidget {
  const DistributorOrdersScreen({super.key});

  @override
  State<DistributorOrdersScreen> createState() => _DistributorOrdersScreenState();
}

class _DistributorOrdersScreenState extends State<DistributorOrdersScreen> {
  List<Map<String, dynamic>> _orders = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = (await Services.api.get('/api/v1/orders', query: {'limit': 200}) as List)
          .cast<Map<String, dynamic>>();
      if (mounted) setState(() => _error = null);
      if (mounted) setState(() => _orders = list);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Distributor Orders')),
      body: _loading && _orders.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _orders.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 80),
                            EmptyView(
                                icon: Icons.local_shipping_outlined,
                                text: 'No orders sent to a distributor yet'),
                          ],
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
                          itemCount: _orders.length,
                          itemBuilder: (_, i) => _card(_orders[i]),
                        ),
                ),
    );
  }

  Widget _card(Map<String, dynamic> o) {
    final date = parseServerTime(o['date']);
    final billed = (o['distributor'] as Map?) ?? (o['client'] as Map?);
    final confirmed = o['state'] == 'sale' || o['state'] == 'done';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(13, 12, 12, 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: (confirmed ? AppColors.success : AppColors.primary).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(Icons.local_shipping_rounded,
                    size: 19, color: confirmed ? AppColors.success : AppColors.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${o['name']}',
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                    Text('${billed?['name'] ?? ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
                  ],
                ),
              ),
              StatusBadge('${o['state']}', label: '${o['state_label'] ?? o['state']}'),
            ],
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              _meta(Icons.calendar_today_rounded, date == null ? '' : fmtDate(date)),
              const SizedBox(width: 14),
              _meta(Icons.inventory_2_rounded, '${o['line_count']} products'),
              const SizedBox(width: 14),
              _meta(Icons.payments_rounded,
                  fmtMoney(o['amount_total'] as num?, o['currency'] as String?)),
            ],
          ),
          const Divider(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => shareOrderSummary(context, o['id'] as int, '${o['name']}'),
                  icon: const Icon(Icons.ios_share_rounded, size: 17),
                  label: const Text('Share summary'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _meta(IconData icon, String text) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.muted),
          const SizedBox(width: 5),
          Text(text, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
        ],
      );
}
