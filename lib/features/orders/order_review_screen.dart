import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';

import '../../core/format.dart';
import '../../core/geo.dart';
import '../../core/services.dart';
import '../../core/theme.dart';

class OrderReviewScreen extends StatefulWidget {
  const OrderReviewScreen({super.key, required this.client, required this.lines, this.free = const []});

  final Map<String, dynamic> client;
  final List<Map<String, dynamic>> lines;

  /// Free goods already chosen on the quantity screen: product_id, name, qty, reason.
  final List<Map<String, dynamic>> free;

  @override
  State<OrderReviewScreen> createState() => _OrderReviewScreenState();
}

class _OrderReviewScreenState extends State<OrderReviewScreen> {
  bool get demandFlow =>
      (Services.auth.profile?.isDemandFlow ?? false) && widget.client['category_type'] != 'distributor';

  final _note = TextEditingController();
  // One id per review screen: retrying after a network error cannot create a duplicate order.
  final String _uuid = const Uuid().v4();
  bool _busy = false;

  /// Free units the schemes give this cart (from the server), and whether it could be asked.
  List<Map<String, dynamic>> _free = [];
  bool _freeChecked = false;
  bool _manualAllowed = false;

  /// Free goods the rep adds by hand: product, qty, reason.
  final List<Map<String, dynamic>> _manual = [];

  /// Who will supply this order: chosen here, before it is sent.
  List<Map<String, dynamic>> _distributors = [];
  int? _distributorId;

  @override
  void initState() {
    super.initState();
    _manual.addAll(widget.free);
    _loadFoc();
    _loadDistributors();
  }

