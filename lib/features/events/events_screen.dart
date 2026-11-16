import 'package:flutter/material.dart';
import '../../core/documents.dart';
import '../../widgets/report_download.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/busy.dart';
import '../../widgets/common.dart';
import '../../widgets/location_picker.dart';
import '../../widgets/skeleton.dart';
import 'event_reports_screen.dart';

const _pageBg = Color(0xFFEEF3FB);
const _orange = Color(0xFFEA580C);
const _green = Color(0xFF16A34A);

num _n(dynamic v) => v is num ? v : num.tryParse('$v') ?? 0;
String _q(num v) => fmtQty(v);

List<Map<String, dynamic>> _list(dynamic v) => ((v as List?) ?? []).cast<Map<String, dynamic>>();

Future<Position?> _here(BuildContext context) async {
  try {
    final last = await Geolocator.getLastKnownPosition();
    if (last != null && DateTime.now().difference(last.timestamp).inMinutes < 2) return last;
    return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 10)));
  } catch (_) {
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) return last;
    } catch (_) {}
    if (context.mounted) showProblem(context, 'Turn on location to continue.');
    return null;
  }
}

/// The lists the screens choose from change rarely, so they are kept for a few minutes.
class _Options {
  static Map<String, dynamic>? _data;
  static DateTime? _at;

  static Future<Map<String, dynamic>> get({bool fresh = false}) async {
    final at = _at;
    if (!fresh && _data != null && at != null && DateTime.now().difference(at).inMinutes < 5) return _data!;
    final data = await Services.api.get('/api/v1/events/options') as Map<String, dynamic>;
    _data = data;
    _at = DateTime.now();
    return data;
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
          // The small note gives way on a narrow screen or a large font, never the title.
          Flexible(
            child: Text(trailing,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
          ),
        ],
      ]),
    );

/// Flavours two to a row: the flavour on the left and a square box for the bottles on the right.
class _Grid extends StatelessWidget {
  const _Grid({required this.products, this.controllers, this.values, this.onChanged, this.prefix = ''});

