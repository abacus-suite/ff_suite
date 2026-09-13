import 'package:flutter/material.dart';

import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../team/team_live_screen.dart';
import '../team/timeline_screen.dart';
import '../receivables/receivables_screen.dart';
import '../targets/targets_screen.dart';
import 'report_view_screen.dart';

/// Icons for the report keys the server sends (Material names, as strings).
const _icons = <String, IconData>{
  'fingerprint': Icons.fingerprint_rounded,
  'storefront': Icons.storefront_rounded,
  'shopping_basket': Icons.shopping_basket_rounded,
  'shopping_cart': Icons.shopping_cart_rounded,
  'payments': Icons.payments_rounded,
  'receipt': Icons.receipt_long_rounded,
  'local_gas_station': Icons.local_gas_station_rounded,
  'beach_access': Icons.beach_access_rounded,
  'route': Icons.route_rounded,
  'add_business': Icons.add_business_rounded,
  'flag': Icons.flag_rounded,
  'task_alt': Icons.task_alt_rounded,
  'assignment_return': Icons.assignment_return_rounded,
  'leaderboard': Icons.leaderboard_rounded,
  'account_balance_wallet': Icons.account_balance_wallet_rounded,
  'inventory_2': Icons.inventory_2_rounded,
  'star': Icons.star_rounded,
  'groups': Icons.groups_rounded,
  'emoji_events': Icons.emoji_events_rounded,
  'sort': Icons.sort_rounded,
  'receipt_long': Icons.receipt_long_rounded,
  'alt_route': Icons.alt_route_rounded,
  'redeem': Icons.redeem_rounded,
  'summarize': Icons.summarize_rounded,
  'calendar_month': Icons.calendar_month_rounded,
};

const _tones = [
  AixoloColors.primary,
  AixoloColors.success,
  AixoloColors.purple,
  AixoloColors.teal,
  AixoloColors.warning,
  AixoloColors.danger,
  AixoloColors.sky,
];

/// Every report in one place. Managers also get their team's live map and
/// day timelines here, and can switch any report to a team member.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  Map<String, dynamic>? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final data = await Services.api.get('/api/v1/reports') as Map<String, dynamic>;
      if (mounted) setState(() => _data = data);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  void _open(Widget screen) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  Future<void> _pickTimeline(List<Map<String, dynamic>> members) async {
    final member = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (context, controller) => ListView(
          controller: controller,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Whose day?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ),
            for (final m in members)
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFFE8EFFF),
                  child: Text('${m['name']}'.isNotEmpty ? '${m['name']}'[0].toUpperCase() : '?',
                      style: const TextStyle(color: AixoloColors.primary, fontWeight: FontWeight.w800)),
                ),
                title: Text('${m['name']}'),
                subtitle: m['code'] == null ? null : Text('${m['code']}'),
                onTap: () => Navigator.pop(sheet, m),
              ),
          ],
        ),
      ),
    );
    if (member == null) return;
    _open(TimelineScreen(employeeId: member['id'] as int, employeeName: '${member['name']}'));
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final reports = ((data?['reports'] as List?) ?? []).cast<Map<String, dynamic>>();
    final members = ((data?['members'] as List?) ?? []).cast<Map<String, dynamic>>();
    final canTeam = data?['can_team'] == true;
    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            if (_error != null) Card(child: ErrorView(message: _error!, onRetry: _load)),
            if (data == null && _error == null)
              const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
            if (canTeam) ...[
              const _Section('My team'),
              Row(
                children: [
                  Expanded(
                    child: _TeamTile(
                      icon: Icons.map_rounded,
                      title: 'Live map',
                      subtitle: 'Where everyone is now',
                      colour: AixoloColors.primary,
                      onTap: () => _open(const TeamLiveScreen()),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _TeamTile(
                      icon: Icons.timeline_rounded,
                      title: 'Timeline',
                      subtitle: 'Replay anyone\'s day',
                      colour: AixoloColors.purple,
                      onTap: () => _pickTimeline(members),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            Card(
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFFFF4D6),
                  child: Icon(Icons.emoji_events_rounded, color: Color(0xFFF5B301)),
                ),
                title: const Text('Leaderboard & targets', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(canTeam ? 'Top performers · split your targets' : 'Where you stand this month'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _open(const TargetsScreen()),
              ),
            ),
            Card(
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFFDECEC),
                  child: Icon(Icons.account_balance_wallet_rounded, color: AixoloColors.danger),
                ),
                title: const Text('Receivables & statements', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('Invoices due and overdue, ageing, customer SOA'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _open(const ReceivablesScreen()),
              ),
            ),
            if (reports.isNotEmpty) _Section(canTeam ? 'Reports · me or my team' : 'My reports'),
            for (var i = 0; i < reports.length; i++)
              Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  leading: CircleAvatar(
                    radius: 22,
                    backgroundColor: _tones[i % _tones.length].withValues(alpha: 0.12),
                    child: Icon(_icons[reports[i]['icon']] ?? Icons.insert_chart_rounded,
                        color: _tones[i % _tones.length]),
                  ),
                  title: Text('${reports[i]['title']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('${reports[i]['description']}'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _open(ReportViewScreen(
                    report: reports[i],
                    members: members,
                    canTeam: canTeam,
                  )),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
      child: Text(title.toUpperCase(),
          style: const TextStyle(fontSize: 12, letterSpacing: 1.1, fontWeight: FontWeight.w800, color: AixoloColors.muted)),
    );
  }
}

class _TeamTile extends StatelessWidget {
  const _TeamTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.colour,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color colour;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colour.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(backgroundColor: colour, child: Icon(icon, color: Colors.white)),
              const SizedBox(height: 10),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              Text(subtitle, style: const TextStyle(color: AixoloColors.muted, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
