import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/geo.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/map.dart';
import '../beat/plan_beat_screen.dart';
import '../collections/collect_payment_screen.dart';
import '../forms/form_fill_screen.dart';
import '../orders/catalog_screen.dart';
import '../visits/step_screen.dart';
import '../../core/local_state.dart';
import '../visits/visit_gate.dart';
import '../visits/stock_count_screen.dart';
import '../receivables/receivables_screen.dart';
import '../returns/return_screen.dart';
import 'client_extras.dart';
import 'product_history_screen.dart';
import 'visit_checkout_screen.dart';

class ClientDetailScreen extends StatefulWidget {
  const ClientDetailScreen({super.key, required this.clientId});

  final int clientId;

  @override
  State<ClientDetailScreen> createState() => _ClientDetailScreenState();
}

class _ClientDetailScreenState extends State<ClientDetailScreen> {
  Map<String, dynamic>? _client;
  Map<String, dynamic>? _current;
  List<Map<String, dynamic>> _forms = [];
  List<Map<String, dynamic>> _steps = [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  /// Where I am, drawn on the customer's map beside the shop.
  LatLng? _me;

  /// Demand, returns and payments only once checked in here (or when visits are not used at all).
  bool get _canAct => _atThisClient || !(Services.auth.profile?.feature('visits') ?? false);

  bool get _atThisClient => _current != null && (_current!['client'] as Map)['id'] == widget.clientId;

  Future<void> _loadMe() async {
    final here = await lastKnownPosition();
    if (here != null && mounted) setState(() => _me = LatLng(here.latitude, here.longitude));
  }

  @override
  void initState() {
    super.initState();
    _loadMe();
    _load();
  }

  Future<List<Map<String, dynamic>>> _formsFor(String trigger, {int? visitId}) async {
    try {
      final list = await Services.api.get('/api/v1/forms', query: {
        'trigger': trigger,
        'partner_id': widget.clientId,
        if (visitId != null) 'visit_id': visitId,
      }) as List;
      return list.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final pos = await lastKnownPosition();
      final results = await Future.wait<dynamic>([
        Services.api.get('/api/v1/clients/${widget.clientId}',
            query: pos == null ? null : {'lat': pos.latitude, 'lng': pos.longitude}),
        Services.api.get('/api/v1/visits/current'),
      ]);
      final current = results[1] as Map<String, dynamic>?;
      final visitHere = current != null && (current['client'] as Map)['id'] == widget.clientId;
      var steps = <Map<String, dynamic>>[];
      if (visitHere && Services.auth.profile!.visitSteps) {
        try {
          // A check-in still waiting to sync has no id: read the steps any visit here has.
          final data = (current['id'] == null
              ? await Services.api.get('/api/v1/visits/0/steps', query: {'partner_id': widget.clientId})
              : await Services.api.get('/api/v1/visits/${current['id']}/steps')) as Map<String, dynamic>;
          steps = [
            for (final step in ((data['steps'] as List?) ?? []).cast<Map<String, dynamic>>())
              LocalState.isStepDone(current, step['id'] as int) ? {...step, 'state': 'done'} : step,
          ];
        } catch (_) {
          // Steps are optional; the visit still works without them.
        }
      }
      var forms = <Map<String, dynamic>>[];
      if (Services.auth.profile!.feature('forms')) {
        final atClient = current != null && (current['client'] as Map)['id'] == widget.clientId;
        forms = [
          if (atClient) ...await _formsFor('visit', visitId: current['id'] as int?),
          ...await _formsFor('contact'),
        ];
      }
      if (!mounted) return;
      setState(() {
        _client = results[0] as Map<String, dynamic>;
        _current = current;
        _forms = forms;
        _steps = steps;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _checkIn() async {
    setState(() => _busy = true);
    try {
      await ensureCheckedIn(context, _client!);
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkOut() async {
    final done = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => VisitCheckoutScreen(visit: _current!)));
    if (done == true && mounted) showSnack(context, 'Visit completed');
    _load();
  }

  /// Checks in here first when needed; false when that did not happen.
  Future<bool> _atClient(Map<String, dynamic> client) async {
    if (_atThisClient || !Services.auth.profile!.feature('visits')) return true;
    final visit = await ensureCheckedIn(context, client);
    await _load();
    return visit != null && mounted;
  }

  Future<void> _takeOrder(Map<String, dynamic> client) async {
    if (!await _atClient(client)) return;
    if (!mounted) return;
    final placed =
        await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => CatalogScreen(client: client)));
    if (placed == true && mounted) showSnack(context, 'Order placed');
    _load();
  }

  Future<void> _collectPayment(Map<String, dynamic> client) async {
    if (!await _atClient(client)) return;
    if (!mounted) return;
    final collected = await Navigator.of(context).push<Map<String, dynamic>>(MaterialPageRoute(
      builder: (_) => CollectPaymentScreen(client: client, visitId: _atThisClient ? _current!['id'] as int? : null),
    ));
    if (collected != null) _load();
  }

  Future<void> _markStepDone(Map<String, dynamic> step, {String note = ''}) async {
    try {
      await Services.outbox.submit('/api/v1/visits/${_current!['id'] ?? 0}/steps/${step['id']}', {
        'note': note,
        if (_current!['uuid'] != null) 'visit_uuid': _current!['uuid'],
      }, label: '${step['name']}');
      LocalState.stepDone(_current!, step['id'] as int);
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
    }
  }

  Future<void> _openStep(Map<String, dynamic> step) async {
    final visitId = _current!['id'] as int?;
    final visitUuid = visitId == null ? _current!['uuid'] as String? : null;
    final type = step['type'] as String;
    bool? done;
    switch (type) {
      case 'stock':
        done = await Navigator.of(context).push<bool>(MaterialPageRoute(
          builder: (_) => StockCountScreen(clientId: widget.clientId, visitId: visitId, visitUuid: visitUuid, step: step),
        ));
      case 'order':
        final placed = await Navigator.of(context)
            .push<bool>(MaterialPageRoute(builder: (_) => CatalogScreen(client: _client!)));
        if (placed == true) {
          await _markStepDone(step, note: 'Order taken');
          done = true;
        }
      case 'form':
        final forms = _forms.where((f) => f['id'] == step['form_id']).toList();
        if (forms.isEmpty) {
          if (mounted) showSnack(context, 'This form is not available for this contact.');
          return;
        }
        final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
          builder: (_) => FormFillScreen(form: forms.first, partnerId: widget.clientId, visitId: visitId),
        ));
        if (saved == true) {
          await _markStepDone(step, note: '${forms.first['name']} filled');
          done = true;
        }
      case 'payment':
        final collected = await Navigator.of(context).push<Map<String, dynamic>>(
            MaterialPageRoute(builder: (_) => CollectPaymentScreen(client: _client!, visitId: visitId)));
        if (collected != null) {
          await _markStepDone(step, note: 'Collected ${fmtMoney(collected['amount'] as num?, collected['currency'] as String?)}');
          done = true;
        }
      default:
        done = await Navigator.of(context)
            .push<bool>(MaterialPageRoute(builder: (_) => StepScreen(visitId: visitId, visitUuid: visitUuid, step: step)));
    }
    if (done == true) {
      LocalState.stepDone(_current!, step['id'] as int);
      _load();
    }
  }

  Future<void> _openForm(Map<String, dynamic> form) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => FormFillScreen(
        form: form,
        partnerId: widget.clientId,
        visitId: form['trigger'] == 'visit' ? (_current?['id'] as int?) : null,
      ),
    ));
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final client = _client;
    final locked = _atThisClient && Services.auth.profile!.visitLock;
    return PopScope(
      canPop: !locked,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) showSnack(context, 'Check out first to leave this visit.');
      },
      child: Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !locked,
        title: Text(asText(client?['name']) ?? Services.auth.profile!.label('client', 'Client')),
        actions: [
          if (client != null) ...[
            IconButton(
              tooltip: 'Statement of account',
              icon: const Icon(Icons.request_quote_rounded),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => StatementScreen(partnerId: widget.clientId, name: '${client['name']}'))),
            ),
            IconButton(
              tooltip: 'History',
              icon: const Icon(Icons.history_rounded),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ClientHistoryScreen(clientId: widget.clientId, name: '${client['name']}'))),
            ),
            IconButton(
              tooltip: 'Edit',
              icon: const Icon(Icons.edit_rounded),
              onPressed: () async {
                final saved = await Navigator.of(context)
                    .push<bool>(MaterialPageRoute(builder: (_) => EditClientScreen(client: client)));
                if (saved == true) _load();
              },
            ),
          ],
        ]),
      body: _loading && client == null
          ? const Center(child: CircularProgressIndicator())
          : client == null
              ? ErrorView(message: _error ?? 'Error', onRetry: _load)
              : RefreshIndicator(onRefresh: _load, child: _content(client)),
    ),
    );
  }

  /// The customer at a glance: who they are, how they stand, and their beat.
  Widget _hero(Map<String, dynamic> c, String? category, List<Map> routes) {
    final name = '${c['name']}';
    final pending = c['approval_state'] == 'pending';
    final owners = ((c['assigned_to'] as List?) ?? []).cast<Map<String, dynamic>>();
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, Color(0xFF3B82F6)],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: Colors.white.withValues(alpha: 0.25),
                child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 26)),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  child: const Icon(Icons.storefront_rounded, size: 12, color: AppColors.primary),
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 20)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (category != null) _heroChip(category),
                    _heroChip(pending ? 'Pending' : 'Active',
                        dot: pending ? AppColors.warning : AppColors.success),
                    if (c['code'] != null) _heroChip('${c['code']}'),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.history_rounded, size: 14, color: Colors.white70),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        [
                          'Last visit: ${lastVisitLabel(c)}',
                          if (owners.isNotEmpty) '${owners.first['name']}',
                        ].join('  ·  '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                      ),
                    ),
                  ],
                ),
                if (routes.isNotEmpty) ...[
                  const SizedBox(height: 9),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                    child: Text('Beat: ${routes.first['name']}',
                        style: const TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.text)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroChip(String text, {Color? dot}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dot != null) ...[
              Container(width: 7, height: 7, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
              const SizedBox(width: 5),
            ],
            Text(text,
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
          ],
        ),
      );

  /// The four things people reach for first.
  Widget _quickRow(Map<String, dynamic> c, Profile profile) {
    final lat = c['lat'] as num?;
    final lng = c['lng'] as num?;
    final phone = asText(c['phone']);
    final actions = <(IconData, String, Color, VoidCallback?)>[
      (Icons.call_rounded, 'Call', AppColors.success, phone == null ? null : () => callPhone(phone)),
      (
        Icons.near_me_rounded,
        'Navigate',
        AppColors.primary,
        lat == null || lng == null ? null : () => openDirections(lat, lng)
      ),
      // Checking in is the thing people reach for at the shop, so it sits here.
      if (profile.feature('visits'))
        (
          _atThisClient ? Icons.logout_rounded : Icons.login_rounded,
          _atThisClient ? 'Check Out' : 'Check In',
          _atThisClient ? AppColors.danger : AppColors.warning,
          _busy ? null : (_atThisClient ? _checkOut : _checkIn)
        ),
      (
        Icons.event_available_rounded,
        'Plan Visit',
        AppColors.purple,
        () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => PlannedDaysScreen(start: DateUtils.dateOnly(DateTime.now()))))
      ),
    ];
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (icon, label, tint, onTap) in actions)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Card(
                  margin: EdgeInsets.zero,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: onTap,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: onTap == null ? AppColors.border : tint,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(icon, color: Colors.white, size: 20),
                          ),
                          const SizedBox(height: 7),
                          Text(label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: onTap == null ? AppColors.muted : AppColors.text)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Where the customer is and how to reach them, with the pin on a small map.
  Widget _locationCard(Map<String, dynamic> c, num? lat, num? lng, num? distance) {
    final inside = distance != null && distance <= ((c['geofence_radius'] as num?) ?? 150);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(11)),
                  child: const Icon(Icons.place_rounded, size: 18, color: AppColors.primary),
                ),
                const SizedBox(width: 9),
                const Expanded(
                  child: Text('Location & Contact',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                ),
                if (lat != null && lng != null)
                  TextButton.icon(
                    onPressed: () => openDirections(lat, lng),
                    icon: const Icon(Icons.map_rounded, size: 16),
                    label: const Text('View on Map'),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (asText(c['address']) != null || asText(c['city']) != null)
              _infoRow(Icons.location_on_rounded, asText(c['city']) ?? '${c['address']}',
                  asText(c['address']) ?? ''),
            if (asText(c['phone']) != null)
              _infoRow(Icons.call_rounded, '${c['phone']}', '',
                  trailing: IconButton(
                    icon: const Icon(Icons.call_rounded, size: 18, color: AppColors.primary),
                    onPressed: () => callPhone('${c['phone']}'),
                  )),
            if (asText(c['gst']) != null) _infoRow(Icons.receipt_long_rounded, '${c['gst']}', 'GST number'),
            _infoRow(
              Icons.radar_rounded,
              lat == null ? 'No GPS location yet' : 'Geofence: ${c['geofence_radius']} m',
              lat == null
                  ? 'It is saved at your first check-in'
                  : (distance == null ? '' : 'You are ${fmtDistance(distance)} away'),
              trailing: lat == null
                  ? null
                  : Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: (inside ? AppColors.success : AppColors.warning).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                  color: inside ? AppColors.success : AppColors.warning,
                                  shape: BoxShape.circle)),
                          const SizedBox(width: 5),
                          Text(inside ? 'Within range' : 'Out of range',
                              style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: inside ? AppColors.success : AppColors.warning)),
                        ],
                      ),
                    ),
            ),
            if (lat != null && lng != null) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  height: 140,
                  child: Stack(
                    children: [
                      AppMap(
                        center: LatLng(lat.toDouble(), lng.toDouble()),
                        zoom: 16,
                        interactive: false,
                        controls: false,
                        myLocation: _me,
                        children: [
                          if (_me != null)
                            MarkerLayer(markers: [
                              Marker(
                                  point: _me!,
                                  width: MyLocationDot.size,
                                  height: MyLocationDot.size,
                                  child: const MyLocationDot()),
                            ]),
                          CircleLayer(circles: [
                            CircleMarker(
                              point: LatLng(lat.toDouble(), lng.toDouble()),
                              radius: ((c['geofence_radius'] as num?) ?? 150).toDouble(),
                              useRadiusInMeter: true,
                              color: AppColors.primary.withValues(alpha: 0.12),
                              borderColor: AppColors.success,
                              borderStrokeWidth: 1.5,
                            ),
                          ]),
                          MarkerLayer(
                            alignment: Alignment.topCenter,
                            markers: [
                              Marker(
                                point: LatLng(lat.toDouble(), lng.toDouble()),
                                width: MapPin.size.width,
                                height: MapPin.size.height,
                                alignment: Alignment.topCenter,
                                child: const MapPin(color: AppColors.danger, icon: Icons.storefront_rounded),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => openDirections(lat, lng),
                            child: const Padding(
                              padding: EdgeInsets.all(8),
                              child: Icon(Icons.directions_rounded, size: 18, color: AppColors.primary),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String title, String subtitle, {Widget? trailing}) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(14)),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(11)),
              child: Icon(icon, size: 17, color: AppColors.primary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                  if (subtitle.isNotEmpty)
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                ],
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      );

  Widget _content(Map<String, dynamic> c) {
    final profile = Services.auth.profile!;
    final lat = c['lat'] as num?;
    final lng = c['lng'] as num?;
    final visits = ((c['recent_visits'] as List?) ?? []).cast<Map<String, dynamic>>();
    final routes = ((c['routes'] as List?) ?? []).cast<Map>();
    final distance = c['distance_m'] as num?;
    final category = asText((c['category'] as Map?)?['name']);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        if (c['approval_state'] == 'pending')
          const Card(
            color: Color(0xFFFFF5E5),
            child: ListTile(leading: Icon(Icons.hourglass_top_rounded, color: AppColors.warning), title: Text('Waiting for manager approval')),
          ),
        _hero(c, category, routes),
        const SizedBox(height: 12),
        _quickRow(c, profile),
        const SizedBox(height: 12),
        _locationCard(c, lat, lng, distance),
        const SizedBox(height: 10),
        ClientBalanceCard(clientId: widget.clientId),
        const SizedBox(height: 10),
        if (profile.feature('visits')) _visitAction(),
        // Checked in at another customer: nothing to take here until they check out there.
        if (profile.feature('orders') && _canAct && c['allow_orders'] != false && c['approval_state'] == 'approved') ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => _takeOrder(c),
            icon: const Icon(Icons.shopping_cart_rounded),
            label: Text(profile.isDemandFlow
                ? 'Take demand'
                : 'Take ${profile.label('order', 'Order').toLowerCase()}'),
          ),
        ],
        if (profile.feature('orders') && _canAct) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () async {
              if (!await _atClient(c) || !mounted) return;
              final sent = await Navigator.of(context)
                  .push<bool>(MaterialPageRoute(builder: (_) => ReturnScreen(client: c)));
              if (sent == true) _load();
            },
            icon: const Icon(Icons.assignment_return_rounded),
            label: const Text('Return / damaged goods'),
          ),
        ],
        // Checked in here: what this customer has taken from us, product by product.
        if (profile.feature('orders') && _atThisClient) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ProductHistoryScreen(clientId: widget.clientId, clientName: '${c['name']}'),
            )),
            icon: const Icon(Icons.inventory_2_rounded),
            label: const Text('Product history'),
          ),
        ],
        if (profile.paymentCollection && _canAct) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => _collectPayment(c),
            icon: const Icon(Icons.payments_rounded),
            label: const Text('Collect payment'),
          ),
        ],
        if (_steps.isNotEmpty)
          SectionCard(
            title: 'Visit steps',
            child: Column(
              children: [
                for (var i = 0; i < _steps.length; i++)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: (_steps[i]['state'] == 'done'
                              ? AppColors.success
                              : _steps[i]['state'] == 'skipped'
                                  ? AppColors.warning
                                  : AppColors.primary)
                          .withValues(alpha: 0.14),
                      child: _steps[i]['state'] == 'done'
                          ? const Icon(Icons.check_rounded, color: AppColors.success)
                          : Text('${i + 1}',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: _steps[i]['state'] == 'skipped' ? AppColors.warning : AppColors.primary)),
                    ),
                    title: Text('${_steps[i]['name']}${_steps[i]['mandatory'] == true ? ' *' : ''}',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(_steps[i]['state'] == 'skipped'
                        ? 'Skipped'
                        : asText(_steps[i]['note']) ?? asText(_steps[i]['instruction']) ?? ''),
                    trailing: _steps[i]['state'] == 'pending'
                        ? const Icon(Icons.chevron_right_rounded)
                        : StatusBadge(_steps[i]['state'] == 'done' ? 'filled' : 'skipped', label: null),
                    onTap: () => _openStep(_steps[i]),
                  ),
              ],
            ),
          ),
        if (_forms.isNotEmpty)
          SectionCard(
            title: 'Forms',
            child: Column(
              children: [
                for (final form in _forms)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFFEDE8FF),
                      child: Icon(Icons.assignment_rounded, color: AppColors.purple),
                    ),
                    title: Text('${form['name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(form['trigger'] == 'visit' ? 'During this visit' : 'Profile'),
                    trailing: form['filled'] == true
                        ? const StatusBadge('filled')
                        : form['mandatory'] == true
                            ? const StatusBadge('required')
                            : const Icon(Icons.chevron_right_rounded),
                    onTap: form['filled'] == true ? null : () => _openForm(form),
                  ),
              ],
            ),
          ),
        if (visits.isNotEmpty)
          SectionCard(
            title: 'Recent visits',
            child: Column(
              children: [
                for (final v in visits)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(v['state'] == 'done' ? Icons.check_circle_rounded : Icons.timelapse_rounded,
                        color: v['state'] == 'done' ? AppColors.success : AppColors.sky),
                    title: Text('${fmtDate(parseServerTime(v['check_in_at'])!)} · '
                        '${fmtTime(v['check_in_at'])}–${fmtTime(v['check_out_at'])}'),
                    subtitle: Text([(v['outcome_type'] as Map?)?['name'], v['note']].whereType<String>().join(' · ')),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _visitAction() {
    final current = _current;
    if (_atThisClient) {
      return GradientButton(
        label: 'Check out (since ${fmtTime(current!['check_in_at'])})',
        icon: Icons.logout_rounded,
        gradient: AppColors.dangerGradient,
        onPressed: _checkOut,
      );
    }
    if (current != null) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.warning_amber_rounded, color: AppColors.warning),
          title: Text('You are checked in at ${(current['client'] as Map)['name']}'),
          subtitle: const Text('Check out there first.'),
        ),
      );
    }
    return GradientButton(label: 'Check in', icon: Icons.login_rounded, busy: _busy, onPressed: _checkIn);
  }
}
