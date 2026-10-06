import 'dart:async';
import 'dart:convert';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

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
import '../../core/duty_watch.dart';
import 'day_journey_screen.dart';
import 'sales_cards.dart';
import 'month_target_card.dart';
import 'recommendations_card.dart';
import 'my_requests_card.dart';
import '../../widgets/sync_status.dart';
import '../beat/beat_today_screen.dart';
import '../clients/client_detail_screen.dart';
import '../clients/clients_screen.dart';
import '../orders/catalog_screen.dart';
import '../../widgets/skeleton.dart';
import '../approvals/approvals_screen.dart';
import '../approvals/my_pending_screen.dart';
import 'team_dashboard.dart';

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

  /// Top Products has its own period: changing it must not move the sales card.
  String _topPeriod = 'today';

  /// A manager's choice: their own day, or the team's.
  bool _teamView = false;

  /// How many requests wait for this manager, for the number on the Approvals button.
  int _pending = 0;

  /// My own requests still waiting for somebody else, for the small icon in the check-in card.
  int _myPending = 0;
  List<Map<String, dynamic>>? _topRows;
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

  /// The attendance we may draw: never yesterday's, however it reached us.
  Map<String, dynamic>? get _day => _isToday(_status) ? _status : null;

  /// Is this attendance payload about the day the phone is living in?
  bool _isToday(Map<String, dynamic>? status) {
    final day = asText(status?['date']);
    return day == null || day == fmtDate(DateTime.now());
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
    // Yesterday's saved copy must never be drawn as today: a day that has
    // turned over shows nothing until the server answers.
    if (!mounted || _status != null || results[0] is! Map) return;
    if (!_isToday((results[0] as Map).cast<String, dynamic>())) return;
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
      // While the day is open the app asks now and then whether it still is.
      DutyWatch.instance.update(
        onDuty: status['punched_in'] == true,
        askEvery: ((status['duty_check_minutes'] as num?) ?? 0).toInt(),
        waitFor: ((status['duty_reply_minutes'] as num?) ?? 5).toInt(),
        shiftEnd: DateTime.tryParse('${(status['shift'] as Map?)?['ends_at'] ?? ''}'.replaceFirst(' ', 'T')),
      );
      DutyWatch.instance.check();
      if (status['punched_in'] == true && !Services.tracker.active.value) {
        await Services.tracker.start(profile);
      } else if (status['punched_in'] != true &&
          Services.tracker.active.value) {
        await Services.tracker.stop();
      }
      unawaited(Services.tracker.flush());
      if (profile.isManager) unawaited(_loadPending());
      unawaited(_loadMyPending());
      // Top Products keeps its own period: bring it up to date when it differs from the sales card's.
      if (_topPeriod != _period) unawaited(_reloadTop(_topPeriod));
      if (!mounted) return;
      setState(() {
        _status = status;
        _visit = results[1] as Map<String, dynamic>?;
        _today = results[2] as Map<String, dynamic>?;
        _sales = results[3] as Map<String, dynamic>?;
        _topRows = null;
        _travel = results[4] as Map<String, dynamic>?;
        _visits = ((results[5] as List?) ?? []).cast<Map<String, dynamic>>();
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      Services.settling.value = false;
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMyPending() async {
    final data = await _optional(Services.api.get('/api/v1/my-pending'));
    if (mounted && data is Map) setState(() => _myPending = ((data['total'] as num?) ?? 0).toInt());
  }

  Future<void> _loadPending() async {
    final data = await _optional(Services.api.get('/api/v1/approvals/summary'));
    if (mounted && data is Map) setState(() => _pending = ((data['total'] as num?) ?? 0).toInt());
  }

  Future<void> _reloadTop(String period) async {
    setState(() => _topPeriod = period);
    final data = await _optional(Services.api
        .get('/api/v1/orders/dashboard', query: {'period': period, 'member': _member}));
    if (mounted && data is Map && _topPeriod == period) {
      setState(() => _topRows = ((data['top_products'] as List?) ?? []).cast<Map<String, dynamic>>());
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
      // The fix is taken while the steps are on screen, so there is no wait between them and the check-in.
      final posFuture = Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.best, timeLimit: Duration(seconds: 25)),
      );
      final placeFuture = currentPlace(fresh: true);
      posFuture.then((_) {}, onError: (_) {});
      placeFuture.then((_) {}, onError: (_) {});
      final shiftEnd = _shiftEndsAt();
      final asksEarly = _profile.earlyCheckoutReason && !punchIn && shiftEnd != null &&
          DateTime.now().isBefore(shiftEnd);
      final needSelfie = _profile.selfieRequired;
      final needVehicle = punchIn && _profile.punchVehicle;
      final needOdometer = _profile.punchOdometer;
      PunchInput? filled = const PunchInput();
      if (needSelfie || needVehicle || needOdometer || asksEarly || (punchIn && _profile.beatAtCheckin)) {
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
            odometerIn: ((_status?['current'] as Map?)?['odometer_in'] as num?)?.toDouble(),
            odometerLast: (_status?['odometer_last'] as num?)?.toDouble(),
            planBeat: punchIn && _profile.beatAtCheckin,
          ),
        ));
        if (filled == null) return; // backed out of the form: nothing is punched
      }
      final pos = await posFuture;
      if (pos.isMocked && !_profile.allowMock) {
        throw 'A fake GPS app was detected. Disable it to punch.';
      }
      final place = await placeFuture;
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
      if (mounted) showProblem(context, e.toString());
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

  /// Every card of the home screen, in the order they are read. Cards that
  /// have nothing to show return an empty widget and are dropped here, so the
  /// gap between what is left stays the same everywhere.
  List<Widget> _cards(Profile profile) {
    final cards = <Widget>[
      if (profile.feature('attendance'))
        _hero(profile)
      else
        HeroBanner(
          routeLabel: profile.feature('routes') ? profile.routeLabel : 'Today',
          onExplore: () =>
              _push(profile.feature('routes') ? const BeatTodayScreen() : const ClientsScreen()),
        ),
      if (_visit != null) _ongoingVisitCard(_visit!),
      _todaySummary(),
      if (_day?['punched_in'] == true && profile.feature('visits')) const RecommendationsCard(),
      if (profile.feature('orders')) ...[_salesCard(), _topProductsCard()],
      _upcomingVisits(profile),
      const MyTasksCard(),
      const MyRequestsCard(),
      _targetBanner(),
      const MonthTargetCard(),
    ];
    return [for (final card in cards) if (card is! SizedBox) card];
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    return Scaffold(
      body: Stack(children: [
        _homeBody(profile),
        ValueListenableBuilder<bool>(
          valueListenable: Services.settling,
          builder: (_, settling, __) => settling
              ? Positioned.fill(
                  child: Container(
                    color: Colors.white.withValues(alpha: 0.88),
                    alignment: Alignment.center,
                    child: const Column(mainAxisSize: MainAxisSize.min, children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 14),
                      Text('Updating your day...', style: TextStyle(fontWeight: FontWeight.w700)),
                    ]),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ]),
    );
  }

  Widget _homeBody(Profile profile) {
    return Builder(builder: (context) {
      return SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            // One gap everywhere: each card only draws itself.
            children: [
              HomeHeader(
                name: profile.name,
                bell: const NotificationBell(),
                onAvatar: () => _push(const ProfileScreen()),
              ),
              const SizedBox(height: 14),
              if (profile.isManager) ...[
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: false, label: Text('Own'), icon: Icon(Icons.person_rounded)),
                    ButtonSegment(value: true, label: Text('Team'), icon: Icon(Icons.groups_rounded)),
                  ],
                  selected: {_teamView},
                  onSelectionChanged: (v) => setState(() => _teamView = v.first),
                ),
                const SizedBox(height: 14),
              ],
              if (profile.isManager) ...[
                _approvalsButton(),
                const SizedBox(height: 14),
              ],
              if (profile.isManager && _teamView)
                const TeamDashboard()
              else if (_loading && _status == null)
                const Padding(
                    padding: EdgeInsets.all(40),
                    child: const LoadingView())
              else if (_error != null && _status == null)
                Card(child: ErrorView(message: _error!, onRetry: _load))
              else ...[
                for (final card in _cards(profile))
                  Padding(padding: const EdgeInsets.only(bottom: 12), child: card),
                const SyncStatusBar(),
              ],
            ],
          ),
        ),
      );
    });
  }

  /// The quick way to everything waiting for a decision, with how many there are.
  Widget _approvalsButton() => InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () async {
          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ApprovalsScreen()));
          _loadPending();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: _pending > 0 ? const [Color(0xFFEA580C), Color(0xFFF59E0B)] : const [Color(0xFF059669), Color(0xFF10B981)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: (_pending > 0 ? const Color(0xFFEA580C) : const Color(0xFF059669)).withValues(alpha: 0.28), blurRadius: 14, offset: const Offset(0, 6))],
          ),
          child: Row(children: [
            const Icon(Icons.fact_check_rounded, color: Colors.white, size: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Approvals', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16.5)),
                Text(_pending > 0 ? 'Handovers, access, expenses, leave and more' : 'Nothing waiting for you',
                    style: const TextStyle(color: Colors.white, fontSize: 12.5)),
              ]),
            ),
            Container(
              constraints: const BoxConstraints(minWidth: 36),
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
              child: Text(_pending > 0 ? '$_pending' : '0',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: _pending > 0 ? const Color(0xFFEA580C) : const Color(0xFF059669))),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded, color: Colors.white),
          ]),
        ),
      );

  /// The day in one card: where it stands, how it is going, and what moves it on.
  Widget _hero(Profile profile) {
    final punchedIn = _day?['punched_in'] == true;
    final current = _day?['current'] as Map<String, dynamic>?;
    final planned = ((_today?['clients'] as List?) ?? []).length;
    final punches = ((_day?['punch_count'] as num?) ?? 0).toInt();
    return CheckInHero(
      punchedIn: punchedIn,
      punchesToday: punches,
      firstCheckIn: fmtTime(((_day?['today'] as List?) ?? []).isEmpty
          ? null
          : (((_day!['today'] as List).first as Map)['check_in'])),
      lastCheckOut: fmtTime(_day?['last_check_out']),
      canResume: _day?['can_resume'] == true,
      since: fmtTime(current?['check_in']),
      worked: fmtHours(_day?['worked_hours_today'] as num?),
      target: planned,
      busy: _punching,
      onDutySince: DateTime.tryParse('${current?['check_in'] ?? ''}')?.toLocal(),
      workedHours: ((_day?['worked_hours_today'] as num?) ?? 0).toDouble(),
      // On a bike or car the meter decides; the phone's own track is the fallback.
      km: (_travel?['odometer_km'] as num?) ?? (_travel?['distance_km'] as num?) ?? 0,
      visits: _visits.length,
      // Time spent moving, counted by the server over the hours on duty.
      travelMinutes: ((_travel?['travel_minutes'] as num?) ?? 0).toInt(),
      onOpenDay: () => _push(const DayJourneyScreen()),
      routeLabel: profile.routeLabel,
      pending: _myPending,
      onPending: () async {
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyPendingScreen()));
        _loadMyPending();
      },
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
      second: rows.any((row) => row.containsKey('distributor'))
          ? [for (final row in rows) ((row['distributor'] as num?) ?? 0).toDouble()]
          : null,
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
      rows: _topRows ??
          (_topPeriod == _period
              ? ((_sales?['top_products'] as List?) ?? []).cast<Map<String, dynamic>>()
              : <Map<String, dynamic>>[]),
      period: _topPeriod,
      onPeriod: _reloadTop,
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

  /// A summary tile that opens today's customers already narrowed to what it counts.
  Widget _drill(String filter, Widget tile) => InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _push(BeatTodayScreen(filter: filter)),
        child: tile,
      );

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
                  child: _drill('all', SummaryTile(
                    icon: Icons.event_note_rounded,
                    colour: AppColors.primary,
                    value: planned,
                    label: 'Planned',
                    percent: planned == 0 ? 0 : 1,
                  )),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _drill('visited', SummaryTile(
                    icon: Icons.check_circle_rounded,
                    colour: AppColors.success,
                    value: visited,
                    label: 'Visited',
                    percent: share(visited),
                  )),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _drill('pending', SummaryTile(
                    icon: Icons.schedule_rounded,
                    colour: AppColors.warning,
                    value: pending,
                    label: 'Pending',
                    percent: share(pending),
                  )),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _drill('cancelled', SummaryTile(
                    icon: Icons.cancel_rounded,
                    colour: AppColors.danger,
                    value: cancelled,
                    label: 'Cancelled',
                    percent: share(cancelled),
                  )),
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
