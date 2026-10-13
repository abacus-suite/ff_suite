import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/skeleton.dart';

const _pageBg = Color(0xFFEEF3FB);
const _orange = Color(0xFFEA580C);
const _green = Color(0xFF16A34A);

num _n(dynamic v) => v is num ? v : num.tryParse('$v') ?? 0;
String _q(num v) => fmtQty(v);

List<Map<String, dynamic>> _list(dynamic v) => ((v as List?) ?? []).cast<Map<String, dynamic>>();

Future<Position?> _here(BuildContext context) async {
  try {
    return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
  } catch (_) {
    if (context.mounted) showProblem(context, 'Turn on location to continue.');
    return null;
  }
}

/// Everything an Events screen shares: the title with its step line, the progress bar and the bottom button.
class _Frame extends StatelessWidget {
  const _Frame({
    required this.subtitle,
    required this.children,
    this.step,
    this.steps = 3,
    this.bottom,
    this.onBack,
  });

  final String subtitle;
  final int? step;
  final int steps;
  final List<Widget> children;
  final Widget? bottom;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBg,
      appBar: AppBar(
        backgroundColor: _pageBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: onBack ?? () => Navigator.of(context).maybePop(),
        ),
        titleSpacing: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Events', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          Text(subtitle, style: const TextStyle(fontSize: 11.5, color: AppColors.muted, fontWeight: FontWeight.w500)),
        ]),
      ),
      bottomNavigationBar: bottom == null
          ? null
          : SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 14), child: bottom)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          if (step != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(children: [
                for (var i = 0; i < steps; i++)
                  Expanded(
                    child: Container(
                      height: 5,
                      margin: EdgeInsets.only(right: i == steps - 1 ? 0 : 6),
                      decoration: BoxDecoration(
                        color: i < step! ? AppColors.primary : const Color(0xFFD5DEEE),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
              ]),
            ),
          ...children,
        ],
      ),
    );
  }
}

Widget _label(String text, {bool required = false}) => Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 5),
      child: Text(required ? '$text *' : text,
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Color(0xFF334155))),
    );

InputDecoration _field([String? hint]) => InputDecoration(
      hintText: hint,
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFD5DEEE))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFD5DEEE))),
    );

Widget _notice(String text, {Color tint = _orange}) => Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tint.withValues(alpha: 0.35)),
      ),
      child: Text(text, style: TextStyle(fontSize: 12.5, color: tint == _green ? const Color(0xFF166534) : tint)),
    );

Widget _sectionTitle(String text, {String? trailing}) => Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Row(children: [
        Text(text, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5)),
        if (trailing != null) ...[
          const SizedBox(width: 6),
          Text(trailing, style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
        ],
      ]),
    );

/// Flavours two to a row: the flavour on the left and a square box for the bottles on the right.
class _Grid extends StatelessWidget {
  const _Grid({required this.products, this.controllers, this.values, this.onChanged});

  final List<Map<String, dynamic>> products;
  final Map<int, TextEditingController>? controllers;
  final Map<int, num>? values;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final width = (box.maxWidth - 10) / 2;
      return Wrap(spacing: 10, runSpacing: 10, children: [
        for (final p in products)
          SizedBox(
            width: width,
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFD5DEEE)),
              ),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(color: const Color(0xFFDCE7FB), borderRadius: BorderRadius.circular(6)),
                      child: Text('${p['code']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: AppColors.primary)),
                    ),
                    const SizedBox(height: 4),
                    Text('${p['name']}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: AppColors.muted, height: 1.15)),
                  ]),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 64,
                  height: 64,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF6F9FF),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFB8C7E6), width: 1.4),
                  ),
                  child: controllers != null
                      ? TextField(
                          controller: controllers![p['id']],
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          onChanged: (_) => onChanged?.call(),
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
                          decoration: const InputDecoration(
                              isDense: true, border: InputBorder.none, hintText: '0', contentPadding: EdgeInsets.zero),
                        )
                      : Text(_q(values?[p['id']] ?? 0),
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
                ),
              ]),
            ),
          ),
      ]);
    });
  }
}

Map<int, TextEditingController> _controllers(List<Map<String, dynamic>> products) =>
    {for (final p in products) p['id'] as int: TextEditingController()};

num _sum(Map<int, TextEditingController> c) =>
    c.values.fold<num>(0, (a, b) => a + (num.tryParse(b.text.trim()) ?? 0));

void _goDashboard(BuildContext context) {
  Navigator.of(context).popUntil((r) => r.isFirst);
  Services.refresh.value++;
}

String _day(Map<String, dynamic> e) => 'Day ${e['day_no']}';

