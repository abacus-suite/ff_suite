import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/geo.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/map.dart';
import '../collections/collect_payment_screen.dart';
import '../forms/form_fill_screen.dart';
import '../orders/catalog_screen.dart';
import '../visits/step_screen.dart';
import '../../core/local_state.dart';
import '../visits/visit_gate.dart';
import '../tasks/task_start.dart';
import '../visits/stock_count_screen.dart';
import '../receivables/receivables_screen.dart';
import 'client_extras.dart';
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

  /// Ticks the visit clock; runs only while checked in here.
  Timer? _clock;

  /// Watches the distance to the shop, for checking in and out by itself.
  Timer? _watch;

  /// Since when the person has been outside the fence. Null while they are inside.
  DateTime? _awaySince;

  /// One arrival check-in per screen: it should not keep retrying after a refusal.
  bool _arriving = false;

  /// Which task this visit was opened for. Its screens are where the work is done and
  /// where the visit is checked out: it ends when the last step is submitted.
  String? get _task => _atThisClient ? asText(_current!['task']) : null;

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

  @override
  void dispose() {
    _clock?.cancel();
    _watch?.cancel();
    super.dispose();
  }

  /// The clock runs while a visit is open here; the watcher, while arrival
  /// check-in is switched on and this customer has a location to arrive at.
  void _syncTimers() {
    final profile = Services.auth.profile;
    final located = _client?['lat'] != null && _client?['lng'] != null;
    if (_atThisClient && _clock == null) {
      _clock = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!_atThisClient) {
      _clock?.cancel();
      _clock = null;
    }
    // Only where they meant to go today. Walking past a shop that is not on the
    // plan - or standing near a lead nobody planned - is not a visit.
    final wantWatch = located &&
        (profile?.autoVisit ?? false) &&
        (profile?.feature('visits') ?? false) &&
        (_client?['planned_today'] == true || _atThisClient) &&
        (_current == null || _atThisClient);
    if (wantWatch && _watch == null) {
      _watch = Timer.periodic(const Duration(seconds: 20), (_) => _watchFence());
      _watchFence();
    } else if (!wantWatch) {
      _watch?.cancel();
      _watch = null;
      _awaySince = null;
    }
  }

  /// Checks in on reaching the shop, and out once they have really left it.
  ///
  /// Leaving is judged with a margin and over time, so that a walk to the car
  /// or one poor GPS fix does not end a visit somebody is still on. A visit
  /// started by hand - an offsite one, say - is never closed this way: the app
  /// only undoes what the app itself did.
  Future<void> _watchFence() async {
    final client = _client;
    final profile = Services.auth.profile;
    if (!mounted || client == null || profile == null) return;
    final lat = (client['lat'] as num?)?.toDouble();
    final lng = (client['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return;
    Position here;
    try {
      here = await currentPosition(recentOk: true);
    } catch (_) {
      return;
    }
    if (!mounted) return;
    final away = Geolocator.distanceBetween(here.latitude, here.longitude, lat, lng);
    setState(() => _me = LatLng(here.latitude, here.longitude));
    final radius = ((client['geofence_radius'] as num?) ?? 150).toDouble();

    if (_atThisClient) {
      if (_current!['auto_start'] != true) return;
      if (away <= radius + profile.autoVisitExitM) {
        _awaySince = null;
        return;
      }
      _awaySince ??= DateTime.now();
      if (DateTime.now().difference(_awaySince!).inSeconds < profile.autoVisitLeaveSecs) return;
      _awaySince = null;
      if (await autoCheckOut(_current!) && mounted) {
        showSnack(context, 'Checked out - you left ${client['name']}');
        await _load();
      }
      return;
    }
    if (_current != null || _arriving || away > radius) return;
    _arriving = true;
    final visit = await autoCheckIn(client);
    if (visit != null && mounted) {
      showSnack(context, 'Checked in - you are at ${client['name']}');
      await _load();
    }
  }

  /// A visit the person asks for again on a chosen day: a note to themselves.
  Future<void> _planVisit(Map<String, dynamic> c) async {
    var day = DateUtils.dateOnly(DateTime.now().add(const Duration(days: 1)));
    final reason = TextEditingController();
    final planned = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (sheet, setSheet) => AlertDialog(
          icon: const Icon(Icons.event_available_rounded, color: AppColors.purple, size: 34),
          title: Text('Plan a visit to ${c['name']}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_month_rounded, color: AppColors.primary),
                title: const Text('Day', style: TextStyle(fontSize: 12.5, color: AppColors.muted)),
                subtitle: Text(fmtDate(day),
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.text)),
                trailing: const Icon(Icons.edit_calendar_rounded, size: 20),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: sheet,
                    initialDate: day,
                    firstDate: DateUtils.dateOnly(DateTime.now()),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) setSheet(() => day = DateUtils.dateOnly(picked));
                },
              ),
              const SizedBox(height: 4),
              TextField(
                controller: reason,
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Why go back?',
                  hintText: 'e.g. owner away, collect payment next week',
                ),
              ),
              const SizedBox(height: 8),
              const Text('It waits for you as a task on that day.',
                  style: TextStyle(fontSize: 12, color: AppColors.muted)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(sheet, false), child: const Text('Cancel')),
            FilledButton.icon(
              onPressed: () => Navigator.pop(sheet, true),
              icon: const Icon(Icons.check_rounded),
              label: const Text('Plan it'),
            ),
          ],
        ),
      ),
    );
    if (planned != true || !mounted) return;
    final why = reason.text.trim();
    try {
      await Services.api.post('/api/v1/tasks', {
        'name': 'Visit ${c['name']}',
        if (why.isNotEmpty) 'description': why,
        'employee_id': Services.auth.profile!.employeeId,
        'partner_id': c['id'],
        'date_deadline': '${day.year.toString().padLeft(4, '0')}-'
            '${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}',
      });
      if (mounted) showSnack(context, 'Planned for ${fmtDate(day)}');
    } catch (e) {
      if (mounted) showProblem(context, e.toString());
    }
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
      _syncTimers();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Checking in asks which task the visit is for, then starts it.
  Future<void> _checkIn() async {
    setState(() => _busy = true);
    try {
      await startTaskForClient(context, _client!);
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// A visit opened for a task is closed by finishing it; one opened for an
  /// order or a payment is checked out here as before.
  Future<void> _checkOut() async {
    if (_task != null) {
      await resumeTask(context, _client!, _current!);
      await _load();
      return;
    }
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
      if (mounted) showProblem(context, e.toString());
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

  @override
  Widget build(BuildContext context) {
    final client = _client;
    final locked = _atThisClient && Services.auth.profile!.visitLock;
    return PopScope(
      canPop: !locked,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) showProblem(context, 'Check out first to leave this visit.');
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
      (Icons.event_available_rounded, 'Plan Visit', AppColors.purple, () => _planVisit(c)),
      // Checking in and out lives here now; there is no second button below.
      if (profile.feature('visits'))
        (
          _atThisClient ? (_task != null ? Icons.assignment_turned_in_rounded : Icons.logout_rounded) : Icons.login_rounded,
          _atThisClient ? (_task != null ? 'Open Task' : 'Check Out') : 'Check In',
          _atThisClient ? AppColors.danger : AppColors.warning,
          _busy || (_current != null && !_atThisClient) ? null : (_atThisClient ? _checkOut : _checkIn)
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
                  : [
                      if (distance != null) 'You are ${fmtDistance(distance)} away',
                      // Say why arrival check-in is or is not watching here.
                      if (Services.auth.profile!.autoVisit)
                        c['planned_today'] == true
                            ? 'Checks you in on arrival'
                            : "Not on today's plan - check in by hand",
                    ].join(' · '),
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
    // A lead buys nothing, owes nothing and returns nothing: the trading
    // actions would only be dead buttons on its screen.
    final lead = c['category_type'] == 'lead';
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
        if (_atThisClient) ...[
          const SizedBox(height: 12),
          _visitClock(),
          const SizedBox(height: 12),
          _visitWork(),
        ],
        if (c['onboard_pending'] == true && _current == null) ...[
          const SizedBox(height: 12),
          Card(
            color: AppColors.warning.withValues(alpha: 0.12),
            child: ListTile(
              leading: const Icon(Icons.assignment_ind_rounded, color: AppColors.warning),
              title: const Text('Confirmed — complete onboarding', style: TextStyle(fontWeight: FontWeight.w800)),
              subtitle: const Text('Add GST and the outlet details, then start the client visit.'),
              trailing: FilledButton(
                onPressed: () async {
                  await completeOnboarding(context, c);
                  if (mounted) _load();
                },
                child: const Text('Start'),
              ),
            ),
          ),
        ],
        if (_current != null && !_atThisClient) ...[
          const SizedBox(height: 12),
          _elsewhereNote(),
        ],
        const SizedBox(height: 12),
        _locationCard(c, lat, lng, distance),
        // A lead owes us nothing yet, so an empty balance card is only noise.
        if (c['category_type'] != 'lead') ...[
          const SizedBox(height: 12),
          ClientBalanceCard(clientId: widget.clientId),
        ],
        // Checked in at another customer: nothing to take here until they check out there.
        if (!lead && profile.feature('orders') && _canAct && c['allow_orders'] != false && c['approval_state'] == 'approved') ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _takeOrder(c),
            icon: const Icon(Icons.shopping_cart_rounded),
            label: Text(profile.isDemandFlow
                ? 'Take demand'
                : 'Take ${profile.label('order', 'Order').toLowerCase()}'),
          ),
        ],
        // Checked in here: what this customer has taken from us, product by product.
        if (!lead && profile.paymentCollection && _canAct) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => _collectPayment(c),
            icon: const Icon(Icons.payments_rounded),
            label: const Text('Collect payment'),
          ),
        ],
        if (_steps.isNotEmpty) ...[
          const SizedBox(height: 12),
          _stepsCard(),
        ],
        if (visits.isNotEmpty) ...[
          const SizedBox(height: 12),
          _visitsCard(visits),
        ],
      ],
    );
  }

  /// The steps of this visit, drawn as a line of work with what is left on it.
  Widget _stepsCard() {
    final done = _steps.where((step) => step['state'] == 'done').length;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 6),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(11)),
                child: const Icon(Icons.checklist_rounded, size: 17, color: AppColors.primary),
              ),
              const SizedBox(width: 9),
              const Expanded(
                child: Text('Visit steps', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
              ),
              Text('$done of ${_steps.length}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.muted)),
            ],
          ),
          const SizedBox(height: 9),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              value: _steps.isEmpty ? 0 : done / _steps.length,
              minHeight: 5,
              backgroundColor: AppColors.background,
            ),
          ),
          const SizedBox(height: 4),
          for (var i = 0; i < _steps.length; i++) _stepRow(i, i == _steps.length - 1),
        ],
      ),
    );
  }

  Widget _stepRow(int i, bool last) {
    final step = _steps[i];
    final state = '${step['state']}';
    final tint = state == 'done'
        ? AppColors.success
        : state == 'skipped'
            ? AppColors.warning
            : AppColors.primary;
    final note = asText(step['note']) ?? asText(step['instruction']);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _openStep(step),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The rail: a dot for this step and a line down to the next one.
            Column(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: state == 'pending' ? Colors.white : tint,
                    shape: BoxShape.circle,
                    border: Border.all(color: tint, width: 1.6),
                  ),
                  child: state == 'done'
                      ? const Icon(Icons.check_rounded, size: 15, color: Colors.white)
                      : state == 'skipped'
                          ? const Icon(Icons.redo_rounded, size: 14, color: Colors.white)
                          : Center(
                              child: Text('${i + 1}',
                                  style: TextStyle(
                                      fontSize: 12, fontWeight: FontWeight.w800, color: tint))),
                ),
                if (!last) Container(width: 2, height: 20, color: AppColors.border),
              ],
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('${step['name']}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                      ),
                      if (step['mandatory'] == true && state == 'pending')
                        const Text('Required',
                            style: TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.warning)),
                    ],
                  ),
                  if (note != null || state == 'skipped')
                    Text(state == 'skipped' ? 'Skipped' : note!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                ],
              ),
            ),
            if (state == 'pending')
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.muted),
              ),
          ],
        ),
      ),
    );
  }

  /// The last few calls here: when, how long, and what came of them.
  Widget _visitsCard(List<Map<String, dynamic>> visits) => Container(
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                      color: AppColors.sky.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(11)),
                  child: const Icon(Icons.history_rounded, size: 17, color: AppColors.sky),
                ),
                const SizedBox(width: 9),
                const Expanded(
                  child: Text('Recent visits', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                ),
                Text('${visits.length}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.muted)),
              ],
            ),
            const SizedBox(height: 4),
            for (final v in visits) _visitRow(v),
          ],
        ),
      );

  Widget _visitRow(Map<String, dynamic> v) {
    final open = v['state'] != 'done';
    final started = parseServerTime(v['check_in_at']);
    final minutes = (v['duration_min'] as num?)?.toInt();
    // A visit opened for a task is called by that task; older ones by what they were for.
    final purpose = switch (v['task']) {
      'client_visit' => 'Client Visit',
      'new_lead' => 'New Lead',
      'lead_follow_up' => 'New Lead Follow Up',
      'adhoc' => 'Adhoc Task',
      'sample_collection' => 'Sample Collection',
      'marketing_supply' => 'Marketing Material Supply',
      _ => switch (v['purpose']) {
          'client_visit' => 'Client visit',
          'chiller_update' => 'Chiller update',
          'other' => 'Other',
          _ => null,
        },
    };
    final note = asText(v['note']);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(14)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: (open ? AppColors.sky : AppColors.success).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(open ? Icons.timelapse_rounded : Icons.check_rounded,
                size: 16, color: open ? AppColors.sky : AppColors.success),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  [
                    if (started != null) fmtDate(started),
                    '${fmtTime(v['check_in_at'])}${open ? ' · still here' : '-${fmtTime(v['check_out_at'])}'}',
                  ].join(' · '),
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                if (purpose != null || (v['outcome_type'] as Map?)?['name'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      [purpose, (v['outcome_type'] as Map?)?['name']].whereType<String>().join(' · '),
                      style: const TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600),
                    ),
                  ),
                if (note != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(note,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                  ),
              ],
            ),
          ),
          if (minutes != null && minutes > 0)
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 2),
              child: Text('$minutes min',
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.muted)),
            ),
        ],
      ),
    );
  }

  /// The task this visit is for, and a way back into it.
  Widget _visitWork() {
    final code = _task;
    if (code == null) return const SizedBox.shrink();
    final name = switch (code) {
      'client_visit' => 'Client Visit',
      'lead_follow_up' => 'New Lead Follow Up',
      'sample_collection' => 'Sample Collection',
      'marketing_supply' => 'Marketing Material Supply',
      _ => 'Task',
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 12, 12, 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.assignment_turned_in_rounded, size: 19, color: AppColors.primary),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                const Text('In progress. Finish it to check out.',
                    style: TextStyle(fontSize: 12, color: AppColors.muted)),
              ],
            ),
          ),
          FilledButton(
            onPressed: _checkOut,
            style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
            child: const Text('Open'),
          ),
        ],
      ),
    );
  }

  /// A thin strip with the time at this customer counting up.
  ///
  /// Checking out already has its own button above, so this only keeps count.
  Widget _visitClock() {
    final started = parseServerTime(_current!['check_in_at']) ?? DateTime.now();
    final spent = DateTime.now().difference(started);
    String two(int value) => value.toString().padLeft(2, '0');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          const Icon(Icons.timer_outlined, size: 17, color: AppColors.success),
          const SizedBox(width: 8),
          Text(
            '${two(spent.inHours)}:${two(spent.inMinutes % 60)}:${two(spent.inSeconds % 60)}',
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: AppColors.success,
                fontFeatures: [FontFeature.tabularFigures()]),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text('at this customer · since ${fmtTime(_current!['check_in_at'])}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          ),
        ],
      ),
    );
  }

  /// Checked in somewhere else: say where, so the greyed-out buttons make sense.
  Widget _elsewhereNote() => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'You are checked in at ${(_current!['client'] as Map)['name']}. '
                'Check out there before working here.',
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
}
