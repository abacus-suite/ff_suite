import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/geo.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/dashboard.dart';

Color _stateColour(String? state) => switch (state) {
      'sale' || 'done' || 'received' || 'supplied' || 'quoted' => AixoloColors.success,
      'cancel' || 'cancelled' || 'rejected' => AixoloColors.danger,
      'draft' || 'sent' || 'collected' || 'submitted' || 'partial' => AixoloColors.warning,
      _ => AixoloColors.muted,
    };

Widget _pill(String? text, String? state) {
  final colour = _stateColour(state);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(color: colour.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
    child: Text(text ?? state ?? '', style: TextStyle(color: colour, fontSize: 11.5, fontWeight: FontWeight.w700)),
  );
}

/// What the customer owes, on the customer screen. Hidden when nothing is owed.
class ClientBalanceCard extends StatefulWidget {
  const ClientBalanceCard({super.key, required this.clientId});

  final int clientId;

  @override
  State<ClientBalanceCard> createState() => _ClientBalanceCardState();
}

class _ClientBalanceCardState extends State<ClientBalanceCard> {
  Map<String, dynamic>? _data;
  bool _open = false;

  @override
  void initState() {
    super.initState();
    Services.api.get('/api/v1/clients/${widget.clientId}/balance').then((data) {
      if (mounted) setState(() => _data = data as Map<String, dynamic>);
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (data == null) return const SizedBox.shrink();
    final currency = data['currency'] as String?;
    final due = (data['due'] as num?) ?? 0;
    final overdue = (data['overdue'] as num?) ?? 0;
    final held = (data['collected_not_deposited'] as num?) ?? 0;
    final invoices = ((data['invoices'] as List?) ?? []).cast<Map<String, dynamic>>();
    if (due == 0 && held == 0) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.verified_rounded, color: AixoloColors.success),
          title: Text('Nothing outstanding', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CardHeader(icon: Icons.account_balance_wallet_rounded, title: 'Balance'),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _figure('Outstanding', fmtMoney(due, currency), AixoloColors.primary)),
                Expanded(
                    child: _figure('Overdue', fmtMoney(overdue, currency),
                        overdue > 0 ? AixoloColors.danger : AixoloColors.muted)),
                if (held > 0) Expanded(child: _figure('With staff', fmtMoney(held, currency), AixoloColors.warning)),
              ],
            ),
            if (invoices.isNotEmpty) ...[
              const SizedBox(height: 6),
              TextButton.icon(
                onPressed: () => setState(() => _open = !_open),
                icon: Icon(_open ? Icons.expand_less_rounded : Icons.expand_more_rounded),
                label: Text('${invoices.length} open invoice${invoices.length == 1 ? '' : 's'}'),
              ),
              if (_open)
                for (final inv in invoices)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('${inv['name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(inv['due_date'] == null
                        ? 'No due date'
                        : inv['overdue'] == true
                            ? 'Due ${inv['due_date']} · ${inv['days_overdue']} days late'
                            : 'Due ${inv['due_date']}'),
                    trailing: Text(fmtMoney(inv['residual'] as num?, currency),
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: inv['overdue'] == true ? AixoloColors.danger : AixoloColors.text)),
                  ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _figure(String label, String value, Color colour) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(color: AixoloColors.muted, fontSize: 12)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: colour)),
        ],
      );
}

/// Everything that happened at a customer: visits, orders or demands, payments.
class ClientHistoryScreen extends StatefulWidget {
  const ClientHistoryScreen({super.key, required this.clientId, required this.name});

  final int clientId;
  final String name;

  @override
  State<ClientHistoryScreen> createState() => _ClientHistoryScreenState();
}