// ====================================================================== the events list
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
      if (mounted) setState(() => _events = _list(data['events']));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final events = _events;
    const names = {'draft': 'Draft', 'running': 'Event Running', 'on_hold': 'On hold', 'done': 'Completed'};
    return Scaffold(
      backgroundColor: _pageBg,
      appBar: AppBar(title: const Text('My Events'), backgroundColor: _pageBg),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NewEventScreen()));
          _load();
        },
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Event'),
      ),
      body: _error != null
          ? ErrorView(message: _error!, onRetry: _load)
          : events == null
              ? const LoadingView()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 100), children: [
                    if (events.isEmpty)
                      const Padding(
                          padding: EdgeInsets.all(40),
                          child: Center(child: Text('No events yet.', style: TextStyle(color: AppColors.muted)))),
                    for (final e in events)
                      Card(
                        child: ListTile(
                          onTap: () async {
                            await Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => EventReportScreen(eventId: e['id'] as int)));
                            _load();
                          },
                          title: Text('${e['name']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                          subtitle: Text([
                            '${names[e['state']] ?? e['state']}',
                            if (e['territory'] != null) '${(e['territory'] as Map)['name']}',
                            '${e['days']} day${e['days'] == 1 ? '' : 's'}',
                          ].join(' · ')),
                          trailing: const Icon(Icons.chevron_right_rounded),
                        ),
                      ),
                  ]),
                ),
    );
  }
}

// ====================================================================== distributor stock entry
class _Block {
  _Block(List<Map<String, dynamic>> products)
      : qty = _controllers(products);
  int? distributor;
  final Map<int, TextEditingController> qty;
  num get total => _sum(qty);
}

/// Distributor-wise stock by flavour. Added distributors are listed on top and can be edited.
class _StockEditor extends StatefulWidget {
  const _StockEditor({
    required this.products,
    required this.distributors,
    required this.blocks,
    required this.heading,
    required this.addLabel,
    required this.addSubtitle,
    required this.onChanged,
    this.first = 'Distributor',
  });

  final List<Map<String, dynamic>> products;
  final List<Map<String, dynamic>> distributors;
  final List<_Block> blocks;
  final String heading;
  final String addLabel;
  final String? addSubtitle;
  final String first;
  final VoidCallback onChanged;

  @override
  State<_StockEditor> createState() => _StockEditorState();
}

class _StockEditorState extends State<_StockEditor> {
  int _editing = 0;

  String _name(int? id) => '${widget.distributors.firstWhere((d) => d['id'] == id, orElse: () => {'name': 'Distributor'})['name']}';

  @override
  Widget build(BuildContext context) {
    final blocks = widget.blocks;
    if (_editing >= blocks.length) _editing = blocks.length - 1;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (var i = 0; i < blocks.length; i++)
        if (i != _editing)
          InkWell(
            onTap: () => setState(() => _editing = i),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_name(blocks[i].distributor), style: const TextStyle(fontWeight: FontWeight.w800)),
                    Text('${_q(blocks[i].total)} bottles · tap to edit',
                        style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
                  ]),
                ),
                const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
              ]),
            ),
          ),
      _label('${widget.first} ${_editing + 1}', required: true),
      DropdownButtonFormField<int>(
        key: ValueKey('d$_editing${blocks.length}'),
        initialValue: blocks[_editing].distributor,
        isExpanded: true,
        decoration: _field('Select distributor'),
        items: [
          for (final d in widget.distributors)
            DropdownMenuItem(value: d['id'] as int, child: Text('${d['name']}', overflow: TextOverflow.ellipsis)),
        ],
        onChanged: (v) {
          setState(() => blocks[_editing].distributor = v);
          widget.onChanged();
        },
      ),
      _sectionTitle(widget.heading),
      _Grid(products: widget.products, controllers: blocks[_editing].qty, onChanged: widget.onChanged),
      const SizedBox(height: 12),
      InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          if (blocks[_editing].distributor == null) {
            showProblem(context, 'Select the distributor first.');
            return;
          }
          setState(() {
            blocks.add(_Block(widget.products));
            _editing = blocks.length - 1;
          });
          widget.onChanged();
        },
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            const CircleAvatar(radius: 16, backgroundColor: AppColors.primary, child: Icon(Icons.add_rounded, color: Colors.white)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.addLabel, style: const TextStyle(fontWeight: FontWeight.w800)),
                if (widget.addSubtitle != null)
                  Text(widget.addSubtitle!, style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
              ]),
            ),
          ]),
        ),
      ),
    ]);
  }
}

List<Map<String, dynamic>> _stockRows(List<_Block> blocks) => [
      for (final b in blocks)
        if (b.distributor != null)
          for (final e in b.qty.entries)
            if ((num.tryParse(e.value.text.trim()) ?? 0) > 0)
              {'distributor_id': b.distributor, 'product_id': e.key, 'qty': num.parse(e.value.text.trim())},
    ];

// ====================================================================== a new event: 3 steps
class NewEventScreen extends StatefulWidget {
  const NewEventScreen({super.key});

  @override
  State<NewEventScreen> createState() => _NewEventScreenState();
}