  final String prefix;

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
                // The full name with the code under it: "Mango Saffron" and MS.
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    if (flavourName(p).isNotEmpty)
                      Text(flavourName(p),
                          softWrap: true,
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, height: 1.2)),
                    if (asText(p['code']) != null) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: const Color(0xFFDCE7FB), borderRadius: BorderRadius.circular(8)),
                        child: Text('${p['code']}',
                            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: AppColors.primary)),
                      ),
                    ],
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
                            isDense: true,
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            errorBorder: InputBorder.none,
                            focusedErrorBorder: InputBorder.none,
                            hintText: '0',
                            contentPadding: EdgeInsets.zero,
                          ),
                        )
                      : Text('$prefix${_q(values?[p['id']] ?? 0)}',
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: prefix.isEmpty ? 20 : 17)),
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

  Widget _row(Map<String, dynamic> e, Map<String, String> names) => Card(
        child: ListTile(
          onTap: () async {
            await Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => e['state'] == 'done'
                    ? EventCompletedScreen(eventId: e['id'] as int, name: '${e['name']}')
                    : EventReportScreen(eventId: e['id'] as int)));
            _load();
          },
          title: Text('${e['name']}', style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text([
            '${names[e['state']] ?? e['state']}',
            if (e['territory'] != null) '${(e['territory'] as Map)['name']}',
            '${e['days']} day${e['days'] == 1 ? '' : 's'}',
            if (e['can_act'] == false) 'by ${(e['created_by'] as Map?)?['name'] ?? ''}',
          ].join(' · ')),
          trailing: const Icon(Icons.chevron_right_rounded),
        ),
      );

  @override
  Widget build(BuildContext context) {
    // As an employee only the person's own events: the team's belong to manager mode.
    final events = _events == null
        ? null
        : [for (final e in _events!) if (Services.managerMode.value || e['can_act'] != false) e];
    const names = {'draft': 'Draft', 'running': 'Event Running', 'on_hold': 'On hold', 'done': 'Completed'};
    return Scaffold(
      backgroundColor: _pageBg,
      appBar: AppBar(title: const Text('My Events'), backgroundColor: _pageBg, actions: [const ReportDownloadButton(reportKey: 'events', title: 'Events')]),
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
                    if (events.any((e) => e['can_act'] == false) && events.any((e) => e['can_act'] != false))
                      const Padding(
                        padding: EdgeInsets.fromLTRB(4, 4, 4, 6),
                        child: Text('My events', style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.muted)),
                      ),
                    for (final e in events.where((e) => e['can_act'] != false)) _row(e, names),
                    if (events.any((e) => e['can_act'] == false)) ...[
                      const Padding(
                        padding: EdgeInsets.fromLTRB(4, 14, 4, 2),
                        child: Text('Team members\' events', style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.muted)),
                      ),
                      const Padding(
                        padding: EdgeInsets.fromLTRB(4, 0, 4, 6),
                        child: Text('You can look at these and change who conducts them; the organiser and their team run the days.',
                            style: TextStyle(fontSize: 11.5, color: AppColors.muted)),
                      ),
                      for (final e in events.where((e) => e['can_act'] == false)) _row(e, names),
                    ],
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
          for (final d in widget.distributors.toList()..sort((a, b) => '${a['name']}'.toLowerCase().compareTo('${b['name']}'.toLowerCase())))
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
  Map<String, dynamic>? _category;
  bool _offer = true;
  int _coupon = 30;
  List<_Block> _blocks = [];
  bool _busy = false;
  Position? _pos;

  // Where the event is: the pin on the map, the address written from it (editable), and what that place falls in.
  LatLng? _pin;
  final _location = TextEditingController();
  int? _districtId;
  bool _locationFailed = false;

  @override
  void initState() {
    super.initState();
    _loadOptions();
    _startLocation();
  }

  @override
  void dispose() {
    _name.dispose();
    _location.dispose();
    super.dispose();
  }

  /// The phone's position puts the pin down first; the person moves it from there.
  Future<void> _startLocation() async {
    setState(() => _locationFailed = false);
    final pos = await _here(context);
    if (!mounted) return;
    setState(() {
      _pos = pos;
      _pin = pos == null ? null : LatLng(pos.latitude, pos.longitude);
      _locationFailed = pos == null;
    });
  }

  /// The pin settled somewhere: the territory and district of the office's lists that it falls in (if any).
  void _onPlace(LatLng point, Map<String, dynamic> place) {
    final territoryId = (place['territory'] is Map ? (place['territory'] as Map)['id'] as num? : null)?.toInt();
    setState(() {
      _pin = point;
      _territory = territoryId == null ? null : _list(_options?['territories']).where((t) => t['id'] == territoryId).firstOrNull;
      _districtId = (place['district'] is Map ? (place['district'] as Map)['id'] as num? : null)?.toInt();
    });
  }

  Future<void> _loadOptions() async {
    try {
      final data = await _Options.get();
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

  /// The distributors of the people conducting the event (their primary and secondary territories, or only the
  /// ones allocated to them), then Kumbayah Foods.
  List<Map<String, dynamic>> get _distributors {
    final all = _list(_options?['distributors']);
    final allowed = <Object?>{
      for (final person in _list(_options?['staff']))
        if (_staff.contains(person['id'])) ...((person['distributor_ids'] as List?) ?? const []),
    };
    final company = all.where((d) => d['company'] == true);
    final chosen = all.where((d) => d['company'] != true && allowed.contains(d['id']));
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
      // A distributor that the people now chosen may not use is taken off.
      final allowed = _distributors.map((d) => d['id']).toSet();
      for (final b in _blocks) {
        if (b.distributor != null && !allowed.contains(b.distributor)) b.distributor = null;
      }
    });
  }

  bool _going = false;

  Future<void> _next() async {
    if (_going) return;
    _going = true;
    try {
      await _nextStep();
    } finally {
      _going = false;
    }
  }

  Future<void> _nextStep() async {
    if (_step == 1) {
      if (_name.text.trim().isEmpty) return showProblem(context, 'Enter the event name.');
      if (_staff.isEmpty) return showProblem(context, 'Select who conducts the event.');
      if (_pin == null) return showProblem(context, 'Turn on location so the event can be placed on the map.');
      if (_location.text.trim().isEmpty) return showProblem(context, 'Enter the location.');
      if (_category == null) return showProblem(context, 'Select the price category.');
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
      final district = _districtId ?? _territory?['district_id'];
      await Services.api.post('/api/v1/events', {
        'name': _name.text.trim(),
        'staff_ids': _staff.toList(),
        'district_id': district,
        if (_territory != null) 'territory_id': _territory!['id'],
        'location': _location.text.trim(),
        'latitude': _pin?.latitude ?? _pos?.latitude,
        'longitude': _pin?.longitude ?? _pos?.longitude,
        'price_category_id': _category!['id'],
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
            // Every name, wrapping onto more lines: all the staff at the event are shown.
            child: Text(staffNames.isEmpty ? 'Select staff' : staffNames,
                softWrap: true,
                style: TextStyle(color: staffNames.isEmpty ? AppColors.muted : AppColors.text)),
          ),
        ),
        _label('Location', required: true),
        if (_pin != null)
          LocationPicker(start: _pin!, controller: _location, onPlace: _onPlace, onRefresh: _startLocation)
        else
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFD5DEEE))),
            child: Row(children: [
              Expanded(
                child: Text(_locationFailed ? 'Turn on location to place the event on the map.' : 'Getting your location…',
                    style: const TextStyle(color: AppColors.muted)),
              ),
              if (_locationFailed) TextButton(onPressed: _startLocation, child: const Text('Try again')),
            ]),
          ),
        _label('Price category', required: true),
        Container(
          height: 42,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(21),
            border: Border.all(color: const Color(0xFFD5DEEE)),
          ),
          child: Row(children: [
            for (final c in _list(_options?['price_categories']))
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _category = c),
                  child: Container(
                    margin: const EdgeInsets.all(3),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _category?['id'] == c['id'] ? const Color(0xFFDCE7FB) : Colors.transparent,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text(_category?['id'] == c['id'] ? '\u2713 ${c['name']}' : '${c['name']}',
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: _category?['id'] == c['id'] ? AppColors.primary : AppColors.muted)),
                  ),
                ),
              ),
          ]),
        ),
        if (_list(_options?['price_categories']).isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('No price category is set up yet. Ask the office to add the 149 and 179 categories.',
                style: TextStyle(fontSize: 12, color: AppColors.warning)),
          ),
        if (_category != null) ...[
          _sectionTitle('MRP by flavour', trailing: '${_category!['name']} category \u00B7 auto'),
          _Grid(
            products: _products,
            prefix: '\u20B9',
            values: {
              for (final p in _products)
                p['id'] as int: _n((_category!['mrp'] as Map)['${p['id']}'] ?? 0),
            },
          ),
        ],
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
    // Each distributor's own stock, product by product.
    final perDist = <int, Map<int, num>>{};
    for (final b in _blocks) {
      if (b.distributor == null) continue;
      b.qty.forEach((pid, c) {
        final v = num.tryParse(c.text.trim()) ?? 0;
        totals[pid] = (totals[pid] ?? 0) + v;
        byDist[b.distributor!] = (byDist[b.distributor!] ?? 0) + v;
        if (v > 0) {
          final mine = perDist.putIfAbsent(b.distributor!, () => {});
          mine[pid] = (mine[pid] ?? 0) + v;
        }
      });
    }
    // Only the products that were given a quantity.
    final stocked = products.where((p) => (totals[p['id']] ?? 0) > 0).toList();
    final names = {for (final d in _list(_options?['distributors'])) d['id'] as int: '${d['name']}'};
    final grand = byDist.values.fold<num>(0, (a, b) => a + b);
    return _Frame(
      subtitle: 'Step 3 of 3 – Confirm Opening Stock',
      step: 3,
      onBack: () => setState(() => _step = 2),
      children: [
        _sectionTitle('Total opening stock', trailing: 'all distributors'),
        if (stocked.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('No stock entered.', style: TextStyle(color: AppColors.muted)))
        else
          _Grid(products: stocked, values: totals),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('By distributor', style: TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            for (final e in byDist.entries.where((e) => e.value > 0)) ...[
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 2),
                child: Row(children: [
                  Expanded(
                      child: Text(names[e.key] ?? '', style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.primary))),
                  Text(_q(e.value), style: const TextStyle(fontWeight: FontWeight.w900)),
                ]),
              ),
              // That distributor's products, each with its quantity.
              for (final p in products.where((p) => (perDist[e.key]?[p['id']] ?? 0) > 0))
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 3, 0, 3),
                  child: Row(children: [
                    Expanded(child: Text(flavourLabel(p), style: const TextStyle(fontSize: 13))),
                    Text(_q(perDist[e.key]![p['id']]!), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  ]),
                ),
            ],
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
  /// The card only shows once the person has checked in for the day.
  const ActiveEventCard({super.key, this.checkedIn = true});

  final bool checkedIn;

  @override
  State<ActiveEventCard> createState() => _ActiveEventCardState();
}

