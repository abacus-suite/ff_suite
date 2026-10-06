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

  Future<bool> _decide(String kind, int id, bool approve,
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
      return true;
    } catch (e) {
      if (mounted) showProblem(context, e.toString());
      return false;
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  /// An expense is approved for what was claimed or for less, and a reason is needed
  /// whenever it is reduced or rejected.
  Future<bool> _decideExpense(Map<String, dynamic> e, bool approve) async {
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
    if (go != true || !mounted) return false;
    if (approve && (value == null || value <= 0 || value > claimed)) {
      await showProblem(context, 'The approved amount must be more than zero and not more than the claim.');
      return false;
    }
    if ((!approve || (value ?? claimed) < claimed) && why.isEmpty) {
      await showProblem(context, approve ? 'Give the reason for reducing the amount.' : 'Give the reason for rejecting.');
      return false;
    }
    return _decide('expense', e['id'] as int, approve,
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
    Future<bool> Function(bool approve)? onDecide,
    _Detail? detail,
  }) {
    final busy = _busy.contains('$kind-$id');
    Future<bool> go(bool a) => (onDecide ?? (x) => _decide(kind, id, x))(a);
    Future<void> view() async {
      if (detail == null) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => _ApprovalDetailScreen(detail: detail, color: color, icon: icon, approveLabel: approveLabel, rejectLabel: rejectLabel, onDecide: go),
      ));
    }

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
            child: InkWell(
              onTap: detail == null ? null : view,
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
                if (detail != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(children: [
                      Icon(Icons.visibility_rounded, size: 15, color: color),
                      const SizedBox(width: 5),
                      Text('View full details', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: color)),
                    ]),
                  ),
              ]),
            ),
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
              detail: _Detail(title: '${(h['distributor'] as Map?)?['name'] ?? ''}', status: 'Waiting for you', amount: fmtMoney(h['amount'] as num?, h['currency'] as String?), facts: [('Handed to', '${(h['distributor'] as Map?)?['name'] ?? '-'}'), ('Handed over by', '${(h['employee'] as Map?)?['name'] ?? '-'}'), ('Date', fmtTime(h['date'])), ('Reference', '${h['reference'] ?? '-'}'), ('Mode', '${h['mode'] ?? '-'}'), ('Collections', '${h['count']}')], lineHead: const ['Outlet', 'Mode', 'Amount'], lines: [for (final p in ((h['payments'] as List?) ?? []).cast<Map<String, dynamic>>()) ['${(p['outlet'] as Map?)?['name']}', '${p['mode'] ?? '-'}${(p['invoices'] as List?)?.isNotEmpty == true ? ' · ${(p['invoices'] as List).join(', ')}' : ''}', fmtMoney(p['amount'] as num?, p['currency'] as String?)]], note: asText(h['note']), steps: const []),
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
              detail: _Detail(title: '${(d['employee'] as Map?)?['name'] ?? d['name']}', status: 'Waiting for you', amount: fmtMoney(d['amount'] as num?, d['currency'] as String?), facts: [('Deposit', '${d['name']}'), ('Submitted by', '${(d['employee'] as Map?)?['name'] ?? '-'}'), ('Submitted', fmtTime(d['submitted_at'])), ('Slip / reference', '${d['reference'] ?? '-'}'), ('Collections', '${d['count']}')], lineHead: const ['From', 'Mode', 'Amount'], lines: [for (final c in ((d['collections'] as List?) ?? []).cast<Map<String, dynamic>>()) ['${(c['contact'] as Map?)?['name'] ?? '-'}', '${(c['mode'] as Map?)?['name'] ?? ''} · ${fmtTime(c['date'])}', fmtMoney(c['amount'] as num?, c['currency'] as String?)]], note: null, steps: const []),
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
              detail: _Detail(title: '${r['target']} (${r['scope_type']})', status: 'Waiting for you', amount: null, facts: [('For', '${(r['employee'] as Map?)?['name'] ?? '-'}'), ('Type', '${r['scope_type']}'), ('Which', '${r['target']}'), ('From', '${r['date_from']}'), ('To', '${r['date_to']}'), ('Given by', r['source'] == 'assigned' ? 'Assigned by a manager' : 'Asked by the employee')], lineHead: const [], lines: const [], note: asText(r['reason']), steps: const []),
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
              detail: _Detail(title: '${n['name']} · ${n['kind'] == 'debit' ? 'Debit' : 'Credit'} note', status: 'Waiting for you', amount: fmtMoney(n['amount'] as num?, n['currency'] as String?), facts: [('Raised for', '${n['source_label']}'), ('Raised by', '${(n['employee'] as Map?)?['name'] ?? '-'}'), ('Distributor', '${(n['distributor'] as Map?)?['name'] ?? '-'}'), ('Outlet', '${(n['outlet'] as Map?)?['name'] ?? '-'}'), ('Demand', '${n['demand'] ?? '-'}'), ('Date', fmtTime(n['date'])), ('Units', fmtQty((n['quantity'] as num?) ?? 0))], lineHead: const ['Product', 'Qty', 'Value'], lines: [for (final l in ((n['lines'] as List?) ?? []).cast<Map<String, dynamic>>()) ['${l['product']}', fmtQty((l['qty'] as num?) ?? 0), fmtMoney(l['subtotal'] as num?, n['currency'] as String?)]], note: asText(n['reason']), steps: const []),
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
              detail: _Detail(title: '${b['name']}', status: 'Waiting for you', amount: null, facts: [('Drawn by', '${(b['added_by'] as Map?)?['name'] ?? '-'}'), ('City', '${b['city'] ?? '-'}'), ('Type', '${b['route_type'] ?? '-'}'), ('Customers', '${b['customer_count']}'), ('Code', '${b['code'] ?? '-'}')], lineHead: const [], lines: const [], note: null, steps: const []),
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
              detail: _Detail(title: '${c['name']}', status: 'Waiting for you', amount: null, facts: [('Added by', '${(c['added_by'] as Map?)?['name'] ?? '-'}'), ('Added on', fmtTime(c['added_at'])), ('Contact type', '${(c['category'] as Map?)?['name'] ?? c['category_type'] ?? '-'}'), ('Address', '${c['address'] ?? '-'}'), ('Phone', '${c['phone'] ?? '-'}'), ('GPS', c['lat'] != null ? 'Location captured' : 'No location')], lineHead: const [], lines: const [], note: null, steps: const []),
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
              detail: _Detail(title: '${(e['employee'] as Map?)?['name'] ?? ''}', status: 'Waiting for you', amount: fmtMoney(e['amount'] as num?, e['currency'] as String?), facts: [('Category', '${(e['category'] as Map?)?['name'] ?? '-'}'), ('Date', '${e['date']}'), ('Contact', '${(e['contact'] as Map?)?['name'] ?? '-'}'), ('Receipts', '${e['receipt_count']}'), ('Claimed', fmtMoney(e['amount'] as num?, e['currency'] as String?))], lineHead: const [], lines: const [], note: asText(e['note']), steps: const []),
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
              detail: _Detail(title: '${(r['employee'] as Map?)?['name'] ?? ''} · ${r['reason_label']}', status: 'Waiting for you', amount: fmtMoney(r['amount'] as num?, r['currency'] as String?), facts: [('Return', '${r['name']}'), ('Customer', '${(r['customer'] as Map?)?['name'] ?? '-'}'), ('Reason', '${r['reason_label']}'), ('Photos', '${r['photos'] ?? 0}')], lineHead: const ['Product', 'Qty'], lines: [for (final l in ((r['lines'] as List?) ?? []).cast<Map<String, dynamic>>()) ['${l['product']}', fmtQty((l['quantity'] as num?) ?? 0)]], note: asText(r['note']), steps: const []),
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
              detail: _Detail(title: '${(l['employee'] as Map?)?['name'] ?? ''}', status: 'Waiting for you', amount: null, facts: [('Type', '${(l['type'] as Map?)?['name'] ?? '-'}'), ('Days', fmtQty(l['days'] as num? ?? 0)), ('From', '${l['from']}'), ('To', '${l['to']}'), ('Half day', l['half_day'] == true ? 'Yes (${l['half_day_period'] ?? ''})' : 'No'), ('Asked on', fmtTime(l['requested_on']))], lineHead: const [], lines: const [], note: asText(l['reason']), steps: [for (final st in (((l['approval'] as Map?)?['steps'] as List?) ?? []).cast<Map<String, dynamic>>()) '${st['name']} · ${st['approver'] ?? ''} · ${st['state']}']),
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
              detail: _Detail(title: '${(a['employee'] as Map?)?['name'] ?? ''}', status: 'Waiting for you', amount: fmtMoney(a['amount'] as num?, a['currency'] as String?), facts: [('Date', '${a['date']}'), ('Distance', '${a['distance_km']} km'), ('Visits', '${a['visit_count']}'), ('Estimated legs', a['estimated'] == true ? 'Yes' : 'No')], lineHead: const ['Leg', 'Distance'], lines: [for (final leg in ((a['legs'] as List?) ?? []).cast<Map<String, dynamic>>()) ['${leg['name']}', '${(leg['km'] as num?)?.toStringAsFixed(1) ?? '0'} km']], note: null, steps: const []),
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
              detail: _Detail(title: '${(r['employee'] as Map)['name']}', status: 'Waiting for you', amount: null, facts: [('Date', '${r['date']}'), ('Check-in', fmtTime(r['check_in'])), ('Check-out', fmtTime(r['check_out'])), ('Reason', '${reasons[r['reason']] ?? r['reason']}')], lineHead: const [], lines: const [], note: asText(r['note']), steps: const []),
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
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () async {
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ApprovalsScreen(start: k.$1)));
        _load();
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          
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
    final kind = widget.start == null ? null : _kinds.firstWhere((k) => k.$1 == widget.start);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(kind?.$2 ?? 'Approvals')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const LoadingView()
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
                children: [
                  if (_error != null) ErrorView(message: _error!, onRetry: _load),
                  if (kind == null) ...[
                    // The main screen is only the categories; each one opens its own list.
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
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: kind.$5.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(18)),
                      child: Row(children: [
                        Icon(kind.$4, color: kind.$5),
                        const SizedBox(width: 10),
                        Expanded(child: Text(kind.$3, style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF0F172A)))),
                        Text('${_count(kind.$1)} waiting', style: TextStyle(fontWeight: FontWeight.w900, color: kind.$5)),
                      ]),
                    ),
                    const SizedBox(height: 12),
                    if (_count(kind.$1) == 0 && _error == null)
                      const Padding(padding: EdgeInsets.all(28), child: EmptyView(icon: Icons.check_circle_rounded, text: 'Nothing waiting here')),
                    ..._cards(kind.$1),
                  ],
                ],
              ),
      ),
    );
  }
}


