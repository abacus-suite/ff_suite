import 'dart:async';
import 'dart:convert';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../../core/photos.dart';
import '../../core/format.dart';
import '../../core/local_state.dart';
import '../../core/models.dart';
import '../../core/permissions.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/dashboard.dart';
import '../../widgets/home_kit.dart';
import '../../widgets/member_picker.dart';
import '../notifications/notifications_screen.dart';
import '../more/profile_screen.dart';
import 'month_target_card.dart';
import 'my_requests_card.dart';
import '../../widgets/sync_status.dart';
import '../beat/beat_today_screen.dart';
import '../clients/client_detail_screen.dart';
import '../clients/clients_screen.dart';
import '../expenses/expenses_screen.dart';
import '../orders/catalog_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.onOpenTab});

  final void Function(String tab)? onOpenTab;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, dynamic>? _status;
  Map<String, dynamic>? _visit;
  Map<String, dynamic>? _today;
  Map<String, dynamic>? _sales;
  Map<String, dynamic>? _travel;
  List<Map<String, dynamic>> _visits = [];
  String _period = 'today';
  String _member = 'me';
  bool _loading = true;
  bool _punching = false;
  String? _error;

  Profile get _profile => Services.auth.profile!;

  @override
  void initState() {
    super.initState();
    Services.refresh.addListener(_load);
    _load();
    Services.auth.refreshProfile().then((_) {
      if (mounted) setState(() {});
    }).catchError((_) {});
  }

  @override
  void dispose() {
    Services.refresh.removeListener(_load);
    super.dispose();
  }

  Future<dynamic> _optional(Future<dynamic> future) =>
      future.catchError((_) => null);

  bool _peeked = false;

  /// The last known day, drawn before the server answers.
  Future<void> _peek() async {
    _peeked = true;
    final profile = _profile;
    final api = Services.api;
    final results = await Future.wait<dynamic>([
      api.peek('/api/v1/attendance/status'),
      api.peek('/api/v1/visits/current'),
      profile.feature('routes') ? api.peek('/api/v1/beat/today') : Future<dynamic>.value(null),
      profile.feature('orders')
          ? api.peek('/api/v1/orders/dashboard', query: {'period': _period, 'member': _member})
          : Future<dynamic>.value(null),
      api.peek('/api/v1/tracking/my-day'),
      api.peek('/api/v1/visits'),
    ]).catchError((_) => <dynamic>[null, null, null, null, null, null]);
    if (!mounted || _status != null || results[0] is! Map) return;
    setState(() {
      _status = (results[0] as Map).cast<String, dynamic>();
      _visit = (results[1] as Map?)?.cast<String, dynamic>();
      _today = (results[2] as Map?)?.cast<String, dynamic>();
      _sales = (results[3] as Map?)?.cast<String, dynamic>();
      _travel = (results[4] as Map?)?.cast<String, dynamic>();
      _visits = ((results[5] as List?) ?? []).cast<Map<String, dynamic>>();
    });
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    if (!_peeked) unawaited(_peek());
    final profile = _profile;
    try {
      final results = await Future.wait<dynamic>([
        Services.api.get('/api/v1/attendance/status'),
        _optional(Services.api.get('/api/v1/visits/current')),
        profile.feature('routes')
            ? _optional(Services.api.get('/api/v1/beat/today'))
            : Future<dynamic>.value(null),
        profile.feature('orders')
            ? _optional(Services.api
                .get('/api/v1/orders/dashboard', query: {'period': _period, 'member': _member}))
            : Future<dynamic>.value(null),
        _optional(Services.api.get('/api/v1/tracking/my-day')),
        _optional(Services.api.get('/api/v1/visits')),
      ]);
      final status = results[0] as Map<String, dynamic>;
      if (status['punched_in'] == true && !Services.tracker.active.value) {
        await Services.tracker.start(profile);
      } else if (status['punched_in'] != true &&
          Services.tracker.active.value) {
        await Services.tracker.stop();
      }
      unawaited(Services.tracker.flush());
      if (!mounted) return;
      setState(() {
        _status = status;
        _visit = results[1] as Map<String, dynamic>?;
        _today = results[2] as Map<String, dynamic>?;
        _sales = results[3] as Map<String, dynamic>?;
        _travel = results[4] as Map<String, dynamic>?;
        _visits = ((results[5] as List?) ?? []).cast<Map<String, dynamic>>();
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reloadSales(String period) async {
    setState(() => _period = period);
    final data = await _optional(Services.api
        .get('/api/v1/orders/dashboard', query: {'period': period, 'member': _member}));
    if (mounted) setState(() => _sales = data as Map<String, dynamic>?);
  }

  Future<void> _punch(bool punchIn) async {
    setState(() => _punching = true);
    try {
      final permissionError = await PermissionsHelper.ensureLocation();
      if (permissionError != null) throw permissionError;
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.best, timeLimit: Duration(seconds: 25)),
      );
      if (pos.isMocked && !_profile.allowMock)
        throw 'A fake GPS app was detected. Disable it to punch.';
      String? selfie;
      if (_profile.selfieRequired) {
        final photo = await takePhoto(ImageSource.camera, selfie: true);
        if (photo == null) throw 'A selfie is required to punch.';
        selfie = base64Encode(photo);
      }
      int? battery;
      try {
        battery = await Battery().batteryLevel;
      } catch (_) {}
      final body = <String, dynamic>{
        'lat': pos.latitude,
        'lng': pos.longitude,
        'accuracy': pos.accuracy,
        'mock': pos.isMocked,
        'battery': battery,
        if (selfie != null) 'selfie': selfie,
        // The server compares it with its own clock (queued offline work is exempt).
        'device_time': DateTime.now().toUtc().toIso8601String(),
      };
      var queued = false;
      if (punchIn) {
        final result = await Services.outbox.submit('/api/v1/attendance/punch-in', body, label: 'Punch in');
        queued = result.queued;
        if (queued) await LocalState.punched(true);
        final background = await PermissionsHelper.ensureBackgroundTracking();
        await Services.tracker.start(_profile);
        if (!background && mounted) {
          showSnack(context,
              'Set location to "Allow all the time" so tracking keeps working.');
        }
      } else {
        await Services.tracker.flush();
        final result = await Services.outbox.submit('/api/v1/attendance/punch-out', body, label: 'Punch out');
        queued = result.queued;
        if (queued) await LocalState.punched(false);
        await Services.tracker.stop();
      }
      if (mounted) {
        showSnack(context, queued ? '${punchIn ? 'Checked in' : 'Checked out'} · Saved on the phone · it will sync when you are back online' : (punchIn ? 'Checked in' : 'Checked out'));
      }
      await _load();
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
    } finally {
      if (mounted) setState(() => _punching = false);
    }
  }

  Future<void> _push(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              HomeHeader(
                name: profile.name,
                bell: const NotificationBell(),
                onAvatar: () => _push(const ProfileScreen()),
              ),
              const SizedBox(height: 14),
              if (_loading && _status == null)
                const Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(child: CircularProgressIndicator()))
              else if (_error != null && _status == null)
                Card(child: ErrorView(message: _error!, onRetry: _load))
              else ...[
                HeroBanner(
                  routeLabel:
                      profile.feature('routes') ? profile.routeLabel : 'Today',
                  onExplore: () => _push(profile.feature('routes')
                      ? const BeatTodayScreen()
                      : const ClientsScreen()),
                ),
                const SizedBox(height: 14),
                if (profile.feature('attendance')) ...[
                  _punchRow(),
                  const SizedBox(height: 14),
                ],
                if (_visit != null) ...[
                  _ongoingVisitCard(_visit!),
                  const SizedBox(height: 12),
                ],
                _todaySummary(),
                const SizedBox(height: 12),
                if (profile.feature('orders')) ...[
                  _salesSummary(),
                  const SizedBox(height: 12),
                ],
                _quickActions(profile),
                const SizedBox(height: 12),
                _targetBanner(),
                const SizedBox(height: 12),
                const MonthTargetCard(),
                const MyTasksCard(),
                const MyRequestsCard(),
                const SizedBox(height: 12),
                _travelCard(),
                const SizedBox(height: 12),
                _lastVisited(profile),
                const SizedBox(height: 12),
                const SyncStatusBar(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _punchRow() {
    final punchedIn = _status?['punched_in'] == true;
    final current = _status?['current'] as Map<String, dynamic>?;
    return IntrinsicHeight(
        child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: PunchTile(
            title: 'Check In',
            subtitle: punchedIn
                ? 'Since ${fmtTime(current?['check_in'])}'
                : 'Start Your Day',
            hint: punchedIn ? 'You are on duty' : 'Tap to mark your location',
            icon: Icons.place_rounded,
            colour: AixoloColors.success,
            enabled: !punchedIn,
            busy: _punching,
            onTap: () => _punch(true),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: PunchTile(
            title: 'Check Out',
            subtitle: punchedIn
                ? 'Worked ${fmtHours(_status?['worked_hours_today'] as num?)}'
                : 'End Your Day',
            hint: punchedIn ? "Complete today's work" : 'Check in first',
            icon: Icons.logout_rounded,
            colour: AixoloColors.danger,
            enabled: punchedIn,
            busy: _punching,
            onTap: () => _punch(false),
          ),
        ),
      ],
    ));
  }

  Widget _quickActions(Profile profile) {
    final actions = <(IconData, String, Color, Widget)>[
      if (profile.feature('routes'))
        (
          Icons.route_rounded,
          'My ${profile.routeLabel}',
          AixoloColors.primary,
          const BeatTodayScreen()
        ),
      if (profile.feature('orders'))
        (
          Icons.inventory_2_rounded,
          'Products',
          AixoloColors.purple,
          const CatalogScreen()
        ),
      (
        Icons.groups_2_rounded,
        '${profile.label('client', 'Customer')}s',
        AixoloColors.warning,
        const ClientsScreen()
      ),
      (
        Icons.receipt_rounded,
        'Expenses',
        AixoloColors.danger,
        const ExpensesScreen()
      ),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CardHeader(icon: Icons.apps_rounded, title: 'Quick Actions'),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final action in actions) ...[
                    QuickAction(
                      icon: action.$1,
                      label: action.$2,
                      colour: action.$3,
                      onTap: () => _push(action.$4),
                    ),
                    const SizedBox(width: 10),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// How the day is going against the plan, in one line.
  Widget _targetBanner() {
    final clients =
        ((_today?['clients'] as List?) ?? []).cast<Map<String, dynamic>>();
    final planned = clients.length;
    final visited = clients
        .where((client) =>
            client['visit_status'] == 'done' ||
            client['plan_status'] == 'visited')
        .length;
    if (planned == 0) {
      return const SizedBox.shrink();
    }
    final left = planned - visited;
    return TargetBanner(
      done: visited,
      target: planned,
      title: left <= 0 ? 'Target reached!' : 'Keep Going!',
      message: left <= 0
          ? "Every planned visit is done. Anything extra counts as a bonus."
          : "You're $left visit${left == 1 ? '' : 's'} away from today's target.",
    );
  }

  Widget _ongoingVisitCard(Map<String, dynamic> visit) {
    final client = visit['client'] as Map;
    return Card(
      color: const Color(0xFFE8F6FF),
      child: ListTile(
        leading: const CircleAvatar(
            backgroundColor: AixoloColors.sky,
            child: Icon(Icons.storefront_rounded, color: Colors.white)),
        title: Text('At ${client['name']}',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
            'Checked in ${fmtTime(visit['check_in_at'])} · tap to continue'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => _push(ClientDetailScreen(clientId: client['id'] as int)),
      ),
    );
  }

  Widget _todaySummary() {
    final clients =
        ((_today?['clients'] as List?) ?? []).cast<Map<String, dynamic>>();
    var visited = 0, pending = 0, cancelled = 0;
    for (final client in clients) {
      final status = client['visit_status'] == 'done'
          ? 'visited'
          : (client['plan_status'] as String? ?? 'planned');
      if (status == 'visited') {
        visited++;
      } else if (status == 'cancelled') {
        cancelled++;
      } else if (status != 'skipped') {
        pending++;
      }
    }
    final planned = clients.length;
    double share(int value) => planned == 0 ? 0 : value / planned;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            CardHeader(
              icon: Icons.assignment_rounded,
              title: 'Today Summary',
              trailing: TextButton(
                onPressed: () => _push(const BeatTodayScreen()),
                child: const Text('View All'),
              ),
            ),
            const SizedBox(height: 12),
            IntrinsicHeight(
                child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: SummaryTile(
                    icon: Icons.event_note_rounded,
                    colour: AixoloColors.primary,
                    value: planned,
                    label: 'Planned',
                    percent: planned == 0 ? 0 : 1,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SummaryTile(
                    icon: Icons.check_circle_rounded,
                    colour: AixoloColors.success,
                    value: visited,
                    label: 'Visited',
                    percent: share(visited),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SummaryTile(
                    icon: Icons.schedule_rounded,
                    colour: AixoloColors.warning,
                    value: pending,
                    label: 'Pending',
                    percent: share(pending),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SummaryTile(
                    icon: Icons.cancel_rounded,
                    colour: AixoloColors.danger,
                    value: cancelled,
                    label: 'Cancelled',
                    percent: share(cancelled),
                  ),
                ),
              ],
            )),
          ],
        ),
      ),
    );
  }

  String get _compareWord => switch (_period) {
        'week' => 'last week',
        'month' => 'last month',
        _ => 'yesterday',
      };

  Widget _salesSummary() {
    final sales = _sales;
    final currency = sales?['currency'] as String?;
    final previous = (sales?['previous'] as Map<String, dynamic>?) ?? const {};
    final hours =
        ((sales?['hours'] as List?) ?? []).cast<Map<String, dynamic>>();
    final daily =
        ((sales?['series'] as List?) ?? []).cast<Map<String, dynamic>>();
    // Today reads by the hour; a longer period reads by the day.
    final rows = _period == 'today' && hours.isNotEmpty ? hours : daily;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CardHeader(
              icon: Icons.bar_chart_rounded,
              title: 'Sales Summary',
              trailing: PeriodSelector(value: _period, onChanged: _reloadSales),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: MemberPicker(
                value: _member,
                dense: true,
                onChanged: (value) {
                  setState(() => _member = value);
                  _reloadSales(_period);
                },
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: StatBox(
                    icon: Icons.shopping_basket_rounded,
                    colour: AixoloColors.primary,
                    label: 'Total ${Services.auth.profile!.orderWord}s',
                    value: '${sales?['count'] ?? 0}',
                    change: (previous['count_change'] as num?)?.toDouble(),
                    compareWith: _compareWord,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: StatBox(
                    icon: Icons.payments_rounded,
                    colour: AixoloColors.success,
                    label: 'Total Value',
                    value: fmtMoney(sales?['amount_total'] as num?, currency),
                    change: (previous['amount_change'] as num?)?.toDouble(),
                    compareWith: _compareWord,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SalesLineChart(
              points: [
                for (final row in rows)
                  ((row['amount'] as num?) ?? 0).toDouble()
              ],
              labels: [for (final row in rows) '${row['label']}'],
              format: (value) => value >= 1000
                  ? '${fmtMoney(value / 1000, currency)}K'
                      .replaceAll('.0K', 'K')
                  : fmtMoney(value, currency),
            ),
          ],
        ),
      ),
    );
  }

  Widget _travelCard() {
    final travel = _travel;
    final points = ((travel?['points'] as List?) ?? [])
        .cast<Map<String, dynamic>>()
        .map((p) =>
            LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble()))
        .toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const CardHeader(
                icon: Icons.route_rounded, title: 'Total Traveled'),
            const SizedBox(height: 12),
            RouteMiniMap(points: points),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                    '${((travel?['distance_km'] as num?) ?? 0).toStringAsFixed(1)} ',
                    style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: AixoloColors.text)),
                const Text('KM today',
                    style: TextStyle(fontSize: 13, color: AixoloColors.muted)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _lastVisited(Profile profile) {
    final recent = _visits.take(5).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            CardHeader(
              icon: Icons.groups_rounded,
              title: 'Last 5 Visited',
              trailing: TextButton(
                  onPressed: () => widget.onOpenTab?.call('customers'),
                  child: const Text('View All')),
            ),
            const SizedBox(height: 4),
            if (recent.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                    'No ${profile.label('visit', 'visit').toLowerCase()}s today yet',
                    style: const TextStyle(color: AixoloColors.muted)),
              )
            else
              for (final visit in recent)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.store_rounded,
                      color: AixoloColors.primary),
                  title: Text('${(visit['client'] as Map)['name']}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14)),
                  trailing: Text(fmtTime(visit['check_in_at']),
                      style: const TextStyle(
                          fontSize: 12, color: AixoloColors.muted)),
                  onTap: () => _push(ClientDetailScreen(
                      clientId: (visit['client'] as Map)['id'] as int)),
                ),
          ],
        ),
      ),
    );
  }
}
