import 'package:flutter/material.dart';

import '../../core/services.dart';
import '../../core/theme.dart';
import '../approvals/approvals_screen.dart';
import '../attendance/month_screen.dart';
import '../attendance/regularisation_screen.dart';
import '../allowance/allowance_screen.dart';
import '../beat/beat_today_screen.dart';
import '../collections/collections_screen.dart';
import '../collections/deposits_receive_screen.dart';
import '../clients/add_client_screen.dart';
import '../expenses/expenses_screen.dart';
import '../leaves/leaves_screen.dart';
import '../notifications/notifications_screen.dart';
import '../reports/reports_screen.dart';
import '../forms/forms_screen.dart';
import '../chat/chat_screen.dart';
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
    final menu = <(IconData, String, Color, Widget)>[
      (Icons.bar_chart_rounded, 'Reports', AppColors.primary, const ReportsScreen()),
      if (profile.isManager) (Icons.account_tree_rounded, 'Team', AppColors.purple, const TeamTreeScreen()),
      (Icons.task_alt_rounded, 'Tasks', AppColors.success, const TasksScreen()),
      (Icons.forum_rounded, 'Chat', AppColors.primary, const ChatListScreen()),
      (Icons.account_balance_wallet_rounded, 'Receivables', AppColors.danger, const ReceivablesScreen()),
      if (profile.feature('routes')) ...[
        (Icons.calendar_month_rounded, 'My ${profile.routeLabel} Plan', AppColors.primary, const BeatTodayScreen()),
        (Icons.edit_calendar_rounded, 'Create Beat Plan', AppColors.sky, const PlanBeatScreen()),
        (Icons.event_note_rounded, 'Planned Days', AppColors.primary, PlannedDaysScreen(start: DateUtils.dateOnly(DateTime.now()))),
      ],
      if (profile.feature('visits'))
        (Icons.add_business_rounded, 'Add ${profile.label('client', 'Customer')}', AppColors.teal, const AddClientScreen()),
      if (profile.feature('attendance')) ...[
        (Icons.event_available_rounded, 'My Attendance', AppColors.success, const MonthScreen()),
        (Icons.edit_calendar_rounded, 'Attendance Correction', AppColors.sky, const RegularisationScreen()),
      ],
      if (profile.feature('forms')) (Icons.assignment_rounded, 'Forms', AppColors.purple, const FormsScreen()),
      (Icons.receipt_rounded, 'My Expenses', AppColors.warning, const ExpensesScreen()),
      (Icons.beach_access_rounded, 'My Time Off', AppColors.sky, const LeavesScreen()),
      (Icons.notifications_none_rounded, 'Notifications', AppColors.primary, const NotificationsScreen()),
      if (profile.feature('allowance'))
        (Icons.local_gas_station_rounded, 'Travel Allowance', AppColors.purple, const AllowanceScreen()),
      if (profile.paymentCollection)
        (Icons.payments_rounded, 'Collections', AppColors.teal, const CollectionsScreen()),
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
