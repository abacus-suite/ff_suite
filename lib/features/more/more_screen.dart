import 'package:flutter/material.dart';
import '../events/events_screen.dart';

import '../../core/services.dart';
import '../../core/theme.dart';
import '../approvals/approvals_screen.dart';
import '../attendance/month_screen.dart';
import '../attendance/regularisation_screen.dart';
import '../allowance/allowance_screen.dart';
import '../beat/beat_today_screen.dart';
import '../beat/my_beat_plan_screen.dart';
import 'contact_access_screen.dart';
import 'my_samples_screen.dart';
import '../collections/collections_screen.dart';
import '../collections/deposits_receive_screen.dart';
import '../expenses/expenses_screen.dart';
import '../leaves/leaves_screen.dart';
import '../notifications/notifications_screen.dart';
import '../reports/reports_screen.dart';
import '../forms/forms_screen.dart';
import '../receivables/receivables_screen.dart';
import '../tasks/tasks_screen.dart';
import 'profile_screen.dart';
import '../beat/plan_beat_screen.dart';
import '../team/team_tree_screen.dart';

/// Every screen that is not a main tab, as a menu. Profile details and
/// logging out live on the profile screen (the avatar on Home).
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final profile = Services.auth.profile!;
    void open(Widget screen) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    // The order and names the client asked for. Planned Days, Forms, Notifications and Chat are gone.
    final menu = <(IconData, String, Color, Widget)>[
      (Icons.bar_chart_rounded, 'Reports', AppColors.primary, const ReportsScreen()),
      (Icons.task_alt_rounded, 'My Tasks', AppColors.success, const TasksScreen()),
      if (profile.feature('routes'))
        (Icons.calendar_month_rounded, 'My ${profile.routeLabel} Plan', AppColors.primary, const MyBeatPlanScreen()),
      (Icons.account_balance_wallet_rounded, 'Receivables', AppColors.danger, const ReceivablesScreen()),
      if (profile.paymentCollection)
        (Icons.payments_rounded, 'My Collection', AppColors.teal, const CollectionsScreen()),
      (Icons.receipt_rounded, 'My Expense', AppColors.warning, const ExpensesScreen()),
      (Icons.science_rounded, 'My Samples', AppColors.teal, const MySamplesScreen()),
      (Icons.celebration_rounded, 'My Events', AppColors.purple, const EventsScreen()),
      if (profile.feature('attendance'))
        (Icons.event_available_rounded, 'My Attendance', AppColors.success, const MonthScreen()),
      (Icons.lock_open_rounded, 'Contact Access', AppColors.sky, const ContactAccessScreen()),
      if (profile.isManager) ...[
        (Icons.fact_check_rounded, 'Approvals', AppColors.warning, const ApprovalsScreen()),
        if (profile.paymentCollection)
          (Icons.account_balance_rounded, 'Money To Receive', AppColors.success, const DepositsReceiveScreen()),
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
              backgroundColor: AppColors.primary,
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
