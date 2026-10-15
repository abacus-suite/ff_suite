import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/skeleton.dart';
import 'demand_send.dart';
import 'distributor_submit.dart';

/// The orders raised from demand: one per send, addressed to a distributor.
///
/// This is where the summary is fetched from afterwards - a distributor asks
/// for it again, or the first message never arrived - so every order keeps its
/// share button for as long as it exists. Search it, filter it by where it has got
/// to, group it by distributor, and it keeps itself up to date.
class DistributorOrdersScreen extends StatefulWidget {
  const DistributorOrdersScreen({super.key});

  @override
  State<DistributorOrdersScreen> createState() => _DistributorOrdersScreenState();
}

class _DistributorOrdersScreenState extends State<DistributorOrdersScreen> with WidgetsBindingObserver {
  List<Map<String, dynamic>> _orders = [];
  bool _loading = true;
  String? _error;
  final _search = TextEditingController();
  String _status = 'all';
  String _sort = 'latest';
  bool _byDistributor = false;
  String _distributor = 'all';
  DateTimeRange? _range;
  Timer? _poll;
  final Set<String> _collapsed = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Services.refresh.addListener(_quiet);
    _load();
    // New answers from distributors arrive while this is open.
    _poll = Timer.periodic(const Duration(seconds: 45), (_) => _quiet());
  }

  @override
  void dispose() {
    _poll?.cancel();
    Services.refresh.removeListener(_quiet);
    WidgetsBinding.instance.removeObserver(this);
    _search.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _quiet();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    await _fetch();
    if (mounted) setState(() => _loading = false);
  }

  /// A refresh that does not blank the screen.
  Future<void> _quiet() async {
    if (!mounted) return;
    await _fetch();
  }

  Future<void> _fetch() async {
    try {
      final list = (await Services.api.get('/api/v1/orders', query: {'limit': 300}) as List).cast<Map<String, dynamic>>();
      if (mounted) {
        setState(() {
          _orders = list;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && _orders.isEmpty) setState(() => _error = e.toString());
    }
  }

  // ------------------------------------------------------------------ state of an order
  bool _confirmed(Map<String, dynamic> o) => o['state'] == 'sale' || o['state'] == 'done';
  bool _turnedDown(Map<String, dynamic> o) => o['distributor_status'] == 'rejected' || o['state'] == 'cancel';
  String _stage(Map<String, dynamic> o) => _turnedDown(o) ? 'turned' : (_confirmed(o) ? 'confirmed' : 'waiting');
  String _who(Map<String, dynamic> o) => '${((o['distributor'] as Map?) ?? (o['client'] as Map?))?['name'] ?? ''}';

  List<Map<String, dynamic>> get _shown {
    final q = _search.text.trim().toLowerCase();
    final rows = _orders.where((o) {
      if (_status != 'all' && _stage(o) != _status) return false;
      if (_distributor != 'all' && _who(o) != _distributor) return false;
      final d = parseServerTime(o['date']);
      if (_range != null && d != null) {
        final day = DateUtils.dateOnly(d.toLocal());
        if (day.isBefore(_range!.start) || day.isAfter(_range!.end)) return false;
      }
      if (q.isEmpty) return true;
      final hay = [
        o['name'], _who(o), o['origin'], o['state_label'], o['distributor_note'],
        ((o['products'] as List?) ?? []).map((p) => (p as Map)['name']).join(' '),
        ((o['amount_total'] as num?) ?? 0).toStringAsFixed(0),
      ].join(' ').toLowerCase();
      return hay.contains(q);
    }).toList();
    switch (_sort) {
      case 'amount':
        rows.sort((a, b) => ((b['amount_total'] as num?) ?? 0).compareTo((a['amount_total'] as num?) ?? 0));
      case 'distributor':
        rows.sort((a, b) => _who(a).toLowerCase().compareTo(_who(b).toLowerCase()));
      default:
        rows.sort((a, b) => '${b['date']}'.compareTo('${a['date']}'));
    }
    return rows;
  }

  int _count(String stage) => _orders.where((o) => _stage(o) == stage).length;

  Color _tone(String stage) => switch (stage) {
        'confirmed' => AppColors.success,
        'turned' => AppColors.danger,
        _ => AppColors.warning,
      };

  // ------------------------------------------------------------------ actions
  /// A turned-down order goes out again, to the same distributor or another.
  Future<void> _resend(Map<String, dynamic> o) async {
    final picked = await pickDistributor(context, demandCount: 1);
    if (picked == null || !mounted) return;
    try {
      final result = await withBusyDialog(() => Services.api.post('/api/v1/orders/${o['id']}/resend', {
            'distributor_id': picked['id'],
          }));
      if (!mounted) return;
      await _load();
      if (mounted) await showSubmittedSheet(context, result as Map<String, dynamic>);
    } catch (e) {
      if (mounted) showProblem(context, e.toString());
    }
  }

  Future<T> withBusyDialog<T>(Future<T> Function() work) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(canPop: false, child: Center(child: _Spinner())),
    );
    try {
      return await work();
    } finally {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    }
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now,
      initialDateRange: _range,
    );
    if (r != null) setState(() => _range = r);
  }

  // ------------------------------------------------------------------ pieces
  Widget _stat(String label, int n, Color tint, String stage) {
    final on = _status == stage;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _status = on ? 'all' : stage),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 12),
          decoration: BoxDecoration(
            color: on ? tint : Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: tint.withValues(alpha: on ? 0.3 : 0.08), blurRadius: 14, offset: const Offset(0, 5))],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$n', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22, color: on ? Colors.white : tint)),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: on ? Colors.white70 : AppColors.muted)),
          ]),
        ),
      ),
    );
  }

  Widget _searchBar() => Container(
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: const Color(0xFF1B3A7A).withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search_rounded, color: AppColors.muted),
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => setState(_search.clear),
                  ),
            hintText: 'Search order, distributor, product or reason',
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 15),
          ),
        ),
      );

  Widget _chip(String label, bool on, VoidCallback tap, {IconData? icon}) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
          onTap: tap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
            decoration: BoxDecoration(
              color: on ? AppColors.primary : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: on ? AppColors.primary : AppColors.border),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[Icon(icon, size: 15, color: on ? Colors.white : AppColors.muted), const SizedBox(width: 5)],
              Text(label,
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: on ? Colors.white : AppColors.text)),
            ]),
          ),
        ),
      );

  Widget _filters() {
    final names = {for (final o in _orders) _who(o)}.where((n) => n.isNotEmpty).toList()..sort();
    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _chip(_range == null ? 'Any date' : '${fmtDate(_range!.start)} - ${fmtDate(_range!.end)}', _range != null, _pickRange,
              icon: Icons.date_range_rounded),
          if (_range != null)
            _chip('Clear date', false, () => setState(() => _range = null), icon: Icons.close_rounded),
          _chip('Group by distributor', _byDistributor, () => setState(() => _byDistributor = !_byDistributor),
              icon: Icons.local_shipping_rounded),
          for (final entry in const [('latest', 'Latest'), ('amount', 'Biggest'), ('distributor', 'Distributor A-Z')])
            _chip(entry.$2, _sort == entry.$1, () => setState(() => _sort = entry.$1), icon: Icons.sort_rounded),
          if (names.length > 1)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Container(
                padding: const EdgeInsets.only(left: 12, right: 4),
                decoration: BoxDecoration(
                    color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.border)),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _distributor,
                    isDense: true,
                    borderRadius: BorderRadius.circular(14),
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: AppColors.text),
                    items: [
                      const DropdownMenuItem(value: 'all', child: Text('All distributors')),
                      for (final n in names) DropdownMenuItem(value: n, child: Text(n, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) => setState(() => _distributor = v ?? 'all'),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _summary() {
    final value = _orders.where((o) => !_turnedDown(o)).fold<double>(0, (s, o) => s + ((o['amount_total'] as num?) ?? 0));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Column(children: [
        Row(children: [
          _stat('With distributor', _count('waiting'), AppColors.warning, 'waiting'),
          const SizedBox(width: 10),
          _stat('Confirmed', _count('confirmed'), AppColors.success, 'confirmed'),
          const SizedBox(width: 10),
          _stat('Rejected', _count('turned'), AppColors.danger, 'turned'),
        ]),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: Text('${_orders.length} orders  ·  ${fmtMoney(value, null)} excluding rejected',
              style: const TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }

  Widget _card(Map<String, dynamic> o) {
    final date = parseServerTime(o['date']);
    final stage = _stage(o);
    final tone = _tone(stage);
    final confirmed = stage == 'confirmed';
    final turnedDown = stage == 'turned';
    final reason = asText(o['distributor_note']);
    final link = asText(o['portal_link']);
    final units = (o['quantity_total'] as num?);
    final products = ((o['products'] as List?) ?? []).cast<Map>();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [BoxShadow(color: const Color(0xFF1B3A7A).withValues(alpha: 0.07), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: 6, color: tone),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${o['name']}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                        const SizedBox(height: 2),
                        Row(children: [
                          const Icon(Icons.local_shipping_rounded, size: 14, color: AppColors.muted),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(_who(o),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13, color: AppColors.muted, fontWeight: FontWeight.w600)),
                          ),
                        ]),
                      ]),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(color: tone.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(
                            turnedDown
                                ? Icons.cancel_rounded
                                : confirmed
                                    ? Icons.check_circle_rounded
                                    : Icons.hourglass_top_rounded,
                            size: 14,
                            color: tone),
                        const SizedBox(width: 4),
                        Text(turnedDown ? 'Rejected' : confirmed ? 'Confirmed' : 'With distributor',
                            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: tone)),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 6, children: [
                    _meta(Icons.calendar_today_rounded, date == null ? '' : fmtDate(date)),
                    _meta(Icons.inventory_2_rounded, '${o['line_count']} products${units != null ? ' · ${fmtQty(units)} units' : ''}'),
                    _meta(Icons.payments_rounded, fmtMoney(o['amount_total'] as num?, o['currency'] as String?), strong: true),
                  ]),
                  if (products.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      products.take(3).map((p) => '${p['name']} × ${fmtQty((p['qty'] as num?) ?? 0)}').join('   ·   ') +
                          (products.length > 3 ? '   +${products.length - 3} more' : ''),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: AppColors.muted, height: 1.3),
                    ),
                  ],
                  if (turnedDown && reason != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(12)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${_who(o)} turned it down',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.danger)),
                        const SizedBox(height: 3),
                        Text(reason, style: const TextStyle(fontSize: 12.5)),
                      ]),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(children: [
                    if (turnedDown)
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => _resend(o),
                          icon: const Icon(Icons.send_rounded, size: 17),
                          label: const Text('Send again'),
                        ),
                      )
                    else ...[
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => shareOrderSummary(context, o['id'] as int, '${o['name']}'),
                          icon: const Icon(Icons.ios_share_rounded, size: 17),
                          label: const Text('Summary'),
                        ),
                      ),
                      if (link != null && !confirmed) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => openWhatsApp(null,
                                'Hello, order ${o['name']} is ready for you. Please review it and accept here: $link'),
                            icon: const Icon(Icons.chat_rounded, size: 17),
                            label: const Text('WhatsApp'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.outlined(
                          tooltip: 'Copy link',
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: link));
                            if (context.mounted) showSnack(context, 'Link copied');
                          },
                          icon: const Icon(Icons.link_rounded, size: 18),
                        ),
                      ],
                    ],
                  ]),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _meta(IconData icon, String text, {bool strong = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(10)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: AppColors.muted),
          const SizedBox(width: 5),
          Text(text,
              style: TextStyle(
                  fontSize: 12, fontWeight: strong ? FontWeight.w900 : FontWeight.w600, color: strong ? AppColors.text : AppColors.muted)),
        ]),
      );

  Widget _groupHeader(String name, List<Map<String, dynamic>> rows) {
    final value = rows.fold<double>(0, (s, o) => s + ((o['amount_total'] as num?) ?? 0));
    final open = !_collapsed.contains(name);
    return GestureDetector(
      onTap: () => setState(() => open ? _collapsed.add(name) : _collapsed.remove(name)),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10, top: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          const Icon(Icons.local_shipping_rounded, size: 18, color: AppColors.primary),
          const SizedBox(width: 9),
          Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5))),
          Text('${rows.length} · ${fmtMoney(value, null)}',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: AppColors.primary)),
          const SizedBox(width: 6),
          Icon(open ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, color: AppColors.primary),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = _shown;
    final groups = <String, List<Map<String, dynamic>>>{};
    if (_byDistributor) {
      for (final o in rows) {
        groups.putIfAbsent(_who(o), () => []).add(o);
      }
    }
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Distributor Orders', style: TextStyle(fontWeight: FontWeight.w900)),
        centerTitle: false,
        actions: [IconButton(tooltip: 'Refresh', onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: _loading && _orders.isEmpty
          ? const LoadingView()
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 28),
                    children: [
                      if (_loading) const LoadingBar(),
                      _summary(),
                      _searchBar(),
                      _filters(),
                      const SizedBox(height: 10),
                      if (rows.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 50),
                          child: EmptyView(
                              icon: Icons.local_shipping_outlined,
                              text: _orders.isEmpty ? 'No orders sent to a distributor yet' : 'No orders match your search'),
                        )
                      else if (_byDistributor)
                        for (final entry in groups.entries) ...[
                          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: _groupHeader(entry.key, entry.value)),
                          if (!_collapsed.contains(entry.key))
                            for (final o in entry.value) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: _card(o)),
                        ]
                      else
                        for (final o in rows) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: _card(o)),
                    ],
                  ),
                ),
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
        child: const SizedBox(width: 30, height: 30, child: CircularProgressIndicator(strokeWidth: 3)),
      );
}
