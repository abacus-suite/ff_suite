class IdName {
  const IdName(this.id, this.name);

  final int id;
  final String name;

  static IdName? from(dynamic json) => json is Map ? IdName(json['id'] as int, '${json['name']}') : null;
}

/// Logged-in user profile returned by /api/v1/me and /auth/login.
class Profile {
  Profile({
    required this.employeeId,
    required this.name,
    required this.isManager,
    required this.isAdmin,
    required this.pingInterval,
    required this.distanceFilter,
    required this.lowBattery,
    required this.selfieRequired,
    this.earlyCheckoutReason = false,
    this.punchVehicle = false,
    this.punchOdometer = false,
    required this.allowMock,
    required this.trackingEnabled,
    required this.visitLock,
    required this.visitSteps,
    required this.stockCount,
    this.visitRecommendations = false,
    required this.paymentCollection,
    this.googleMapsKey = '',
    this.mapProvider = 'open',
    this.orderFlow = 'direct',
    this.photoVersion,
    this.idleLogoutHours = 0,
    this.code,
    this.team,
    this.manager,
    this.designation,
    this.shiftName,
    this.scope = 'own',
    this.routeLabel = 'Beat',
    this.routes = const [],
    this.features = const {},
    this.labels = const {},
  });

  final int employeeId;
  final String name;
  final String? code;
  final String? team;
  final String? manager;
  final String? designation;
  final String? shiftName;
  final bool isManager;
  final bool isAdmin;
  final String scope;
  final int pingInterval;
  final int distanceFilter;
  final int lowBattery;
  final bool selfieRequired;

  /// Somebody leaving before the shift ends must say why.
  final bool earlyCheckoutReason;

  /// Ask how the person travels today when they check in.
  final bool punchVehicle;

  /// Ask for a photo of the odometer and its reading at both punches.
  final bool punchOdometer;
  final bool allowMock;
  final bool trackingEnabled;
  final bool visitLock;
  final bool visitSteps;
  final bool stockCount;

  /// Office setting: show the "Visit next" suggestions on Home.
  final bool visitRecommendations;
  final bool paymentCollection;

  /// Key set in Odoo settings; empty means the app uses the free basemap.
  final String googleMapsKey;

  /// 'google' (paid tiles, needs the key) or 'open' (free CARTO / OpenStreetMap tiles).
  final String mapProvider;

  /// 'direct' books a sale order at the outlet; 'demand' collects demand for
  /// the office to consolidate into distributor quotations.
  final String orderFlow;

  /// Changes when the profile photo does; null when there is none.
  final String? photoVersion;

  /// Log the app out after this many hours unused (0 = never).
  final int idleLogoutHours;

  bool get isDemandFlow => orderFlow == 'demand';

  /// What an order is called in this company.
  String get orderWord => isDemandFlow ? 'Demand' : 'Order';
  final String routeLabel;
  final List<IdName> routes;
  final Map<String, bool> features;
  final Map<String, String> labels;

  /// Feature switched on for this employee's department (default: on).
  bool feature(String name) => features[name] ?? true;

  /// Department wording, e.g. label('client', 'Client') -> "Doctor".
  String label(String key, String fallback) {
    final value = labels[key];
    return value == null || value.isEmpty ? fallback : value;
  }

  static String? _name(dynamic ref) => ref is Map ? ref['name'] as String? : null;

  factory Profile.fromJson(Map<String, dynamic> json) {
    final employee = json['employee'] as Map<String, dynamic>;
    final roles = json['roles'] as Map<String, dynamic>;
    final settings = json['settings'] as Map<String, dynamic>;
    final shift = json['shift'] as Map<String, dynamic>?;
    final app = json['app'] as Map<String, dynamic>?;
    return Profile(
      employeeId: employee['id'] as int,
      name: employee['name'] as String,
      code: employee['code'] as String?,
      team: _name(employee['team']),
      manager: _name(employee['manager']),
      designation: _name(employee['designation']),
      shiftName: shift?['name'] as String?,
      isManager: roles['is_manager'] == true,
      isAdmin: roles['is_admin'] == true,
      scope: roles['scope'] as String? ?? 'own',
      pingInterval: (settings['ping_interval'] as num? ?? 120).toInt(),
      distanceFilter: (settings['distance_filter'] as num? ?? 50).toInt(),
      lowBattery: (settings['low_battery'] as num? ?? 20).toInt(),
      selfieRequired: settings['selfie_required'] == true,
      earlyCheckoutReason: settings['early_checkout_reason'] == true,
      punchVehicle: settings['punch_vehicle'] == true,
      punchOdometer: settings['punch_odometer'] == true,
      allowMock: settings['allow_mock'] == true,
      trackingEnabled: employee['tracking_enabled'] != false,
      visitLock: settings['visit_lock'] == true,
      visitSteps: settings['visit_steps'] == true,
      stockCount: settings['stock_count'] == true,
      visitRecommendations: settings['visit_recommendations'] == true,
      paymentCollection: settings['payment_collection'] == true,
      googleMapsKey: '${settings['google_maps_key'] ?? ''}',
      mapProvider: '${settings['map_provider'] ?? ((settings['google_maps_key'] ?? '') != '' ? 'google' : 'open')}',
      orderFlow: '${settings['order_flow'] ?? 'direct'}',
      photoVersion: employee['photo_version'] as String?,
      idleLogoutHours: (settings['idle_logout_hours'] as num? ?? 0).toInt(),
      routeLabel: employee['route_label'] as String? ?? 'Beat',
      routes: ((employee['routes'] as List?) ?? []).map(IdName.from).whereType<IdName>().toList(),
      features: ((app?['features'] as Map?) ?? {}).map((k, v) => MapEntry('$k', v == true)),
      labels: ((app?['labels'] as Map?) ?? {}).map((k, v) => MapEntry('$k', '${v ?? ''}')),
    );
  }
}
