import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/skeleton.dart';

/// Money this employee holds, and where each part of it has to go:
/// money from distributors goes to the office, money from outlets goes to the
/// distributor those outlets buy from.
class CollectionsScreen extends StatefulWidget {
  const CollectionsScreen({super.key});

  @override
  State<CollectionsScreen> createState() => _CollectionsScreenState();
}

class _CollectionsScreenState extends State<CollectionsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  Map<String, dynamic>? _data;
  Map<String, dynamic> _toDistributors = const {};
  List<Map<String, dynamic>> _deposits = [];
  List<Map<String, dynamic>> _handovers = [];
  List<Map<String, dynamic>> _modes = [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    Services.refresh.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    Services.refresh.removeListener(_load);
    _tabs.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _list(String path) async =>
      (await Services.api.get(path) as List).cast<Map<String, dynamic>>();

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = _data == null;
      _error = null;
    });
    try {
      final month = await Services.api.get('/api/v1/collections') as Map<String, dynamic>;
      final deposits = await _list('/api/v1/deposits');
      Map<String, dynamic> pending = const {};
      List<Map<String, dynamic>> handovers = const [];
      try {
        pending = await Services.api.get('/api/v1/handovers/pending') as Map<String, dynamic>;
        handovers = await _list('/api/v1/handovers');
      } catch (_) {
        // an older server has no hand-over to distributors yet
      }
      if (_modes.isEmpty) {
        try {
          _modes = await _list('/api/v1/collection-modes');
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _data = month;
        _deposits = deposits;
        _toDistributors = pending;
        _handovers = handovers;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  String? get _currency => _data?['currency'] as String?;

  Future<void> _submitDeposit(Map<String, dynamic> pending) async {
    final reference = TextEditingController();
    final person = TextEditingController();
    var when = DateTime.now();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: const Text('Submit to the office'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${fmtMoney(pending['amount'] as num?, _currency)} from ${pending['count']} '
                    'distributor collections'),
                const SizedBox(height: 12),
                TextField(
                  controller: person,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Who in the company took it', prefixIcon: Icon(Icons.person_rounded)),
                ),
                const SizedBox(height: 10),
                _DateField(value: when, onChanged: (d) => setDialog(() => when = d)),
                const SizedBox(height: 10),
                TextField(
                  controller: reference,
                  decoration: const InputDecoration(labelText: 'Slip / receipt number (optional)'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (person.text.trim().isEmpty) {
                  showSnack(ctx, 'Enter the name of the person who took the money.');
                  return;
                }
                Navigator.of(ctx).pop(true);
              },
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    );
    final ref = reference.text.trim();
    final who = person.text.trim();
    reference.dispose();
    person.dispose();
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await Services.outbox.submit('/api/v1/deposits', {
        'reference': ref,
        'uuid': const Uuid().v4(),
        'handed_to': who,
        'date': when.toUtc().toIso8601String(),
      });
      settleAndRefresh();
      if (mounted) showSnack(context, 'Submitted to the office');
    } catch (e) {
      if (mounted) showProblem(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _handOver(Map<String, dynamic> group) async {
    final distributor = group['distributor'] as Map<String, dynamic>;
    final payments = (group['payments'] as List).cast<Map<String, dynamic>>();
    final picked = {for (final p in payments) p['id'] as int};
    // What is given from each outlet collection: all that is still held, unless changed.
    final amounts = {
      for (final p in payments)
        p['id'] as int: TextEditingController(text: _plain((p['held'] ?? p['amount']) as num)),
    };
    final reference = TextEditingController();
    final note = TextEditingController();
    final person = TextEditingController();
    var when = DateTime.now();
    int? mode;
    String? problem;
    final go = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        num given(Map<String, dynamic> p) => num.tryParse(amounts[p['id']]!.text.trim()) ?? 0;
        final total = payments.where((p) => picked.contains(p['id'])).fold<num>(0, (sum, p) => sum + given(p));
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Hand over to ${distributor['name']}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                TextField(
                  controller: person,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: 'Who at ${distributor['name']} took it',
                    prefixIcon: const Icon(Icons.person_rounded),
                  ),
                ),
                const SizedBox(height: 10),
                _DateField(value: when, onChanged: (d) => setSheet(() => when = d)),
                const SizedBox(height: 12),
                for (final p in payments) _paymentRow(p, picked, amounts[p['id']]!, setSheet),
                const Divider(),
                if (_modes.isNotEmpty)
                  DropdownButtonFormField<int>(
                    initialValue: mode,
                    decoration: const InputDecoration(labelText: 'How you gave it'),
                    items: [
                      for (final m in _modes) DropdownMenuItem(value: m['id'] as int, child: Text('${m['name']}')),
                    ],
                    onChanged: (v) => setSheet(() => mode = v),
                  ),
                const SizedBox(height: 8),
                TextField(
                  controller: reference,
                  decoration: const InputDecoration(labelText: 'Receipt / reference (optional)'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: note,
                  decoration: const InputDecoration(labelText: 'Note about this handover'),
                ),
                if (problem != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(problem!, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700)),
                  ),
                const SizedBox(height: 14),
                GradientButton(
                  label: 'Hand over ${fmtMoney(total, group['currency'] as String?)}',
                  icon: Icons.handshake_rounded,
                  onPressed: picked.isEmpty || total <= 0
                      ? null
                      : () {
                          final bad = payments.where((p) {
                            if (!picked.contains(p['id'])) return false;
                            final held = (p['held'] ?? p['amount']) as num;
                            return given(p) <= 0 || given(p) - held > 0.005;
                          });
                          if (person.text.trim().isEmpty) {
                            setSheet(() => problem = 'Enter the name of the person who took the money.');
                          } else if (bad.isNotEmpty) {
                            setSheet(() => problem =
                                'Check the amount for ${(bad.first['outlet'] as Map)['name']}: it must be more than 0 and no more than what is still with you.');
                          } else {
                            Navigator.of(ctx).pop(true);
                          }
                        },
                ),
              ],
            ),
          ),
        );
      }),
    );
    final ref = reference.text.trim();
    final memo = note.text.trim();
    final who = person.text.trim();
    final items = [
      for (final p in payments)
        if (picked.contains(p['id']))
          {'payment_id': p['id'], 'amount': num.tryParse(amounts[p['id']]!.text.trim()) ?? 0},
    ];
    reference.dispose();
    note.dispose();
    person.dispose();
    for (final c in amounts.values) {
      c.dispose();
    }
    if (go != true) return;
    setState(() => _busy = true);
    try {
      await Services.outbox.submit('/api/v1/handovers', {
        'uuid': const Uuid().v4(),
        'distributor_id': distributor['id'],
        'items': items,
        'mode_id': mode,
        'reference': ref,
        'note': memo,
        'received_by': who,
        'date': when.toUtc().toIso8601String(),
      });
      settleAndRefresh();
      if (mounted) showSnack(context, 'Handed over to ${distributor['name']}');
    } catch (e) {
      if (mounted) showProblem(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _plain(num v) => v == v.roundToDouble() ? '${v.toInt()}' : v.toStringAsFixed(2);

  /// One outlet collection: tick it, see what was collected and what was already given, change today's part.
  Widget _paymentRow(Map<String, dynamic> p, Set<int> picked, TextEditingController amount, StateSetter setSheet) {
    final currency = p['currency'] as String?;
    final total = p['amount'] as num;
    final handed = (p['handed'] as num?) ?? 0;
    final held = (p['held'] as num?) ?? total;
    final parts = ((p['parts'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final on = picked.contains(p['id']);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: on ? AppColors.primary.withValues(alpha: 0.05) : Colors.white,
        border: Border.all(color: on ? AppColors.primary.withValues(alpha: 0.4) : AppColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Checkbox(
            value: on,
            visualDensity: VisualDensity.compact,
            onChanged: (v) => setSheet(() => v == true ? picked.add(p['id'] as int) : picked.remove(p['id'])),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${(p['outlet'] as Map)['name']}', style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(
                [
                  'Collected ${fmtMoney(total, currency)}',
                  fmtTime(p['date']),
                  if (asText(p['mode']) != null) '${p['mode']}',
                ].join(' · '),
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ]),
          ),
        ]),
        Padding(
          padding: const EdgeInsets.only(left: 12, top: 4),
          child: Wrap(spacing: 8, runSpacing: 4, children: [
            _chip('Given before ${fmtMoney(handed, currency)}', AppColors.success),
            _chip('Still with you ${fmtMoney(held, currency)}', AppColors.warning),
          ]),
        ),
        for (final part in parts)
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 3),
            child: Text(
              '${fmtMoney(part['amount'] as num?, currency)} on ${fmtTime(part['date'])} (${part['handover']}, ${part['state']})',
              style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
            ),
          ),
        if (on)
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 8),
            child: TextField(
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setSheet(() {}),
              decoration: InputDecoration(
                labelText: 'Giving now',
                isDense: true,
                helperText: 'Up to ${fmtMoney(held, currency)}',
              ),
            ),
          ),
      ]),
    );
  }

  Widget _chip(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
        child: Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
      );

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final forOffice = (data?['pending'] as Map<String, dynamic>?)?['amount'] as num? ?? 0;
    final forDistributors = _toDistributors['amount'] as num? ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Collections'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [Tab(text: 'Office'), Tab(text: 'Distributors'), Tab(text: 'History')],
        ),
      ),
      body: _loading
          ? const LoadingView()
          : _error != null && data == null
              ? ErrorView(message: _error!, onRetry: _load)
              : Column(
                  children: [
                    _holdingBar(forOffice, forDistributors),
                    Expanded(
                      child: TabBarView(
                        controller: _tabs,
                        children: [_officeTab(data), _distributorsTab(), _historyTab(data)],
                      ),
                    ),
                  ],
                ),
    );
  }

  /// The two amounts at a glance, each one opening its own tab.
  Widget _holdingBar(num office, num distributors) {
    Widget tile(String label, String sub, num amount, IconData icon, Color color, int tab) => Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _tabs.animateTo(tab),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: color.withValues(alpha: 0.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(icon, size: 18, color: color),
                    const SizedBox(width: 6),
                    Expanded(child: Text(label, style: TextStyle(fontWeight: FontWeight.w700, color: color))),
                  ]),
                  const SizedBox(height: 6),
                  Text(fmtMoney(amount, _currency), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  if (sub.isNotEmpty) Text(sub, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                ],
              ),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(children: [
        tile('For the office', '', office, Icons.apartment_rounded, AppColors.primary, 0),
        const SizedBox(width: 10),
        tile('For distributors', '', distributors, Icons.local_shipping_rounded, AppColors.warning, 1),
      ]),
    );
  }

  Widget _officeTab(Map<String, dynamic>? data) {
    final pending = data?['pending'] as Map<String, dynamic>? ?? const {};
    final count = pending['count'] as int? ?? 0;
    final blocked = pending['blocked'] == true;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (count == 0)
            const SectionCard(
              title: 'Nothing to submit',
              child: Text('All distributor money you collected has reached the office.',
                  style: TextStyle(color: AppColors.muted)),
            )
          else
            Card(
              color: (blocked ? AppColors.danger : AppColors.warning).withValues(alpha: 0.10),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(blocked ? Icons.block_rounded : Icons.account_balance_wallet_rounded,
                          color: blocked ? AppColors.danger : AppColors.warning),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text('With you: ${fmtMoney(pending['amount'] as num?, _currency)}',
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      ),
                      Text('$count items', style: const TextStyle(color: AppColors.muted)),
                    ]),
                    const SizedBox(height: 8),
                    Text(blocked
                        ? (pending['over_amount'] == true
                            ? 'You hold more than the allowed limit. Submit it to the office — check-in is blocked until then.'
                            : 'You have held this money for too many days. Submit it to the office — check-in is blocked until then.')
                        : 'Submit this to the office to keep your check-ins working.'),
                    const SizedBox(height: 12),
                    GradientButton(
                      label: 'Submit to Office',
                      icon: Icons.upload_rounded,
                      busy: _busy,
                      onPressed: _busy ? null : () => _submitDeposit(pending),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'My deposits',
            child: Column(children: [
              for (final d in _deposits)
                _moneyTile(
                  title: '${d['name']}',
                  subtitle: '${d['count']} collections · ${fmtTime(d['submitted_at'])}',
                  amount: d['amount'] as num?,
                  currency: d['currency'] as String?,
                  state: '${d['state']}',
                ),
              if (_deposits.isEmpty) const _Empty('No deposits yet.'),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _distributorsTab() {
    final groups = ((_toDistributors['groups'] as List?) ?? const []).cast<Map<String, dynamic>>();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (groups.isEmpty)
            const SectionCard(
              title: 'Nothing to hand over',
              child: Text('You hold no outlet money for any distributor.', style: TextStyle(color: AppColors.muted)),
            ),
          for (final g in groups) _distributorCard(g),
          const SizedBox(height: 4),
          SectionCard(
            title: 'My handovers',
            child: Column(children: [
              for (final h in _handovers)
                _moneyTile(
                  title: '${h['name']} · ${(h['distributor'] as Map)['name']}',
                  subtitle: [
                    '${h['count']} collections',
                    fmtTime(h['date']),
                    if (asText(h['received_by']) != null) 'taken by ${h['received_by']}',
                  ].join(' · '),
                  amount: h['amount'] as num?,
                  currency: h['currency'] as String?,
                  state: '${h['state']}',
                ),
              if (_handovers.isEmpty) const _Empty('No handovers yet.'),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _distributorCard(Map<String, dynamic> g) {
    final distributor = g['distributor'] as Map<String, dynamic>;
    final payments = (g['payments'] as List).cast<Map<String, dynamic>>();
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const CircleAvatar(
                  backgroundColor: Color(0x1FF59E0B),
                  child: Icon(Icons.local_shipping_rounded, color: AppColors.warning)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${distributor['name']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  Text('${g['count']} outlet collections · since ${fmtTime(g['oldest_date'])}',
                      style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                ]),
              ),
              Text(fmtMoney(g['amount'] as num?, g['currency'] as String?),
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            ]),
            const SizedBox(height: 8),
            for (final p in payments.take(4))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [
                  const Icon(Icons.storefront_rounded, size: 14, color: AppColors.muted),
                  const SizedBox(width: 6),
                  Expanded(child: Text('${(p['outlet'] as Map)['name']}', overflow: TextOverflow.ellipsis)),
                  Text(fmtMoney((p['held'] ?? p['amount']) as num?, p['currency'] as String?)),
                ]),
              ),
            if (payments.length > 4)
              Text('+ ${payments.length - 4} more', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            const SizedBox(height: 12),
            GradientButton(
              label: 'Hand over to ${distributor['name']}',
              icon: Icons.handshake_rounded,
              busy: _busy,
              onPressed: _busy ? null : () => _handOver(g),
            ),
          ],
        ),
      ),
    );
  }

  Widget _historyTab(Map<String, dynamic>? data) {
    final rows = ((data?['collections'] as List?) ?? const []).cast<Map<String, dynamic>>();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionCard(
            title: 'Collected this month',
            action: Text(fmtMoney(data?['total_amount'] as num?, _currency),
                style: const TextStyle(fontWeight: FontWeight.w800)),
            child: Column(children: [
              for (final c in rows)
                _moneyTile(
                  title: '${c['contact']?['name'] ?? '-'}',
                  subtitle: [
                    '${c['mode']?['name'] ?? ''}',
                    if (asText(c['reference']) != null) '${c['reference']}',
                    fmtTime(c['date']),
                  ].join(' · '),
                  amount: c['amount'] as num?,
                  currency: c['currency'] as String?,
                  state: '${c['state']}',
                ),
              if (rows.isEmpty) const _Empty('Nothing collected yet this month.'),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _moneyTile({
    required String title,
    required String subtitle,
    required num? amount,
    required String? currency,
    required String state,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(fmtMoney(amount, currency), style: const TextStyle(fontWeight: FontWeight.w700)),
          StatusBadge(state),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(text, style: const TextStyle(color: AppColors.muted)),
      );
}

/// A date to change; today unless the handover happened earlier.
class _DateField extends StatelessWidget {
  const _DateField({required this.value, required this.onChanged});

  final DateTime value;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: value,
          firstDate: now.subtract(const Duration(days: 90)),
          lastDate: now,
        );
        if (picked != null) {
          onChanged(DateTime(picked.year, picked.month, picked.day, now.hour, now.minute));
        }
      },
      child: InputDecorator(
        decoration: const InputDecoration(labelText: 'Date given', prefixIcon: Icon(Icons.event_rounded)),
        child: Text('${value.day.toString().padLeft(2, '0')}-${value.month.toString().padLeft(2, '0')}-${value.year}'),
      ),
    );
  }
}
