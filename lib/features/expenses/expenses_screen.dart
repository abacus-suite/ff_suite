import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import 'expense_form_screen.dart';
import 'new_expense_screen.dart';

/// My Expenses: what was claimed and approved, the claims not sent yet (tick
/// and send them), and how each sent one fared.
class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  Map<String, dynamic>? _data;
  bool _loading = true;
  bool _sending = false;
  String? _error;
  final Set<int> _picked = {};

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
      if (mounted) {
        setState(() {
          _data = data;
          _error = null;
          final ids = _claims.where((c) => c['can_send'] == true).map((c) => c['id'] as int).toSet();
          _picked.retainAll(ids);
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _claims => ((_data?['claims'] as List?) ?? []).cast<Map<String, dynamic>>();

  void _shiftMonth(int months) {
    setState(() => _month = DateTime(_month.year, _month.month + months));
    _load();
  }

  Future<void> _new() async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const NewExpenseScreen(openList: false)));
    if (saved == true) _load();
  }

  Future<void> _open(Map<String, dynamic> claim) async {
    if (claim['editable'] == true) {
      final saved = await Navigator.of(context)
          .push<bool>(MaterialPageRoute(builder: (_) => ExpenseFormScreen(kind: 'claim', existing: claim)));
      if (saved == true) _load();
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => _Detail(claim: claim),
    );
  }

  Future<void> _send() async {
    setState(() => _sending = true);
    try {
      await Services.api.post('/api/v1/expenses/send', {'ids': _picked.toList()});
      if (mounted) showSnack(context, 'Sent for approval');
      _picked.clear();
      await _load();
    } catch (e) {
      if (mounted) await showProblem(context, e.toString(), title: 'Could not send');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// "Mon 05 Oct, 10:00 am" for the first deadline still ahead.
  String? get _deadline {
    final dates = _claims
        .where((c) => c['state'] == 'draft' && c['send_deadline'] != null)
        .map((c) => parseServerTime(c['send_deadline']))
        .whereType<DateTime>()
        .map((d) => d.toLocal())
        .toList()
      ..sort();
    if (dates.isEmpty) return null;
    final d = dates.first;
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '${days[d.weekday - 1]} ${d.day.toString().padLeft(2, '0')} ${monthNames[d.month - 1].substring(0, 3)}, '
        '$hour:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'am' : 'pm'}';
  }

  (Color, String) _style(String state) => switch (state) {
        'approved' => (AppColors.success, 'Approved'),
        'partial' => (AppColors.warning, 'Partly approved'),
        'rejected' => (AppColors.danger, 'Rejected'),
        'submitted' => (AppColors.sky, 'Sent for approval'),
        _ => (AppColors.muted, 'Not sent'),
      };

  Widget _tile(Map<String, dynamic> c, String? currency) {
    final state = '${c['state']}';
    final (tint, label) = _style(state);
    final canSend = c['can_send'] == true;
    final draft = state == 'draft';
    final cat = '${(c['category'] as Map?)?['name'] ?? ''}';
    final sub = (c['sub_category'] as Map?)?['name'];
    final reason = c['reason'];
    final approved = c['approved_amount'] as num?;
    final pics = (c['receipt_count'] as num?) ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: const Color(0xFF1B3A7A).withValues(alpha: 0.06), blurRadius: 16, offset: const Offset(0, 5))],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _open(c),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 14, 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (draft)
              Checkbox(
                value: _picked.contains(c['id']),
                onChanged: canSend
                    ? (v) => setState(() => v == true ? _picked.add(c['id'] as int) : _picked.remove(c['id']))
                    : null,
              )
            else
              const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(sub == null ? cat : '$cat · $sub', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 3),
                Text(
                  draft && !canSend && c['send_blocker'] != null
                      ? '${c['send_blocker']}'
                      : '${c['date']} · ${pics == 0 ? 'No picture' : '$pics picture${pics == 1 ? '' : 's'}'}',
                  style: TextStyle(fontSize: 12.5, color: draft && !canSend ? AppColors.danger : AppColors.muted),
                ),
                if (state == 'partial' && approved != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Approved ${fmtMoney(approved, currency)} of ${fmtMoney(c['amount'] as num?, currency)}',
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                  ),
                if ((state == 'partial' || state == 'rejected') && reason != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text('Reason: $reason', style: TextStyle(fontSize: 12.5, color: tint)),
                  ),
              ]),
            ),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(fmtMoney(c['amount'] as num?, currency), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(color: tint.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                child: Text(label, style: TextStyle(color: tint, fontWeight: FontWeight.w800, fontSize: 11)),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final currency = data?['currency'] as String?;
    final now = DateTime.now();
    final isCurrent = _month.year == now.year && _month.month == now.month;
    final deadline = _deadline;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('My Expenses')),
      floatingActionButton: _picked.isEmpty
          ? FloatingActionButton.extended(
              onPressed: _new, icon: const Icon(Icons.add_rounded), label: const Text('New expense'))
          : null,
      bottomNavigationBar: _picked.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: GradientButton(
                  label: 'Send for approval (${_picked.length})',
                  icon: Icons.send_rounded,
                  busy: _sending,
                  onPressed: _send,
                ),
              ),
            ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
          children: [
            Card(
              child: Row(children: [
                IconButton(onPressed: () => _shiftMonth(-1), icon: const Icon(Icons.chevron_left_rounded)),
                Expanded(
                  child: Center(
                    child: Text('${monthNames[_month.month - 1]} ${_month.year}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
                IconButton(
                    onPressed: isCurrent ? null : () => _shiftMonth(1), icon: const Icon(Icons.chevron_right_rounded)),
              ]),
            ),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null) ErrorView(message: _error!, onRetry: _load),
            if (data != null)
              Row(children: [
                Expanded(child: _total('Claimed', data['total_amount'] as num?, currency, AppColors.primary)),
                const SizedBox(width: 10),
                Expanded(child: _total('Approved', data['approved_amount'] as num?, currency, AppColors.success)),
              ]),
            if (deadline != null)
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 4),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(16)),
                child: Row(children: [
                  const Icon(Icons.schedule_rounded, color: AppColors.warning),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Send the week\'s expenses by $deadline. After that only your manager can add them.',
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                  ),
                ]),
              ),
            const SizedBox(height: 10),
            if (_claims.isEmpty && !_loading) const EmptyView(icon: Icons.receipt_rounded, text: 'No expenses this month'),
            for (final c in _claims) _tile(c, currency),
          ],
        ),
      ),
    );
  }

  Widget _total(String label, num? v, String? currency, Color tint) => Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(fmtMoney(v, currency), style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: tint)),
          Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
        ]),
      );
}

