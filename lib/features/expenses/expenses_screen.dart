import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import 'new_expense_screen.dart';

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;

  String get _monthKey => '${_month.year}-${_month.month.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await Services.api.get('/api/v1/expenses', query: {'month': _monthKey}) as Map<String, dynamic>;
      if (mounted) setState(() => (_data = data, _error = null));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _shiftMonth(int months) {
    setState(() => _month = DateTime(_month.year, _month.month + months));
    _load();
  }

  Future<void> _newClaim() async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const NewExpenseScreen()));
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final claims = ((data?['claims'] as List?) ?? []).cast<Map<String, dynamic>>();
    final currency = data?['currency'] as String?;
    final now = DateTime.now();
    final isCurrent = _month.year == now.year && _month.month == now.month;
    return Scaffold(
      appBar: AppBar(title: const Text('My Expenses')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newClaim,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New claim'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
          children: [
            Card(
              child: Row(
                children: [
                  IconButton(onPressed: () => _shiftMonth(-1), icon: const Icon(Icons.chevron_left_rounded)),
                  Expanded(
                    child: Center(
                      child: Text('${monthNames[_month.month - 1]} ${_month.year}',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                  IconButton(
                    onPressed: isCurrent ? null : () => _shiftMonth(1),
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ),
            ),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null) ErrorView(message: _error!, onRetry: _load),
            if (data != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Column(
                        children: [
                          Text(fmtMoney(data['total_amount'] as num?, currency),
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                          const Text('Claimed', style: TextStyle(color: AixoloColors.muted, fontSize: 12)),
                        ],
                      ),
                      Column(
                        children: [
                          Text(fmtMoney(data['approved_amount'] as num?, currency),
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AixoloColors.success)),
                          const Text('Approved', style: TextStyle(color: AixoloColors.muted, fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            if (claims.isEmpty && !_loading)
              const EmptyView(icon: Icons.receipt_rounded, text: 'No claims this month'),
            for (final claim in claims)
              Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AixoloColors.warning.withValues(alpha: 0.12),
                    child: const Icon(Icons.receipt_long_rounded, color: AixoloColors.warning),
                  ),
                  title: Text('${(claim['category'] as Map?)?['name'] ?? ''}',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text([
                    claim['date'] as String,
                    if ((claim['contact'] as Map?)?['name'] != null) '${(claim['contact'] as Map)['name']}',
                    if ((claim['receipt_count'] as int? ?? 0) > 0) '${claim['receipt_count']} receipt(s)',
                    if (claim['note'] != null) '${claim['note']}',
                  ].join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(fmtMoney(claim['amount'] as num?, currency),
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      StatusBadge('${claim['state']}'),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