class _NewEventScreenState extends State<NewEventScreen> {
  Map<String, dynamic>? _options;
  int _step = 1;
  final _name = TextEditingController();
  final Set<int> _staff = {};
  Map<String, dynamic>? _territory;
  bool _offer = true;
  int _coupon = 30;
  List<_Block> _blocks = [];
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
    super.dispose();
  }

  Future<void> _loadOptions() async {
    try {
      final data = await Services.api.get('/api/v1/events/options') as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _options = data;
        _blocks = [_Block(_list(data['products']))];
        final staff = _list(data['staff']);
        final me = Services.auth.profile;
        for (final s in staff) {
          if (me != null && s['name'] == me.name) _staff.add(s['id'] as int);
        }
      });
    } catch (e) {
      if (mounted) showProblem(context, e.toString());
    }
  }

  List<Map<String, dynamic>> get _products => _list(_options?['products']);

  /// The territory's distributors, then Kumbayah Foods.
  List<Map<String, dynamic>> get _distributors {
    final all = _list(_options?['distributors']);
    final local = ((_territory?['distributor_ids'] as List?) ?? []).toSet();
    final company = all.where((d) => d['company'] == true);
    final chosen = all.where((d) => d['company'] != true && (local.isEmpty || local.contains(d['id'])));
    return [...chosen, ...company];
  }

  Future<void> _pickStaff() async {
    final staff = _list(_options?['staff']);
    final picked = Set<int>.from(_staff);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) => StatefulBuilder(
        builder: (context, setSheet) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Conducted by', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17))),
            ),
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                for (final s in staff)
                  CheckboxListTile(
                    value: picked.contains(s['id']),
                    title: Text('${s['name']}'),
                    onChanged: (v) => setSheet(() => v == true ? picked.add(s['id'] as int) : picked.remove(s['id'])),
                  ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton(onPressed: () => Navigator.pop(sheet), child: const Text('Done')),
            ),
          ]),
        ),
      ),
    );
    setState(() {
      _staff
        ..clear()
        ..addAll(picked);
    });
  }

  Future<void> _next() async {
    if (_step == 1) {
      if (_name.text.trim().isEmpty) return showProblem(context, 'Enter the event name.');
      if (_staff.isEmpty) return showProblem(context, 'Select who conducts the event.');
      if (_territory == null) return showProblem(context, 'Select the location.');
      _pos ??= await _here(context);
      if (_pos == null) return;
    }
    if (_step == 2) {
      if (_stockRows().isEmpty) return showProblem(context, 'Enter the opening stock for at least one distributor.');
    }
    setState(() => _step++);
  }

  List<Map<String, dynamic>> _stockRows() => _stockRowsOf(_blocks);

  List<Map<String, dynamic>> _stockRowsOf(List<_Block> b) => [
        for (final block in b)
          if (block.distributor != null)
            for (final e in block.qty.entries)
              if ((num.tryParse(e.value.text.trim()) ?? 0) > 0)
                {'distributor_id': block.distributor, 'product_id': e.key, 'qty': num.parse(e.value.text.trim())},
      ];

  Future<void> _confirm() async {
    setState(() => _busy = true);
    try {
      final district = _territory?['district_id'];
      await Services.api.post('/api/v1/events', {
        'name': _name.text.trim(),
        'staff_ids': _staff.toList(),
        'district_id': district,
        'territory_id': _territory!['id'],
        'location': '${_territory!['name']}',
        'latitude': _pos?.latitude,
        'longitude': _pos?.longitude,
        'mrp': _territory!['mrp'],
        'has_offer': _offer,
        if (_offer) 'offer_price': _coupon,
        'stock': _stockRows(),
        'confirm': true,
      });
      if (!mounted) return;
      final total = _stockRows().fold<num>(0, (a, r) => a + (r['qty'] as num));
      await Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => _MessageScreen(
          title: _name.text.trim(),
          message: 'Opening stock confirmed – ${_q(total)} bottles. Event is running. '
              'Task is on hold till you end the day or the event.',
        ),
      ));
    } catch (e) {
      if (mounted) showProblem(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = _options;
    if (o == null) {
      return const _Frame(subtitle: 'Loading', children: [Padding(padding: EdgeInsets.all(40), child: LoadingView())]);
    }
    switch (_step) {
      case 1:
        return _details();
      case 2:
        return _Frame(
          subtitle: 'Step 2 of 3 – Opening Stock',
          step: 2,
          onBack: () => setState(() => _step = 1),
          bottom: GradientButton(label: 'Next', onPressed: _next),
          children: [
            _StockEditor(
              products: _products,
              distributors: _distributors,
              blocks: _blocks,
              heading: 'Opening stock (bottles)',
              addLabel: 'Add another distributor',
              addSubtitle: null,
              onChanged: () => setState(() {}),
            ),
          ],
        );
      default:
        return _confirmStep();
    }
  }

  Widget _details() {
    final territories = _list(_options?['territories']);
    final staffNames = _list(_options?['staff']).where((s) => _staff.contains(s['id'])).map((s) => s['name']).join(', ');
    return _Frame(
      subtitle: 'Step 1 of 3 – Event Details',
      step: 1,
      bottom: GradientButton(label: 'Next', onPressed: _next),
      children: [
        _label('Event name', required: true),
        TextField(controller: _name, textCapitalization: TextCapitalization.words, decoration: _field('e.g. Lulu Mall Sampling')),
        _label('Conducted by', required: true),
        InkWell(
          onTap: _pickStaff,
          child: InputDecorator(
            decoration: _field().copyWith(suffixIcon: const Icon(Icons.keyboard_arrow_down_rounded)),
            child: Text(staffNames.isEmpty ? 'Select staff' : staffNames,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: staffNames.isEmpty ? AppColors.muted : AppColors.text)),
          ),
        ),
        _label('Location (District / Territory)', required: true),
        DropdownButtonFormField<int>(
          initialValue: _territory?['id'] as int?,
          isExpanded: true,
          decoration: _field('Select territory'),
          items: [
            for (final t in territories)
              DropdownMenuItem(
                  value: t['id'] as int,
                  child: Text(t['district'] != null ? '${t['district']} · ${t['name']}' : '${t['name']}',
                      overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => setState(() {
            _territory = territories.firstWhere((t) => t['id'] == v);
            for (final b in _blocks) {
              b.distributor = null;
            }
          }),
        ),
        _label('MRP'),
        InputDecorator(
          decoration: _field(),
          child: Text(
            _territory == null || _n(_territory!['mrp']) == 0
                ? 'Fills automatically from the territory'
                : '₹${_q(_n(_territory!['mrp']))}  (auto – as per territory)',
            style: TextStyle(color: _territory == null ? AppColors.muted : AppColors.text),
          ),
        ),
        _label('Offer'),
        Container(
          height: 42,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(21),
            border: Border.all(color: const Color(0xFFD5DEEE)),
          ),
          child: Row(children: [
            for (final yes in [true, false])
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _offer = yes),
                  child: Container(
                    margin: const EdgeInsets.all(3),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _offer == yes ? const Color(0xFFDCE7FB) : Colors.transparent,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text(yes ? (_offer ? '✓ Yes' : 'Yes') : (!_offer ? '✓ No' : 'No'),
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: _offer == yes ? AppColors.primary : AppColors.muted)),
                  ),
                ),
              ),
          ]),
        ),
        if (_offer) ...[
          const SizedBox(height: 10),
          Row(children: [
            for (final v in [20, 30, 50])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text('₹$v'),
                  selected: _coupon == v,
                  showCheckmark: false,
                  selectedColor: AppColors.primary,
                  labelStyle: TextStyle(color: _coupon == v ? Colors.white : AppColors.text, fontWeight: FontWeight.w800),
                  onSelected: (_) => setState(() => _coupon = v),
                ),
              ),
          ]),
        ],
      ],
    );
  }

  Widget _confirmStep() {
    final products = _products;
    final totals = <int, num>{};
    final byDist = <int, num>{};
    for (final b in _blocks) {
      if (b.distributor == null) continue;
      b.qty.forEach((pid, c) {
        final v = num.tryParse(c.text.trim()) ?? 0;
        totals[pid] = (totals[pid] ?? 0) + v;
        byDist[b.distributor!] = (byDist[b.distributor!] ?? 0) + v;
      });
    }
    final names = {for (final d in _list(_options?['distributors'])) d['id'] as int: '${d['name']}'};
    final grand = byDist.values.fold<num>(0, (a, b) => a + b);
    return _Frame(
      subtitle: 'Step 3 of 3 – Confirm Opening Stock',
      step: 3,
      onBack: () => setState(() => _step = 2),
      children: [
        _sectionTitle('Total opening stock', trailing: 'all distributors'),
        _Grid(products: products, values: totals),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('By distributor', style: TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            for (final e in byDist.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Expanded(child: Text(names[e.key] ?? '')),
                  Text(_q(e.value), style: const TextStyle(fontWeight: FontWeight.w800)),
                ]),
              ),
            const Divider(),
            Row(children: [
              const Expanded(child: Text('Total', style: TextStyle(fontWeight: FontWeight.w900))),
              Text(_q(grand), style: const TextStyle(fontWeight: FontWeight.w900)),
            ]),
          ]),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: () => setState(() => _step = 2),
              child: const Text('‹ Back to edit'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _green, minimumSize: const Size.fromHeight(48)),
              onPressed: _busy ? null : _confirm,
              child: _busy
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Confirm'),
            ),
          ),
        ]),
      ],
    );
  }
}

