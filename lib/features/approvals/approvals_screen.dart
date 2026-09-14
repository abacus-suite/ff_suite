import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../attendance/regularisation_screen.dart' show reasons;

/// Everything a manager has to decide: corrections, new contacts, allowances, expenses.
class ApprovalsScreen extends StatefulWidget {
  const ApprovalsScreen({super.key});

  @override
  State<ApprovalsScreen> createState() => _ApprovalsScreenState();
}

class _ApprovalsScreenState extends State<ApprovalsScreen> {
  List<Map<String, dynamic>> _regularisations = [];
  List<Map<String, dynamic>> _clients = [];
  List<Map<String, dynamic>> _allowances = [];
  List<Map<String, dynamic>> _expenses = [];
  List<Map<String, dynamic>> _leaves = [];
  List<Map<String, dynamic>> _returns = [];
  bool _loading = true;
  String? _error;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<dynamic> _optional(Future<dynamic> future) => future.catchError((_) => null);

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait<dynamic>([
        Services.api.get('/api/v1/approvals'),
        _optional(Services.api.get('/api/v1/allowances/to-approve')),
        _optional(Services.api.get('/api/v1/expenses/to-approve')),
        _optional(Services.api.get('/api/v1/leaves/to-approve')),
        _optional(Services.api.get('/api/v1/returns/to-approve')),
      ]);
      final base = results[0] as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _regularisations = ((base['regularisation'] as List?) ?? []).cast<Map<String, dynamic>>();
        _clients = ((base['clients'] as List?) ?? []).cast<Map<String, dynamic>>();
        _allowances = ((results[1] as List?) ?? []).cast<Map<String, dynamic>>();
        _expenses = ((results[2] as List?) ?? []).cast<Map<String, dynamic>>();
        _leaves = ((results[3] as List?) ?? []).cast<Map<String, dynamic>>();
        _returns = ((results[4] as List?) ?? []).cast<Map<String, dynamic>>();
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _decide(String kind, int id, bool approve) async {
    final key = '$kind-$id';
    setState(() => _busy.add(key));
    try {
      final decision = approve ? 'approve' : 'reject';
      final path = kind == 'return' ? '/api/v1/returns/$id/$decision' : '/api/v1/approvals/$kind/$id/$decision';
      await Services.outbox.submit(path, {'uuid': const Uuid().v4()});
      if (mounted) showSnack(context, approve ? 'Approved' : 'Rejected');
      await _load();
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  Widget _card({
    required String kind,
    required int id,
    required IconData icon,
    required Color color,
    required String title,
    required List<String> lines,
    String? amount,
  }) {
    final busy = _busy.contains('$kind-$id');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(radius: 16, backgroundColor: color.withValues(alpha: 0.12), child: Icon(icon, size: 18, color: color)),
                const SizedBox(width: 10),
                Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
                if (amount != null) Text(amount, style: const TextStyle(fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 6),
            for (final line in lines)
              Text(line, style: const TextStyle(fontSize: 13, color: AppColors.muted)),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(onPressed: busy ? null : () => _decide(kind, id, false), child: const Text('Reject')),
                const SizedBox(width: 8),
                FilledButton(onPressed: busy ? null : () => _decide(kind, id, true), child: const Text('Approve')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final empty = _regularisations.isEmpty && _clients.isEmpty && _allowances.isEmpty &&
        _expenses.isEmpty && _leaves.isEmpty && _returns.isEmpty;
    final total = _regularisations.length + _clients.length + _allowances.length +
        _expenses.length + _leaves.length + _returns.length;
    return Scaffold(
      appBar: AppBar(title: Text(total == 0 ? 'Approvals' : 'Approvals ($total)')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                children: [
                  if (_error != null) ErrorView(message: _error!, onRetry: _load),
                  if (empty && _error == null)
                    const EmptyView(icon: Icons.check_circle_rounded, text: 'Nothing to approve right now'),
                  if (_clients.isNotEmpty) const _Section('New contacts'),
                  for (final c in _clients)
                    _card(
                      kind: 'client',
                      id: c['id'] as int,
                      icon: Icons.storefront_rounded,
                      color: AppColors.teal,
                      title: '${c['name']}',
                      lines: [
                        'Added by ${(c['added_by'] as Map?)?['name'] ?? '-'} · ${fmtTime(c['added_at'])}',
                        if (c['address'] != null) '${c['address']}',
                        if (c['phone'] != null) 'Phone ${c['phone']}',
                        c['lat'] != null ? 'GPS location captured' : 'No GPS location',
                      ],
                    ),
                  if (_expenses.isNotEmpty) const _Section('Expense claims'),
                  for (final e in _expenses)
                    _card(
                      kind: 'expense',
                      id: e['id'] as int,
                      icon: Icons.receipt_long_rounded,
                      color: AppColors.warning,
                      title: '${(e['employee'] as Map?)?['name'] ?? ''}',
                      amount: fmtMoney(e['amount'] as num?, e['currency'] as String?),
                      lines: [
                        '${(e['category'] as Map?)?['name'] ?? ''} · ${e['date']}',
                        if ((e['contact'] as Map?)?['name'] != null) 'Contact: ${(e['contact'] as Map)['name']}',
                        '${e['receipt_count']} receipt(s)${e['note'] != null ? ' · ${e['note']}' : ''}',
                      ],
                    ),
                  if (_returns.isNotEmpty) const _Section('Returns & damaged'),
                  for (final r in _returns)
                    _card(
                      kind: 'return',
                      id: r['id'] as int,
                      icon: Icons.assignment_return_rounded,
                      color: AppColors.danger,
                      title: '${(r['employee'] as Map?)?['name'] ?? ''} · ${r['reason_label']}',
                      amount: fmtMoney(r['amount'] as num?, r['currency'] as String?),
                      lines: [
                        '${r['name']} · ${(r['customer'] as Map?)?['name'] ?? ''}',
                        for (final line in ((r['lines'] as List?) ?? []).cast<Map<String, dynamic>>().take(4))
                          '• ${line['product']} × ${fmtQty((line['quantity'] as num?) ?? 0)}',
                        if ((r['photos'] as num? ?? 0) > 0) '${r['photos']} photo(s)',
                        if (asText(r['note']) != null) '${r['note']}',
                      ],
                    ),
                  if (_leaves.isNotEmpty) const _Section('Time off'),
                  for (final l in _leaves)
                    _card(
                      kind: 'leave',
                      id: l['id'] as int,
                      icon: Icons.beach_access_rounded,
                      color: AppColors.sky,
                      title: '${(l['employee'] as Map?)?['name'] ?? ''}',
                      lines: [
                        '${(l['type'] as Map?)?['name'] ?? ''} · ${fmtQty(l['days'] as num? ?? 0)} days',
                        '${l['from']}${l['to'] != l['from'] ? ' → ${l['to']}' : ''}',
                        if (asText(l['reason']) != null) '${l['reason']}',
                      ],
                    ),
                  if (_allowances.isNotEmpty) const _Section('Travel allowance'),
                  for (final a in _allowances)
                    _card(
                      kind: 'allowance',
                      id: a['id'] as int,
                      icon: Icons.local_gas_station_rounded,
                      color: AppColors.purple,
                      title: '${(a['employee'] as Map?)?['name'] ?? ''}',
                      amount: fmtMoney(a['amount'] as num?, a['currency'] as String?),
                      lines: [
                        '${a['date']} · ${a['distance_km']} km · ${a['visit_count']} visits',
                        if (a['estimated'] == true) 'Some legs are estimated',
                        for (final leg in ((a['legs'] as List?) ?? []).cast<Map<String, dynamic>>().take(3))
                          '• ${leg['name']} (${(leg['km'] as num?)?.toStringAsFixed(1) ?? '0'} km)',
                      ],
                    ),
                  if (_regularisations.isNotEmpty) const _Section('Attendance corrections'),
                  for (final r in _regularisations)
                    _card(
                      kind: 'regularisation',
                      id: r['id'] as int,
                      icon: Icons.edit_calendar_rounded,
                      color: AppColors.sky,
                      title: '${(r['employee'] as Map)['name']}',
                      lines: [
                        'Date ${r['date']} · In ${fmtTime(r['check_in'])} · Out ${fmtTime(r['check_out'])}',
                        'Reason: ${reasons[r['reason']] ?? r['reason']}',
                        if (r['note'] != null) 'Note: ${r['note']}',
                      ],
                    ),
                ],
              ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 4),
      child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
    );
  }
}