  /// The distributors this outlet can be supplied by, with the usual one first.
  Future<void> _loadDistributors() async {
    try {
      final data = await Services.api.get('/api/v1/distributors',
          query: {'partner_id': widget.client['id']}) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _distributors = ((data['distributors'] as List?) ?? []).cast<Map<String, dynamic>>();
        _distributorId = data['suggested_id'] as int?;
      });
    } catch (_) {
      // No distributors set up: the order goes straight to the customer.
    }
  }

  Future<void> _loadFoc() async {
    try {
      final results = await Future.wait([
        Services.api.get('/api/v1/foc/schemes', query: {'partner_id': widget.client['id']}),
        Services.api.post('/api/v1/foc/preview', {
          'partner_id': widget.client['id'],
          'lines': [for (final l in widget.lines) {'product_id': l['id'], 'qty': l['qty']}],
        }),
      ]);
      if (!mounted) return;
      setState(() {
        _manualAllowed = (results[0] as Map)['manual_allowed'] == true;
        _free = ((results[1] as List?) ?? []).cast<Map<String, dynamic>>();
        _freeChecked = true;
      });
    } catch (_) {
      // Offline or no FOC module: the server works the free units out when the order arrives.
    }
  }

  Future<void> _addManual() async {
    final added = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (sheet) => _FreeGoodsSheet(lines: widget.lines),
    );
    if (added == null || !mounted) return;
    setState(() => _manual.add(added));
  }

  /// One free line: a green card with what is free and why.
  Widget _freeCard({required String name, required String note, required num qty, bool scheme = false, VoidCallback? onRemove}) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.25)),
      ),
      child: Row(children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
          child: Icon(scheme ? Icons.auto_awesome_rounded : Icons.redeem_rounded, color: AppColors.success, size: 19),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
            Text(note, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          ]),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(color: AppColors.success, borderRadius: BorderRadius.circular(20)),
          child: Text('+${fmtQty(qty)} free', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12)),
        ),
        if (onRemove != null)
          IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.close_rounded, size: 18), onPressed: onRemove)
        else
          const SizedBox(width: 8),
      ]),
    );
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  double get _total => widget.lines
      .fold(0.0, (sum, l) => sum + ((l['price'] as num?) ?? 0) * ((l['qty'] as num?) ?? 0));

  double get _tax => widget.lines.fold(
      0.0,
      (sum, l) =>
          sum + ((l['price'] as num?) ?? 0) * ((l['qty'] as num?) ?? 0) * ((l['tax_percent'] as num?) ?? 0) / 100);

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      Position? pos;
      try {
        pos = await currentPosition(recentOk: true);
      } catch (_) {
        // Orders are accepted without a fresh GPS fix.
      }
      final result = await Services.outbox.submit('/api/v1/orders', {
        'partner_id': widget.client['id'],
        'lines': [
          for (final l in widget.lines) {'product_id': l['id'], 'qty': l['qty']},
        ],
        if (_manual.isNotEmpty)
          'foc': [for (final m in _manual) {'product_id': m['product_id'], 'qty': m['qty'], 'reason': m['reason']}],
        'note': _note.text.trim(),
        if (_distributorId != null) 'distributor_id': _distributorId,
        'lat': pos?.latitude,
        'lng': pos?.longitude,
        'uuid': _uuid,
      }, label: '${demandFlow ? 'Demand' : 'Order'} · ${widget.client['name']}');
      final order = result.map;
      if (!mounted) return;
      if (result.queued) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: const Icon(Icons.cloud_off_rounded, color: AppColors.warning, size: 48),
            title: Text('${demandFlow ? 'Demand' : 'Order'} saved offline'),
            content: const Text('It is kept on this phone and goes to the office as soon as you have network.'),
            actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
          ),
        );
        if (mounted) Navigator.of(context).pop(true);
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.check_circle, color: Colors.green, size: 48),
          title: Text(demandFlow
              ? 'Demand ${order['name']} recorded'
              : 'Order ${order['name']} placed'),
          content: Text(demandFlow
              ? '${fmtMoney(order['amount_untaxed'] as num?, order['currency'] as String?)} + '
                  '${fmtMoney(order['amount_tax'] as num?, order['currency'] as String?)} tax = '
                  '${fmtMoney(order['amount_total'] as num?, order['currency'] as String?)}. '
                  'The office will send it to the distributor.'
              : 'Total ${fmtMoney(order['amount_total'] as num?, order['currency'] as String?)} incl. tax'),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showProblem(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Who supplies the order: the field picks, the office sees it on the record.
  Widget _distributorCard() {
    final chosen = _distributors.where((d) => d['id'] == _distributorId).firstOrNull;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                      color: AppColors.purple.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(11)),
                  child: const Icon(Icons.local_shipping_rounded, size: 18, color: AppColors.purple),
                ),
                const SizedBox(width: 9),
                const Expanded(
                  child: Text('Supplied by', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              demandFlow
                  ? 'The office sends this demand to the distributor you choose.'
                  : 'The order is billed to the distributor; the shop stays on it as the outlet.',
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<int>(
              initialValue: chosen == null ? null : _distributorId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Distributor',
                prefixIcon: Icon(Icons.store_mall_directory_rounded, size: 19, color: AppColors.primary),
                filled: true,
                fillColor: Colors.white,
              ),
              items: [
                for (final distributor in _distributors)
                  DropdownMenuItem(
                    value: distributor['id'] as int,
                    child: Text(
                      [
                        '${distributor['name']}',
                        if (asText(distributor['city']) != null) '· ${distributor['city']}',
                      ].join(' '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) => setState(() => _distributorId = value),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(demandFlow ? 'Review Demand' : 'Review Order')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.store),
            title: Text(widget.client['name'] as String, style: theme.textTheme.titleMedium),
          ),
          if (_distributors.isNotEmpty) _distributorCard(),
          const Divider(),
          for (final l in widget.lines)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l['name'] as String),
              subtitle: Text('${fmtQty(l['qty'] as num)} × ${fmtMoney(l['price'] as num?)}'
                  '${((l['tax_percent'] as num?) ?? 0) > 0 ? '  ·  + ${fmtQty(l['tax_percent'] as num)}% tax' : ''}'),
              trailing: Text(fmtMoney(((l['price'] as num?) ?? 0) * (l['qty'] as num))),
            ),
          if (_free.isNotEmpty || _manual.isNotEmpty || _manualAllowed || !_freeChecked) ...[
            const Divider(),
            Row(
              children: [
                const Icon(Icons.redeem_rounded, color: AppColors.success, size: 20),
                const SizedBox(width: 8),
                const Expanded(child: Text('Free goods (FOC)', style: TextStyle(fontWeight: FontWeight.w800))),
                if (_manualAllowed && widget.lines.isNotEmpty)
                  TextButton.icon(onPressed: _addManual, icon: const Icon(Icons.add_rounded), label: const Text('Add')),
              ],
            ),
            if (!_freeChecked)
              const Text('Free units from schemes are worked out when the order reaches the office.',
                  style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
            for (final f in _free)
              _freeCard(
                name: '${(f['product'] as Map)['name']}',
                note: '${(f['scheme'] as Map)['name']} · ${(f['scheme'] as Map)['summary']}',
                qty: (f['qty'] as num?) ?? 0,
                scheme: true,
              ),
            for (final m in _manual)
              _freeCard(
                name: '${m['name']}',
                note: '${m['reason']}',
                qty: m['qty'] as num,
                onRemove: () => setState(() => _manual.remove(m)),
              ),
            if (_freeChecked && _free.isEmpty && _manual.isEmpty)
              const Text('No scheme applies to this cart.', style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
          ],
          const Divider(),
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(demandFlow ? 'Untaxed (at PTR)' : 'Untaxed'),
            trailing: Text(fmtMoney(_total)),
          ),
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Taxes'),
            trailing: Text(fmtMoney(_tax)),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Total', style: TextStyle(fontWeight: FontWeight.w800)),
            trailing: Text(fmtMoney(_total + _tax), style: theme.textTheme.titleMedium),
          ),
          Text('Free goods carry no tax. The server works out the final taxes.', style: theme.textTheme.bodySmall),
          const SizedBox(height: 16),
          TextField(
            controller: _note,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Note for the office (optional)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy ? null : _submit,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send),
            label: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(demandFlow ? 'Record demand' : 'Place order'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Adds free goods by hand: pick the product, how many, and why.
class _FreeGoodsSheet extends StatefulWidget {
  const _FreeGoodsSheet({required this.lines});

  final List<Map<String, dynamic>> lines;

  @override
  State<_FreeGoodsSheet> createState() => _FreeGoodsSheetState();
}

class _FreeGoodsSheetState extends State<_FreeGoodsSheet> {
  static const _reasons = ['Sample', 'Display', 'Damage cover', 'Festival offer', 'Other'];
  int? _product;
  double _qty = 1;
  String? _reason;
  final _other = TextEditingController();
  String? _problem;

  @override
  void initState() {
    super.initState();
    if (widget.lines.length == 1) _product = widget.lines.first['id'] as int;
  }

  @override
  void dispose() {
    _other.dispose();
    super.dispose();
  }

  Map<String, dynamic>? get _line => widget.lines.where((l) => l['id'] == _product).firstOrNull;

  void _add() {
    final reason = _reason == 'Other' ? _other.text.trim() : _reason;
    if (_product == null) {
      setState(() => _problem = 'Choose the product that is free');
      return;
    }
    if (_qty <= 0) {
      setState(() => _problem = 'Enter how many are free');
      return;
    }
    if (reason == null || reason.isEmpty) {
      setState(() => _problem = _reason == 'Other' ? 'Describe the reason' : 'Choose the reason');
      return;
    }
    Navigator.pop(context, {'product_id': _product, 'name': _line!['name'], 'qty': _qty, 'reason': reason});
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 14),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
      );

  Widget _round(IconData icon, VoidCallback onTap) => Material(
        color: AppColors.primary.withValues(alpha: 0.1),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.all(10), child: Icon(icon, color: AppColors.primary)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final price = ((_line?['price'] as num?) ?? 0) * _qty;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(15)),
                child: const Icon(Icons.redeem_rounded, color: AppColors.success),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Add free goods', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
                  Text('Given free with this order (FOC)', style: TextStyle(fontSize: 12.5, color: AppColors.muted)),
                ]),
              ),
            ]),
            _label('Which product'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final l in widget.lines)
                ChoiceChip(
                  label: Text('${l['name']}', overflow: TextOverflow.ellipsis),
                  selected: _product == l['id'],
                  onSelected: (_) => setState(() => _product = l['id'] as int),
                  selectedColor: AppColors.primary,
                  labelStyle: TextStyle(
                      fontWeight: FontWeight.w700, color: _product == l['id'] ? Colors.white : AppColors.text),
                  showCheckmark: false,
                ),
            ]),
            _label('How many free'),
            Row(children: [
              _round(Icons.remove_rounded, () => setState(() => _qty = (_qty - 1).clamp(0, 9999))),
              Expanded(
                child: Center(
                  child: Text(fmtQty(_qty), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 30)),
                ),
              ),
              _round(Icons.add_rounded, () => setState(() => _qty += 1)),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              for (final n in const [1, 2, 5, 10, 20])
                ActionChip(label: Text('$n'), onPressed: () => setState(() => _qty = n.toDouble())),
            ]),
            if (_line != null && price > 0)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text('Worth ${fmtMoney(price)} at PTR, free of charge',
                    style: const TextStyle(fontSize: 12.5, color: AppColors.success, fontWeight: FontWeight.w700)),
              ),
            _label('Why is it free *'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final r in _reasons)
                ChoiceChip(
                  label: Text(r),
                  selected: _reason == r,
                  onSelected: (_) => setState(() => _reason = r),
                  selectedColor: AppColors.success,
                  labelStyle: TextStyle(fontWeight: FontWeight.w700, color: _reason == r ? Colors.white : AppColors.text),
                  showCheckmark: false,
                ),
            ]),
            if (_reason == 'Other')
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: TextField(
                  controller: _other,
                  decoration: InputDecoration(
                    hintText: 'Describe the reason',
                    filled: true,
                    fillColor: AppColors.background,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                ),
              ),
            if (_problem != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_problem!, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700)),
              ),
            const SizedBox(height: 18),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: _add,
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                      backgroundColor: AppColors.success,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Add free goods'),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}
