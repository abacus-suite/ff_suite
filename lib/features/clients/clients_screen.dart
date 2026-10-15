import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/format.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/geo.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/map.dart';
import '../../widgets/map_clusters.dart';
import '../../widgets/sdk_map.dart';
import '../../widgets/member_picker.dart';
import 'add_client_screen.dart';
import 'client_detail_screen.dart';
import '../../widgets/skeleton.dart';

/// Contacts with search, category chips, "nearby" sorting and a map.
/// In [pickMode] tapping a contact returns it to the caller.
class ClientsScreen extends StatefulWidget {
  const ClientsScreen({super.key, this.pickMode = false, this.embedded = false, this.onPick});

  final bool pickMode;

  /// What to do with a contact the moment it is chosen, before this screen closes.
  /// Returns what to hand back, or null to stay and let them choose again. It runs
  /// here so that any question it asks - an offsite check-in, say - is asked over
  /// the list they chose from, not over whatever was underneath.
  final Future<Map<String, dynamic>?> Function(BuildContext context, Map<String, dynamic> client)? onPick;
  final bool embedded;

  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  // The full list first: 'Nearby' hides anybody further than 25 km.
  bool _nearby = false;
  bool _showMap = false;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _clients = [];
  List<Map<String, dynamic>> _categories = [];
  int? _categoryId;
  bool _neverVisited = false;
  int? _territoryId;
  int? _beatId;
  String _group = 'none';
  List<Map<String, dynamic>> _territories = [];
  List<Map<String, dynamic>> _beats = [];
  int _total = 0;
  bool _loadingMore = false;
  final ScrollController _scroll = ScrollController();
  Map<String, dynamic> _counts = const {};
  String _sort = 'latest';
  LatLng? _me;
  String _member = 'me';
  final MapController _mapController = MapController();
  double _zoom = 12;

  /// Every located contact, as points. The list is paged; the map is not, or
  /// it would be a map of the first page rather than of the customers.
  List<Map<String, dynamic>> _points = [];
  bool _pointsLoading = false;

  /// Where the map is looking, so only what is on screen has to be grouped.
  MapView? _view;

  /// Where to put the map next, when a tap on a bubble asks for a closer look.
  LatLng? _centre;

  /// The last grouping, kept until the zoom step or the view really changes:
  /// regrouping nine thousand points on every frame of a pinch is what made
  /// the map crawl.
  List<MapCluster> _clusters = const [];
  String _clusterKey = '';