class _ClientHistoryScreenState extends State<ClientHistoryScreen> {
  Map<String, dynamic>? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await Services.api.get('/api/v1/clients/${widget.clientId}/history', query: {'limit': 50});
      if (mounted) setState(() => (_data = data as Map<String, dynamic>, _error = null));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = Services.auth.profile!;
    final data = _data;
    List<Map<String, dynamic>> rows(String key) => ((data?[key] as List?) ?? []).cast<Map<String, dynamic>>();
    final sales = profile.isDemandFlow ? rows('demands') : rows('orders');
    final tabs = [
      ('Visits', rows('visits')),
      ('${profile.orderWord}s', sales),
      if (profile.paymentCollection) ('Payments', rows('collections')),
    ];
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text('History · ${widget.name}'),
          bottom: TabBar(tabs: [for (final t in tabs) Tab(text: '${t.$1} (${t.$2.length})')]),
        ),
        body: _error != null
            ? ErrorView(message: _error!, onRetry: _load)
            : data == null
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    children: [
                      _list(tabs[0].$2, _visitTile, 'No visits yet'),
                      _list(tabs[1].$2, _saleTile, 'Nothing ordered yet'),
                      if (profile.paymentCollection) _list(tabs[2].$2, _paymentTile, 'No payments yet'),
                    ],
                  ),
      ),
    );
  }

  Widget _list(List<Map<String, dynamic>> items, Widget Function(Map<String, dynamic>) tile, String empty) {
    if (items.isEmpty) {
      return Center(child: Text(empty, style: const TextStyle(color: AixoloColors.muted)));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 6),
        itemBuilder: (_, i) => Card(child: tile(items[i])),
      ),
    );
  }

  Widget _visitTile(Map<String, dynamic> v) => ListTile(
        leading: Icon(v['visit_type'] == 'offsite' ? Icons.wrong_location_rounded : Icons.storefront_rounded,
            color: v['visit_type'] == 'offsite' ? AixoloColors.danger : AixoloColors.primary),
        title: Text('${fmtTime(v['check_in_at'])}${v['check_out_at'] != null ? ' – ${fmtTime(v['check_out_at'])}' : ''}',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text([
          if (v['duration_min'] != null && v['duration_min'] != 0) '${v['duration_min']} min',
          if ((v['outcome_type'] as Map?)?['name'] != null) (v['outcome_type'] as Map)['name'],
          if (v['note'] != null) v['note'],
        ].join(' · ')),
        trailing: _pill(v['visit_type'] == 'offsite' ? 'Offsite' : 'Onsite', v['visit_type'] == 'offsite' ? 'cancel' : 'done'),
      );

  Widget _saleTile(Map<String, dynamic> o) => ListTile(
        leading: const Icon(Icons.receipt_long_rounded, color: AixoloColors.primary),
        title: Text('${o['name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text([
          fmtTime(o['date']),
          if ((o['employee'] as Map?)?['name'] != null) (o['employee'] as Map)['name'],
          if ((o['distributor'] as Map?)?['name'] != null) 'via ${(o['distributor'] as Map)['name']}',
        ].join(' · ')),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(fmtMoney(o['amount'] as num?, o['currency'] as String?), style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 3),
            _pill(o['state_label'] as String?, o['state'] as String?),
          ],
        ),
      );

  Widget _paymentTile(Map<String, dynamic> c) => ListTile(
        leading: const Icon(Icons.payments_rounded, color: AixoloColors.teal),
        title: Text('${c['mode']}', style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text([fmtTime(c['date']), if (c['reference'] != null) c['reference']].join(' · ')),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(fmtMoney(c['amount'] as num?, c['currency'] as String?), style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 3),
            _pill(c['state_label'] as String?, c['state'] as String?),
          ],
        ),
      );
}

/// Fix a customer's phone, address, or put its pin where you stand.
class EditClientScreen extends StatefulWidget {
  const EditClientScreen({super.key, required this.client});

  final Map<String, dynamic> client;

  @override
  State<EditClientScreen> createState() => _EditClientScreenState();
}

class _EditClientScreenState extends State<EditClientScreen> {
  late final _name = TextEditingController(text: '${widget.client['name'] ?? ''}');
  late final _phone = TextEditingController(text: '${widget.client['phone'] ?? ''}');
  late final _email = TextEditingController(text: '${widget.client['email'] ?? ''}');
  final _street = TextEditingController();
  final _city = TextEditingController();
  final _zip = TextEditingController();
  bool _moveLocation = false;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _street, _city, _zip]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final body = <String, dynamic>{
        'name': _name.text.trim(),
        'phone': _phone.text.trim(),
        'email': _email.text.trim(),
        if (_street.text.trim().isNotEmpty) 'street': _street.text.trim(),
        if (_city.text.trim().isNotEmpty) 'city': _city.text.trim(),
        if (_zip.text.trim().isNotEmpty) 'zip': _zip.text.trim(),
      };
      if (_moveLocation) {
        final pos = await currentPosition();
        body.addAll({'set_location': true, 'lat': pos.latitude, 'lng': pos.longitude, 'mock': pos.isMocked});
      }
      final result = await Services.outbox.submit('/api/v1/clients/${widget.client['id']}/update', body,
          label: 'Edit customer · ${_name.text.trim()}');
      if (!mounted) return;
      if (!result.queued) showSnack(context, _moveLocation ? 'Saved · location updated' : 'Saved');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(TextEditingController c, String label, {TextInputType? type, String? hint}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(controller: c, keyboardType: type, decoration: InputDecoration(labelText: label, hintText: hint)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit customer')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _field(_name, 'Name'),
          _field(_phone, 'Phone', type: TextInputType.phone),
          _field(_email, 'Email', type: TextInputType.emailAddress),
          if (widget.client['address'] != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('Current address: ${widget.client['address']}', style: const TextStyle(color: AixoloColors.muted)),
            ),
          _field(_street, 'Street / area', hint: 'Leave empty to keep'),
          _field(_city, 'City', hint: 'Leave empty to keep'),
          _field(_zip, 'PIN code', type: TextInputType.number, hint: 'Leave empty to keep'),
          Card(
            child: SwitchListTile(
              value: _moveLocation,
              onChanged: (v) => setState(() => _moveLocation = v),
              secondary: const Icon(Icons.my_location_rounded, color: AixoloColors.primary),
              title: const Text('Put the pin where I am standing'),
              subtitle: Text(widget.client['lat'] == null
                  ? 'This customer has no location yet'
                  : 'Only when you are at the shop · the office sees the change'),
            ),
          ),
          const SizedBox(height: 12),
          GradientButton(label: 'Save changes', icon: Icons.check_rounded, busy: _busy, onPressed: _save),
        ],
      ),
    );
  }
}