class _ActiveEventCardState extends State<ActiveEventCard> {
  List<Map<String, dynamic>> _events = [];
  int _index = 0;
  final _pager = PageController();

  @override
  void initState() {
    super.initState();
    Services.refresh.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    Services.refresh.removeListener(_load);
    _pager.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await Services.api.get('/api/v1/events', query: {'active': '1'}) as Map<String, dynamic>;
      final events = _list(data['events']);
      if (mounted) {
        setState(() {
          _events = events;
          if (_index >= events.length) _index = 0;
        });
      }
    } catch (_) {
      // Offline or the module is not on the server: the card is simply not shown.
    }
  }

  bool _opening = false;

  Future<void> _continue(Map<String, dynamic> event) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      await _continueEvent(event);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _continueEvent(Map<String, dynamic> event) async {
    Map<String, dynamic> e = event;
    final pos = await withBusy(context, 'Checking your location…', () => _here(context));
    if (pos == null || !mounted) return;
    final lat = (e['latitude'] as num?)?.toDouble();
    final lng = (e['longitude'] as num?)?.toDouble();
    final limit = ((e['geofence_m'] as num?) ?? 200).toInt();
    if (limit > 0 && lat != null && lng != null && !(lat == 0 && lng == 0)) {
      final metres = Geolocator.distanceBetween(pos.latitude, pos.longitude, lat, lng);
      if (metres > limit) {
        showProblem(context, 'You are ${metres.round()} m from the event. Be within $limit m of the event location to continue.');
        return;
      }
    }
    // The server says which day is being worked on: a day closed after midnight still belongs to yesterday.
    final today = asText(e['working_day']) ?? fmtDate(DateTime.now());
    final closedToday = ((e['day_dates'] as List?) ?? []).contains(today);
    if (closedToday) {
      showProblem(context, 'Day ${e['days']} is closed. Start Day ${((e['days'] as num?) ?? 0).toInt() + 1} tomorrow.');
      return;
    }
    // The card is light; the stock figures for the day are read now, under a "please wait".
    try {
      e = await withBusy(context, 'Opening the event…',
          () async => await Services.api.get('/api/v1/events/${e['id']}') as Map<String, dynamic>);
    } catch (err) {
      if (mounted) showProblem(context, err.toString());
      return;
    }
    if (!mounted) return;
    // A later day starts with its opening stock (Step 2 and 3) before it can be ended.
    final laterDay = (e['has_previous_day'] == true);
    if (e['state'] == 'on_hold' && laterDay) {
      final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => _StartDayScreen(event: e)));
      if (ok != true || !mounted) return;
      try {
        e = await withBusy(context, 'Opening the event…',
            () async => await Services.api.get('/api/v1/events/${e['id']}') as Map<String, dynamic>);
      } catch (_) {
        return;
      }
      if (!mounted) return;
    }
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${e['name']}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            Text('${_day(e)} · Event Running', style: const TextStyle(color: AppColors.muted)),
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
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => _EndScreen(event: e, last: choice == 'end')));
    _load();
  }

  /// Every running event, one under the other, each with its own button to continue or close it.
  void _showList() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
            Text('${_events.length} events running', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            const SizedBox(height: 10),
            for (final e in _events)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _card(e, onOpen: () {
                  Navigator.pop(sheet);
                  _continue(e);
                }),
              ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Nobody who has not checked in sees the events of the day.
    if (!widget.checkedIn) return const SizedBox.shrink();
    if (_events.isEmpty) {
      // No event running: where its card was, the one finished today says it is closed.
      return ValueListenableBuilder(
        valueListenable: eventJustCompleted,
        builder: (context, done, _) {
          if (done == null || done.day != fmtDate(DateTime.now())) return const SizedBox.shrink();
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _green.withValues(alpha: 0.35)),
            ),
            child: Text('${done.name} – event completed. Task closed.',
                style: const TextStyle(fontSize: 12.5, color: Color(0xFF166534), fontWeight: FontWeight.w600)),
          );
        },
      );
    }
    if (_events.length == 1) return _card(_events.first, onOpen: () => _continue(_events.first));
    // Several events: swipe left or right between them; the count at the top right opens the whole list.
    return Column(children: [
      Align(
        alignment: Alignment.centerRight,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _showList,
          child: Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: _orange, borderRadius: BorderRadius.circular(14)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.celebration_rounded, size: 14, color: Colors.white),
              const SizedBox(width: 5),
              Text('${_index + 1}/${_events.length}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12)),
              const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: Colors.white),
            ]),
          ),
        ),
      ),
      SizedBox(
        height: 134,
        child: PageView.builder(
          controller: _pager,
          itemCount: _events.length,
          onPageChanged: (i) => setState(() => _index = i),
          itemBuilder: (_, i) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: _card(_events[i], onOpen: () => _continue(_events[i])),
          ),
        ),
      ),
    ]);
  }

  Widget _card(Map<String, dynamic> e, {required VoidCallback onOpen}) {
    final staff = (e['staff'] as List?)?.length ?? 0;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _orange, width: 1.6),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          const CircleAvatar(backgroundColor: _orange, child: Icon(Icons.celebration_rounded, color: Colors.white)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${e['name']}', maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
              Text(e['state'] == 'on_hold'
                  ? '${(e['territory'] as Map?)?['name'] ?? ''} · Day ${e['days']} closed · $staff staff'
                  : '${(e['territory'] as Map?)?['name'] ?? ''} · ${_day(e)} · $staff staff',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
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
            onPressed: _opening ? null : onOpen,
            child: _opening
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(e['state'] == 'on_hold' ? 'Start Day ${((e['days'] as num?) ?? 0).toInt() + 1} ›' : 'Continue event ›'),
          ),
        ),
      ]),
    );
  }
}