class _MessageScreen extends StatelessWidget {
  const _MessageScreen({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (_, __) => _goDashboard(context),
      child: _Frame(
        subtitle: title,
        onBack: () => _goDashboard(context),
        bottom: GradientButton(label: 'Go to Dashboard', onPressed: () => _goDashboard(context)),
        children: [_notice(message, tint: _green)],
      ),
    );
  }
}

// ====================================================================== the card on Home
class ActiveEventCard extends StatefulWidget {
  const ActiveEventCard({super.key});

  @override
  State<ActiveEventCard> createState() => _ActiveEventCardState();
}

class _ActiveEventCardState extends State<ActiveEventCard> {
  Map<String, dynamic>? _event;

  @override
  void initState() {
    super.initState();
    Services.refresh.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    Services.refresh.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await Services.api.get('/api/v1/events', query: {'active': '1'}) as Map<String, dynamic>;
      final events = _list(data['events']);
      if (mounted) setState(() => _event = events.isEmpty ? null : events.first);
    } catch (_) {
      // Offline or the module is not on the server: the card is simply not shown.
    }
  }

  Future<void> _continue() async {
    final e = _event!;
    final pos = await _here(context);
    if (pos == null || !mounted) return;
    final lat = (e['latitude'] as num?)?.toDouble();
    final lng = (e['longitude'] as num?)?.toDouble();
    if (lat != null && lng != null && !(lat == 0 && lng == 0)) {
      final metres = Geolocator.distanceBetween(pos.latitude, pos.longitude, lat, lng);
      if (metres > 200) {
        showProblem(context, 'You are ${metres.round()} m from the event. Be within 200 m of the event location to continue.');
        return;
      }
    }
    final today = fmtDate(DateTime.now());
    final closedToday = ((e['day_dates'] as List?) ?? []).contains(today);
    if (closedToday) {
      showProblem(context, 'Today is already closed. The event continues tomorrow.');
      return;
    }
    // A later day starts with its opening stock (Step 2 and 3) before it can be ended.
    final laterDay = (e['has_previous_day'] == true);
    if (e['state'] == 'on_hold' && laterDay) {
      final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => _NextDayStockScreen(event: e)));
      if (ok != true || !mounted) return;
      await _load();
      if (_event == null || !mounted) return;
    }
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${_event!['name']}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            Text('${_day(_event!)} · Event Running', style: const TextStyle(color: AppColors.muted)),
            const SizedBox(height: 10),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(backgroundColor: Color(0xFFFFEDD5), child: Icon(Icons.schedule_rounded, color: _orange)),
              title: const Text('End of the Day', style: TextStyle(fontWeight: FontWeight.w800)),
              subtitle: const Text('Event continues tomorrow'),
              onTap: () => Navigator.pop(sheet, 'day'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(backgroundColor: Color(0xFFDCE7FB), child: Icon(Icons.flag_rounded, color: AppColors.primary)),
              title: const Text('End of the Event', style: TextStyle(fontWeight: FontWeight.w800)),
              subtitle: const Text('Last day – close the event and see the report'),
              onTap: () => Navigator.pop(sheet, 'end'),
            ),
          ]),
        ),
      ),
    );
    if (choice == null || !mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => _EndScreen(event: _event!, last: choice == 'end')));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final e = _event;
    if (e == null) return const SizedBox.shrink();
    final staff = (e['staff'] as List?)?.length ?? 0;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _orange, width: 1.6),
      ),
      child: Column(children: [
        Row(children: [
          const CircleAvatar(backgroundColor: _orange, child: Icon(Icons.celebration_rounded, color: Colors.white)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${e['name']}', maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
              Text('${(e['territory'] as Map?)?['name'] ?? ''} · ${_day(e)} · $staff staff',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(color: _orange, borderRadius: BorderRadius.circular(14)),
            child: Text(e['state'] == 'on_hold' ? '● On hold' : '● Event Running',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11)),
          ),
        ]),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
            onPressed: _continue,
            child: const Text('Continue event ›'),
          ),
        ),
      ]),
    );
  }
}

