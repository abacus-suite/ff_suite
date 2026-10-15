import 'package:flutter/material.dart';

import 'sales_cards.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/dashboard.dart';
import '../targets/targets_screen.dart';
import '../tasks/tasks_screen.dart';

/// This month's targets against what is done so far. Hidden until the office
/// sets a target (or when the Targets module is not installed).
class MonthTargetCard extends StatefulWidget {
  const MonthTargetCard({super.key});

  @override
  State<MonthTargetCard> createState() => _MonthTargetCardState();
}

class _MonthTargetCardState extends State<MonthTargetCard> {
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    Services.refresh.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    Services.refresh.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await Services.api.get('/api/v1/targets') as Map<String, dynamic>;
      if (mounted) setState(() => _data = data);
    } catch (_) {
      // No targets module or no target: the card simply stays away.
    }
  }

  static const _icons = {
    'visits': Icons.storefront_rounded,
    'customers': Icons.add_business_rounded,
    'sales': Icons.shopping_basket_rounded,
    'collections': Icons.payments_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final me = _data?['me'] as Map<String, dynamic>?;
    if (me == null) return const SizedBox.shrink();
    final metrics = ((me['metrics'] as List?) ?? []).cast<Map<String, dynamic>>();
    final achievement = (me['achievement'] as num?)?.toInt() ?? 0;
    final currency = _data?['currency'] as String?;
    final month = DateTime.tryParse('${_data?['month']}');
    const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September',
      'October', 'November', 'December'];
    String value(Map<String, dynamic> m, String key) =>
        m['money'] == true ? fmtMoney(m[key] as num?, currency) : fmtQty((m[key] as num?) ?? 0);
    return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CardHeader(
                icon: Icons.flag_rounded,
                title: 'My targets${month == null ? '' : ' · ${months[month.month - 1]}'}',
                trailing: InkWell(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TargetsScreen())),
                  child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: (achievement >= 100 ? AppColors.success : AppColors.primary).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('$achievement%',
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: achievement >= 100 ? AppColors.success : AppColors.primary)),
                ),
                ),
              ),
              const SizedBox(height: 10),
              for (final m in metrics) ...[
                Row(
                  children: [
                    Icon(_icons[m['key']] ?? Icons.flag_rounded, size: 18, color: AppColors.muted),
                    const SizedBox(width: 8),
                    Expanded(child: Text('${m['label']}', style: const TextStyle(fontWeight: FontWeight.w600))),
                    Text('${value(m, 'actual')} / ${value(m, 'target')}',
                        style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    minHeight: 7,
                    value: (((m['percent'] as num?) ?? 0) / 100).clamp(0.0, 1.0).toDouble(),
                    backgroundColor: AppColors.border,
                    color: ((m['percent'] as num?) ?? 0) >= 100 ? AppColors.success : AppColors.primary,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (me['incentive'] != null)
                Row(
                  children: [
                    const Icon(Icons.card_giftcard_rounded, size: 18, color: AppColors.success),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text('${(me['incentive'] as Map)['status'] ?? 'Incentive'}',
                            style: const TextStyle(color: AppColors.muted, fontSize: 12.5))),
                    Text(fmtMoney((me['incentive'] as Map)['earned'] as num?, currency),
                        style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.success)),
                  ],
                ),
            ],
          ),
        ),
    );
  }
}

/// Open tasks at a glance, with a way into the list.
class MyTasksCard extends StatefulWidget {
  const MyTasksCard({super.key});

  @override
  State<MyTasksCard> createState() => _MyTasksCardState();
}

class _MyTasksCardState extends State<MyTasksCard> {
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    Services.refresh.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    Services.refresh.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await Services.api.get('/api/v1/tasks', query: {'state': 'todo,in_progress'})
          as Map<String, dynamic>;
      if (mounted) setState(() => _data = data);
    } catch (_) {
      // Tasks module not installed.
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (data == null) return const SizedBox.shrink();
    final tasks = ((data['tasks'] as List?) ?? []).cast<Map<String, dynamic>>();
    final summary = (data['summary'] as Map?)?.cast<String, dynamic>() ?? const {};
    void openList() async {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TasksScreen()));
      _load();
    }

    return Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CardHead(
                icon: Icons.task_alt_rounded,
                title: 'My Tasks',
                subtitle: 'Stay on top of your work',
                tint: AppColors.success,
                trailing: TextButton(
                  onPressed: openList,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [Text('View All'), Icon(Icons.chevron_right_rounded, size: 18)],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              if (tasks.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppColors.success.withValues(alpha: 0.12),
                        AppColors.success.withValues(alpha: 0.03),
                      ],
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const Icon(Icons.checklist_rounded, color: AppColors.success, size: 27),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Nothing open.',
                                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                            SizedBox(height: 2),
                            Text('Nice! You are all caught up.',
                                style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
                          ],
                        ),
                      ),
                    ],
                  ),
                )
              else ...[
                if ((summary['overdue'] ?? 0) > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('${summary['overdue']} overdue',
                        style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700)),
                  ),
                for (final task in tasks.take(3))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: Icon(Icons.circle, size: 12, color: taskStateColour(task)),
                    title: Text('${task['name']}', maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text([
                      if ((task['customer'] as Map?)?['name'] != null) (task['customer'] as Map)['name'],
                      if (task['due'] != null) 'Due ${task['due']}',
                    ].join(' · ')),
                    trailing: Text(taskStateWord(task),
                        style: TextStyle(color: taskStateColour(task), fontSize: 12, fontWeight: FontWeight.w700)),
                    onTap: () async {
                      await Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => TaskDetailScreen(task: task, canAct: true)));
                      _load();
                    },
                  ),
              ],
            ],
          ),
        ),
    );
  }
}
