import 'package:field_force_app/core/format.dart';
import 'package:field_force_app/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fmtHours formats hours and minutes', () {
    expect(fmtHours(7.5), '7h 30m');
    expect(fmtHours(null), '0h 00m');
  });

  test('fmtDate pads month and day', () {
    expect(fmtDate(DateTime(2026, 1, 5)), '2026-01-05');
  });

  test('Profile knows whether orders are demands in this company', () {
    Map<String, dynamic> payload(String flow) => {
          'employee': {'id': 1, 'name': 'Officer'},
          'roles': {'scope': 'own'},
          'settings': {'order_flow': flow},
        };

    final direct = Profile.fromJson(payload('direct'));
    expect(direct.isDemandFlow, isFalse);
    expect(direct.orderWord, 'Order');

    final demand = Profile.fromJson(payload('demand'));
    expect(demand.isDemandFlow, isTrue);
    expect(demand.orderWord, 'Demand');
  });

  test('Profile parses the /api/v1/me payload', () {
    final profile = Profile.fromJson({
      'employee': {
        'id': 7,
        'name': 'Ravi',
        'code': 'KF@S008',
        'team': {'id': 1, 'name': 'North Kerala'},
        'manager': null,
        'designation': null,
        'tracking_enabled': true,
      },
      'roles': {'is_manager': true, 'is_admin': false},
      'shift': {'id': 1, 'name': 'General'},
      'settings': {
        'ping_interval': 120,
        'distance_filter': 50,
        'low_battery': 20,
        'selfie_required': true,
        'allow_mock': false,
      },
    });
    expect(profile.employeeId, 7);
    expect(profile.team, 'North Kerala');
    expect(profile.isManager, isTrue);
    expect(profile.selfieRequired, isTrue);
    expect(profile.shiftName, 'General');
  });
}
