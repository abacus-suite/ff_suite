import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/skeleton.dart';

const _stateText = {'draft': 'Draft', 'running': 'Event Running', 'on_hold': 'On Hold', 'done': 'Ended'};

num _n(dynamic v) => v is num ? v : num.tryParse('$v') ?? 0;

Future<Position?> _here(BuildContext context) async {
  try {
    return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
  } catch (_) {
    if (context.mounted) showProblem(context, 'Turn on location to continue.');
    return null;
  }
}

/// The events the person created or runs, with a button to start a new one.
class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  List<Map<String, dynamic>>? _events;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await Services.api.get('/api/v1/events') as Map<String, dynamic>;
      if (mounted) setState(() => _events = ((data['events'] as List?) ?? []).cast<Map<String, dynamic>>());
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final events = _events;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Events')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(const NewEventScreen()),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Event'),
      ),
      body: _error != null
          ? ErrorView(message: _error!, onRetry: _load)
          : events == null
              ? const LoadingView()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                    children: [
                      if (events.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(40),
                          child: Center(child: Text('No events yet.', style: TextStyle(color: AppColors.muted))),
                        ),
                      for (final e in events)
                        Card(
                          child: ListTile(
                            onTap: () => _open(EventDetailScreen(eventId: e['id'] as int)),
                            title: Text('${e['name']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                            subtitle: Text([
                              '${_stateText[e['state']] ?? e['state']}',
                              if ((e['territory'] as Map?) != null) '${(e['territory'] as Map)['name']}',
                              'Rs. ${e['offer_price']} offer',
                              '${e['days']} day${e['days'] == 1 ? '' : 's'}',
                            ].join(' · ')),
                            trailing: const Icon(Icons.chevron_right_rounded),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }
}

/// Step 1 details, step 2 opening stock by distributor, step 3 confirm.
class NewEventScreen extends StatefulWidget {
  const NewEventScreen({super.key});

  @override
  State<NewEventScreen> createState() => _NewEventScreenState();
}

class _NewEventScreenState extends State<NewEventScreen> {
  Map<String, dynamic>? _options;
  int _step = 0;
  final _name = TextEditingController();
  final _location = TextEditingController();
  final Set<int> _staff = {};
  int? _district;
  int? _territory;
  int _offer = 20;
  // One block per distributor: the distributor id and a quantity per product id.
  final List<Map<String, dynamic>> _blocks = [];
  bool _busy = false;
  Position? _pos;

  @override
  void initState() {
    super.initState();
    _loadOptions();
  }

  @override
  void dispose() {
    _name.dispose();
    _location.dispose();
    for (final b in _blocks) {
      for (final c in (b['qty'] as Map<int, TextEditingController>).values) {
        c.dispose();
      }
    }
    super.dispose();
  }

