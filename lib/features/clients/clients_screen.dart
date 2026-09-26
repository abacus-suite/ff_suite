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

/// Contacts with search, category chips, "nearby" sorting and a map.
/// In [pickMode] tapping a contact returns it to the caller.
class ClientsScreen extends StatefulWidget {
  const ClientsScreen({super.key, this.pickMode = false, this.embedded = false});

  final bool pickMode;
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
  int _total = 0;
  Map<String, dynamic> _counts = const {};
  String _sort = 'latest';
  LatLng? _me;
  String _member = 'me';
  final MapController _mapController = MapController();
  double _zoom = 12;

  String get _clientLabel => Services.auth.profile!.label('client', 'Client');

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _mapController.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    try {
      final list = await Services.api.get('/api/v1/contact-categories') as List;
      if (mounted) setState(() => _categories = list.cast<Map<String, dynamic>>());
    } catch (_) {
      // Chips are optional.
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final query = <String, dynamic>{'limit': 100};
      final q = _search.text.trim();
      if (q.isNotEmpty) query['q'] = q;
      if (_categoryId != null) query['category_id'] = _categoryId;
      if (_member != 'me') query['member'] = _member;
      if (_nearby) {
        // Never leave the list spinning on a slow GPS fix: fall back to the last known place.
        final pos = await currentPosition(recentOk: true)
            .timeout(const Duration(seconds: 12))
            .catchError((_) async => (await lastKnownPosition())!);
        _me = LatLng(pos.latitude, pos.longitude);
        query.addAll({'lat': pos.latitude, 'lng': pos.longitude, 'radius_km': 25});
      }
      final data = await Services.api.get('/api/v1/clients', query: query) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _clients = (data['clients'] as List).cast<Map<String, dynamic>>();
        _total = data['total'] as int;
        _counts = (data['counts'] as Map?)?.cast<String, dynamic>() ?? const {};
        _sortClients();
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearch(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _load);
  }

  Future<void> _open(Map<String, dynamic> client) async {
    if (widget.pickMode) {
      Navigator.of(context).pop(client);
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
            _searchBox(),
            if (_categories.isNotEmpty) _categoryChips(),
            _filterRow(),
            if (!_showMap) _countsCard(),
            _resultRow(),
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            if (_error != null) Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
            Expanded(child: _showMap ? _map() : _list()),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 12, 8),
      child: Row(
        children: [
          if (!widget.embedded && Navigator.of(context).canPop())
            IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back_rounded)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.pickMode ? 'Choose $_clientLabel' : '${_clientLabel}s',
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppColors.text)),
                Text('Manage your customers and outlets',
                    style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
              ],
            ),
          ),
          if (Services.auth.profile?.isManager == true)
            MemberPicker(
              value: _member,
              dense: true,
              onChanged: (value) {
                setState(() => _member = value);
                _load();
              },
            ),
        ],
      ),
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
        child: TextField(
          controller: _search,
          onChanged: _onSearch,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search_rounded, color: AppColors.muted),
            hintText: 'Search name, code, phone, city...',
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
        ),
      ),
    );
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
    if (rows.isEmpty) return const SizedBox.shrink();
    final tints = [AppColors.success, AppColors.warning, AppColors.purple, AppColors.sky];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              _countBox(Icons.groups_2_rounded, '${_countFor(null)}', 'Total', AppColors.primary),
              for (final (i, row) in rows.take(3).indexed)
                _countBox(_categoryIcon(row['type'] as String?), '${row['count']}', '${row['name']}',
                    tints[i % tints.length]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _countBox(IconData icon, String value, String label, Color tint) => Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
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
                _viewButton(Icons.map_rounded, 'Map', _showMap, () => setState(() => _showMap = true)),
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
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
              itemCount: _clients.length,
              itemBuilder: (_, i) => ClientTile(client: _clients[i], onTap: () => _open(_clients[i])),
            ),
    );
  }

  Widget _map() {
    final located = _clients.where((c) => c['lat'] != null).toList();
    if (located.isEmpty && _me == null) {
      return const EmptyView(icon: Icons.location_off_rounded, text: 'No contacts with a GPS location');
    }
    final centre =
        _me ?? LatLng((located.first['lat'] as num).toDouble(), (located.first['lng'] as num).toDouble());
    // Far out the pins gather into counted bubbles; zooming in breaks them apart.
    final clusters = clusterPoints(located, _zoom);
    if (SdkMap.available) {
      // Google's own map, drawn by the phone: no charge, and the roads people know.
      return Stack(
        children: [
          SdkMap(
            centre: centre,
            zoom: _zoom,
            myLocation: _me,
            onCameraIdle: (zoom, _) {
              if ((zoom - _zoom).abs() > 0.15 && mounted) setState(() => _zoom = zoom);
            },
            pins: [
              for (final (i, cluster) in clusters.indexed)
                SdkPin(
                  id: 'c$i-${cluster.items.length}-${cluster.centre.latitude}',
                  point: cluster.centre,
                  count: cluster.items.length,
                  label: cluster.isSingle ? '${cluster.items.first['name']}' : null,
                  colour: cluster.isSingle && cluster.items.first['approval_state'] != 'approved'
                      ? AppColors.warning
                      : AppColors.primary,
                  onTap: () => cluster.isSingle ? _open(cluster.items.first) : _openCluster(cluster),
                ),
            ],
          ),
          _mapCount(located.length),
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

  /// How many customers the map is showing, in the corner.
  Widget _mapCount(int count) => Positioned(
          left: 12,
          bottom: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [BoxShadow(color: Color(0x1A0F1B3D), blurRadius: 10, offset: Offset(0, 3))],
            ),
            child: Text('$count on the map',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ),
      );

  /// Zoom into a bubble; when it holds customers at one spot, list them instead.
  void _openCluster(MapCluster cluster) {
    final camera = _mapController.camera;
    if (camera.zoom < 16) {
      _mapController.move(cluster.centre, math.min(camera.zoom + 2.5, 17));
      setState(() => _zoom = math.min(camera.zoom + 2.5, 17));
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
              ClientTile(
                  client: client,
                  onTap: () {
                    Navigator.of(context).pop();
                    _open(client);
                  }),
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