/// Everything about one request, laid out for reading before a decision.
class _Detail {
  const _Detail({
    required this.title,
    this.status = 'Waiting for you',
    this.amount,
    this.facts = const [],
    this.lineHead = const [],
    this.lines = const [],
    this.note,
    this.steps = const [],
  });

  final String title;
  final String status;
  final String? amount;
  final List<(String, String)> facts;
  final List<String> lineHead;
  final List<List<String>> lines;
  final String? note;
  final List<String> steps;
}

class _ApprovalDetailScreen extends StatefulWidget {
  const _ApprovalDetailScreen({
    required this.detail,
    required this.color,
    required this.icon,
    required this.approveLabel,
    required this.rejectLabel,
    required this.onDecide,
  });

  final _Detail detail;
  final Color color;
  final IconData icon;
  final String approveLabel;
  final String rejectLabel;
  final Future<bool> Function(bool approve) onDecide;

  @override
  State<_ApprovalDetailScreen> createState() => _ApprovalDetailScreenState();
}

class _ApprovalDetailScreenState extends State<_ApprovalDetailScreen> {
  bool _busy = false;
  static const _ink = Color(0xFF0F172A);
  static const _sub = Color(0xFF475569);

  Future<void> _go(bool approve) async {
    setState(() => _busy = true);
    final done = await widget.onDecide(approve);
    if (!mounted) return;
    setState(() => _busy = false);
    if (done) Navigator.of(context).pop();
  }

