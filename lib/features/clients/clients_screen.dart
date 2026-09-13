import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/format.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/geo.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/map.dart';
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
  bool _nearby = true;
  bool _showMap = false;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _clients = [];
  List<Map<String, dynamic>> _categories = [];
  int? _categoryId;
  int _total = 0;
  LatLng? _me;

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
      if (_nearby) {
        final pos = await currentPosition();
        _me = LatLng(pos.latitude, pos.longitude);
        query.addAll({'lat': pos.latitude, 'lng': pos.longitude, 'radius_km': 25});
      }
      final data = await Services.api.get('/api/v1/clients', query: query) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _clients = (data['clients'] as List).cast<Map<String, dynamic>>();
        _total = data['total'] as int;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded,
        title: Text(widget.pickMode ? 'Choose $_clientLabel' : '${_clientLabel}s'),
        actions: [
          IconButton(
            tooltip: _showMap ? 'List' : 'Map',
            icon: Icon(_showMap ? Icons.view_list_rounded : Icons.map_rounded),
            onPressed: () => setState(() => _showMap = !_showMap),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add_business_rounded),
        label: Text('Add $_clientLabel'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
            child: TextField(
              controller: _search,
              onChanged: _onSearch,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'Search name, code, phone, city',
                isDense: true,
              ),
            ),
          ),
          if (_categories.length > 1)
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  for (final category in [<String, dynamic>{'id': null, 'name': 'All'}, ..._categories])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text('${category['name']}'),
                        selected: _categoryId == category['id'],
                        onSelected: (_) {
                          setState(() => _categoryId = category['id'] as int?);
                          _load();
                        },
                      ),
                    ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('Nearby'), icon: Icon(Icons.near_me_rounded)),
                    ButtonSegment(value: false, label: Text('All'), icon: Icon(Icons.list_alt_rounded)),
                  ],
                  selected: {_nearby},
                  onSelectionChanged: (s) {
                    setState(() => _nearby = s.first);
                    _load();
                  },
                ),
                const Spacer(),
                Text('$_total found', style: const TextStyle(fontSize: 12, color: AixoloColors.muted)),
              ],
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null) Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
          Expanded(child: _showMap ? _map() : _list()),
        ],
      ),
    );
  }

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
    final center = _me ?? LatLng((located.first['lat'] as num).toDouble(), (located.first['lng'] as num).toDouble());
    return AixoloMap(
      center: center,
      zoom: 12,
      myLocation: _me,
      fitPoints: [
        if (_me != null) _me!,
        for (final c in located) LatLng((c['lat'] as num).toDouble(), (c['lng'] as num).toDouble()),
      ],
      children: [
        MarkerLayer(
          markers: [
            if (_me != null)
              Marker(point: _me!, width: MyLocationDot.size, height: MyLocationDot.size, child: const MyLocationDot()),
          ],
        ),
        MarkerLayer(
          alignment: Alignment.topCenter,
          markers: [
            for (final c in located)
              Marker(
                point: LatLng((c['lat'] as num).toDouble(), (c['lng'] as num).toDouble()),
                width: MapPinWithLabel.size.width,
                height: MapPinWithLabel.size.height,
                alignment: Alignment.topCenter,
                child: MapPinWithLabel(
                  label: '${c['name']}',
                  color: c['approval_state'] == 'approved' ? AixoloColors.primary : AixoloColors.warning,
                  icon: Icons.storefront_rounded,
                  onTap: () => _open(c),
                ),
              ),
          ],
        ),
      ],
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
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AixoloColors.primary.withValues(alpha: 0.10),
          child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: const TextStyle(color: AixoloColors.primary, fontWeight: FontWeight.w800)),
        ),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          [if (pending) 'Pending approval', if (category != null) category, lastVisitLabel(client)].join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: client['distance_m'] != null
            ? Text(fmtDistance(client['distance_m'] as num?), style: const TextStyle(color: AixoloColors.muted, fontSize: 12))
            : null,
        onTap: onTap,
      ),
    );
  }
}
