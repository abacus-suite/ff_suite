import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import 'sales_cards.dart';
import '../allowance/allowance_screen.dart';
import '../expenses/expenses_screen.dart';
import '../leaves/leaves_screen.dart';

/// Everything the employee has asked the office for, in one place.
///
/// Leave, expenses and travel allowance all end in somebody else's approval
/// queue, and the question people actually ask is the same for all three: has
/// it been approved yet? So they are counted together, with a row each.
class MyRequestsCard extends StatefulWidget {
  const MyRequestsCard({super.key});

  @override
  State<MyRequestsCard> createState() => _MyRequestsCardState();
}

class _MyRequestsCardState extends State<MyRequestsCard> {
  Map<String, _RequestLine> _lines = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    Services.refresh.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    Services.refresh.removeListener(_load);
    super.dispose();
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
      _maybe(Services.api.get('/api/v1/leaves')),
      _maybe(Services.api.get('/api/v1/expenses')),
      _maybe(Services.api.get('/api/v1/allowances')),
    ]);
    if (!mounted) return;

    final lines = <String, _RequestLine>{};

    final leaves = results[0] as Map<String, dynamic>?;
    if (leaves != null) {
      final summary = (leaves['summary'] as Map?) ?? const {};
      lines['leave'] = _RequestLine(
        label: 'Time off',
        icon: Icons.beach_access_rounded,
        colour: AppColors.sky,
        waiting: (summary['waiting'] as int?) ?? 0,
        approved: (summary['approved'] as int?) ?? 0,
        detail: _lastState(((leaves['leaves'] as List?) ?? []).cast<Map<String, dynamic>>()),
      );
    }

    final expenses = results[1] as Map<String, dynamic>?;
    if (expenses != null) {
      final rows = ((expenses['claims'] as List?) ?? []).cast<Map<String, dynamic>>();
      lines['expense'] = _RequestLine(
        label: 'Expenses',
        icon: Icons.receipt_long_rounded,
        colour: AppColors.warning,
        waiting: rows.where((row) => row['state'] == 'submitted').length,
        approved: rows.where((row) => row['state'] == 'approved').length,
        detail: '${fmtMoney(expenses['total_amount'] as num?, expenses['currency'] as String?)} this month',
      );
    }

    final allowances = results[2] as Map<String, dynamic>?;
    if (allowances != null) {
      final rows = ((allowances['claims'] as List?) ?? []).cast<Map<String, dynamic>>();
      lines['allowance'] = _RequestLine(
        label: 'Travel allowance',
        icon: Icons.local_gas_station_rounded,
        colour: AppColors.purple,
        waiting: rows.where((row) => row['state'] == 'submitted').length,
        approved: rows.where((row) => row['state'] == 'approved').length,
        detail: '${fmtMoney(allowances['total_amount'] as num?, allowances['currency'] as String?)} this month',
      );
    }

    setState(() {
      _lines = lines;
      _loading = false;
    });
  }

  String _lastState(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return 'Nothing requested yet';
    final latest = rows.first;
    return '${latest['type']?['name'] ?? ''} · ${latest['state_label'] ?? ''}';
  }

  void _open(String key) {
    final screen = switch (key) {
      'leave' => const LeavesScreen(),
      'expense' => const ExpensesScreen(),
      _ => const AllowanceScreen(),
    };
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _lines.isEmpty) {
      return const SizedBox.shrink();
    }
    final waiting = _lines.values.fold<int>(0, (sum, line) => sum + line.waiting);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CardHead(
                icon: Icons.description_rounded,
                title: 'My Requests',
                subtitle: 'Time off, expenses and claims',
                tint: AppColors.purple,
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: (waiting == 0 ? AppColors.success : AppColors.warning).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(waiting == 0 ? 'All settled' : '$waiting waiting',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: waiting == 0 ? AppColors.success : AppColors.warning)),
                ),
              ),
              const SizedBox(height: 10),
              for (final entry in _lines.entries) _tile(entry.key, entry.value),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tile(String key, _RequestLine line) {
    final pending = line.waiting > 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _open(key),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: line.colour.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(line.icon, size: 19, color: line.colour),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(line.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                    const SizedBox(height: 1),
                    Text(line.detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: (pending ? AppColors.warning : line.colour).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Text(
                    pending
                        ? '${line.waiting} waiting'
                        : (line.approved > 0 ? '${line.approved} approved' : 'Request'),
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: pending ? AppColors.warning : line.colour)),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _RequestLine {
  const _RequestLine({
    required this.label,
    required this.icon,
    required this.colour,
    required this.waiting,
    required this.approved,
    required this.detail,
  });

  final String label;
  final IconData icon;
  final Color colour;
  final int waiting;
  final int approved;
  final String detail;
}