/// Distributor by distributor: each flavour with what stayed from yesterday, what is added today, and the total.
Widget _openingByDistributor({
  required List<Map<String, dynamic>> products,
  required Map<int, String> names,
  required Map<int, Map<int, num>> stayed,
  required Map<int, Map<int, num>> added,
  String stayedLabel = 'stayed',
}) {
  final ids = {...stayed.keys, ...added.keys}.toList()..sort((a, b) => (names[a] ?? '').compareTo(names[b] ?? ''));
  num grand = 0;
  final children = <Widget>[];
  for (final id in ids) {
    final rows = [
      for (final p in products)
        if (((stayed[id]?[p['id']] ?? 0) + (added[id]?[p['id']] ?? 0)) > 0) p,
    ];
    if (rows.isEmpty) continue;
    final total = rows.fold<num>(0, (a, p) => a + (stayed[id]?[p['id']] ?? 0) + (added[id]?[p['id']] ?? 0));
    grand += total;
    children.add(Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 2),
      child: Row(children: [
        Expanded(child: Text(names[id] ?? '', style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.primary))),
        Text(_q(total), style: const TextStyle(fontWeight: FontWeight.w900)),
      ]),
    ));
    for (final p in rows) {
      final kept = stayed[id]?[p['id']] ?? 0;
      final plus = added[id]?[p['id']] ?? 0;
      children.add(Padding(
        padding: const EdgeInsets.fromLTRB(10, 3, 0, 3),
        child: Row(children: [
          Expanded(child: Text(flavourLabel(p), style: const TextStyle(fontSize: 13))),
          if (kept > 0)
            Text('${_q(kept)} $stayedLabel', style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
          if (kept > 0 && plus > 0) const Text('  +  ', style: TextStyle(fontSize: 11.5, color: AppColors.muted)),
          if (plus > 0) Text('${_q(plus)} added', style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
          const SizedBox(width: 10),
          Text(_q(kept + plus), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        ]),
      ));
    }
  }
  if (children.isEmpty) return const SizedBox.shrink();
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('By distributor', style: TextStyle(fontWeight: FontWeight.w900)),
      ...children,
      const Divider(),
      Row(children: [
        const Expanded(child: Text('Total', style: TextStyle(fontWeight: FontWeight.w900))),
        Text(_q(grand), style: const TextStyle(fontWeight: FontWeight.w900)),
      ]),
    ]),
  );
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
  // Opening stock can be entered for any product, not only the ones used the day before.
  late List<Map<String, dynamic>> _allProducts = _products;
  late List<_Block> _blocks = [_Block(_allProducts)];
  bool _busy = false;

  bool get _returned => widget.event['returned_yesterday'] == true;

  /// What stayed at the event from yesterday: distributor -> flavour -> bottles.
  Map<int, Map<int, num>> get _stayed {
    if (_returned) return {};
    final out = <int, Map<int, num>>{};
    for (final r in _list(widget.event['carry'])) {
      final d = (r['distributor'] as Map)['id'] as int;
      final mine = out.putIfAbsent(d, () => {});
      final pid = r['product_id'] as int;
      mine[pid] = (mine[pid] ?? 0) + _n(r['qty']);
    }
    return out;
  }

  /// What is being added today, by the distributor chosen for each block.
  Map<int, Map<int, num>> get _addedNow {
    final out = <int, Map<int, num>>{};
    for (final b in _blocks) {
      final d = b.distributor;
      if (d == null) continue;
      b.qty.forEach((pid, c) {
        final v = num.tryParse(c.text.trim()) ?? 0;
        if (v <= 0) return;
        final mine = out.putIfAbsent(d, () => {});
        mine[pid] = (mine[pid] ?? 0) + v;
      });
    }
    return out;
  }

  Map<int, String> get _names {
    final out = <int, String>{for (final d in _distributors) d['id'] as int: '${d['name']}'};
    for (final r in _list(widget.event['carry'])) {
      final d = r['distributor'] as Map;
      out.putIfAbsent(d['id'] as int, () => '${d['name']}');
    }
    for (final d in _list(widget.event['distributors'])) {
      out.putIfAbsent(d['id'] as int, () => '${d['name']}');
    }
    return out;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await _Options.get();
      final all = _list(data['distributors']);
      // Only the distributors of the people conducting the event (as on Day 1), then Kumbayah Foods.
      final staffIds = {for (final s in _list(widget.event['staff'])) s['id']};
      final allowed = <Object?>{
        for (final person in _list(data['staff']))
          if (staffIds.contains(person['id'])) ...((person['distributor_ids'] as List?) ?? const []),
        for (final d in _list(widget.event['distributors'])) d['id'],
      };
      final everything = _list(data['products']);
      if (mounted) {
        setState(() {
          _distributors = [
            ...all.where((d) => d['company'] != true && allowed.contains(d['id'])),
            ...all.where((d) => d['company'] == true),
          ];
          if (everything.isNotEmpty) {
            _allProducts = everything;
            _blocks = [_Block(everything)];
          }
        });
      }
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
          if (_allProducts.every((p) => (totals[p['id']] ?? 0) <= 0))
            const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('No stock entered.', style: TextStyle(color: AppColors.muted)))
          else
            _Grid(products: _allProducts.where((p) => (totals[p['id']] ?? 0) > 0).toList(), values: totals),
          const SizedBox(height: 14),
          _openingByDistributor(products: _allProducts, names: _names, stayed: _stayed, added: _addedNow),
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
          const SizedBox(height: 10),
          // Yesterday's stay, distributor by distributor and flavour by flavour.
          _openingByDistributor(products: _allProducts, names: _names, stayed: _stayed, added: const {}),
          const SizedBox(height: 14),
        ],
        _StockEditor(
          products: _allProducts,
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
  late final Map<int, TextEditingController> _closing = _controllers(_products);
  late final List<_Block> _returns = [_Block(_products)];
  final _coupons = TextEditingController();
  final _cash = TextEditingController();
  List<Map<String, dynamic>> _distributors = [];
  bool _busy = false;

  late final Map<int, num> _available = {
    for (final r in _list(widget.event['opening'])) r['product_id'] as int: _n(r['opening']) + _n(r['added']),
  };

  @override
  void initState() {
    super.initState();
    // Stock can only go back to a distributor this event took stock from.
    _distributors = _list(widget.event['distributors']);
  }

  @override
  void dispose() {
    _cash.dispose();
    _coupons.dispose();
    super.dispose();
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
    setState(() => _step = 2);
  }

  /// What staff sent back to distributors, for a flavour (all distributors together).
  num _returned(int pid) {
    num total = 0;
    for (final b in _returns) {
      total += num.tryParse(b.qty[pid]?.text.trim() ?? '') ?? 0;
    }
    return total;
  }

  /// What staff left at the event, for a flavour. On the last day nothing stays.
  num _stays(int pid) => widget.last ? 0 : (num.tryParse(_closing[pid]!.text.trim()) ?? 0);

  /// Sales = opening + added - samples - damage - returned - closing, worked out by the app. Whatever is neither
  /// sent back nor left at the event has been sold.
  num _sold(int pid) => _left(pid) - _returned(pid) - _stays(pid);

  void _toStepThree() {
    for (final p in _products) {
      final pid = p['id'] as int;
      if (_sold(pid) < 0) {
        showProblem(context, '${p['name']}: returned or closing stock is more than what is left (${_q(_left(pid))}).');
        return;
      }
    }
    setState(() => _step = 3);
  }

  Future<void> _submit() async {
    for (final p in _products) {
      final pid = p['id'] as int;
      if (_sold(pid) < 0) {
        showProblem(context, '${p['name']}: returned or closing stock is more than what is left (${_q(_left(pid))}).');
        return;
      }
    }
    if (widget.event['has_offer'] == true && (int.tryParse(_coupons.text.trim()) == null)) {
      showProblem(context, 'Enter the number of coupons used today.');
      return;
    }
    if (num.tryParse(_cash.text.trim().replaceAll(',', '')) == null) {
      showProblem(context, 'Enter the cash received today.');
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await Services.api.post('/api/v1/events/${widget.event['id']}/${widget.last ? 'end' : 'day'}', {
        'samples': _map(_samples),
        'damage': _map(_damage),
        // Some can go back and some can stay, on the same day; anything else is sold.
        'closing': widget.last ? <String, dynamic>{} : _map(_closing),
        'returns': _stockRows(_returns),
        'coupons_used': int.tryParse(_coupons.text.trim()) ?? 0,
        'cash_received': num.tryParse(_cash.text.trim().replaceAll(',', '')) ?? 0,
      }) as Map<String, dynamic>;
      if (!mounted) return;
      if (widget.last) {
        await Navigator.of(context).pushReplacement(MaterialPageRoute(
            builder: (_) => EventCashSummaryScreen(
                eventId: widget.event['id'] as int, name: '${widget.event['name']}')));
      } else {
        final returned = _products.fold<num>(0, (a, p) => a + _returned(p['id'] as int));
        await Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => _DayClosedScreen(
            name: '${widget.event['name']}',
            dayNo: ((result['days'] as num?) ?? 1).toInt(),
            returned: returned,
            closing: _n(result['closing_total']),
            coupons: int.tryParse(_coupons.text.trim()) ?? 0,
            cash: num.tryParse(_cash.text.trim().replaceAll(',', '')) ?? 0,
            hasOffer: widget.event['has_offer'] == true,
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
    final dayLabel = _day(widget.event);
    final coupon = _n(widget.event['offer_price']);
    if (_step == 1) {
      return _Frame(
        subtitle: 'Step 1 of 3 \u2013 $title \u00B7 $dayLabel',
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
    if (_step == 3) {
      return _Frame(
        subtitle: 'Step 3 of 3 \u2013 $title \u00B7 $dayLabel',
        step: 3,
        steps: 3,
        onBack: () => setState(() => _step = 2),
        bottom: GradientButton(
          label: widget.last ? 'Next' : 'End the day',
          busy: _busy,
          onPressed: _busy ? null : _submit,
        ),
        children: [
          if (widget.event['has_offer'] == true) ...[
            _label('Coupons used today (\u20B9${_q(coupon)} offer)', required: true),
            TextField(controller: _coupons, keyboardType: TextInputType.number, decoration: _field('0')),
          ],
          _label('Cash received today', required: true),
          TextField(
            controller: _cash,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: _field('\u20B9 0'),
          ),
        ],
      );
    }
    return _Frame(
      subtitle: 'Step 2 of 3 \u2013 $title \u00B7 $dayLabel',
      step: 2,
      steps: 3,
      onBack: () => setState(() => _step = 1),
      bottom: GradientButton(label: 'Next', onPressed: _toStepThree),
      children: [
        // Return some of it to the distributors, keep some at the event, or both: what is neither is counted as sold.
        _StockEditor(
          products: _products,
          distributors: _distributors,
          blocks: _returns,
          first: widget.last ? 'Return remaining stock to' : 'Return to',
          heading: 'Qty returned',
          addLabel: 'Return to another distributor',
          addSubtitle: 'Optional: leave it empty if nothing goes back',
          onChanged: () => setState(() {}),
        ),
        if (!widget.last) ...[
          _sectionTitle('Stays at the event', trailing: 'count the bottles left'),
          _Grid(products: _products, controllers: _closing, onChanged: () => setState(() {})),
        ],
        if (_products.any((p) => _sold(p['id'] as int) > 0))
          const Padding(
            padding: EdgeInsets.only(top: 4, bottom: 2),
            child: Text('Stock that is neither returned nor left at the event is counted as sold.',
                style: TextStyle(fontSize: 11.5, color: AppColors.muted)),
          ),
        _sectionTitle('Sales (auto)', trailing: 'calculated by the app'),
        _Grid(products: _products, values: {for (final p in _products) p['id'] as int: _sold(p['id'] as int)}),
      ],
    );
  }
}

/// Day closed: the event is on hold till the next day, with the day's summary.
class _DayClosedScreen extends StatelessWidget {
  const _DayClosedScreen({
    required this.name,
    required this.dayNo,
    required this.returned,
    required this.closing,
    required this.coupons,
    required this.cash,
    required this.hasOffer,
  });

  final String name;
  final int dayNo;
  final num returned;
  final num closing;
  final int coupons;
  final num cash;
  final bool hasOffer;

  @override
  Widget build(BuildContext context) {
    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(children: [
            Expanded(child: Text(label, style: const TextStyle(color: AppColors.muted))),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
          ]),
        );
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (_, __) => _goDashboard(context),
      child: _Frame(
        subtitle: name,
        onBack: () => _goDashboard(context),
        bottom: GradientButton(label: 'Go to Dashboard', onPressed: () => _goDashboard(context)),
        children: [
          _notice('Day $dayNo closed. Task on hold till tomorrow.', tint: _green),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Day $dayNo summary', style: const TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              if (returned > 0) row('Returned to distributor', '${_q(returned)} bottles'),
              if (closing > 0) row('Closing stock at the event', '${_q(closing)} bottles'),
              if (hasOffer) row('Coupons used today', '$coupons'),
              row('Cash received today', '\u20B9${_q(cash)}'),
            ]),
          ),
        ],
      ),
    );
  }
}

