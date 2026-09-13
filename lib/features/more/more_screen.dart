import 'package:flutter/material.dart';

import '../../core/services.dart';
import '../../core/theme.dart';
import '../approvals/approvals_screen.dart';
import '../attendance/month_screen.dart';
import '../attendance/regularisation_screen.dart';
import '../allowance/allowance_screen.dart';
import '../beat/beat_today_screen.dart';
import '../beat/plan_day_screen.dart';
import '../collections/collections_screen.dart';
import '../collections/deposits_receive_screen.dart';
import '../clients/add_client_screen.dart';
import '../expenses/expenses_screen.dart';
import '../leaves/leaves_screen.dart';
import '../notifications/notifications_screen.dart';
import '../reports/reports_screen.dart';
import '../forms/forms_screen.dart';
import 'profile_screen.dart';

/// Every screen that is not a main tab, as a menu. Profile details and
/// logging out live on the profile screen (the avatar on Home).
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final profile = Services.auth.profile!;
    void open(Widget screen) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    final menu = <(IconData, String, Color, Widget)>[
      (Icons.bar_chart_rounded, 'Reports', AixoloColors.primary, const ReportsScreen()),
      if (profile.feature('routes')) ...[
        (Icons.calendar_month_rounded, 'My ${profile.routeLabel} Plan', AixoloColors.primary, const BeatTodayScreen()),
        (Icons.edit_calendar_rounded, 'Plan a ${profile.routeLabel} Day', AixoloColors.sky, const PlanDayScreen()),
      ],
      if (profile.feature('visits'))
        (Icons.add_business_rounded, 'Add ${profile.label('client', 'Customer')}', AixoloColors.teal, const AddClientScreen()),
      if (profile.feature('attendance')) ...[
        (Icons.event_available_rounded, 'My Attendance', AixoloColors.success, const MonthScreen()),
        (Icons.edit_calendar_rounded, 'Attendance Correction', AixoloColors.sky, const RegularisationScreen()),
      ],
      if (profile.feature('forms')) (Icons.assignment_rounded, 'Forms', AixoloColors.purple, const FormsScreen()),
      (Icons.receipt_rounded, 'My Expenses', AixoloColors.warning, const ExpensesScreen()),
      (Icons.beach_access_rounded, 'My Time Off', AixoloColors.sky, const LeavesScreen()),
      (Icons.notifications_none_rounded, 'Notifications', AixoloColors.primary, const NotificationsScreen()),
      if (profile.feature('allowance'))
        (Icons.local_gas_station_rounded, 'Travel Allowance', AixoloColors.purple, const AllowanceScreen()),
      if (profile.paymentCollection)
        (Icons.payments_rounded, 'Collections', AixoloColors.teal, const CollectionsScreen()),
      if (profile.isManager) ...[
        (Icons.fact_check_rounded, 'Approvals', AixoloColors.warning, const ApprovalsScreen()),
        if (profile.paymentCollection)
          (Icons.account_balance_rounded, 'Money To Receive', AixoloColors.success, const DepositsReceiveScreen()),
      ],
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('More'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            tooltip: 'My profile',
            icon: CircleAvatar(
              radius: 16,
              backgroundColor: AixoloColors.primary,
              child: Text(profile.name.isNotEmpty ? profile.name[0].toUpperCase() : '?',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
            ),
            onPressed: () => open(const ProfileScreen()),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
        children: [
          for (final entry in menu)
            Card(
              child: ListTile(
                leading: CircleAvatar(
                  radius: 18,
                  backgroundColor: entry.$3.withValues(alpha: 0.12),
                  child: Icon(entry.$1, color: entry.$3, size: 20),
                ),
                title: Text(entry.$2, style: const TextStyle(fontWeight: FontWeight.w600)),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => open(entry.$4),
              ),
            ),
        ],
      ),
    );
  }
}
