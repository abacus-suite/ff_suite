import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../attendance/regularisation_screen.dart' show reasons;
import '../../widgets/skeleton.dart';

/// One quick-access place for everything a manager has to decide, sorted into categories with the
/// number waiting on each. Tap a category to see only its requests.
class ApprovalsScreen extends StatefulWidget {
  const ApprovalsScreen({super.key, this.start});

  /// A category to open on, e.g. from a shortcut.
  final String? start;

  @override
  State<ApprovalsScreen> createState() => _ApprovalsScreenState();
}

class _ApprovalsScreenState extends State<ApprovalsScreen> {
  final Map<String, List<Map<String, dynamic>>> _items = {};
  bool _loading = true;
  String? _error;
  late String _open = widget.start ?? 'all';
  final Set<String> _busy = {};

  /// key, title, one line about it, icon, colour
  static const _kinds = <(String, String, String, IconData, Color)>[
    ('handovers', 'Handovers', 'Outlet money given to distributors', Icons.handshake_rounded, Color(0xFF0E9F6E)),
    ('deposits', 'Money to receive', 'Cash the team submitted to the office', Icons.account_balance_rounded, Color(0xFF0891B2)),
    ('access', 'Contact access', 'Territory, beat or city requests', Icons.lock_open_rounded, Color(0xFF2563EB)),
    ('contacts', 'New contacts', 'Customers added in the field', Icons.storefront_rounded, Color(0xFF0D9488)),
    ('notes', 'Debit / credit notes', 'Samples, free goods, damage, margin', Icons.request_quote_rounded, Color(0xFFD97706)),
    ('expenses', 'Expense claims', 'Claims and card expenses', Icons.receipt_long_rounded, Color(0xFFEA580C)),
    ('leaves', 'Time off', 'Leave requests', Icons.beach_access_rounded, Color(0xFF0284C7)),
    ('returns', 'Returns', 'Damaged and returned stock', Icons.assignment_return_rounded, Color(0xFFDC2626)),
    ('allowances', 'Travel allowance', 'Daily allowance claims', Icons.local_gas_station_rounded, Color(0xFF7C3AED)),
    ('regularisation', 'Attendance fixes', 'Corrections to check-in and out', Icons.edit_calendar_rounded, Color(0xFF4F46E5)),
    ('beats', 'New beats', 'Beats drawn in the app', Icons.route_rounded, Color(0xFF9333EA)),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<dynamic> _optional(Future<dynamic> future) => future.catchError((_) => null);

  List<Map<String, dynamic>> _list(dynamic v) => ((v as List?) ?? []).cast<Map<String, dynamic>>();

  Future<void> _load() async {
    setState(() => _loading = _items.isEmpty);
    try {
      final results = await Future.wait<dynamic>([
        Services.api.get('/api/v1/approvals'),
        _optional(Services.api.get('/api/v1/allowances/to-approve')),
        _optional(Services.api.get('/api/v1/expenses/to-approve')),
        _optional(Services.api.get('/api/v1/leaves/to-approve')),
        _optional(Services.api.get('/api/v1/returns/to-approve')),
        _optional(Services.api.get('/api/v1/contact-access')),
        _optional(Services.api.get('/api/v1/handovers/to-confirm')),
        _optional(Services.api.get('/api/v1/deposits/to-receive')),
        _optional(Services.api.get('/api/v1/notes/to-approve')),
        _optional(Services.api.get('/api/v1/beats/to-approve')),
      ]);
      final base = results[0] as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _items['regularisation'] = _list(base['regularisation']);
        _items['contacts'] = _list(base['clients']);
        _items['allowances'] = _list(results[1]);
        _items['expenses'] = _list(results[2]);
        _items['leaves'] = _list(results[3]);
        _items['returns'] = _list(results[4]);
        _items['access'] = _list((results[5] as Map?)?['to_decide']);
        _items['handovers'] = _list(results[6]);
        _items['deposits'] = _list(results[7]);
        _items['notes'] = _list(results[8]);
        _items['beats'] = _list(results[9]);
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _count(String key) => _items[key]?.length ?? 0;
  int get _total => _kinds.fold(0, (s, k) => s + _count(k.$1));

  Future<void> _decide(String kind, int id, bool approve,
      {Map<String, dynamic> extra = const {}, String? path, Map<String, dynamic>? payload}) async {
    final key = '$kind-$id';
    setState(() => _busy.add(key));
    try {
      final decision = approve ? 'approve' : 'reject';
      final target = path ??
          switch (kind) {
            'return' => '/api/v1/returns/$id/$decision',
            _ => '/api/v1/approvals/$kind/$id/$decision',
          };
      await Services.outbox.submit(target, payload ?? {'uuid': const Uuid().v4(), ...extra});
      if (mounted) showSnack(context, approve ? 'Approved' : 'Rejected');
      settleAndRefresh();
      await _load();
    } catch (e) {
      if (mounted) showProblem(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  /// An expense is approved for what was claimed or for less, and a reason is needed
  /// whenever it is reduced or rejected.
  Future<void> _decideExpense(Map<String, dynamic> e, bool approve) async {
    final claimed = (e['amount'] as num?)?.toDouble() ?? 0;
    final amount = TextEditingController(text: claimed == claimed.roundToDouble() ? '${claimed.toInt()}' : '$claimed');
    final reason = TextEditingController();
    final go = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, set) {
          final reduced = approve && (double.tryParse(amount.text.trim()) ?? claimed) < claimed;
          return AlertDialog(
            title: Text(approve ? 'Approve expense' : 'Reject expense'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              if (approve)
                TextField(
                  controller: amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => set(() {}),
                  decoration: InputDecoration(labelText: 'Approved amount (claimed ${fmtMoney(claimed, e['currency'] as String?)})'),
                ),
              TextField(
                controller: reason,
                maxLines: 2,
                decoration: InputDecoration(
                    labelText: approve ? (reduced ? 'Reason for reducing *' : 'Note (optional)') : 'Reason for rejecting *'),
              ),
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(dialog, true), child: Text(approve ? 'Approve' : 'Reject')),
            ],
          );
        },
      ),
    );
    final value = double.tryParse(amount.text.trim());
    final why = reason.text.trim();
    amount.dispose();
    reason.dispose();
    if (go != true || !mounted) return;
    if (approve && (value == null || value <= 0 || value > claimed)) {
      await showProblem(context, 'The approved amount must be more than zero and not more than the claim.');
      return;
    }
    if ((!approve || (value ?? claimed) < claimed) && why.isEmpty) {
      await showProblem(context, approve ? 'Give the reason for reducing the amount.' : 'Give the reason for rejecting.');
      return;
    }
    await _decide('expense', e['id'] as int, approve,
        extra: {if (approve) 'amount': value, if (why.isNotEmpty) 'reason': why});
  }


  Widget _card({
    required String kind,
    required int id,
    required IconData icon,
    required Color color,
    required String title,
    required List<String> lines,
    String? amount,
    String approveLabel = 'Approve',
    String rejectLabel = 'Reject',
    Future<void> Function(bool approve)? onDecide,
  }) {
    final busy = _busy.contains('$kind-$id');
    Future<void> go(bool a) => (onDecide ?? (x) => _decide(kind, id, x))(a);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: const Color(0xFF1B3A7A).withValues(alpha: 0.07), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(width: 6, color: color),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
                    child: Icon(icon, size: 20, color: color),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Color(0xFF0F172A))),
                  ),
                  if (amount != null) Text(amount, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Color(0xFF0F172A))),
                ]),
                const SizedBox(height: 8),
                for (final line in lines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(line, style: const TextStyle(fontSize: 13, color: Color(0xFF334155), height: 1.25)),
                  ),
                const SizedBox(height: 8),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  OutlinedButton(
                    onPressed: busy ? null : () => go(false),
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger, side: const BorderSide(color: AppColors.danger)),
                    child: Text(rejectLabel),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: busy ? null : () => go(true), child: Text(approveLabel)),
                ]),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  /// The cards of one category.
  List<Widget> _cards(String key) {
    final rows = _items[key] ?? const [];
    final color = _kinds.firstWhere((k) => k.$1 == key).$5;
    switch (key) {
      case 'handovers':
        return [
          for (final h in rows)
            _card(
              kind: 'handover',
              id: h['id'] as int,
              icon: Icons.handshake_rounded,
              color: color,
              title: '${(h['distributor'] as Map?)?['name'] ?? ''}',
              amount: fmtMoney(h['amount'] as num?, h['currency'] as String?),
              approveLabel: 'Confirm',
              lines: [
                'From ${(h['employee'] as Map?)?['name'] ?? ''} · ${h['count']} collection(s) · ${fmtTime(h['date'])}',
                for (final p in ((h['payments'] as List?) ?? []).cast<Map<String, dynamic>>().take(5))
                  '• ${(p['outlet'] as Map?)?['name']} ${fmtMoney(p['amount'] as num?, p['currency'] as String?)}',
                if (asText(h['reference']) != null) 'Reference ${h['reference']}',
              ],
              onDecide: (a) => _decide('handover', h['id'] as int, a,
                  path: '/api/v1/handovers/${h['id']}/${a ? 'confirm' : 'reject'}', payload: {'uuid': const Uuid().v4()}),
            ),
        ];
      case 'deposits':
        return [
          for (final d in rows)
            _card(
              kind: 'deposit',
              id: d['id'] as int,
              icon: Icons.account_balance_rounded,
              color: color,
              title: '${(d['employee'] as Map?)?['name'] ?? d['name']}',
              amount: fmtMoney(d['amount'] as num?, d['currency'] as String?),
              approveLabel: 'Received',
              lines: ['${d['name']} · ${d['count']} collection(s) · ${fmtTime(d['submitted_at'])}', if (asText(d['reference']) != null) 'Slip ${d['reference']}'],
              onDecide: (a) => _decide('deposit', d['id'] as int, a,
                  path: '/api/v1/deposits/${d['id']}/${a ? 'receive' : 'reject'}', payload: {'uuid': const Uuid().v4()}),
            ),
        ];
      case 'access':
        return [
          for (final r in rows)
            _card(
              kind: 'access',
              id: r['id'] as int,
              icon: Icons.lock_open_rounded,
              color: color,
              title: '${r['target']} (${r['scope_type']})',
              lines: [
                'For ${(r['employee'] as Map?)?['name'] ?? ''}',
                '${r['date_from']} to ${r['date_to']}',
                if (asText(r['reason']) != null) 'Reason: ${r['reason']}',
              ],
              onDecide: (a) => _decide('access', r['id'] as int, a,
                  path: '/api/v1/contact-access/${r['id']}/decide', payload: {'approve': a}),
            ),
        ];
      case 'notes':
        return [
          for (final n in rows)
            _card(
              kind: 'note',
              id: n['id'] as int,
              icon: Icons.request_quote_rounded,
              color: color,
              title: '${n['name']} · ${n['kind'] == 'debit' ? 'Debit' : 'Credit'} note',
              amount: fmtMoney(n['amount'] as num?, n['currency'] as String?),
              lines: [
                '${n['source_label']} · raised by ${(n['employee'] as Map?)?['name'] ?? ''}',
                if (n['distributor'] != null) 'Distributor: ${(n['distributor'] as Map)['name']}',
                if (n['outlet'] != null) 'Outlet: ${(n['outlet'] as Map)['name']}',
                if (asText(n['demand']) != null) 'Demand ${n['demand']}',
                if (asText(n['reason']) != null) '${n['reason']}',
                for (final l in ((n['lines'] as List?) ?? []).cast<Map<String, dynamic>>().take(4))
                  '• ${l['product']} × ${fmtQty((l['qty'] as num?) ?? 0)}',
              ],
              onDecide: (a) => _decide('note', n['id'] as int, a,
                  path: '/api/v1/notes/${n['id']}/${a ? 'approve' : 'reject'}', payload: {'uuid': const Uuid().v4()}),
            ),
        ];
      case 'beats':
        return [
          for (final b in rows)
            _card(
              kind: 'beat',
              id: b['id'] as int,
              icon: Icons.route_rounded,
              color: color,
              title: '${b['name']}',
              lines: [
                'Drawn by ${(b['added_by'] as Map?)?['name'] ?? ''}',
                '${b['customer_count']} customers${b['city'] != null ? ' · ${b['city']}' : ''}',
              ],
              onDecide: (a) => _decide('beat', b['id'] as int, a, path: '/api/v1/beats/${b['id']}/decide', payload: {'approve': a}),
            ),
        ];
      case 'contacts':
        return [
          for (final c in rows)
            _card(
              kind: 'client',
              id: c['id'] as int,
              icon: Icons.storefront_rounded,
              color: color,
              title: '${c['name']}',
              lines: [
                'Added by ${(c['added_by'] as Map?)?['name'] ?? '-'} · ${fmtTime(c['added_at'])}',
                if (c['address'] != null) '${c['address']}',
                if (c['phone'] != null) 'Phone ${c['phone']}',
                c['lat'] != null ? 'GPS location captured' : 'No GPS location',
              ],
            ),
        ];
      case 'expenses':
        return [
          for (final e in rows)
            _card(
              kind: 'expense',
              onDecide: (approve) => _decideExpense(e, approve),
              id: e['id'] as int,
              icon: Icons.receipt_long_rounded,
              color: color,
              title: '${(e['employee'] as Map?)?['name'] ?? ''}',
              amount: fmtMoney(e['amount'] as num?, e['currency'] as String?),
              lines: [
                '${(e['category'] as Map?)?['name'] ?? ''} · ${e['date']}',
                if ((e['contact'] as Map?)?['name'] != null) 'Contact: ${(e['contact'] as Map)['name']}',
                '${e['receipt_count']} receipt(s)${e['note'] != null ? ' · ${e['note']}' : ''}',
              ],
            ),
        ];
      case 'returns':
        return [
          for (final r in rows)
            _card(
              kind: 'return',
              id: r['id'] as int,
              icon: Icons.assignment_return_rounded,
              color: color,
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
        ];
      case 'leaves':
        return [
          for (final l in rows)
            _card(
              kind: 'leave',
              id: l['id'] as int,
              icon: Icons.beach_access_rounded,
              color: color,
              title: '${(l['employee'] as Map?)?['name'] ?? ''}',
              lines: [
                '${(l['type'] as Map?)?['name'] ?? ''} · ${fmtQty(l['days'] as num? ?? 0)} days',
                '${l['from']}${l['to'] != l['from'] ? ' to ${l['to']}' : ''}',
                if (asText(l['reason']) != null) '${l['reason']}',
              ],
            ),
        ];
      case 'allowances':
        return [
          for (final a in rows)
            _card(
              kind: 'allowance',
              id: a['id'] as int,
              icon: Icons.local_gas_station_rounded,
              color: color,
              title: '${(a['employee'] as Map?)?['name'] ?? ''}',
              amount: fmtMoney(a['amount'] as num?, a['currency'] as String?),
              lines: [
                '${a['date']} · ${a['distance_km']} km · ${a['visit_count']} visits',
                if (a['estimated'] == true) 'Some legs are estimated',
                for (final leg in ((a['legs'] as List?) ?? []).cast<Map<String, dynamic>>().take(3))
                  '• ${leg['name']} (${(leg['km'] as num?)?.toStringAsFixed(1) ?? '0'} km)',
              ],
            ),
        ];
      default:
        return [
          for (final r in rows)
            _card(
              kind: 'regularisation',
              id: r['id'] as int,
              icon: Icons.edit_calendar_rounded,
              color: color,
              title: '${(r['employee'] as Map)['name']}',
              lines: [
                'Date ${r['date']} · In ${fmtTime(r['check_in'])} · Out ${fmtTime(r['check_out'])}',
                'Reason: ${reasons[r['reason']] ?? r['reason']}',
                if (r['note'] != null) 'Note: ${r['note']}',
              ],
            ),
        ];
    }
  }

  // ------------------------------------------------------------------ the hub
  Widget _hero() => Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF1E3A8A), Color(0xFF2563EB), Color(0xFF0891B2)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(26),
          boxShadow: [BoxShadow(color: const Color(0xFF2563EB).withValues(alpha: 0.28), blurRadius: 20, offset: const Offset(0, 9))],
        ),
        child: Row(children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text('$_total', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 26)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_total == 0 ? 'All caught up' : 'Waiting for you',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 19)),
              const SizedBox(height: 3),
              Text(_total == 0 ? 'Nothing to approve right now.' : 'Pick a category to see its requests.',
                  style: const TextStyle(color: Colors.white, fontSize: 13)),
            ]),
          ),
        ]),
      );

  Widget _tile((String, String, String, IconData, Color) k) {
    final n = _count(k.$1);
    final on = _open == k.$1;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => setState(() => _open = on ? 'all' : k.$1),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: on ? k.$5.withValues(alpha: 0.12) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: on ? k.$5 : Colors.transparent, width: 1.8),
          boxShadow: [BoxShadow(color: const Color(0xFF1B3A7A).withValues(alpha: 0.07), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: k.$5.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
              child: Icon(k.$4, color: k.$5, size: 21),
            ),
            const Spacer(),
            Container(
              constraints: const BoxConstraints(minWidth: 28),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: n > 0 ? AppColors.danger : const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(14)),
              child: Text('$n',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5, color: n > 0 ? Colors.white : const Color(0xFF475569))),
            ),
          ]),
          const SizedBox(height: 10),
          Text(k.$2, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5, color: Color(0xFF0F172A))),
          const SizedBox(height: 2),
          Text(k.$3, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: Color(0xFF475569), height: 1.2)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shown = _open == 'all' ? _kinds.where((k) => _count(k.$1) > 0).toList() : _kinds.where((k) => k.$1 == _open).toList();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Approvals')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const LoadingView()
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
                children: [
                  if (_error != null) ErrorView(message: _error!, onRetry: _load),
                  _hero(),
                  const SizedBox(height: 14),
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1.32,
                    children: [for (final k in _kinds) _tile(k)],
                  ),
                  const SizedBox(height: 16),
                  if (_open != 'all')
                    Align(
                      alignment: Alignment.centerLeft,
                      child: InputChip(label: const Text('Show all categories'), onPressed: () => setState(() => _open = 'all')),
                    ),
                  if (shown.isEmpty && _error == null)
                    const Padding(padding: EdgeInsets.all(28), child: EmptyView(icon: Icons.check_circle_rounded, text: 'Nothing to approve right now')),
                  for (final k in shown) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
                      child: Row(children: [
                        Icon(k.$4, color: k.$5, size: 19),
                        const SizedBox(width: 8),
                        Text('${k.$2} (${_count(k.$1)})', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF0F172A))),
                      ]),
                    ),
                    if (_count(k.$1) == 0)
                      const Padding(padding: EdgeInsets.all(12), child: Text('Nothing waiting here.', style: TextStyle(color: Color(0xFF475569)))),
                    ..._cards(k.$1),
                  ],
                ],
              ),
      ),
    );
  }
}
