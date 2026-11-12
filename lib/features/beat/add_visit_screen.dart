import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/format.dart';
import '../../core/geo.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import 'added_visits.dart';
import 'create_beat_screen.dart' show outletArea, territoryLabel;

/// "Near" starts at this many kilometres from the phone; the person changes it in the filter and it is kept.
const _defaultRadiusKm = 5.0;
const _radiusKey = 'add_visit_radius_km';

/// One group of the list: its name and the clients in it.
class _VGroup {
  _VGroup(this.key, this.label);

  final String key;
  final String label;
  final List<Map<String, dynamic>> rows = [];
}

/// Add a Visit: tick one or more outlets, distributors or leads that are not in today's beat and add them to today.
/// The list is in two collapsed groups, Within 5 km (the distance is the person's to set in the filter) and Others,
/// each client with its distance; it can be searched, narrowed to those near, filtered by category, territory,
/// area and beat, and grouped by any of them.
/// Returns true when something was added.
class AddVisitScreen extends StatefulWidget {
  const AddVisitScreen({super.key, this.skipIds = const {}});

  /// Already in today's beat (planned, added or visited): not offered again.
  final Set<Object?> skipIds;

  @override
  State<AddVisitScreen> createState() => _AddVisitScreenState();
}

class _AddVisitScreenState extends State<AddVisitScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  int _loadToken = 0;

  List<Map<String, dynamic>> _clients = [];
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _territories = [];
  List<Map<String, dynamic>> _beats = [];
  final Map<Object?, Map<String, dynamic>> _picked = {};
  Position? _here;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  // What the list is narrowed to, and how it is grouped.
  int? _categoryId;
  int? _territoryId;
  int? _areaId;
  String? _area;
  final Set<int> _beatIds = {};
  bool _nearOnly = false;
  double _radiusKm = _defaultRadiusKm;
  String _group = 'distance';
  final Set<String> _open = {};

  static const _allAreas = '__all_areas__';

  @override
  void initState() {
    super.initState();
    _load();
    _loadFilterLists();
    _loadRadius();
  }

  /// The distance chosen last time: what "near" means for this person.
  Future<void> _loadRadius() async {
    try {
      final saved = double.tryParse(await Services.storage.read(_radiusKey) ?? '');
      if (saved != null && saved >= 1 && saved <= 100 && mounted) setState(() => _radiusKm = saved);
    } catch (_) {}
  }

  Future<void> _saveRadius() async {
    try {
      await Services.storage.write(_radiusKey, '$_radiusKm');
    } catch (_) {}
  }

  String get _kmText => _radiusKm == _radiusKm.roundToDouble() ? '${_radiusKm.round()} km' : '${_radiusKm.toStringAsFixed(1)} km';

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  bool get _filtered => _categoryId != null || _territoryId != null || _areaId != null || _beatIds.isNotEmpty;

  Map<String, dynamic> _query(int offset) {
    final q = _search.text.trim();
    final here = _here;
    return {
      'limit': 200,
      if (offset > 0) 'offset': offset,
      if (q.isNotEmpty) 'q': q,
      // Everybody, nearest first, each with its distance: the near ones and the others are told apart here.
      if (here != null) ...{'lat': here.latitude, 'lng': here.longitude, 'by_distance': 1},
      if (_categoryId != null) 'category_id': _categoryId,
      if (_territoryId != null) 'territory_id': _territoryId,
      if (_areaId != null) 'area_id': _areaId,
      if (_beatIds.isNotEmpty) 'beat_ids': _beatIds.join(','),
    };
  }

  Future<void> _load() async {
    final token = ++_loadToken;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _here ??= await currentPosition(recentOk: true)
          .timeout(const Duration(seconds: 12))
          .then<Position?>((p) => p, onError: (_) => lastKnownPosition());
      final all = <Map<String, dynamic>>[];
      var categories = _categories;
      while (true) {
        final data = await Services.api.get('/api/v1/clients', query: _query(all.length)) as Map<String, dynamic>;
        if (!mounted || token != _loadToken) return;
        final rows = ((data['clients'] as List?) ?? []).cast<Map<String, dynamic>>();
        final total = (data['total'] as num?)?.toInt() ?? rows.length;
        if (all.isEmpty) {
          final cats = (((data['counts'] as Map?)?['categories']) as List?) ?? const [];
          categories = cats.cast<Map<String, dynamic>>();
        }
        all.addAll(rows);
        // Every page is fetched, so the groups and their counts are complete.
        if (rows.isEmpty || all.length >= total || all.length >= 2000) break;
      }
      if (!mounted || token != _loadToken) return;
      setState(() {
        _clients = all;
        if (categories.isNotEmpty) _categories = categories;
      });
    } catch (e) {
      if (mounted && token == _loadToken) setState(() => _error = e.toString());
    } finally {
      if (mounted && token == _loadToken) setState(() => _loading = false);
    }
  }

  Future<void> _loadFilterLists() async {
    try {
      final data = await Services.api.get('/api/v1/clients/filters') as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _territories = ((data['territories'] as List?) ?? []).cast<Map<String, dynamic>>();
        _beats = ((data['beats'] as List?) ?? []).cast<Map<String, dynamic>>();
      });
    } catch (_) {
      // Without them the territory, area and beat filters simply have nothing to offer.
    }
  }

  void _onSearch(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _load);
  }

  /// Outlets, distributors and leads can all be added to today's visits.
  static bool _visitable(Map<String, dynamic> c) => true;

  double? _metres(Map<String, dynamic> c) => metresTo(_here, c);

  // ---------------------------------------------------------------- grouping

  Map<String, dynamic>? get _territory => _territories.where((t) => t['id'] == _territoryId).firstOrNull;

  List<_VGroup> _groups() {
    final rows = _clients.where((c) => _visitable(c) && !widget.skipIds.contains(c['id'])).toList();
    bool isNear(Map<String, dynamic> c) {
      final m = _metres(c);
      return m != null && m <= _radiusKm * 1000;
    }

    if (_group == 'distance') {
      final near = _VGroup('near', 'Within $_kmText');
      final others = _VGroup('others', 'Others');
      for (final c in rows) {
        (isNear(c) ? near : others).rows.add(c);
      }
      return _nearOnly ? [near] : [near, others];
    }

    final shown = _nearOnly ? rows.where(isNear).toList() : rows;
    final groups = <String, _VGroup>{};
    final none = _VGroup('none', const {'territory': 'No city / town', 'area': 'No area', 'beat': 'No beat', 'category': 'No category'}[_group] ?? 'None');

    List<(String, String)> refsOf(Map<String, dynamic> c) {
      (String, String)? ref(Object? r, String prefix) =>
          r is Map && r['id'] != null ? ('$prefix${r['id']}', '${r['name']}') : null;
      switch (_group) {
        case 'territory':
          final many = (c['territories'] as List?) ?? const [];
          return [for (final r in many.isNotEmpty ? many : [c['territory']]) if (ref(r, 't') != null) ref(r, 't')!];
        case 'area':
          if (c.containsKey('area_master')) {
            final r = ref(c['area_master'], 'a');
            return r == null ? const [] : [r];
          }
          final name = outletArea(c);
          return name == null ? const [] : [('n$name', name)];
        case 'beat':
          return [for (final r in ((c['routes'] as List?) ?? const [])) if (ref(r, 'b') != null) ref(r, 'b')!];
        default:
          final r = ref(c['category'], 'c');
          return r == null ? const [] : [r];
      }
    }

    for (final c in shown) {
      final refs = refsOf(c);
      if (refs.isEmpty) {
        none.rows.add(c);
        continue;
      }
      for (final (key, label) in refs) {
        groups.putIfAbsent(key, () => _VGroup(key, label)).rows.add(c);
      }
    }
    final ordered = groups.values.toList()..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    if (none.rows.isNotEmpty) ordered.add(none);
    return ordered;
  }

  // ---------------------------------------------------------------- adding

  Future<void> _addToToday() async {
    if (_picked.isEmpty) return;
    setState(() => _busy = true);
    await AddedVisits.add(_picked.values.toList());
    // Saved in today's plan too, as planned stops: they then count in the day's summary and the Next Visit
    // suggestion. Offline or on an older server the list kept on the phone still shows them.
    try {
      await Services.api.post('/api/v1/route-plan/add-visit', {'partner_ids': _picked.keys.toList()});
    } catch (_) {}
    if (!mounted) return;
    showSnack(context, _picked.length == 1 ? 'Added to today\'s beat' : '${_picked.length} added to today\'s beat');
    Navigator.of(context).pop(true);
  }

  // ---------------------------------------------------------------- the screen

  @override
  Widget build(BuildContext context) {
    final groups = _groups();
    final visible = groups.fold<int>(0, (sum, g) => sum + g.rows.length);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Add a Visit', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          Text('Choose the client – nothing else',
              style: TextStyle(fontSize: 11.5, color: AppColors.muted, fontWeight: FontWeight.w500)),
        ]),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
          child: GradientButton(
            label: _picked.isEmpty ? 'Add to today\'s beat' : 'Add ${_picked.length} to today\'s beat',
            busy: _busy,
            onPressed: _picked.isEmpty || _busy ? null : _addToToday,
          ),
        ),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _search,
                onChanged: _onSearch,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: 'Search outlet / distributor / lead…',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.border)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            _filterButton(),
          ]),
        ),
        _chipsRow(),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: _error != null && _clients.isEmpty
                ? ListView(children: [ErrorView(message: _error!, onRetry: _load)])
                : ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
                    if (_here == null && !_loading)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: Text('Your location is not available, so distances cannot be shown and everyone is under Others.',
                            style: TextStyle(fontSize: 12, color: AppColors.warning)),
                      ),
                    if (visible == 0 && !_loading)
                      const EmptyView(icon: Icons.storefront_rounded, text: 'No outlet to add here.\nTry a search or change the filter.'),
                    for (final g in groups) ..._groupWidgets(g),
                  ]),
          ),
        ),
      ]),
    );
  }

  Widget _filterButton() => InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _openFilters,
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: _filtered || _group != 'distance' ? AppColors.primary.withValues(alpha: 0.1) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _filtered || _group != 'distance' ? AppColors.primary : AppColors.border),
          ),
          child: const Icon(Icons.filter_alt_rounded, color: AppColors.primary),
        ),
      );

  /// All, or only the clients near: two quick choices above the list.
  Widget _chipsRow() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
        child: Row(children: [
          ChoiceChip(
            label: const Text('All'),
            selected: !_nearOnly,
            onSelected: (_) => setState(() => _nearOnly = false),
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            avatar: const Icon(Icons.near_me_rounded, size: 16),
            label: Text('Near me · $_kmText'),
            selected: _nearOnly,
            onSelected: (_) => setState(() => _nearOnly = true),
          ),
          const Spacer(),
          if (_picked.isNotEmpty)
            Text('${_picked.length} selected', style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.primary, fontSize: 12.5)),
        ]),
      );

  List<Widget> _groupWidgets(_VGroup g) {
    final open = _open.contains(g.key);
    return [
      Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 2),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() => open ? _open.remove(g.key) : _open.add(g.key)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(children: [
                Expanded(
                  child: Text(g.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5, color: AppColors.primary)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                  child: Text('${g.rows.length}',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: AppColors.primary)),
                ),
                Icon(open ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, color: AppColors.muted),
              ]),
            ),
          ),
        ),
      ),
      if (open && g.rows.isEmpty)
        const Padding(
          padding: EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: Text('Nobody in this group.', style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
        ),
      if (open) for (final c in g.rows) _row(c),
    ];
  }

  Widget _row(Map<String, dynamic> c) {
    final on = _picked.containsKey(c['id']);
    final where = asText((c['district'] as Map?)?['name']) ?? asText(c['address']) ?? asText(c['city']);
    final metres = _metres(c);
    final detail = [if (where != null) where, if (metres != null) fmtDistance(metres)].join(' · ');
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: CheckboxListTile(
        value: on,
        controlAffinity: ListTileControlAffinity.leading,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        onChanged: (v) => setState(() => v == true ? _picked[c['id']] = c : _picked.remove(c['id'])),
        title: Text('${c['name']}', style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: detail.isEmpty ? null : Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }

  // ---------------------------------------------------------------- the filter sheet

  /// The territory dropdown: "All", then Primary, Secondary and Other under their own labels, A to Z.
  List<DropdownMenuItem<int>> _territoryItems() {
    int byName(Map<String, dynamic> a, Map<String, dynamic> b) =>
        territoryLabel(a).toLowerCase().compareTo(territoryLabel(b).toLowerCase());
    Widget label(String text) => Text(text.toUpperCase(),
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 0.6, color: AppColors.muted));
    final items = <DropdownMenuItem<int>>[const DropdownMenuItem(value: 0, child: Text('All cities / towns'))];
    var header = -1;
    for (final (kind, title) in const [
      ('primary', 'Primary City / Town'),
      ('secondary', 'Secondary City / Town'),
      ('other', 'Other (team / beat)'),
    ]) {
      final rows = _territories.where((t) => (t['kind'] ?? 'primary') == kind).toList()..sort(byName);
      if (rows.isEmpty) continue;
      items.add(DropdownMenuItem(value: header--, enabled: false, child: label(title)));
      for (final t in rows) {
        items.add(DropdownMenuItem(
          value: t['id'] as int,
          child: Padding(padding: const EdgeInsets.only(left: 8), child: Text(territoryLabel(t), overflow: TextOverflow.ellipsis)),
        ));
      }
    }
    return items;
  }

  List<String> _areaNames() {
    final sent = _territory?['areas'];
    final names = <String>[
      if (sent is List) for (final a in sent) if (a is Map && asText(a['name']) != null) '${a['name']}',
    ]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return names;
  }

  int? _areaIdOf(String? name) {
    final sent = _territory?['areas'];
    if (name == null || sent is! List) return null;
    for (final a in sent) {
      if (a is Map && asText(a['name']) == name) return (a['id'] as num?)?.toInt();
    }
    return null;
  }

  Future<void> _openFilters() async {
    if (_territories.isEmpty && _beats.isEmpty) await _loadFilterLists();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (sheet) => StatefulBuilder(
        builder: (context, setSheet) {
          final areas = _areaNames();
          final beats = _beats.where((b) => _territoryId == null || b['territory_id'] == _territoryId).toList()
            ..sort((a, b) => '${a['name']}'.toLowerCase().compareTo('${b['name']}'.toLowerCase()));

          Widget heading(IconData icon, String text) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(children: [
                  Icon(icon, size: 22, color: AppColors.muted),
                  const SizedBox(width: 12),
                  Text(text, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                ]),
              );

          Widget dropdown<T>({
            required T? value,
            required List<DropdownMenuItem<T>> items,
            required String hint,
            required void Function(T?) onChanged,
          }) =>
              Container(
                constraints: const BoxConstraints(minHeight: 54),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<T>(
                    value: value,
                    isExpanded: true,
                    hint: Text(hint, style: const TextStyle(color: AppColors.muted)),
                    icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.muted),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black87),
                    items: items,
                    onChanged: items.isEmpty ? null : (v) => setSheet(() => onChanged(v)),
                  ),
                ),
              );

          Widget chip(String label, bool on, VoidCallback onTap) => ChoiceChip(
                label: Text(label),
                selected: on,
                onSelected: (_) => setSheet(onTap),
              );

          return SafeArea(
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Container(
                  color: AppColors.primary.withValues(alpha: 0.05),
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                  child: Column(children: [
                    Container(
                      width: 44,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(color: AppColors.muted.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(2)),
                    ),
                    Row(children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(15)),
                        child: const Icon(Icons.filter_alt_rounded, color: AppColors.primary, size: 26),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Filter Visits', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 21)),
                          Text('Find the client to add', style: TextStyle(color: AppColors.muted, fontSize: 14)),
                        ]),
                      ),
                      InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => Navigator.pop(sheet),
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white, border: Border.all(color: AppColors.border)),
                          child: const Icon(Icons.close_rounded),
                        ),
                      ),
                    ]),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    heading(Icons.near_me_outlined, 'Near distance'),
                    Row(children: [
                      Expanded(
                        child: Slider(
                          value: _radiusKm.clamp(1, 100),
                          min: 1,
                          max: 100,
                          divisions: 99,
                          label: _kmText,
                          onChanged: (v) => setSheet(() => _radiusKm = v.roundToDouble()),
                        ),
                      ),
                      SizedBox(
                        width: 64,
                        child: Text(_kmText, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                      ),
                    ]),
                    Wrap(spacing: 8, runSpacing: 6, children: [
                      for (final km in const [2.0, 5.0, 10.0, 25.0, 50.0])
                        chip('${km.round()} km', _radiusKm == km, () => _radiusKm = km),
                    ]),
                    const SizedBox(height: 22),
                    heading(Icons.sell_outlined, 'Category'),
                    Wrap(spacing: 8, runSpacing: 6, children: [
                      chip('All', _categoryId == null, () => _categoryId = null),
                      for (final c in _categories)
                        chip('${c['name']}', _categoryId == c['id'], () => _categoryId = c['id'] as int),
                    ]),
                    const SizedBox(height: 22),
                    heading(Icons.location_on_outlined, 'City / Town'),
                    dropdown<int>(
                      value: _territoryId,
                      hint: 'All cities / towns',
                      items: _territoryItems(),
                      onChanged: (v) {
                        final picked = (v == null || v <= 0) ? null : v;
                        if (picked != _territoryId) {
                          _area = null;
                          _areaId = null;
                          _beatIds.clear();
                        }
                        _territoryId = picked;
                      },
                    ),
                    const SizedBox(height: 22),
                    heading(Icons.map_outlined, 'Area'),
                    dropdown<String>(
                      value: areas.contains(_area) ? _area : null,
                      hint: _territoryId == null
                          ? 'Choose a city / town first'
                          : (areas.isEmpty ? 'No areas for this city / town yet' : 'All areas'),
                      items: [
                        if (areas.isNotEmpty) const DropdownMenuItem(value: _allAreas, child: Text('All areas')),
                        for (final a in areas) DropdownMenuItem(value: a, child: Text(a, overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (v) {
                        final picked = v == _allAreas ? null : v;
                        _area = picked;
                        _areaId = _areaIdOf(picked);
                      },
                    ),
                    const SizedBox(height: 22),
                    heading(Icons.route_outlined, 'Beat'),
                    if (beats.isEmpty)
                      const Text('No beats', style: TextStyle(color: AppColors.muted))
                    else
                      Wrap(spacing: 8, runSpacing: 6, children: [
                        for (final b in beats)
                          FilterChip(
                            label: Text('${b['name']}'),
                            selected: _beatIds.contains(b['id']),
                            onSelected: (on) => setSheet(() => on ? _beatIds.add(b['id'] as int) : _beatIds.remove(b['id'])),
                          ),
                      ]),
                    const SizedBox(height: 22),
                    heading(Icons.grid_view_rounded, 'Group by'),
                    Wrap(spacing: 8, runSpacing: 6, children: [
                      chip('Distance', _group == 'distance', () => _group = 'distance'),
                      chip('City / Town', _group == 'territory', () => _group = 'territory'),
                      chip('Area', _group == 'area', () => _group = 'area'),
                      chip('Beat', _group == 'beat', () => _group = 'beat'),
                      chip('Category', _group == 'category', () => _group = 'category'),
                    ]),
                  ]),
                ),
                const Divider(height: 28),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Row(children: [
                    Expanded(
                      flex: 4,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(56),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: () => setSheet(() {
                          _categoryId = null;
                          _territoryId = null;
                          _area = null;
                          _areaId = null;
                          _beatIds.clear();
                          _radiusKm = _defaultRadiusKm;
                          _group = 'distance';
                        }),
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Clear All', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 5,
                      child: GradientButton(label: 'Apply Filter', icon: Icons.check_rounded, onPressed: () => Navigator.pop(sheet)),
                    ),
                  ]),
                ),
              ]),
            ),
          );
        },
      ),
    );
    // Whatever the filter was closed with is kept: the distance stays for the next time too.
    _saveRadius();
    if (mounted) {
      setState(_open.clear);
      _load();
    }
  }
}