  Widget _card(String title, Widget child) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: const Color(0xFF1B3A7A).withValues(alpha: 0.07), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: _ink)),
          const SizedBox(height: 10),
          child,
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final d = widget.detail;
    final c = widget.color;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Request details')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [c, c.withValues(alpha: 0.78)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: c.withValues(alpha: 0.3), blurRadius: 18, offset: const Offset(0, 8))],
          ),
          child: Row(children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(16)),
              child: Icon(widget.icon, color: Colors.white, size: 27),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(d.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(12)),
                  child: Text(d.status, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
                ),
              ]),
            ),
            if (d.amount != null) Text(d.amount!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 20)),
          ]),
        ),
        const SizedBox(height: 14),
        if (d.facts.isNotEmpty)
          _card(
            'Details',
            Column(children: [
              for (final (k, v) in d.facts)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(width: 118, child: Text(k, style: const TextStyle(color: _sub, fontSize: 13.5, fontWeight: FontWeight.w600))),
                    Expanded(child: Text(v, style: const TextStyle(color: _ink, fontSize: 14, fontWeight: FontWeight.w800))),
                  ]),
                ),
            ]),
          ),
        if (d.lines.isNotEmpty)
          _card(
            'Items (${d.lines.length})',
            Column(children: [
              if (d.lineHead.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(children: [
                    for (final (i, h) in d.lineHead.indexed)
                      Expanded(
                        flex: i == 0 ? 5 : 3,
                        child: Text(h.toUpperCase(),
                            textAlign: i == 0 ? TextAlign.left : TextAlign.right,
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: _sub, letterSpacing: 0.4)),
                      ),
                  ]),
                ),
              for (final row in d.lines)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFE2E8F0)))),
                  child: Row(children: [
                    for (final (i, cell) in row.indexed)
                      Expanded(
                        flex: i == 0 ? 5 : 3,
                        child: Text(cell,
                            textAlign: i == 0 ? TextAlign.left : TextAlign.right,
                            style: TextStyle(fontSize: 13.5, fontWeight: i == row.length - 1 ? FontWeight.w900 : FontWeight.w700, color: _ink)),
                      ),
                  ]),
                ),
            ]),
          ),
        if (d.steps.isNotEmpty)
          _card('Approval steps', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final st in d.steps) Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text(st, style: const TextStyle(color: _ink, fontSize: 13.5))),
          ])),
        if (d.note != null) _card('Note', Text(d.note!, style: const TextStyle(color: _ink, fontSize: 14, height: 1.35))),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(children: [
            Expanded(
              child: SizedBox(
                height: 52,
                child: OutlinedButton(
                  onPressed: _busy ? null : () => _go(false),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.danger,
                      side: const BorderSide(color: AppColors.danger),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26))),
                  child: Text(widget.rejectLabel, style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: _busy ? null : () => _go(true),
                  style: FilledButton.styleFrom(backgroundColor: c, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26))),
                  child: _busy
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                      : Text(widget.approveLabel, style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