// ====================================================================== next day: opening stock
class _NextDayStockScreen extends StatefulWidget {
  const _NextDayStockScreen({required this.event});

  final Map<String, dynamic> event;

  @override
  State<_NextDayStockScreen> createState() => _NextDayStockScreenState();
}

class _NextDayStockScreenState extends State<_NextDayStockScreen> {
  int _step = 2;
  List<Map<String, dynamic>> _distributors = [];
  late final List<Map<String, dynamic>> _products = _list(widget.event['products']);
  late final List<_Block> _blocks = [_Block(_products)];
  bool _busy = false;

  bool get _returned => widget.event['returned_yesterday'] == true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await Services.api.get('/api/v1/events/options') as Map<String, dynamic>;
      final all = _list(data['distributors']);
      if (mounted) setState(() => _distributors = [...all.where((d) => d['company'] != true), ...all.where((d) => d['company'] == true)]);
    } catch (_) {}
  }

  Future<void> _confirm() async {
    setState(() => _busy = true);
    try {
      await Services.api.post('/api/v1/events/${widget.event['id']}/stock', {'stock': _stockRows(_blocks)});
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showProblem(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final opening = {for (final r in _list(widget.event['opening'])) r['product_id'] as int: _n(r['opening']) + 0};
    final carried = _returned ? <int, num>{} : opening;
    if (_step == 3) {
      final totals = <int, num>{...carried};
      for (final b in _blocks) {
        b.qty.forEach((pid, c) => totals[pid] = (totals[pid] ?? 0) + (num.tryParse(c.text.trim()) ?? 0));
      }
      return _Frame(
        subtitle: 'Step 3 of 3 – Confirm Opening Stock · ${_day(widget.event)}',
        step: 3,
        onBack: () => setState(() => _step = 2),
        children: [
          _sectionTitle('Total opening stock', trailing: 'all distributors'),
          _Grid(products: _products, values: totals),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  onPressed: () => setState(() => _step = 2),
                  child: const Text('‹ Back to edit')),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _green, minimumSize: const Size.fromHeight(48)),
                onPressed: _busy ? null : _confirm,
                child: const Text('Confirm'),
              ),
            ),
          ]),
        ],
      );
    }
    return _Frame(
      subtitle: 'Step 2 of 3 – Opening Stock · ${_day(widget.event)}',
      step: 2,
      bottom: GradientButton(
        label: 'Next – confirm',
        onPressed: () {
          if (_returned && _stockRows(_blocks).isEmpty) {
            showProblem(context, 'The stock was returned yesterday. Enter the opening stock from a distributor.');
            return;
          }
          setState(() => _step = 3);
        },
      ),
      children: [
        if (_returned)
          _notice('Stock was returned yesterday – opening stock starts at 0.')
        else ...[
          _notice('No return yesterday – opening stock = yesterday\'s closing stock.'),
          _sectionTitle('Opening stock (from Day ${(widget.event['day_no'] as num) - 1} closing)'),
          _Grid(products: _products, values: carried),
          const SizedBox(height: 14),
        ],
        _StockEditor(
          products: _products,
          distributors: _distributors,
          blocks: _blocks,
          heading: _returned ? 'Opening stock (bottles)' : 'Stock to add (bottles)',
          addLabel: _returned ? 'Add another distributor' : 'Add stock from a distributor',
          addSubtitle: _returned ? null : 'Select distributor → qty by flavour',
          onChanged: () => setState(() {}),
        ),
      ],
    );
  }
}

