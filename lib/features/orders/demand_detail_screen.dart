import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/group_kit.dart';
import 'demand_send.dart';
import 'distributor_submit.dart';
import '../../widgets/skeleton.dart';

/// One demand in full: the outlet, who supplies it, where it has got to, every
/// line with its price, tax and discount, and the orders it went into.
class DemandDetailScreen extends StatefulWidget {
  const DemandDetailScreen({super.key, required this.id, this.canSend = false});

  final int id;
  final bool canSend;

  @override
  State<DemandDetailScreen> createState() => _DemandDetailScreenState();
}

class _DemandDetailScreenState extends State<DemandDetailScreen> {
  Map<String, dynamic>? _d;
  String? _error;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await Services.api.get('/api/v1/demands/${widget.id}') as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _d = d;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  List<Map<String, dynamic>> get _lines => ((_d?['lines'] as List?) ?? []).cast<Map<String, dynamic>>();
  List<Map<String, dynamic>> get _orders => ((_d?['orders'] as List?) ?? []).cast<Map<String, dynamic>>();

  BoxDecoration get _card => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [BoxShadow(color: const Color(0xFF1B3A7A).withValues(alpha: 0.06), blurRadius: 16, offset: const Offset(0, 6))],
      );

  Color _tone(String s) => switch (s) {
        'supplied' || 'approved' => AppColors.success,
        'cancelled' || 'rejected' => AppColors.danger,
        'quoted' || 'partial' || 'waiting' => AppColors.warning,
        _ => AppColors.primary,
      };

  Future<void> _send() async {
    final done = await sendDemands(context, [_d!]);
    if (done) {
      _changed = true;
      await _load();
    }
  }

  Future<void> _resendDemand() async {
    final dist = await pickDistributor(context, demandCount: 1);
    if (dist == null || !mounted) return;
    try {
      final result = await Services.api.post('/api/v1/demands/${_d!['id']}/resend', {'distributor_id': dist['id']})
          as Map<String, dynamic>;
      _changed = true;
      await _load();
      if (mounted) await showSubmittedSheet(context, result);
    } catch (e) {
      if (mounted) await showProblem(context, e.toString());
    }
  }

  Future<void> _resend(Map<String, dynamic> order) async {
    final dist = await pickDistributor(context, demandCount: 1);
    if (dist == null || !mounted) return;
    try {
      final result = await Services.api.post('/api/v1/orders/${order['id']}/resend', {'distributor_id': dist['id']})
          as Map<String, dynamic>;
      _changed = true;
      await _load();
      if (mounted) await showSubmittedSheet(context, result);
    } catch (e) {
      if (mounted) await showProblem(context, e.toString());
    }
  }

  Widget _section(String title, Widget child, {Widget? trailing}) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: _card,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15.5))),
            if (trailing != null) trailing,
          ]),
          const SizedBox(height: 12),
          child,
        ]),
      );

  Widget _hero(Map<String, dynamic> d) {
    final tone = _tone('${d['state']}');
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          colors: [tone, tone.withValues(alpha: 0.72)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [BoxShadow(color: tone.withValues(alpha: 0.3), blurRadius: 22, offset: const Offset(0, 10))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text('${d['name']}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 20)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(20)),
            child: Text('${d['state_label']}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
          ),
        ]),
        const SizedBox(height: 6),
        Text('${(d['client'] as Map?)?['name'] ?? ''}',
            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 14),
        Text(fmtMoney(d['amount_total'] as num?, d['currency'] as String?),
            style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w900, height: 1)),
        const SizedBox(height: 4),
        Text(
          [
            if (parseServerTime(d['date']) != null) prettyDay(parseServerTime(d['date'])!),
            if ((d['employee'] as Map?)?['name'] != null) '${(d['employee'] as Map)['name']}',
            if ((d['route'] as Map?)?['name'] != null) '${(d['route'] as Map)['name']}',
          ].join('  ·  '),
          style: const TextStyle(color: Colors.white70, fontSize: 12.5),
        ),
      ]),
    );
  }

  Widget _distributor(Map<String, dynamic> d) {
    final dist = (d['distributor'] as Map?)?.cast<String, dynamic>();
    final mapped = dist != null;
    final tint = mapped ? AppColors.success : AppColors.warning;
    return _section(
      'Distributor',
      Row(children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(color: tint.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(15)),
          child: Icon(mapped ? Icons.local_shipping_rounded : Icons.link_off_rounded, color: tint),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(mapped ? '${dist['name']}' : 'No distributor linked',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            Text(
                mapped
                    ? 'Linked to this outlet. The order goes to them unless you choose another.'
                    : 'You pick one when you send this on, and it is added to the demand.',
                style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          ]),
        ),
      ]),
    );
  }

  /// Raised → sent → accepted → supplied, and what happened to free goods.
  Widget _timeline(Map<String, dynamic> d) {
    final state = '${d['state']}';
    final request = (d['request'] as Map?)?.cast<String, dynamic>();
    if (request != null) return _requestTimeline(d, request);
    final orders = _orders;
    final sent = orders.isNotEmpty || state == 'quoted' || state == 'partial' || state == 'supplied';
    final accepted = orders.any((o) => o['state'] == 'sale' || o['state'] == 'done') || state == 'supplied';
    final turnedDown = orders.where((o) => o['distributor_status'] == 'rejected' || o['state'] == 'cancel').toList();
    final steps = <(String, String, bool, Color?)>[
      ('Demand raised', prettyDay(parseServerTime(d['date']) ?? DateTime.now()), true, null),
      ('Sent to distributor', sent ? '${orders.isNotEmpty ? orders.first['name'] : ''}' : 'Not sent yet', sent, null),
      if (turnedDown.isNotEmpty && !accepted)
        ('Rejected', '${turnedDown.first['distributor_note'] ?? 'No reason given'}', true, AppColors.danger),
      ('Distributor accepted', accepted ? 'Order confirmed' : 'Waiting', accepted, null),
      ('Supplied', state == 'supplied' ? 'Delivered' : '', state == 'supplied', null),
    ];
    return _section(
      'Progress',
      Column(children: [
        for (var i = 0; i < steps.length; i++)
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Column(children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: steps[i].$3 ? (steps[i].$4 ?? AppColors.success) : AppColors.border,
                  ),
                  child: Icon(steps[i].$4 != null ? Icons.close_rounded : Icons.check_rounded,
                      size: 15, color: steps[i].$3 ? Colors.white : Colors.transparent),
                ),
                if (i < steps.length - 1)
                  Expanded(child: Container(width: 2, color: steps[i].$3 ? AppColors.success.withValues(alpha: 0.4) : AppColors.border)),
              ]),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(steps[i].$1,
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: steps[i].$3 ? (steps[i].$4 ?? AppColors.text) : AppColors.muted)),
                    if (steps[i].$2.isNotEmpty)
                      Text(steps[i].$2, style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
                  ]),
                ),
              ),
            ]),
          ),
      ]),
    );
  }

  /// Raised -> sent -> approved -> delivery, for a demand that went to the distributor as a request.
  Widget _requestTimeline(Map<String, dynamic> d, Map<String, dynamic> request) {
    final state = '${d['state']}';
    final rejected = state == 'rejected';
    final approved = state == 'approved' || state == 'supplied';
    final approvedQty = (d['approved_qty'] as num?) ?? 0;
    final deliveredQty = (d['delivered_qty'] as num?) ?? 0;
    final steps = <(String, String, bool, Color?)>[
      ('Demand raised', prettyDay(parseServerTime(d['date']) ?? DateTime.now()), true, null),
      ('Sent to distributor', '${request['name']}', true, null),
      if (rejected) ('Rejected', '${d['reject_note'] ?? 'No reason given'}', true, AppColors.danger),
      if (!rejected) ('Distributor approved', approved ? 'Approved ${fmtQty(approvedQty)} units' : 'Waiting', approved, null),
      if (!rejected)
        (
          '${d['delivery_status'] ?? 'Delivery'}',
          approved ? '${fmtQty(deliveredQty)} of ${fmtQty(approvedQty)} units delivered' : '',
          state == 'supplied',
          null
        ),
    ];
    return _section('Progress', _stepList(steps));
  }

  Widget _stepList(List<(String, String, bool, Color?)> steps) => Column(children: [
        for (var i = 0; i < steps.length; i++)
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Column(children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: steps[i].$3 ? (steps[i].$4 ?? AppColors.success) : AppColors.border,
                  ),
                  child: Icon(steps[i].$4 != null ? Icons.close_rounded : Icons.check_rounded,
                      size: 15, color: steps[i].$3 ? Colors.white : Colors.transparent),
                ),
                if (i < steps.length - 1)
                  Expanded(
                      child: Container(
                          width: 2, color: steps[i].$3 ? AppColors.success.withValues(alpha: 0.4) : AppColors.border)),
              ]),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(steps[i].$1,
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: steps[i].$3 ? (steps[i].$4 ?? AppColors.text) : AppColors.muted)),
                    if (steps[i].$2.isNotEmpty)
                      Text(steps[i].$2, style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
                  ]),
                ),
              ),
            ]),
          ),
      ]);

  /// The link the distributor uses, while the demand waits for them, and the way to send it on again.
  Widget _requestCard(Map<String, dynamic> d) {
    final request = (d['request'] as Map?)?.cast<String, dynamic>();
    if (request == null) return const SizedBox.shrink();
    final state = '${d['state']}';
    final link = request['portal_link'] as String?;
    final dist = (d['distributor'] as Map?)?['name'];
    final rejected = state == 'rejected';
    final waiting = state == 'waiting';
    final tone = rejected ? AppColors.danger : waiting ? AppColors.warning : AppColors.success;
    return _section(
      'Distributor request',
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: tone.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('${request['name']}', style: const TextStyle(fontWeight: FontWeight.w900))),
            Text(
                rejected
                    ? 'Rejected'
                    : waiting
                        ? 'Waiting for approval'
                        : 'Approved',
                style: TextStyle(color: tone, fontWeight: FontWeight.w800, fontSize: 12)),
          ]),
          if (dist != null) Text('To $dist', style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
          if (rejected && d['reject_note'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Reason: ${d['reject_note']}', style: const TextStyle(color: AppColors.danger, fontSize: 12.5)),
            ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, children: [
            if (link != null && waiting) ...[
              OutlinedButton.icon(
                onPressed: () => openWhatsApp((d['distributor'] as Map?)?['phone'] as String?,
                    'Hello $dist, demand ${request['name']} is ready for you. Please review and approve it here: $link'),
                icon: const Icon(Icons.chat_rounded, size: 16),
                label: const Text('WhatsApp link'),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: link));
                  if (mounted) showSnack(context, 'Link copied');
                },
                icon: const Icon(Icons.link_rounded, size: 16),
                label: const Text('Copy link'),
              ),
            ],
            if (rejected)
              FilledButton.icon(
                onPressed: _resendDemand,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Send again'),
              ),
          ]),
        ]),
      ),
    );
  }

  /// What reached the outlet, delivery by delivery. This is what the outlet is billed for.
  Widget _deliveries(Map<String, dynamic> d) {
    final rows = ((d['deliveries'] as List?) ?? []).cast<Map<String, dynamic>>();
    if (rows.isEmpty) return const SizedBox.shrink();
    final currency = d['currency'] as String?;
    return _section(
      'Deliveries',
      Column(children: [
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.local_shipping_rounded, size: 18, color: AppColors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${r['name']} · ${fmtTime(r['date'])}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text(
                      [for (final l in (r['lines'] as List).cast<Map<String, dynamic>>()) '${l['product']} × ${fmtQty(l['qty'] as num)}']
                          .join(', '),
                      style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
                ]),
              ),
              Text(fmtMoney(r['amount'] as num?, currency), style: const TextStyle(fontWeight: FontWeight.w900)),
            ]),
          ),
        const Divider(height: 20),
        Row(children: [
          const Expanded(child: Text('Billed to the outlet', style: TextStyle(fontWeight: FontWeight.w800))),
          Text(fmtMoney(d['delivered_amount'] as num?, currency),
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        ]),
      ]),
    );
  }

  Widget _line(Map<String, dynamic> l, String? currency) {
    final free = l['foc'] == true;
    final tax = (l['tax_percent'] as num?) ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
              color: (free ? AppColors.success : AppColors.primary).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
          child: Icon(free ? Icons.redeem_rounded : Icons.inventory_2_rounded,
              size: 19, color: free ? AppColors.success : AppColors.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${(l['product'] as Map)['name']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            const SizedBox(height: 2),
            Text(
              '${fmtQty(l['qty'] as num)}${l['uom'] != null ? ' ${l['uom']}' : ''} × ${fmtMoney(l['price_unit'] as num?, currency)}'
              '${free ? '  ·  Free (100% off)' : ''}'
              '${!free && ((l['discount'] as num?) ?? 0) > 0 ? '  ·  ${l['discount']}% off' : ''}'
              '${tax > 0 && !free ? '  ·  +${fmtQty(tax)}% tax' : ''}',
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
            if (((l['approved_qty'] as num?) ?? 0) > 0)
              Text('Approved ${fmtQty(l['approved_qty'] as num)} · Delivered ${fmtQty((l['delivered_qty'] as num?) ?? 0)}',
                  style: const TextStyle(fontSize: 11.5, color: AppColors.primary, fontWeight: FontWeight.w700)),
            if (((l['quoted_qty'] as num?) ?? 0) > 0)
              Text('${fmtQty(l['quoted_qty'] as num)} ordered from the distributor',
                  style: const TextStyle(fontSize: 11.5, color: AppColors.primary, fontWeight: FontWeight.w700)),
            if (free && l['foc_note'] != null)
              Text('${l['foc_note']}', style: const TextStyle(fontSize: 11.5, color: AppColors.success)),
          ]),
        ),
        Text(fmtMoney(l['subtotal'] as num?, currency), style: const TextStyle(fontWeight: FontWeight.w900)),
      ]),
    );
  }

  Widget _totals(Map<String, dynamic> d) {
    final currency = d['currency'] as String?;
    Widget row(String label, num? v, {bool strong = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Expanded(child: Text(label, style: TextStyle(fontWeight: strong ? FontWeight.w900 : FontWeight.w600, color: strong ? AppColors.text : AppColors.muted))),
            Text(fmtMoney(v, currency), style: TextStyle(fontWeight: FontWeight.w900, fontSize: strong ? 18 : 14)),
          ]),
        );
    return Column(children: [
      const Divider(height: 22),
      row('Untaxed', d['amount_untaxed'] as num?),
      row('Taxes', d['amount_tax'] as num?),
      row('Total', d['amount_total'] as num?, strong: true),
    ]);
  }

  Widget _order(Map<String, dynamic> o) {
    final status = '${o['distributor_status'] ?? ''}';
    final turned = status == 'rejected' || o['state'] == 'cancel';
    final confirmed = o['state'] == 'sale' || o['state'] == 'done';
    final tone = turned ? AppColors.danger : confirmed ? AppColors.success : AppColors.warning;
    final label = turned ? 'Rejected' : confirmed ? 'Accepted' : 'Waiting for the distributor';
    final link = o['portal_link'] as String?;
    final dist = (o['distributor'] as Map?)?['name'] ?? (_d?['distributor'] as Map?)?['name'];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: tone.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('${o['name']}', style: const TextStyle(fontWeight: FontWeight.w900))),
          Text(label, style: TextStyle(color: tone, fontWeight: FontWeight.w800, fontSize: 12)),
        ]),
        if (dist != null) Text('To $dist', style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
        if (turned && o['distributor_note'] != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Reason: ${o['distributor_note']}', style: const TextStyle(color: AppColors.danger, fontSize: 12.5)),
          ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 4, children: [
          if (link != null && !confirmed && !turned) ...[
            OutlinedButton.icon(
              onPressed: () => openWhatsApp(
                  (_d?['distributor'] as Map?)?['phone'] as String?,
                  'Hello $dist, order ${o['name']} is ready for you. Please review it and accept here: $link'),
              icon: const Icon(Icons.chat_rounded, size: 16),
              label: const Text('WhatsApp link'),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: link));
                if (mounted) showSnack(context, 'Link copied');
              },
              icon: const Icon(Icons.link_rounded, size: 16),
              label: const Text('Copy link'),
            ),
          ],
          OutlinedButton.icon(
            onPressed: () => shareOrderSummary(context, o['id'] as int, '${o['name']}'),
            icon: const Icon(Icons.ios_share_rounded, size: 16),
            label: const Text('Summary'),
          ),
          if (turned)
            FilledButton.icon(
              onPressed: () => _resend(o),
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Send again'),
            ),
        ]),
      ]),
    );
  }

  Widget _freeGoods(Map<String, dynamic> d) {
    final status = '${d['foc_status']}';
    final label = switch (status) {
      'pending' => 'Goes on the distributor order as free lines (100% off) when you send it',
      'requested' => 'On the distributor order at 100% off, waiting for delivery',
      _ => 'Delivered',
    };
    return _section(
      'Free goods',
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        if (status == 'requested')
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: FilledButton.icon(
              onPressed: () async {
                try {
                  await Services.api.post('/api/v1/demands/${d['id']}/foc-delivered', {});
                  _changed = true;
                  await _load();
                } catch (e) {
                  if (mounted) await showProblem(context, e.toString());
                }
              },
              icon: const Icon(Icons.check_rounded, size: 18),
              label: const Text('Free goods delivered'),
            ),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    final sendable = d != null && widget.canSend && demandSendable(d);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: const Text('Demand')),
        bottomNavigationBar: sendable
            ? SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: FilledButton.icon(
                    onPressed: _send,
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                    icon: const Icon(Icons.local_shipping_rounded),
                    label: const Text('Send to distributor'),
                  ),
                ),
              )
            : null,
        body: d == null
            ? Center(child: _error != null ? Padding(padding: const EdgeInsets.all(24), child: Text(_error!)) : const LoadingView())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _hero(d),
                    const SizedBox(height: 14),
                    _distributor(d),
                    _timeline(d),
                    _requestCard(d),
                    _deliveries(d),
                    if (d['foc_status'] != null) _freeGoods(d),
                    _section(
                      'Products',
                      Column(children: [
                        for (final l in _lines) _line(l, d['currency'] as String?),
                        _totals(d),
                      ]),
                      trailing: Text('${_lines.length} ${_lines.length == 1 ? 'line' : 'lines'}',
                          style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                    ),
                    if (_orders.isNotEmpty)
                      _section('Distributor orders', Column(children: [for (final o in _orders) _order(o)])),
                    if (d['note'] != null) _section('Note', Text('${d['note']}')),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
      ),
    );
  }
}