/// Start Day N: how yesterday closed, then the opening stock for today.
class _StartDayScreen extends StatelessWidget {
  const _StartDayScreen({required this.event});

  final Map<String, dynamic> event;

  @override
  Widget build(BuildContext context) {
    final last = (event['last_day'] as Map?)?.cast<String, dynamic>() ?? const {};
    final returned = last['closing_action'] == 'return';
    final dayNo = ((event['days'] as num?) ?? 0).toInt();
    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(children: [
            Expanded(child: Text(label, style: const TextStyle(color: AppColors.muted))),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
          ]),
        );
    return _Frame(
      subtitle: '${event['name']} \u00B7 Start Day ${dayNo + 1}',
      bottom: GradientButton(
        label: 'Enter opening stock \u203A',
        onPressed: () async {
          final ok = await Navigator.of(context)
              .push<bool>(MaterialPageRoute(builder: (_) => _NextDayStockScreen(event: event)));
          if (ok == true && context.mounted) Navigator.of(context).pop(true);
        },
      ),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Yesterday (Day $dayNo)', style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            row('Closing stock', returned ? 'Returned to distributor' : 'Stayed at the event'),
            if (returned) row('Qty returned', '${_q(_n(last['returned']))} bottles'),
            if (!returned) row('Bottles at the event', '${_q(_n(last['closing']))}'),
            if (event['has_offer'] == true) row('Coupons used', '${last['coupons'] ?? 0}'),
            row('Cash received', '\u20B9${_q(_n(last['cash']))}'),
          ]),
        ),
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

  /// Add one more person or remove one from the people conducting the event.
  Future<void> _editPeople() async {
    try {
      final data = await withBusy(context, 'Loading the team…',
          () async => await Services.api.get('/api/v1/events/${widget.eventId}/staff') as Map<String, dynamic>);
      if (!mounted) return;
      final candidates = _list(data['candidates']);
      final picked = {for (final x in _list(data['staff'])) x['id'] as int};
      final saved = await showModalBottomSheet<bool>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (sheet) => StatefulBuilder(
          builder: (context, setSheet) => SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Conducted by', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17))),
                ),
                Flexible(
                  child: ListView(shrinkWrap: true, children: [
                    for (final x in candidates)
                      CheckboxListTile(
                        value: picked.contains(x['id']),
                        title: Text('${x['name']}'),
                        onChanged: (v) => setSheet(() {
                          if (v == true) {
                            picked.add(x['id'] as int);
                          } else {
                            picked.remove(x['id']);
                          }
                        }),
                      ),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    onPressed: picked.isEmpty ? null : () => Navigator.pop(sheet, true),
                    child: const Text('Save'),
                  ),
                ),
              ]),
            ),
          ),
        ),
      );
      if (saved != true || !mounted) return;
      await Services.api.post('/api/v1/events/${widget.eventId}/staff', {'staff_ids': picked.toList()});
      _load();
    } catch (err) {
      if (mounted) showProblem(context, err.toString());
    }
  }

  Future<void> _excel() async {
    setState(() => _exporting = true);
    try {
      final result = await Services.api.post('/api/v1/events/${widget.eventId}/export', {}) as Map<String, dynamic>;
      final url = Uri.parse(await Services.api.url('${result['path']}'));
      final saved = await downloadAndSave(url, fallbackName: 'event_report.xlsx');
      if (saved && mounted) showSnack(context, 'Report saved.');
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
              ('Organiser', '${(e['created_by'] as Map?)?['name'] ?? ''}'),
              ('Conducted by', _list(e['staff']).map((x) => '${x['name']}').join(', ')),
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
        if (e['can_edit_staff'] == true) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
            onPressed: _editPeople,
            icon: const Icon(Icons.group_add_rounded),
            label: const Text('Add or remove people'),
          ),
        ],
        if (e['can_act'] == false) ...[
          const SizedBox(height: 10),
          _notice('Manager view: ${(e['created_by'] as Map?)?['name'] ?? 'the organiser'} and the team run this event\'s days.'),
        ],
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
                            child: cellText(flavourLabel(r), bold: true, align: TextAlign.left)),
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