  Future<void> _loadOptions() async {
    try {
      final data = await Services.api.get('/api/v1/events/options') as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _options = data;
        _addBlock();
      });
    } catch (e) {
      if (mounted) showProblem(context, e.toString());
    }
  }

  List<Map<String, dynamic>> _list(String key) => ((_options?[key] as List?) ?? []).cast<Map<String, dynamic>>();

  void _addBlock() {
    final products = _list('products');
    _blocks.add({
      'distributor': null,
      'qty': {for (final p in products) p['id'] as int: TextEditingController()},
    });
  }

  String _validateDetails() {
    if (_name.text.trim().isEmpty) return 'Give the event a name.';
    if (_staff.isEmpty) return 'Choose who conducts the event.';
    if (_territory == null) return 'Choose the territory.';
    return '';
  }

  List<Map<String, dynamic>> _stockRows() {
    final rows = <Map<String, dynamic>>[];
    for (final b in _blocks) {
      final d = b['distributor'] as int?;
      if (d == null) continue;
      (b['qty'] as Map<int, TextEditingController>).forEach((pid, c) {
        final q = num.tryParse(c.text.trim()) ?? 0;
        if (q > 0) rows.add({'distributor_id': d, 'product_id': pid, 'qty': q});
      });
    }
    return rows;
  }

  Future<void> _next() async {
    if (_step == 0) {
      final problem = _validateDetails();
      if (problem.isNotEmpty) return showProblem(context, problem);
      _pos ??= await _here(context);
      if (_pos == null) return;
    }
    if (_step == 1 && _stockRows().isEmpty) {
      return showProblem(context, 'Add the opening stock for at least one distributor.');
    }
    if (_step < 2) {
      setState(() => _step++);
    } else {
      _submit();
    }
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      await Services.api.post('/api/v1/events', {
        'name': _name.text.trim(),
        'staff_ids': _staff.toList(),
        'district_id': _district,
        'territory_id': _territory,
        'location': _location.text.trim(),
        'latitude': _pos?.latitude,
        'longitude': _pos?.longitude,
        'offer_price': _offer,
        'stock': _stockRows(),
        'confirm': true,
      });
      if (!mounted) return;
      showSnack(context, 'Event Running');
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showProblem(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = _options;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text('New Event · Step ${_step + 1} of 3')),
      body: o == null
          ? const LoadingView()
          : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
              if (_step == 0) ..._details(),
              if (_step == 1) ..._stock(),
              if (_step == 2) ..._confirm(),
              const SizedBox(height: 10),
              Row(children: [
                if (_step > 0)
                  Expanded(
                    child: OutlinedButton(onPressed: () => setState(() => _step--), child: const Text('Back')),
                  ),
                if (_step > 0) const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: GradientButton(
                    label: _step == 2 ? 'Confirm & start event' : 'Next',
                    icon: Icons.arrow_forward_rounded,
                    busy: _busy,
                    onPressed: _busy ? null : _next,
                  ),
                ),
              ]),
            ]),
    );
  }

  List<Widget> _details() {
    final territories = _list('territories').where((t) => _district == null || t['district_id'] == _district);
    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(children: [
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Event name *')),
            const SizedBox(height: 10),
            DropdownButtonFormField<int>(
              initialValue: _district,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'City / District'),
              items: [for (final d in _list('districts')) DropdownMenuItem(value: d['id'] as int, child: Text('${d['name']}'))],
              onChanged: (v) => setState(() {
                _district = v;
                _territory = null;
              }),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<int>(
              initialValue: _territory,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Territory *'),
              items: [for (final t in territories) DropdownMenuItem(value: t['id'] as int, child: Text('${t['name']}'))],
              onChanged: (v) => setState(() => _territory = v),
            ),
            const SizedBox(height: 10),
            TextField(controller: _location, decoration: const InputDecoration(labelText: 'Event location')),
          ]),
        ),
      ),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Conducted by *', style: TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 6, children: [
              for (final s in _list('staff'))
                FilterChip(
                  label: Text('${s['name']}'),
                  selected: _staff.contains(s['id']),
                  onSelected: (v) => setState(() => v ? _staff.add(s['id'] as int) : _staff.remove(s['id'])),
                ),
            ]),
          ]),
        ),
      ),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Offer price', style: TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              showSelectedIcon: false,
              segments: [for (final p in (_options!['offers'] as List)) ButtonSegment(value: p as int, label: Text('Rs. $p'))],
              selected: {_offer},
              onSelectionChanged: (v) => setState(() => _offer = v.first),
            ),
            const SizedBox(height: 6),
            const Text('MRP is filled in automatically for each flavour.',
                style: TextStyle(fontSize: 12, color: AppColors.muted)),
          ]),
        ),
      ),
    ];
  }

  List<Widget> _stock() {
    final products = _list('products');
    return [
      for (final (i, b) in _blocks.indexed)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              DropdownButtonFormField<int>(
                initialValue: b['distributor'] as int?,
                isExpanded: true,
                decoration: InputDecoration(labelText: 'Distributor ${i + 1} *'),
                items: [
                  for (final d in _list('distributors'))
                    DropdownMenuItem(value: d['id'] as int, child: Text('${d['name']}', overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() => b['distributor'] = v),
              ),
              const SizedBox(height: 8),
              for (final p in products)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(children: [
                    Expanded(
                      child: Text('${p['name']}${'${p['code']}'.isEmpty ? '' : ' (${p['code']})'}',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    SizedBox(
                      width: 90,
                      child: TextField(
                        controller: (b['qty'] as Map<int, TextEditingController>)[p['id']],
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(isDense: true, hintText: 'Qty'),
                      ),
                    ),
                  ]),
                ),
            ]),
          ),
        ),
      OutlinedButton.icon(
        onPressed: () => setState(_addBlock),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add another distributor'),
      ),
    ];
  }

  List<Widget> _confirm() {
    final rows = _stockRows();
    final names = {for (final d in _list('distributors')) d['id']: d['name']};
    final products = {for (final p in _list('products')) p['id']: p};
    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_name.text.trim(), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
            const SizedBox(height: 4),
            Text('Rs. $_offer offer · ${_location.text.trim()}', style: const TextStyle(color: AppColors.muted)),
            const Divider(height: 22),
            const Text('Opening stock', style: TextStyle(fontWeight: FontWeight.w900)),
            for (final r in rows)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(children: [
                  Expanded(
                    child: Text('${names[r['distributor_id']]} · ${products[r['product_id']]?['name']}'),
                  ),
                  Text('${fmtQty(_n(r['qty']))}', style: const TextStyle(fontWeight: FontWeight.w800)),
                ]),
              ),
          ]),
        ),
      ),
    ];
  }
}

/// One event: its state, End of Day, End of Event and the report.
class EventDetailScreen extends StatefulWidget {
  const EventDetailScreen({super.key, required this.eventId});

