import 'dart:async';
import 'dart:convert';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../core/photos.dart';
import 'punch_form.dart';
import '../../core/format.dart';
import '../../core/geo.dart';
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
import 'day_journey_screen.dart';
import 'sales_cards.dart';
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
  final PageController _visitPages = PageController(viewportFraction: 0.86);
  int _visitPage = 0;
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
    _visitPages.dispose();
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
      final shiftEnd = _shiftEndsAt();
      final asksEarly = _profile.earlyCheckoutReason && !punchIn && shiftEnd != null &&
          DateTime.now().isBefore(shiftEnd);
      final needSelfie = _profile.selfieRequired;
      final needVehicle = punchIn && _profile.punchVehicle;
      final needOdometer = _profile.punchOdometer;
      PunchInput? filled = const PunchInput();
      if (needSelfie || needVehicle || needOdometer || asksEarly) {
        if (!mounted) return;
        filled = await Navigator.of(context).push<PunchInput>(MaterialPageRoute(
          builder: (_) => PunchFormScreen(
            punchIn: punchIn,
            needSelfie: needSelfie,
            needVehicle: needVehicle,
            needOdometer: needOdometer,
            vehicle: punchIn ? null : (_status?['current'] as Map?)?['vehicle'] as String?,
            shiftEndsAt: shiftEnd,
            askEarlyReason: _profile.earlyCheckoutReason,
          ),
        ));
        if (filled == null) return; // backed out of the form: nothing is punched
      }
      final selfie = filled.selfie == null ? null : base64Encode(filled.selfie!);
      final vehicle = filled.vehicle;
      final vehicleNote = filled.vehicleNote;
      final earlyReason = filled.earlyReason;
      final odometer = filled.odometer;
      final odometerPhoto = filled.odometerPhoto == null ? null : base64Encode(filled.odometerPhoto!);
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
        if (vehicleNote != null && vehicleNote.isNotEmpty) 'vehicle_note': vehicleNote,
        if (earlyReason != null && earlyReason.isNotEmpty) 'early_reason': earlyReason,
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

  /// When today's shift is due to end, as the phone reads the clock.
  DateTime? _shiftEndsAt() {
    final ends = (_status?['shift'] as Map?)?['ends_at'];
    return ends == null ? null : DateTime.tryParse('$ends');
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
                  _salesCard(),
                  const SizedBox(height: 12),
                  _topProductsCard(),
                  const SizedBox(height: 12),
                ],
                _travelCard(),
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
      onDutySince: DateTime.tryParse('${current?['check_in'] ?? ''}')?.toLocal(),
      workedHours: ((_status?['worked_hours_today'] as num?) ?? 0).toDouble(),
      routeLabel: profile.routeLabel,
      onPunch: () => _punch(!punchedIn),
    );
  }

  /// What was sold, in its own wide card.
  Widget _salesCard() {
    final sales = _sales;
    final previous = (sales?['previous'] as Map<String, dynamic>?) ?? const {};
    final hours = ((sales?['hours'] as List?) ?? []).cast<Map<String, dynamic>>();
    final daily = ((sales?['series'] as List?) ?? []).cast<Map<String, dynamic>>();
    final rows = _period == 'today' && hours.isNotEmpty ? hours : daily;
    final today = DateTime.now();
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return SalesCard(
      amount: (sales?['amount_total'] as num?) ?? 0,
      currency: sales?['currency'] as String?,
      change: (previous['amount_change'] as num?)?.toDouble(),
      compareWith: _compareWord,
      count: ((sales?['count'] as num?) ?? 0).toInt(),
      points: [for (final row in rows) ((row['amount'] as num?) ?? 0).toDouble()],
      labels: [for (final row in rows) '${row['label']}'],
      period: _period,
      onPeriod: _reloadSales,
      subtitle: '${today.day} ${months[today.month - 1]} ${today.year}, ${days[today.weekday - 1]}',
      onOpen: _openSalesDetail,
    );
  }

  /// What moved most, in its own wide card.
  Widget _topProductsCard() {
    return TopProductsCard(
      rows: ((_sales?['top_products'] as List?) ?? []).cast<Map<String, dynamic>>(),
      period: _period,
      onPeriod: _reloadSales,
      onViewAll: () => _push(const CatalogScreen()),
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

  Widget _travelCard() {
    final travel = _travel;
    final raw = ((travel?['points'] as List?) ?? []).cast<Map<String, dynamic>>();
    final points = raw
        .map((p) => LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble()))
        .toList();
    // How long the day has been moving: first position to last.
    final first = raw.isEmpty ? null : DateTime.tryParse('${raw.first['ts']}');
    final last = raw.isEmpty ? null : DateTime.tryParse('${raw.last['ts']}');
    final minutes = first != null && last != null ? last.difference(first).inMinutes : 0;
    return TravelCard(
      km: (travel?['distance_km'] as num?) ?? 0,
      points: points,
      visits: _visits.length,
      minutes: minutes,
      onOpen: () => _push(const DayJourneyScreen()),
      onOpenMap: () => _push(const DayJourneyScreen(showMapFirst: true)),
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
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CardHead(
              icon: Icons.event_available_rounded,
              title: 'Upcoming Visits',
              subtitle: '${waiting.length} still to see today',
              tint: AppColors.primary,
              trailing: TextButton(
                onPressed: () => _push(const BeatTodayScreen()),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [Text('View All'), Icon(Icons.chevron_right_rounded, size: 18)],
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 128,
              child: PageView.builder(
                controller: _visitPages,
                padEnds: false,
                itemCount: waiting.length,
                onPageChanged: (page) => setState(() => _visitPage = page),
                itemBuilder: (_, i) => Padding(
                  padding: EdgeInsets.only(right: i == waiting.length - 1 ? 0 : 10),
                  child: _upcomingCard(waiting[i], i),
                ),
              ),
            ),
            if (waiting.length > 1) ...[
              const SizedBox(height: 8),
              Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < waiting.length; i++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: i == _visitPage ? 18 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: i == _visitPage ? AppColors.primary : AppColors.border,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _upcomingCard(Map<String, dynamic> client, int index) {
    final tint = index.isEven ? AppColors.primary : AppColors.purple;
    final address = asText(client['address']) ?? asText((client['district'] as Map?)?['name']) ?? '';
    final metres = client['distance_m'] as num?;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _push(ClientDetailScreen(clientId: client['id'] as int)),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [tint.withValues(alpha: 0.1), tint.withValues(alpha: 0.03)],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(13)),
                  child: Icon(Icons.storefront_rounded, color: tint, size: 21),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${client['name']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5)),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(Icons.location_on_outlined, size: 12, color: AppColors.muted),
                          const SizedBox(width: 2),
                          Expanded(
                            child: Text(address,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11.5, color: AppColors.muted, height: 1.25)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
              ],
            ),
            const Spacer(),
            Row(
              children: [
                _visitChip(Icons.tag_rounded, 'Stop ${client['sequence'] ?? index + 1}', tint),
                const SizedBox(width: 8),
                if (metres != null) _visitChip(Icons.near_me_rounded, fmtDistance(metres), AppColors.muted),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _visitChip(IconData icon, String text, Color tint) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(11)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: tint),
            const SizedBox(width: 4),
            Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: tint)),
          ],
        ),
      );

  Widget _quickActions(Profile profile) {
    final actions = <(IconData, String, String, Color, Widget)>[
      if (profile.feature('routes'))
        (
          Icons.route_rounded,
          'My ${profile.routeLabel}',
          "View today's plan",
          AppColors.primary,
          const BeatTodayScreen()
        ),
      if (profile.feature('orders'))
        (Icons.inventory_2_rounded, 'Products', 'Browse products', AppColors.purple, const CatalogScreen()),
      (
        Icons.groups_2_rounded,
        '${profile.label('client', 'Customer')}s',
        'Manage your customers',
        AppColors.warning,
        const ClientsScreen()
      ),
      (Icons.receipt_rounded, 'Expenses', 'Add new expense', AppColors.danger, const ExpensesScreen()),
    ];
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CardHead(
              icon: Icons.bolt_rounded,
              title: 'Quick Actions',
              subtitle: 'Get things done faster',
              tint: AppColors.success,
            ),
            const SizedBox(height: 12),
            // Two by two, sized by their own content: a grid inside a card
            // leaves an empty strip when the rows are shorter than it expects.
            for (var row = 0; row < (actions.length + 1) ~/ 2; row++)
              Padding(
                padding: EdgeInsets.only(bottom: row == (actions.length - 1) ~/ 2 ? 0 : 10),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: _actionTile(actions[row * 2])),
                      const SizedBox(width: 10),
                      Expanded(
                        child: row * 2 + 1 < actions.length
                            ? _actionTile(actions[row * 2 + 1])
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _actionTile((IconData, String, String, Color, Widget) action) {
    final (icon, label, hint, tint, screen) = action;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _push(screen),
      child: Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [tint.withValues(alpha: 0.12), tint.withValues(alpha: 0.03)],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: tint, size: 19),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5)),
                      Text(hint,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, color: AppColors.muted, height: 1.2)),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
                  child: const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 15),
                ),
              ],
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


}
