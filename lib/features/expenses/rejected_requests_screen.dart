import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../allowance/allowance_screen.dart';
import 'expense_form_screen.dart';
import 'expenses_screen.dart';
import 'payment_request_screens.dart';

/// Everything that was rejected, from every expense category, in one list: why, how much, and where it came from.
class RejectedRequestsScreen extends StatefulWidget {
  const RejectedRequestsScreen({super.key, required this.month});

  final DateTime month;

  @override
  State<RejectedRequestsScreen> createState() => _RejectedRequestsScreenState();
}

class _RejectedRequestsScreenState extends State<RejectedRequestsScreen> {
  List<_Rejected>? _rows;

  String get _key => '${widget.month.year}-${widget.month.month.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<dynamic> _maybe(Future<dynamic> call) async {
    try {
      return await call;
    } catch (_) {
      return null; // the module behind it may not be installed
    }
  }

  Future<void> _load() async {
    final results = await Future.wait<dynamic>([
      _maybe(Services.api.get('/api/v1/expenses', query: {'month': _key, 'kind': 'claim'})),
      _maybe(Services.api.get('/api/v1/expenses', query: {'month': _key, 'kind': 'card'})),
      _maybe(Services.api.get('/api/v1/allowances', query: {'month': _key})),
      _maybe(Services.api.get('/api/v1/expense-requests')),
    ]);
    final rows = <_Rejected>[];

    List<Map<String, dynamic>> list(dynamic data, String key) =>
        ((data is Map ? data[key] : null) as List? ?? const []).cast<Map<String, dynamic>>();

    for (final (i, kind) in const [(0, 'claim'), (1, 'card')]) {
      for (final c in list(results[i], 'claims')) {
        if (c['state'] != 'rejected') continue;
        final cat = '${(c['category'] as Map?)?['name'] ?? 'Expense'}';
        final sub = (c['sub_category'] as Map?)?['name'];
        rows.add(_Rejected(
          source: kind == 'card' ? 'Expense Submission' : 'Expense Claiming',
          title: sub == null ? cat : '$cat · $sub',
          date: '${c['date'] ?? ''}',
          amount: c['amount'] as num?,
          reason: asText(c['reason']),
          open: () => ExpenseListScreen(kind: kind, month: widget.month),
        ));
      }
    }
    for (final c in list(results[2], 'claims')) {
      if (c['state'] != 'rejected') continue;
      rows.add(_Rejected(
        source: 'Travel Allowance',
        title: '${c['date']} · ${c['distance_km']} km',
        date: '${c['date'] ?? ''}',
        amount: c['amount'] as num?,
        reason: asText(c['reason']) ?? asText(c['reject_reason']),
        open: () => const AllowanceScreen(),
      ));
    }
    for (final r in list(results[3], 'requests')) {
      if (r['state'] != 'rejected') continue;
      final date = '${r['date'] ?? r['created'] ?? ''}';
      if (date.length >= 7 && date.substring(0, 7) != _key) continue;
      rows.add(_Rejected(
        source: 'Payment request',
        title: asText((r['sub_category'] as Map?)?['name'])?.split(' / ').last.trim() ?? 'Payment request',
        date: date,
        amount: r['amount'] as num?,
        reason: asText(r['reason']),
        open: () => const PaymentRequestsScreen(),
      ));
    }
    rows.sort((a, b) => b.date.compareTo(a.date));
    if (mounted) setState(() => _rows = rows);
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text('Rejected Requests · ${monthNames[widget.month.month - 1]} ${widget.month.year}')),
      body: rows == null
          ? const Center(child: CircularProgressIndicator())
          : rows.isEmpty
              ? const EmptyView(icon: Icons.thumb_up_alt_outlined, text: 'Nothing was rejected this month.')
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
                    for (final r in rows)
                      Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => r.open())),
                          leading: CircleAvatar(
                            backgroundColor: AppColors.danger.withValues(alpha: 0.12),
                            child: const Icon(Icons.block_rounded, color: AppColors.danger),
                          ),
                          title: Text(r.title, style: const TextStyle(fontWeight: FontWeight.w800)),
                          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${r.source}${r.date.isEmpty ? '' : ' · ${r.date}'}'),
                            if (r.reason != null)
                              Text('Reason: ${r.reason}', style: const TextStyle(color: AppColors.danger, fontSize: 12.5)),
                          ]),
                          trailing: Text(fmtMoney(r.amount), style: const TextStyle(fontWeight: FontWeight.w900)),
                          isThreeLine: r.reason != null,
                        ),
                      ),
                  ]),
                ),
    );
  }
}

class _Rejected {
  _Rejected({required this.source, required this.title, required this.date, this.amount, this.reason, required this.open});

  final String source;
  final String title;
  final String date;
  final num? amount;
  final String? reason;
  final Widget Function() open;
}