  String get _clientLabel => Services.auth.profile!.label('client', 'Client');

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _loadFilterLists();
    _scroll.addListener(() {
      if (_scroll.hasClients && _scroll.position.pixels > _scroll.position.maxScrollExtent - 700) _loadMore();
    });
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _mapController.dispose();
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  /// The map's own fetch: id, name and a coordinate, for everything visible.
  Future<void> _loadPoints() async {
    if (_pointsLoading) return;
    setState(() => _pointsLoading = true);
    try {
      final query = <String, dynamic>{};
      final q = _search.text.trim();
      if (q.isNotEmpty) query['q'] = q;
      if (_categoryId != null) query['category_id'] = _categoryId;
      if (_neverVisited) query['never_visited'] = 1;
      if (_member != 'me') query['member'] = _member;
      final data = await Services.api.get('/api/v1/clients/map', query: query) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _points = ((data['points'] as List?) ?? []).cast<Map<String, dynamic>>();
        _clusterKey = '';
      });
    } catch (e) {
      if (mounted) showProblem(context, e.toString());
    } finally {
      if (mounted) setState(() => _pointsLoading = false);
    }
  }

  Future<void> _loadCategories() async {
    try {
      final list = await Services.api.get('/api/v1/contact-categories') as List;
      if (mounted) setState(() => _categories = list.cast<Map<String, dynamic>>());
    } catch (_) {
      // Chips are optional.
    }
  }

  /// One page of the list, with whatever filters are on.
  Future<Map<String, dynamic>> _fetch({int offset = 0}) async {
    final query = <String, dynamic>{'limit': 100, if (offset > 0) 'offset': offset};
    final q = _search.text.trim();
    if (q.isNotEmpty) query['q'] = q;
    if (_categoryId != null) query['category_id'] = _categoryId;
    if (_neverVisited) query['never_visited'] = 1;
    if (_territoryId != null) query['territory_id'] = _territoryId;
    if (_beatId != null) query['beat_id'] = _beatId;
    if (_member != 'me') query['member'] = _member;
    if (_nearby) {
      // Never leave the list spinning on a slow GPS fix: fall back to the last known place.
      final pos = await currentPosition(recentOk: true)
          .timeout(const Duration(seconds: 12))
          .catchError((_) async => (await lastKnownPosition())!);
      _me = LatLng(pos.latitude, pos.longitude);
      query.addAll({'lat': pos.latitude, 'lng': pos.longitude, 'radius_km': 25});
    }
    return await Services.api.get('/api/v1/clients', query: query) as Map<String, dynamic>;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _fetch();
      if (!mounted) return;
      setState(() {
        _clients = (data['clients'] as List).cast<Map<String, dynamic>>();
        _total = data['total'] as int;
        _counts = (data['counts'] as Map?)?.cast<String, dynamic>() ?? const {};
        _sortClients();
      });
      // The map shows the same filter, so its points are refetched with the list.
      if (_showMap) unawaited(_loadPoints());
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// The next hundred, when the list is scrolled near its end.
  Future<void> _loadMore() async {
    if (_loading || _loadingMore || _clients.length >= _total) return;
    setState(() => _loadingMore = true);
    try {
      final data = await _fetch(offset: _clients.length);
      if (!mounted) return;
      final more = (data['clients'] as List).cast<Map<String, dynamic>>();
      final have = _clients.map((c) => c['id']).toSet();
      setState(() {
        _clients = [..._clients, ...more.where((c) => !have.contains(c['id']))];
        _total = data['total'] as int;
        _sortClients();
      });
    } catch (_) {
      // The next scroll tries again.
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _onSearch(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _load);
  }

  /// Hands the chosen contact back, after whatever has to happen to it first.
  Future<void> _choose(Map<String, dynamic> client) async {
    final handler = widget.onPick;
    if (handler == null) {
      Navigator.of(context).pop(client);
      return;
    }
    final result = await handler(context, client);
    if (result != null && mounted) Navigator.of(context).pop(result);
  }

  /// A map point holds only an id and a name, so it is opened by id.
  Future<void> _openPoint(Map<String, dynamic> point) async {
    if (widget.pickMode) {
      // A pin carries only an id and a name; what follows needs the whole contact.
      try {
        final full = await Services.api.get('/api/v1/clients/${point['id']}') as Map<String, dynamic>;
        if (mounted) await _choose(full);
      } catch (_) {
        if (mounted) await _choose(point);
      }
      return;
    }
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => ClientDetailScreen(clientId: point['id'] as int)));
    _load();
  }

  Future<void> _open(Map<String, dynamic> client) async {
    if (widget.pickMode) {
      await _choose(client);
      return;
    }
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => ClientDetailScreen(clientId: client['id'] as int)));
    _load();
  }

  Future<void> _add() async {
    final created =
        await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const AddClientScreen()));
    if (created == true) _load();
  }

  /// Newest first, nearest first, or by name.
  void _sortClients() {
    switch (_sort) {
      case 'name':
        _clients.sort((a, b) => '${a['name']}'.toLowerCase().compareTo('${b['name']}'.toLowerCase()));
      case 'nearest':
        _clients.sort((a, b) =>
            ((a['distance_m'] as num?) ?? 1 << 30).compareTo((b['distance_m'] as num?) ?? 1 << 30));
      case 'visited':
        _clients.sort((a, b) =>
            ((a['days_since_visit'] as num?) ?? 1 << 30).compareTo((b['days_since_visit'] as num?) ?? 1 << 30));
      default:
        _clients.sort((a, b) => (b['id'] as int).compareTo(a['id'] as int));
    }
  }

  int _countFor(int? categoryId) {
    final rows = ((_counts['categories'] as List?) ?? []).cast<Map<String, dynamic>>();
    if (categoryId == null) return ((_counts['total'] as num?) ?? _total).toInt();
    final row = rows.where((r) => r['id'] == categoryId).firstOrNull;
    return ((row?['count'] as num?) ?? 0).toInt();
  }

  IconData _categoryIcon(String? type) => switch (type) {
        'outlet' => Icons.storefront_rounded,
        'distributor' => Icons.local_shipping_rounded,
        'customer' => Icons.person_rounded,
        _ => Icons.grid_view_rounded,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: _add,
        child: const Icon(Icons.add_rounded, size: 28),
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _header(),
            _countsCard(),
            _searchBox(),
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            if (_error != null) Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
            Expanded(child: _showMap ? _map() : _list()),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    final toggle = Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _viewButton(Icons.format_list_bulleted_rounded, 'List', !_showMap,
              () => setState(() => _showMap = false)),
          _viewButton(Icons.map_rounded, 'Map', _showMap, () {
            setState(() => _showMap = true);
            if (_points.isEmpty) _loadPoints();
          }),
        ],
      ),
    );
    final picker = Services.auth.profile?.isManager == true
        ? MemberPicker(
            value: _member,
            dense: true,
            onChanged: (value) {
              setState(() => _member = value);
              _load();
            },
          )
        : null;
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.pickMode ? 'Choose $_clientLabel' : '${_clientLabel}s',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppColors.text)),
        Text(widget.pickMode ? 'Pick who this is for' : 'Manage your customers and outlets',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
      ],
    );
    final back = !widget.embedded && Navigator.of(context).canPop();
    if (widget.embedded) {
      // The tab has the whole width: title, then the list or map switch and the person picker.
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 12, 8),
        child: Row(children: [
          Expanded(child: title),
          toggle,
          if (picker != null) ...[const SizedBox(width: 6), picker],
        ]),
      );
    }
    // A page with a back arrow: back, title, then the list or map switch on the right.
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 12, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (back)
            IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.arrow_back_rounded))
          else
            const SizedBox(width: 8),
          Expanded(child: title),
          const SizedBox(width: 6),
          toggle,
        ]),
        if (picker != null)
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 8),
            child: Align(alignment: Alignment.centerLeft, child: picker),
          ),
      ]),
    );
  }

  Widget _searchBox() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(children: [
          Expanded(child: TextField(
          controller: _search,
          onChanged: _onSearch,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search_rounded, color: AppColors.muted),
            hintText: 'Search name, code...',
            border: InputBorder.none,
            focusedBorder: InputBorder.none,
            enabledBorder: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () {
                      _search.clear();
                      _load();
                    },
                  ),
          ),
        )),
          IconButton(
            tooltip: 'Territory, beat and group by',
            icon: Icon(Icons.tune_rounded,
                color: (_territoryId == null && _beatId == null && _group == 'none') ? AppColors.muted : AppColors.primary),
            onPressed: _openFilterSheet,
          ),
          _kindDropdown(),
        ]),
      ),
    );
  }

  static const _kindLabels = {
    'all': 'All',
    'outlet': 'Outlets',
    'distributor': 'Distributors',
    'lead': 'Leads',
    'never': 'Never Visited',
  };

  /// Which choice of [_kindLabels] is on now.
  String get _kindNow {
    if (_neverVisited) return 'never';
    if (_categoryId == null) return 'all';
    final match = _categories.where((c) => c['id'] == _categoryId).firstOrNull;
    final type = '${match?['type'] ?? ''}';
    return _kindLabels.containsKey(type) ? type : 'all';
  }

  /// The filter on the right of the search bar: All, Outlets, Distributors, Leads, Never Visited.
  Widget _kindDropdown() {
    return Container(
      height: 36,
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      constraints: const BoxConstraints(maxWidth: 124),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.5)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _kindNow,
          isDense: true,
          isExpanded: true,
          borderRadius: BorderRadius.circular(14),
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: AppColors.primary),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.primary),
          selectedItemBuilder: (_) => [
            for (final e in _kindLabels.entries) Align(alignment: Alignment.centerLeft, child: Text(e.value, maxLines: 1, overflow: TextOverflow.ellipsis)),
          ],
          items: [for (final e in _kindLabels.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
          onChanged: (v) {
            if (v != null) _applyKind(v);
          },
        ),
      ),
    );
  }

  Future<void> _loadFilterLists() async {
    try {
      final data = await Services.api.get('/api/v1/clients/filters') as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _territories = ((data['territories'] as List?) ?? []).cast<Map<String, dynamic>>();
          _beats = ((data['beats'] as List?) ?? []).cast<Map<String, dynamic>>();
        });
      }
    } catch (_) {
      // Older server: the extra filters simply do not appear.
    }
  }

  /// Narrow the list to a territory (primary or secondary) or a beat, and group it by either.
  Future<void> _openFilterSheet() async {
    if (_territories.isEmpty && _beats.isEmpty) await _loadFilterLists();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) => StatefulBuilder(
        builder: (context, setSheet) {
          Widget chips<T>(List<(String, T?)> items, T? current, void Function(T?) onPick) => Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final (label, value) in items)
                    ChoiceChip(
                      label: Text(label),
                      selected: current == value,
                      onSelected: (_) {
                        onPick(value);
                        setSheet(() {});
                      },
                    ),
                ],
              );
          final beats = _beats.where((b) => _territoryId == null || b['territory_id'] == _territoryId).toList();
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Territory', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                const SizedBox(height: 8),
                chips<int>([
                  ('All', null),
                  for (final t in _territories)
                    ('${t['name']}${t['kind'] == 'secondary' ? ' (secondary)' : t['kind'] == 'other' ? ' (team / beat)' : ''}', t['id'] as int),
                ], _territoryId, (v) {
                  _territoryId = v;
                  if (_beatId != null && beats.every((b) => b['id'] != _beatId)) _beatId = null;
                }),
                const SizedBox(height: 16),
                const Text('Beat', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                const SizedBox(height: 8),
                chips<int>([
                  ('All', null),
                  for (final b in beats) ('${b['name']}', b['id'] as int),
                ], _beatId, (v) => _beatId = v),
                const SizedBox(height: 16),
                const Text('Group by', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                const SizedBox(height: 8),
                chips<String>(const [
                  ('None', 'none'),
                  ('Territory', 'territory'),
                  ('Beat', 'beat'),
                ], _group, (v) => _group = v ?? 'none'),
                const SizedBox(height: 18),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        _territoryId = null;
                        _beatId = null;
                        _group = 'none';
                        setSheet(() {});
                      },
                      child: const Text('Clear'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(onPressed: () => Navigator.pop(sheet), child: const Text('Apply')),
                  ),
                ]),
              ]),
            ),
          );
        },
      ),
    );
    if (mounted) {
      setState(() {});
      _load();
    }
  }

  /// One of the filter choices: a kind of contact, everybody, or those never visited.
  void _applyKind(String kind) {
    setState(() {
      _neverVisited = kind == 'never';
      if (kind == 'all' || kind == 'never') {
        _categoryId = null;
      } else {
        final match = _categories.where((c) => c['type'] == kind).firstOrNull;
        _categoryId = match?['id'] as int?;
      }
    });
    _load();
  }

  Widget _categoryChips() {
    final chips = [<String, dynamic>{'id': null, 'name': 'All', 'type': null}, ..._categories];
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final category in chips)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _chip(
                icon: _categoryIcon(category['type'] as String?),
                label: '${category['name']}',
                count: _countFor(category['id'] as int?),
                selected: _categoryId == category['id'],
                onTap: () {
                  setState(() => _categoryId = category['id'] as int?);
                  _load();
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _chip({
    required IconData icon,
    required String label,
    required int count,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: selected ? AppColors.primary : AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: selected ? Colors.white : AppColors.muted),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : AppColors.text)),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: selected ? Colors.white : AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('$count',
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: selected ? AppColors.primary : AppColors.muted)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _filterRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Row(
        children: [
          _chip(
            icon: Icons.near_me_rounded,
            label: 'Nearby',
            count: 0,
            selected: _nearby,
            onTap: () {
              if (_nearby) return;
              setState(() => _nearby = true);
              _load();
            },
          ),
          const SizedBox(width: 8),
          _chip(
            icon: Icons.format_list_bulleted_rounded,
            label: 'All ${_clientLabel}s',
            count: 0,
            selected: !_nearby,
            onTap: () {
              if (!_nearby) return;
              setState(() => _nearby = false);
              _load();
            },
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.only(left: 10, right: 2),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _sort,
                isDense: true,
                borderRadius: BorderRadius.circular(14),
                icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: AppColors.muted),
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.text),
                items: const [
                  DropdownMenuItem(value: 'latest', child: Text('Latest')),
                  DropdownMenuItem(value: 'name', child: Text('Name')),
                  DropdownMenuItem(value: 'nearest', child: Text('Nearest')),
                  DropdownMenuItem(value: 'visited', child: Text('Visited')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _sort = value;
                    _sortClients();
                  });
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// How many of each kind this person is looking after.
  Widget _countsCard() {
    final rows = ((_counts['categories'] as List?) ?? []).cast<Map<String, dynamic>>();
    int ofType(String type) =>
        rows.where((r) => r['type'] == type).fold<int>(0, (sum, r) => sum + ((r['count'] as num?) ?? 0).toInt());
    final never = ((_counts['never_visited'] as num?) ?? 0).toInt();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              _countBox(Icons.groups_2_rounded, '${_countFor(null)}', 'Total', AppColors.primary, () => _applyKind('all')),
              _countBox(Icons.storefront_rounded, '${ofType('outlet')}', 'Outlet', AppColors.success, () => _applyKind('outlet')),
              _countBox(Icons.local_shipping_rounded, '${ofType('distributor')}', 'Distributor', AppColors.purple,
                  () => _applyKind('distributor')),
              _countBox(Icons.person_add_alt_1_rounded, '${ofType('lead')}', 'Lead', AppColors.warning, () => _applyKind('lead')),
              _countBox(Icons.visibility_off_rounded, '$never', 'Never Visited', AppColors.danger, () => _applyKind('never')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _countBox(IconData icon, String value, String label, Color tint, VoidCallback onTap) => Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          decoration: BoxDecoration(
            color: tint.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(11)),
                child: Icon(icon, size: 17, color: tint),
              ),
              const SizedBox(height: 6),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: AppColors.muted)),
            ],
          ),
        ),
        ),
      );

  Widget _resultRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
      child: Row(
        children: [
          Text('$_total ${_clientLabel.toLowerCase()}${_total == 1 ? '' : 's'} found',
              style: const TextStyle(fontSize: 12.5, color: AppColors.muted, fontWeight: FontWeight.w600)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                _viewButton(Icons.format_list_bulleted_rounded, 'List', !_showMap,
                    () => setState(() => _showMap = false)),
                _viewButton(Icons.map_rounded, 'Map', _showMap, () { setState(() => _showMap = true); if (_points.isEmpty) _loadPoints(); }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _viewButton(IconData icon, String label, bool selected, VoidCallback onTap) => InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: selected ? Colors.white : AppColors.muted),
              const SizedBox(width: 5),
              Text(label,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: selected ? Colors.white : AppColors.muted)),
            ],
          ),
        ),
      );

  Widget _list() {
    return RefreshIndicator(
      onRefresh: _load,
      child: _clients.isEmpty && !_loading
          ? ListView(children: [
              EmptyView(
                icon: Icons.storefront_rounded,
                text: _nearby ? 'No ${_clientLabel.toLowerCase()}s within 25 km' : 'No ${_clientLabel.toLowerCase()}s found',
              ),
            ])
          : Builder(builder: (context) {
              final rows = _groupedRows();
              return ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
              itemCount: rows.length + (_clients.length < _total ? 1 : 0),
              itemBuilder: (_, i) {
                if (i >= rows.length) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
                  );
                }
                final row = rows[i];
                if (row is String) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(2, 14, 2, 6),
                    child: Text(row, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: AppColors.primary)),
                  );
                }
                final c = row as Map<String, dynamic>;
                return ClientTile(client: c, onTap: () => _open(c));
              },
              );
            }),
    );
  }

  /// The list as rows: a header whenever the territory or the beat changes, when grouping is on.
  List<Object> _groupedRows() {
    if (_group == 'none') return List<Object>.from(_clients);
    String keyOf(Map<String, dynamic> c) {
      if (_group == 'territory') return '${(c['territory'] as Map?)?['name'] ?? 'No territory'}';
      final routes = (c['routes'] as List?) ?? const [];
      return routes.isEmpty ? 'No beat' : '${(routes.first as Map)['name']}';
    }

    final sorted = [..._clients]..sort((a, b) {
        final byGroup = keyOf(a).toLowerCase().compareTo(keyOf(b).toLowerCase());
        return byGroup != 0 ? byGroup : '${a['name']}'.toLowerCase().compareTo('${b['name']}'.toLowerCase());
      });
    final rows = <Object>[];
    String? last;
    for (final c in sorted) {
      final key = keyOf(c);
      if (key != last) {
        rows.add(key);
        last = key;
      }
      rows.add(c);
    }
    return rows;
  }

  /// What to draw right now: the points on screen, grouped for this zoom.
  ///
  /// Worked out once per view rather than per frame. Grouping is cheap, but
  /// nine thousand points times sixty frames a second is not, and the bubbles
  /// only ever change when the zoom step or the view does.
  List<MapCluster> _visibleClusters() {
    final view = _view;
    final step = _zoom.round();
    final key = view == null
        ? 'all:$step:${_points.length}'
        : '$step:${view.south.toStringAsFixed(2)}:${view.west.toStringAsFixed(2)}:'
            '${view.north.toStringAsFixed(2)}:${view.east.toStringAsFixed(2)}:${_points.length}';
    if (key == _clusterKey) return _clusters;
    final inView = view == null
        ? _points
        : _points
            .where((p) => view.holds((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble()))
            .toList();
    _clusters = clusterPoints(inView, step.toDouble());
    _clusterKey = key;
    return _clusters;
  }

  Widget _map() {
    final located = _points.isNotEmpty
        ? _points
        : _clients.where((c) => c['lat'] != null).toList();
    if (located.isEmpty && _me == null) {
      return _pointsLoading
          ? const LoadingView()
          : const EmptyView(icon: Icons.location_off_rounded, text: 'No contacts with a GPS location');
    }
    final centre = _centre ??
        _me ??
        LatLng((located.first['lat'] as num).toDouble(), (located.first['lng'] as num).toDouble());
    final clusters = _visibleClusters();
    if (SdkMap.available) {
      // Google's own map, drawn by the phone: no charge, and the roads people know.
      return Stack(
        children: [
          SdkMap(
            centre: centre,
            zoom: _zoom,
            myLocation: _me,
            onCameraIdle: (view) {
              if (!mounted) return;
              // Redraw only when the bubbles could actually differ.
              final moved = _view == null ||
                  (view.zoom.round() != _zoom.round()) ||
                  ((view.centre.latitude - _view!.centre.latitude).abs() >
                      (view.north - view.south).abs() * 0.25) ||
                  ((view.centre.longitude - _view!.centre.longitude).abs() >
                      (view.east - view.west).abs() * 0.25);
              if (!moved) return;
              setState(() {
                _view = view;
                _zoom = view.zoom;
              });
            },
            pins: [
              for (final cluster in clusters)
                SdkPin(
                  // Steady ids: a bubble that has not changed is not redrawn.
                  id: '${cluster.centre.latitude.toStringAsFixed(4)},'
                      '${cluster.centre.longitude.toStringAsFixed(4)}x${cluster.items.length}',
                  point: cluster.centre,
                  count: cluster.items.length,
                  label: cluster.isSingle ? '${cluster.items.first['name']}' : null,
                  colour: cluster.isSingle && cluster.items.first['approval_state'] != 'approved'
                      ? AppColors.warning
                      : AppColors.primary,
                  onTap: () => cluster.isSingle ? _openPoint(cluster.items.first) : _openCluster(cluster),
                ),
            ],
          ),
          _mapCount(located.length, google: true),
          if (_pointsLoading)
            const Positioned(
              top: 10,
              left: 0,
              right: 0,
              child: Center(
                child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
              ),
            ),
        ],
      );
    }
    return Stack(
      children: [
        AppMap(
          controller: _mapController,
          center: centre,
          zoom: 12,
          myLocation: _me,
          onCamera: (camera) {
            if ((camera.zoom - _zoom).abs() > 0.15 && mounted) {
              setState(() => _zoom = camera.zoom);
            }
          },
          fitPoints: [
            if (_me != null) _me!,
            for (final c in located) LatLng((c['lat'] as num).toDouble(), (c['lng'] as num).toDouble()),
          ],
          children: [
            MarkerLayer(
              markers: [
                if (_me != null)
                  Marker(
                      point: _me!,
                      width: MyLocationDot.size,
                      height: MyLocationDot.size,
                      child: const MyLocationDot()),
              ],
            ),
            MarkerLayer(
              alignment: Alignment.topCenter,
              markers: [
                for (final cluster in clusters)
                  if (cluster.isSingle)
                    Marker(
                      point: cluster.centre,
                      width: MapPinWithLabel.size.width,
                      height: MapPinWithLabel.size.height,
                      alignment: Alignment.topCenter,
                      child: MapPinWithLabel(
                        label: '${cluster.items.first['name']}',
                        color: cluster.items.first['approval_state'] == 'approved'
                            ? AppColors.primary
                            : AppColors.warning,
                        icon: Icons.storefront_rounded,
                        onTap: () => _open(cluster.items.first),
                      ),
                    )
                  else
                    Marker(
                      point: cluster.centre,
                      width: ClusterBubble.sizeFor(cluster.items.length),
                      height: ClusterBubble.sizeFor(cluster.items.length),
                      alignment: Alignment.center,
                      child: ClusterBubble(
                        count: cluster.items.length,
                        onTap: () => _openCluster(cluster),
                      ),
                    ),
              ],
            ),
          ],
        ),
        _mapCount(located.length),
      ],
    );
  }

  /// How many customers the map is showing, and which map is drawing them.
  Widget _mapCount(int count, {bool google = false}) => Positioned(
          left: 12,
          bottom: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [BoxShadow(color: Color(0x1A0F1B3D), blurRadius: 10, offset: Offset(0, 3))],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(google ? Icons.verified_rounded : Icons.public_rounded,
                    size: 13, color: google ? AppColors.success : AppColors.muted),
                const SizedBox(width: 5),
                Text('$count on the map · ${google ? 'Google map (free)' : 'Free map'}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
      );

  /// Zoom into a bubble; when it holds customers at one spot, list them instead.
  void _openCluster(MapCluster cluster) {
    // Far out, a bubble means "look closer here" rather than "list these".
    if (_zoom < 15.5) {
      final closer = math.min(_zoom + 2.5, 17.0);
      if (!SdkMap.available) _mapController.move(cluster.centre, closer);
      setState(() {
        _zoom = closer;
        _centre = cluster.centre;
        _clusterKey = '';
      });
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text('${cluster.items.length} ${_clientLabel.toLowerCase()}s here',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ),
            for (final client in cluster.items)
              if (client.containsKey('category'))
                ClientTile(
                    client: client,
                    onTap: () {
                      Navigator.of(context).pop();
                      _open(client);
                    })
              else
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFE8EFFF),
                    child: Icon(Icons.storefront_rounded, color: AppColors.primary),
                  ),
                  title: Text('${client['name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.of(context).pop();
                    _openPoint(client);
                  },
                ),
          ],
        ),
      ),
    );
  }
}