/// A sent expense: read only, with the decision and the reason.
class _Detail extends StatelessWidget {
  const _Detail({required this.claim});

  final Map<String, dynamic> claim;

  @override
  Widget build(BuildContext context) {
    final currency = claim['currency'] as String?;
    final sub = (claim['sub_category'] as Map?)?['name'];
    final rows = <(String, String)>[
      ('Category', '${(claim['category'] as Map?)?['name'] ?? ''}'),
      if (sub != null) ('Sub category', '$sub'),
      ('Date', '${claim['date']}'),
      ('Claimed', fmtMoney(claim['amount'] as num?, currency)),
      if (claim['approved_amount'] != null) ('Approved', fmtMoney(claim['approved_amount'] as num?, currency)),
      ('Status', '${claim['state_label']}'),
      if (claim['reason'] != null) ('Reason', '${claim['reason']}'),
      if (claim['note'] != null) ('Description', '${claim['note']}'),
      ('Pictures', '${claim['receipt_count']}'),
    ];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Expense details', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          const SizedBox(height: 12),
          for (final (k, v) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 104, child: Text(k, style: const TextStyle(color: AppColors.muted))),
                Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w700))),
              ]),
            ),
          const SizedBox(height: 6),
          const Text('A sent expense cannot be edited.', style: TextStyle(fontSize: 12, color: AppColors.muted)),
        ]),
      ),
    );
  }
}