// ====================================================================== end of the day / end of the event
class _EndScreen extends StatefulWidget {
  const _EndScreen({required this.event, required this.last});

  final Map<String, dynamic> event;
  final bool last;

  @override
  State<_EndScreen> createState() => _EndScreenState();
}

class _EndScreenState extends State<_EndScreen> {
  int _step = 1;
  late final List<Map<String, dynamic>> _products = _list(widget.event['products']);
  late final Map<int, TextEditingController> _samples = _controllers(_products);
  late final Map<int, TextEditingController> _damage = _controllers(_products);
  late final List<_Block> _returns = [_Block(_products)];
  final _coupons = TextEditingController();
  List<Map<String, dynamic>> _distributors = [];
  bool _returnIt = false;
  bool _busy = false;

  late final Map<int, num> _available = {
    for (final r in _list(widget.event['opening'])) r['product_id'] as int: _n(r['opening']) + _n(r['added']),
  };

  @override
  void initState() {
    super.initState();
    _returnIt = widget.last;
    _load();
  }

  @override
  void dispose() {
    _coupons.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await Services.api.get('/api/v1/events/options') as Map<String, dynamic>;
      final all = _list(data['distributors']);
      if (mounted) setState(() => _distributors = [...all.where((d) => d['company'] != true), ...all.where((d) => d['company'] == true)]);
    } catch (_) {}
  }

  num _left(int pid) =>
      (_available[pid] ?? 0) - (num.tryParse(_samples[pid]!.text.trim()) ?? 0) - (num.tryParse(_damage[pid]!.text.trim()) ?? 0);

  Map<String, dynamic> _map(Map<int, TextEditingController> c) =>
      {for (final e in c.entries) '${e.key}': num.tryParse(e.value.text.trim()) ?? 0};

  void _toStepTwo() {
    for (final p in _products) {
      final pid = p['id'] as int;
      if (_left(pid) < 0) {
        showProblem(context, '${p['name']}: samples and damage are more than the stock (${_q(_available[pid] ?? 0)}).');
        return;
      }
    }
    // The stock that is left is what goes back, so the first distributor starts with it filled in.
    final first = _returns.first;
    for (final p in _products) {
      final pid = p['id'] as int;
      final left = _left(pid);
      first.qty[pid]!.text = _returnIt && left > 0 ? _q(left) : '';
    }
    setState(() => _step = 2);
  }

  Future<void> _submit() async {
    if (_returnIt && _stockRows(_returns).isEmpty) {
      showProblem(context, 'Choose the distributor the stock goes back to.');
      return;
    }
    if (widget.last && widget.event['has_offer'] == true && (int.tryParse(_coupons.text.trim()) == null)) {
      showProblem(context, 'Enter the number of coupons used.');
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await Services.api.post('/api/v1/events/${widget.event['id']}/${widget.last ? 'end' : 'day'}', {
        'samples': _map(_samples),
        'damage': _map(_damage),
        'action': _returnIt ? 'return' : 'stays',
        'returns': _returnIt ? _stockRows(_returns) : [],
        if (widget.last) 'coupons_used': int.tryParse(_coupons.text.trim()) ?? 0,
      }) as Map<String, dynamic>;
      if (!mounted) return;
      if (widget.last) {
        await Navigator.of(context).pushReplacement(MaterialPageRoute(
            builder: (_) => EventReportScreen(eventId: widget.event['id'] as int, justEnded: true)));
      } else {
        final closing = _n(result['closing_total']);
        await Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => _MessageScreen(
            title: '${widget.event['name']}',
            message: '${_day(widget.event)} closed. Task on hold till tomorrow. '
                'Closing stock at the event: ${_q(closing)} bottles.',
          ),
        ));
      }
    } catch (e) {
      if (mounted) showProblem(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.last ? 'End of the Event' : 'End of the Day';
    if (_step == 1) {
      return _Frame(
        subtitle: '$title · 1 of 2',
        step: 1,
        steps: 3,
        bottom: GradientButton(label: 'Next', onPressed: _toStepTwo),
        children: [
          _sectionTitle(widget.last ? 'Samples given (last day)' : 'Samples given'),
          _Grid(products: _products, controllers: _samples),
          _sectionTitle(widget.last ? 'Damage (last day)' : 'Damage'),
          _Grid(products: _products, controllers: _damage),
        ],
      );
    }
    final coupon = _n(widget.event['offer_price']);
    return _Frame(
      subtitle: '$title · 2 of 2',
      step: 2,
      steps: 3,
      onBack: () => setState(() => _step = 1),
      bottom: GradientButton(
        label: widget.last ? 'End the event' : 'End the day',
        busy: _busy,
        onPressed: _busy ? null : _submit,
      ),
      children: [
        if (!widget.last) ...[
          _sectionTitle('Closing stock'),
          Container(
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(21),
              border: Border.all(color: const Color(0xFFD5DEEE)),
            ),
            child: Row(children: [
              for (final back in [false, true])
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _returnIt = back),
                    child: Container(
                      margin: const EdgeInsets.all(3),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _returnIt == back ? const Color(0xFFDCE7FB) : Colors.transparent,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text(back ? (_returnIt ? '✓ Return to distributor' : 'Return to distributor')
                          : (!_returnIt ? '✓ Stays at the event' : 'Stays at the event'),
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5,
                              color: _returnIt == back ? AppColors.primary : AppColors.muted)),
                    ),
                  ),
                ),
            ]),
          ),
        ],
        if (_returnIt)
          _StockEditor(
            products: _products,
            distributors: _distributors,
            blocks: _returns,
            first: widget.last ? 'Return remaining stock to' : 'Return to',
            heading: 'Qty returned',
            addLabel: 'Return to another distributor',
            addSubtitle: null,
            onChanged: () => setState(() {}),
          )
        else ...[
          _sectionTitle('Stays at the event', trailing: 'bottles'),
          _Grid(products: _products, values: {for (final p in _products) p['id'] as int: _left(p['id'] as int)}),
        ],
        if (widget.last && widget.event['has_offer'] == true) ...[
          _label('No. of coupons used (₹${_q(coupon)} offer)', required: true),
          TextField(controller: _coupons, keyboardType: TextInputType.number, decoration: _field('0')),
        ],
      ],
    );
  }
}