  final int eventId;

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  Map<String, dynamic>? _event;
  Map<String, dynamic>? _report;
  String? _reportDay;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final e = await Services.api.get('/api/v1/events/${widget.eventId}') as Map<String, dynamic>;
      final r = await Services.api.get('/api/v1/events/${widget.eventId}/report',
          query: {if (_reportDay != null) 'day': _reportDay!}) as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _event = e;
          _report = r;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  /// The 200 m rule: end of day and end of event happen at the event.
  Future<bool> _atEvent() async {
    final e = _event!;
    final pos = await _here(context);
    if (pos == null) return false;
    final lat = (e['latitude'] as num?)?.toDouble();
    final lng = (e['longitude'] as num?)?.toDouble();
    if (lat == null || lng == null || (lat == 0 && lng == 0)) return true;
    final metres = Geolocator.distanceBetween(pos.latitude, pos.longitude, lat, lng);
    if (metres > 200 && mounted) {
      showProblem(context, 'You are ${metres.round()} m from the event. Be within 200 m to continue.');
      return false;
    }
    return true;
  }

  Future<void> _closeDay({required bool end}) async {
    if (!await _atEvent() || !mounted) return;
    final products = <int, Map<String, dynamic>>{};
    for (final s in (_event!['stock'] as List).cast<Map<String, dynamic>>()) {
      final p = s['product'] as Map<String, dynamic>;
      products[p['id'] as int] = {'name': p['name'], 'code': s['code']};
    }
    final opening = {for (final r in (_event!['today'] as List).cast<Map<String, dynamic>>()) r['product_id'] as int: _n(r['opening'])};
    final result = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => _DayEntryScreen(eventId: widget.eventId, products: products, opening: opening, end: end),
    ));
    if (result == true) _load();
  }

  Future<void> _resume() async {
    try {
      await Services.api.post('/api/v1/events/${widget.eventId}/resume', {});
      _load();
    } catch (e) {
      if (mounted) showProblem(context, e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = _event;
    final report = _report;
    final days = ((report?['days'] as List?) ?? []).cast<String>();
    final rows = ((report?['rows'] as List?) ?? []).cast<Map<String, dynamic>>();
    final totals = (report?['totals'] as Map?)?.cast<String, dynamic>() ?? const {};
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(e == null ? 'Event' : '${e['name']}')),
      body: _error != null
          ? ErrorView(message: _error!, onRetry: _load)
          : e == null
              ? const LoadingView()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${_stateText[e['state']] ?? e['state']}',
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: AppColors.primary)),
                          const SizedBox(height: 4),
                          Text('Rs. ${e['offer_price']} offer · ${e['location']}',
                              style: const TextStyle(color: AppColors.muted)),
                          Text('Conducted by ${(e['staff'] as List).map((s) => (s as Map)['name']).join(', ')}',
                              style: const TextStyle(color: AppColors.muted)),
                          if (e['state'] != 'done') ...[
                            const SizedBox(height: 12),
                            if (e['state'] == 'on_hold')
                              FilledButton(onPressed: _resume, child: const Text('Resume event'))
                            else ...[
                              FilledButton(onPressed: () => _closeDay(end: false), child: const Text('End of Day')),
                              const SizedBox(height: 8),
                              OutlinedButton(onPressed: () => _closeDay(end: true), child: const Text('End of Event')),
                            ],
                          ],
                        ]),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(children: [
                      const Expanded(child: Text('Event report', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16))),
                      DropdownButton<String?>(
                        value: _reportDay,
                        hint: const Text('All days'),
                        items: [
                          const DropdownMenuItem<String?>(value: null, child: Text('All days')),
                          for (final d in days) DropdownMenuItem<String?>(value: d, child: Text(d)),
                        ],
                        onChanged: (v) {
                          setState(() => _reportDay = v);
                          _load();
                        },
                      ),
                    ]),
                    if (rows.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: Text('Nothing recorded yet.', style: TextStyle(color: AppColors.muted)),
                      )
                    else
                      Card(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            columnSpacing: 14,
                            columns: const [
                              DataColumn(label: Text('Flavour')),
                              DataColumn(label: Text('Open'), numeric: true),
                              DataColumn(label: Text('Added'), numeric: true),
                              DataColumn(label: Text('Samples'), numeric: true),
                              DataColumn(label: Text('Damage'), numeric: true),
                              DataColumn(label: Text('Return'), numeric: true),
                              DataColumn(label: Text('Close'), numeric: true),
                              DataColumn(label: Text('Sold'), numeric: true),
                              DataColumn(label: Text('Value'), numeric: true),
                            ],
                            rows: [
                              for (final r in rows)
                                DataRow(cells: [
                                  DataCell(Text('${(r['product'] as Map)['name']}')),
                                  for (final k in ['opening', 'added', 'samples', 'damage', 'returned', 'closing', 'sold', 'value'])
                                    DataCell(Text(fmtQty(_n(r[k])))),
                                ]),
                              DataRow(cells: [
                                const DataCell(Text('Total', style: TextStyle(fontWeight: FontWeight.w900))),
                                for (final k in ['opening', 'added', 'samples', 'damage', 'returned', 'closing', 'sold', 'value'])
                                  DataCell(Text(fmtQty(_n(totals[k])), style: const TextStyle(fontWeight: FontWeight.w900))),
                              ]),
                            ],
                          ),
                        ),
                      ),
                    if (e['state'] == 'done')
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text('Coupons used: ${e['coupons_used']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                  ]),
                ),
    );
  }
}