class ClientTile extends StatelessWidget {
  const ClientTile({super.key, required this.client, this.onTap});

  final Map<String, dynamic> client;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final category = asText((client['category'] as Map?)?['name']);
    final pending = client['approval_state'] == 'pending';
    final name = '${client['name']}';
    final address = asText(client['address']) ?? asText((client['district'] as Map?)?['name']) ?? '';
    final owners = ((client['assigned_to'] as List?) ?? []).cast<Map<String, dynamic>>();
    final phone = asText(client['phone']);
    final located = client['lat'] != null;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                        child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                            style: const TextStyle(
                                color: AppColors.primary, fontWeight: FontWeight.w900, fontSize: 18)),
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const Icon(Icons.storefront_rounded, size: 9, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            if (category != null) _tag(category, AppColors.muted, AppColors.background),
                            _dotTag(pending ? 'Pending' : 'Active',
                                pending ? AppColors.warning : AppColors.success),
                          ],
                        ),
                        if (address.isNotEmpty) ...[
                          const SizedBox(height: 5),
                          Row(
                            children: [
                              const Icon(Icons.location_on_outlined, size: 13, color: AppColors.muted),
                              const SizedBox(width: 3),
                              Expanded(
                                child: Text(address,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  Column(
                    children: [
                      Row(
                        children: [
                          if (phone != null) _round(Icons.call_rounded, () => callNumber(phone)),
                          if (located)
                            _round(Icons.near_me_rounded,
                                () => openDirections(client['lat'] as num, client['lng'] as num)),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(height: 1, color: AppColors.border),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _foot(Icons.calendar_today_rounded, 'Last visited', lastVisitLabel(client),
                        AppColors.primary),
                  ),
                  Container(width: 1, height: 26, color: AppColors.border),
                  Expanded(
                    child: _foot(
                        Icons.person_rounded,
                        owners.length > 1 ? 'Assigned to' : 'Assigned to',
                        owners.isEmpty
                            ? 'Nobody'
                            : (owners.length == 1
                                ? '${owners.first['name']}'
                                : '${owners.first['name']} +${owners.length - 1}'),
                        AppColors.purple),
                  ),
                  if (client['distance_m'] != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 4, right: 4),
                      child: Text(fmtDistance(client['distance_m'] as num?),
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.muted)),
                    ),
                  const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tag(String text, Color colour, Color background) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(9)),
        child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: colour)),
      );

  Widget _dotTag(String text, Color colour) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: colour.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 6, height: 6, decoration: BoxDecoration(color: colour, shape: BoxShape.circle)),
            const SizedBox(width: 4),
            Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: colour)),
          ],
        ),
      );

  Widget _round(IconData icon, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(left: 6),
        child: Material(
          color: AppColors.background,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Padding(padding: const EdgeInsets.all(8), child: Icon(icon, size: 17, color: AppColors.primary)),
          ),
        ),
      );

  Widget _foot(IconData icon, String label, String value, Color tint) => Row(
        children: [
          Icon(icon, size: 15, color: tint),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: const TextStyle(fontSize: 10.5, color: AppColors.muted)),
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ],
      );
}