// ====================================================================== the event report
class EventReportScreen extends StatefulWidget {
  const EventReportScreen({super.key, required this.eventId, this.justEnded = false});

  final int eventId;
  final bool justEnded;

  @override
  State<EventReportScreen> createState() => _EventReportScreenState();
}

class _EventReportScreenState extends State<EventReportScreen> {
  Map<String, dynamic>? _data;
  String? _day;
  String? _error;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await Services.api.get('/api/v1/events/${widget.eventId}/report',
          query: {if (_day != null) 'day': _day!}) as Map<String, dynamic>;
      if (mounted) setState(() => _data = data);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _excel() async {
    setState(() => _exporting = true);
    try {
      final result = await Services.api.post('/api/v1/events/${widget.eventId}/export', {}) as Map<String, dynamic>;
      final url = Uri.parse(await Services.api.url('${result['path']}'));
      final opened = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!opened && mounted) showSnack(context, 'Could not open the download.');
    } catch (e) {
      if (mounted) showProblem(context, e.toString());
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    if (_error != null) {
      return _Frame(subtitle: 'Event report', children: [ErrorView(message: _error!, onRetry: _load)]);
    }
    if (d == null) {
      return const _Frame(subtitle: 'Event report', children: [Padding(padding: EdgeInsets.all(40), child: LoadingView())]);
    }
    final e = (d['event'] as Map).cast<String, dynamic>();
    final rows = _list(d['rows']);
    final totals = (d['totals'] as Map).cast<String, dynamic>();
    final days = ((d['days'] as List?) ?? []).cast<String>();
    final coupons = (d['coupons'] as Map).cast<String, dynamic>();
    final staff = (e['staff'] as List?)?.length ?? 0;
    final addedAll = _n(totals['opening']) + _n(totals['added']);

    Widget summary() => Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
          child: Wrap(runSpacing: 10, children: [
            for (final item in [
              ('Opening + added', _q(addedAll), AppColors.text),
              ('Samples', _q(_n(totals['samples'])), AppColors.text),
              ('Damage', _q(_n(totals['damage'])), AppColors.text),
              ('Returned', _q(_n(totals['returned'])), AppColors.text),
              ('Sales (auto)', _q(_n(totals['sold'])), _green),
              ('Coupons used', e['has_offer'] == true ? '${coupons['used']} × ₹${coupons['value']}' : '–', AppColors.text),
            ])
              SizedBox(
                width: (MediaQuery.of(context).size.width - 32 - 28) / 2,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(item.$1, style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
                  Text(item.$2, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: item.$3)),
                ]),
              ),
          ]),
        );

    Widget cellText(String t, {bool head = false, Color? color, bool bold = false, TextAlign align = TextAlign.right}) =>
        Text(t,
            textAlign: align,
            style: TextStyle(
                fontSize: head ? 11 : 12.5,
                color: head ? AppColors.muted : color,
                fontWeight: head || bold ? FontWeight.w800 : FontWeight.w500));

    return _Frame(
      subtitle: widget.justEnded ? '${e['name']} · ${d['days'] != null ? days.length : 0} days' : '${e['name']}',
      onBack: widget.justEnded ? () => _goDashboard(context) : null,
      bottom: widget.justEnded ? GradientButton(label: 'Done', onPressed: () => _goDashboard(context)) : null,
      children: [
        if (widget.justEnded) ...[
          summary(),
          const SizedBox(height: 10),
          _notice('Event completed. Full flavour-wise report below.', tint: _green),
        ],
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
          child: Wrap(runSpacing: 10, children: [
            for (final item in [
              ('Location', '${e['location']}'),
              ('MRP · Offer', '₹${_q(_n(e['mrp']))} · ${e['has_offer'] == true ? '₹${e['offer_price']}' : 'No offer'}'),
              ('Conducted by', '$staff staff'),
              ('Coupons used', '${coupons['used']}'),
            ])
              SizedBox(
                width: (MediaQuery.of(context).size.width - 32 - 28) / 2,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(item.$1, style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
                  Text(item.$2, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                ]),
              ),
          ]),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
          child: rows.isEmpty
              ? const Padding(padding: EdgeInsets.all(16), child: Text('Nothing recorded yet.', style: TextStyle(color: AppColors.muted)))
              : Table(
                  columnWidths: const {0: FlexColumnWidth(1.4)},
                  children: [
                    TableRow(children: [
                      cellText('Flav', head: true, align: TextAlign.left),
                      for (final h in ['Open', 'Add', 'Smpl', 'Dmg', 'Ret', 'Sales']) cellText(h, head: true),
                    ]),
                    for (final r in rows)
                      TableRow(children: [
                        Padding(padding: const EdgeInsets.symmetric(vertical: 5),
                            child: cellText('${r['code']}', bold: true, align: TextAlign.left)),
                        for (final k in ['opening', 'added', 'samples', 'damage', 'returned'])
                          Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: cellText(_q(_n(r[k])))),
                        Padding(padding: const EdgeInsets.symmetric(vertical: 5),
                            child: cellText(_q(_n(r['sold'])), color: _green, bold: true)),
                      ]),
                    TableRow(
                      decoration: const BoxDecoration(color: Color(0xFFEEF3FB)),
                      children: [
                        Padding(padding: const EdgeInsets.symmetric(vertical: 6),
                            child: cellText('Total', bold: true, align: TextAlign.left)),
                        for (final k in ['opening', 'added', 'samples', 'damage', 'returned'])
                          Padding(padding: const EdgeInsets.symmetric(vertical: 6),
                              child: cellText(_q(_n(totals[k])), bold: true)),
                        Padding(padding: const EdgeInsets.symmetric(vertical: 6),
                            child: cellText(_q(_n(totals['sold'])), color: _green, bold: true)),
                      ],
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (var i = 0; i < days.length; i++)
            ChoiceChip(
              label: Text('Day ${i + 1}'),
              selected: _day == days[i],
              onSelected: (_) {
                setState(() => _day = days[i]);
                _load();
              },
            ),
          ChoiceChip(
            label: const Text('All days'),
            selected: _day == null,
            onSelected: (_) {
              setState(() => _day = null);
              _load();
            },
          ),
        ]),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: _exporting ? null : _excel,
          icon: _exporting
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.table_view_rounded),
          label: const Text('Download Excel'),
        ),
      ],
    );
  }
}