/// End of Day or End of Event: samples, damage, closing stock (stays or returned), and at the end the coupons.
class _DayEntryScreen extends StatefulWidget {
  const _DayEntryScreen({required this.eventId, required this.products, required this.opening, required this.end});

  final int eventId;
  final Map<int, Map<String, dynamic>> products;
  final Map<int, num> opening;
  final bool end;

  @override
  State<_DayEntryScreen> createState() => _DayEntryScreenState();
}

class _DayEntryScreenState extends State<_DayEntryScreen> {
  late final Map<int, Map<String, TextEditingController>> _c = {
    for (final id in widget.products.keys)
      id: {for (final k in ['added', 'samples', 'damage', 'returned', 'closing']) k: TextEditingController()},
  };
  final _coupons = TextEditingController();
  String _action = 'stays';
  bool _hold = false;
  bool _busy = false;

  @override
  void dispose() {
    for (final m in _c.values) {
      for (final c in m.values) {
        c.dispose();
      }
    }
    _coupons.dispose();
    super.dispose();
  }

  num _v(int id, String k) => num.tryParse(_c[id]![k]!.text.trim()) ?? 0;

  Future<void> _save() async {
    for (final id in widget.products.keys) {
      final left = (widget.opening[id] ?? 0) + _v(id, 'added') - _v(id, 'samples') - _v(id, 'damage') - _v(id, 'returned');
      if (_v(id, 'closing') > left) {
        return showProblem(context, 'Closing stock of ${widget.products[id]!['name']} is more than what was available.');
      }
    }
    if (widget.end && (num.tryParse(_coupons.text.trim()) == null)) {
      return showProblem(context, 'Enter the number of coupons used.');
    }
    setState(() => _busy = true);
    try {
      await Services.api.post('/api/v1/events/${widget.eventId}/${widget.end ? 'end' : 'day'}', {
        'lines': [
          for (final id in widget.products.keys)
            {
              'product_id': id,
              'added': _v(id, 'added'),
              'samples': _v(id, 'samples'),
              'damage': _v(id, 'damage'),
              'returned': _v(id, 'returned'),
              'closing': _v(id, 'closing'),
              'action': _action,
            },
        ],
        if (widget.end) 'coupons_used': int.tryParse(_coupons.text.trim()) ?? 0,
        if (!widget.end) 'hold': _hold,
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showProblem(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget field(int id, String k, String label) => SizedBox(
          width: 78,
          child: TextField(
            controller: _c[id]![k],
            keyboardType: TextInputType.number,
            decoration: InputDecoration(isDense: true, labelText: label),
          ),
        );
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(widget.end ? 'End of Event' : 'End of Day')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
        for (final entry in widget.products.entries)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${entry.value['name']}', style: const TextStyle(fontWeight: FontWeight.w900)),
                Text('Opening ${fmtQty(widget.opening[entry.key] ?? 0)}',
                    style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  field(entry.key, 'added', 'Added'),
                  field(entry.key, 'samples', 'Samples'),
                  field(entry.key, 'damage', 'Damage'),
                  if (widget.end) field(entry.key, 'returned', 'Return'),
                  field(entry.key, 'closing', 'Closing'),
                ]),
              ]),
            ),
          ),
        if (!widget.end)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Closing stock', style: TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 'stays', label: Text('Stays at event')),
                    ButtonSegment(value: 'returned', label: Text('Returned')),
                  ],
                  selected: {_action},
                  onSelectionChanged: (v) => setState(() => _action = v.first),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Put the event on hold'),
                  value: _hold,
                  onChanged: (v) => setState(() => _hold = v),
                ),
              ]),
            ),
          )
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: TextField(
                controller: _coupons,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Coupons used *'),
              ),
            ),
          ),
        const SizedBox(height: 8),
        GradientButton(
          label: widget.end ? 'End event' : 'Save end of day',
          icon: Icons.check_rounded,
          busy: _busy,
          onPressed: _busy ? null : _save,
        ),
      ]),
    );
  }
}
