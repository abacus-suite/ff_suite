import 'dart:async';
import 'dart:convert';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../../core/photos.dart';
import 'punch_extras.dart';
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
import 'home_cards.dart';
import 'month_target_card.dart';
import 'recommendations_card.dart';
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
      final place = await currentPlace(fresh: true);
      String? selfie;
      if (_profile.selfieRequired) {
        final photo = await takePhoto(ImageSource.camera, selfie: true);
        if (photo == null) throw 'A selfie is required to punch.';
        selfie = base64Encode(photo);
      }
      String? vehicle;
      if (punchIn && _profile.punchVehicle) {
        if (!mounted) return;
        vehicle = await askVehicle(context);
        if (vehicle == null) throw 'Choose how you are travelling today.';
      }
      String? odometerPhoto;
      double? odometer;
      if (_profile.punchOdometer) {
        final photo = await takePhoto(ImageSource.camera);
        if (photo == null) throw 'A photo of the odometer is required.';
        if (!mounted) return;
        final reading = await askOdometer(context);
        if (reading == null) throw 'Enter the odometer reading.';
        odometerPhoto = base64Encode(photo);
        odometer = reading;
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
        if (place.address.isNotEmpty) 'address': place.address,
        if (selfie != null) 'selfie': selfie,
        if (vehicle != null) 'vehicle': vehicle,
        if (odometer != null) 'odometer': odometer,
        if (odometerPhoto != null) 'odometer_photo': odometerPhoto,
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
                if (profile.feature('attendance')) ...[
                  _hero(profile),
                  const SizedBox(height: 14),
                ] else ...[
                  HeroBanner(
                    routeLabel: profile.feature('routes') ? profile.routeLabel : 'Today',
                    onExplore: () => _push(profile.feature('routes')
                        ? const BeatTodayScreen()
                        : const ClientsScreen()),
                  ),
                  const SizedBox(height: 14),
                ],
                if (_visit != null) ...[
                  _ongoingVisitCard(_visit!),
                  const SizedBox(height: 12),
                ],
                _todaySummary(),
                const SizedBox(height: 12),
                if (_status?['punched_in'] == true && profile.feature('visits')) const RecommendationsCard(),
                if (profile.feature('orders')) ...[
                  _salesAndProducts(),
                  const SizedBox(height: 12),
                ],
                _travelStrip(),
                const SizedBox(height: 12),
                _upcomingVisits(profile),
                const SizedBox(height: 12),
                const MyTasksCard(),
                const MyRequestsCard(),
                const SizedBox(height: 12),
                _quickActions(profile),
                const SizedBox(height: 12),
                _targetBanner(),
                const SizedBox(height: 12),
                const MonthTargetCard(),
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

  /// The day in one card: where it stands and the button that moves it on.
  Widget _hero(Profile profile) {
    final punchedIn = _status?['punched_in'] == true;
    final current = _status?['current'] as Map<String, dynamic>?;
    final planned = ((_today?['clients'] as List?) ?? []).length;
    return CheckInHero(
      punchedIn: punchedIn,
      since: fmtTime(current?['check_in']),
      worked: fmtHours(_status?['worked_hours_today'] as num?),
      target: planned,
      busy: _punching,
      routeLabel: profile.routeLabel,
      onPunch: () => _punch(!punchedIn),
    );
  }

  /// Today's money on the left, what moved on the right.
  Widget _salesAndProducts() {
    final sales = _sales;
    final currency = sales?['currency'] as String?;
    final previous = (sales?['previous'] as Map<String, dynamic>?) ?? const {};
    final hours = ((sales?['hours'] as List?) ?? []).cast<Map<String, dynamic>>();
    final daily = ((sales?['series'] as List?) ?? []).cast<Map<String, dynamic>>();
    final rows = _period == 'today' && hours.isNotEmpty ? hours : daily;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: MiniCard(
              icon: Icons.bar_chart_rounded,
              title: switch (_period) { 'week' => "Week's Sales", 'month' => "Month's Sales", _ => "Today's Sales" },
              action: InkWell(
                onTap: _openSalesDetail,
                child: const Icon(Icons.open_in_new_rounded, size: 16, color: AppColors.muted),
              ),
              child: SalesGlance(
                amount: (sales?['amount_total'] as num?) ?? 0,
                currency: currency,
                change: (previous['amount_change'] as num?)?.toDouble(),
                compareWith: _compareWord,
                bars: [for (final row in rows) ((row['amount'] as num?) ?? 0).toDouble()],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: MiniCard(
              icon: Icons.inventory_2_rounded,
              title: 'Top Products',
              onTap: () => _push(const CatalogScreen()),
              child: TopProducts(
                rows: ((sales?['top_products'] as List?) ?? []).cast<Map<String, dynamic>>(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The full sales card, with its period and person choices, on demand.
  void _openSalesDetail() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (_, __) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          builder: (_, controller) => Container(
            decoration: const BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
              children: [_salesSummary()],
            ),
          ),
        ),
      ),
    );
  }

  Widget _travelStrip() {
    final travel = _travel;
    final points = ((travel?['points'] as List?) ?? [])
        .cast<Map<String, dynamic>>()
        .map((p) => LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble()))
        .toList();
    return TravelStrip(
      km: (travel?['distance_km'] as num?) ?? 0,
      change: (travel?['distance_change'] as num?)?.toDouble(),
      points: points,
      onOpen: () => _push(const BeatTodayScreen()),
    );
  }

  /// The customers still to be seen today, as cards you can swipe through.
  Widget _upcomingVisits(Profile profile) {
    final clients = ((_today?['clients'] as List?) ?? []).cast<Map<String, dynamic>>();
    final waiting = clients
        .where((c) => c['visit_status'] == 'pending' && c['plan_status'] != 'cancelled')
        .take(8)
        .toList();
    if (waiting.isEmpty) return const SizedBox.shrink();
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.place_rounded, size: 18, color: AppColors.primary),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text('Upcoming Visits', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                ),
                TextButton(
                  onPressed: () => _push(const BeatTodayScreen()),
                  child: const Text('View All'),
                ),
              ],
            ),
            SizedBox(
              height: 78,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: waiting.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) => _upcomingCard(waiting[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _upcomingCard(Map<String, dynamic> client) {
    final address = asText(client['address']) ?? asText((client['district'] as Map?)?['name']) ?? '';
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _push(ClientDetailScreen(clientId: client['id'] as int)),
      child: Container(
        width: 210,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(14)),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.storefront_rounded, size: 19, color: AppColors.primary),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('${client['name']}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined, size: 12, color: AppColors.muted),
                      const SizedBox(width: 2),
                      Expanded(
                        child: Text(address,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.muted),
          ],
        ),
      ),
    );
  }

  Widget _quickActions(Profile profile) {
    final actions = <(IconData, String, Color, Widget)>[
      if (profile.feature('routes'))
        (
          Icons.route_rounded,
          'My ${profile.routeLabel}',
          AppColors.primary,
          const BeatTodayScreen()
        ),
      if (profile.feature('orders'))
        (
          Icons.inventory_2_rounded,
          'Products',
          AppColors.purple,
          const CatalogScreen()
        ),
      (
        Icons.groups_2_rounded,
        '${profile.label('client', 'Customer')}s',
        AppColors.warning,
        const ClientsScreen()
      ),
      (
        Icons.receipt_rounded,
        'Expenses',
        AppColors.danger,
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
            backgroundColor: AppColors.sky,
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
                    colour: AppColors.primary,
                    value: planned,
                    label: 'Planned',
                    percent: planned == 0 ? 0 : 1,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SummaryTile(
                    icon: Icons.check_circle_rounded,
                    colour: AppColors.success,
                    value: visited,
                    label: 'Visited',
                    percent: share(visited),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SummaryTile(
                    icon: Icons.schedule_rounded,
                    colour: AppColors.warning,
                    value: pending,
                    label: 'Pending',
                    percent: share(pending),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SummaryTile(
                    icon: Icons.cancel_rounded,
                    colour: AppColors.danger,
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
                    colour: AppColors.primary,
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
                    colour: AppColors.success,
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
                    style: const TextStyle(color: AppColors.muted)),
              )
            else
              for (final visit in recent)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.store_rounded,
                      color: AppColors.primary),
                  title: Text('${(visit['client'] as Map)['name']}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14)),
                  trailing: Text(fmtTime(visit['check_in_at']),
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.muted)),
                  onTap: () => _push(ClientDetailScreen(
                      clientId: (visit['client'] as Map)['id'] as int)),
                ),
          ],
        ),
      ),
    );
  }
}
