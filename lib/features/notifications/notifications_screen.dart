import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../allowance/allowance_screen.dart';
import '../approvals/approvals_screen.dart';
import '../attendance/regularisation_screen.dart';
import '../beat/plan_beat_screen.dart';
import '../clients/clients_screen.dart';
import '../expenses/expenses_screen.dart';
import '../leaves/leaves_screen.dart';
import '../orders/orders_screen.dart';
import '../tasks/tasks_screen.dart';
import '../../widgets/skeleton.dart';

/// The bell, with however many are unread.
class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key, this.colour = AppColors.text});

  final Color colour;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: Services.notifications.unread,
      builder: (context, unread, _) => Stack(
        clipBehavior: Clip.none,
        children: [
          IconButton(
            tooltip: 'Notifications',
            icon: Icon(Icons.notifications_none_rounded, color: colour),
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const NotificationsScreen())),
          ),
          if (unread > 0)
            Positioned(
              right: 4,
              top: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                constraints: const BoxConstraints(minWidth: 18),
                decoration: BoxDecoration(
                  color: AppColors.danger,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: Text(
                  unread > 99 ? '99+' : '$unread',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// What the office has told me, newest first.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final rows = await Services.notifications.list();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
      // Seeing the list is reading it: the bell's count goes back to zero.
      if (rows.any((r) => r['read'] != true)) unawaited(Services.notifications.markRead());
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  /// Open whatever the notification is about.
  Future<void> _open(Map<String, dynamic> row) async {
    if (row['read'] != true && row['id'] != null) {
      await Services.notifications.markRead(ids: [row['id'] as int]);
    }
    if (!mounted) return;
    final screen = resolveNotificationScreen(row);
    if (screen == null) {
      await _load();
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    if (mounted) await _load();
  }

  /// What a notification is about, from the record it came from: a task, a leave, a distributor, or anything else.
  String _topic(Map<String, dynamic> row) {
    final model = '${row['model'] ?? ''}'.toLowerCase();
    final text = '${row['title'] ?? ''} ${row['body'] ?? ''}'.toLowerCase();
    if (model.contains('leave') || text.contains('leave')) return 'leave';
    if (model.contains('demand') || text.contains('demand')) return 'demand';
    if (model.contains('sale') || text.contains('order')) return 'order';
    if (model.contains('distributor') || text.contains('distributor') || text.contains('delivery')) return 'distributor';
    if (model.contains('task') || text.contains('task')) return 'task';
    return switch ('${row['kind']}') {
      'approval' => 'approval',
      'decision' => 'decision',
      _ => 'info',
    };
  }

  IconData _icon(String topic) => switch (topic) {
        'task' => Icons.assignment_turned_in_rounded,
        'leave' => Icons.beach_access_rounded,
        'demand' => Icons.inventory_2_rounded,
        'order' => Icons.shopping_bag_rounded,
        'distributor' => Icons.local_shipping_rounded,
        'approval' => Icons.how_to_reg_rounded,
        'decision' => Icons.task_alt_rounded,
        _ => Icons.notifications_rounded,
      };

  Color _colour(String topic) => switch (topic) {
        'task' => const Color(0xFF16A34A),
        'leave' => const Color(0xFF2563EB),
        'demand' => const Color(0xFF0F766E),
        'order' => const Color(0xFF7C3AED),
        'distributor' => const Color(0xFFEA8A00),
        'approval' => AppColors.warning,
        'decision' => AppColors.success,
        _ => AppColors.primary,
      };

  /// The round icon of a notification: white on solid green for a task, a coloured icon on a pale disc for the rest.
  Widget _badge(String topic) {
    final colour = _colour(topic);
    final solid = topic == 'task';
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: solid ? colour : colour.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(solid ? 12 : 22),
      ),
      child: Icon(_icon(topic), color: solid ? Colors.white : colour, size: 23),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          if (_rows.isNotEmpty)
            TextButton(
              onPressed: () async {
                await Services.notifications.remove();
                await _load();
              },
              child: const Text('Clear all'),
            ),
        ],
      ),
      body: _loading
          ? const LoadingView()
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  if (_error != null) ErrorView(message: _error!, onRetry: _load),
                  if (_rows.isEmpty && _error == null)
                    const EmptyView(icon: Icons.notifications_off_rounded, text: 'Nothing to read'),
                  for (final row in _rows) _tile(row),
                ],
              ),
            ),
    );
  }

  Widget _tile(Map<String, dynamic> row) {
    final topic = _topic(row);
    return Dismissible(
      key: ValueKey('n${row['id']}'),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom: 10),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(color: AppColors.danger, borderRadius: BorderRadius.circular(16)),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
      ),
      onDismissed: (_) {
        setState(() => _rows.remove(row));
        if (row['id'] != null) unawaited(Services.notifications.remove(ids: [row['id'] as int]));
      },
      child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _open(row),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(children: [
            _badge(topic),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${row['title']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                if (asText(row['body']) != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(asText(row['body'])!,
                        maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
                  ),
              ]),
            ),
          ]),
        ),
      ),
    ),
    );
  }
}

/// Route to the appropriate screen for a notification or push payload.
Widget? resolveNotificationScreen(Map<String, dynamic> row) {
  final model = asText(row['model']);
  final kind = asText(row['kind']);
  final approval = kind == 'approval';
  final text = '${row['title'] ?? ''} ${row['body'] ?? ''}'.toLowerCase();

  if (approval) {
    final startTab = switch (model) {
      'ff.expense.claim' => 'expenses',
      'hr.leave' => 'leaves',
      'ff.allowance.claim' => 'allowances',
      'ff.da.claim' || 'ff.da' => 'da',
      'ff.regularisation' => 'regularisation',
      'ff.beat.app' || 'ff.beat' => 'beats',
      'res.partner' => 'contacts',
      'ff.cash.handover' => 'handovers',
      'ff.office.deposit' => 'deposits',
      'ff.distributor.note' => 'notes',
      'stock.picking' || 'ff.return' => 'returns',
      'ff.partner.access' => 'access',
      _ => null,
    };
    if (startTab != null) {
      return ApprovalsScreen(start: startTab);
    }
    if (text.contains('expense')) return const ApprovalsScreen(start: 'expenses');
    if (text.contains('leave')) return const ApprovalsScreen(start: 'leaves');
    if (text.contains('allowance') || text.contains(' ta')) return const ApprovalsScreen(start: 'allowances');
    if (text.contains(' da') || text.contains('daily')) return const ApprovalsScreen(start: 'da');
    if (text.contains('regularis') || text.contains('punch') || text.contains('attendance')) {
      return const ApprovalsScreen(start: 'regularisation');
    }
    if (text.contains('beat')) return const ApprovalsScreen(start: 'beats');
    if (text.contains('outlet') || text.contains('client') || text.contains('contact')) {
      return const ApprovalsScreen(start: 'contacts');
    }
    if (text.contains('return')) return const ApprovalsScreen(start: 'returns');
    if (text.contains('handover')) return const ApprovalsScreen(start: 'handovers');
    if (text.contains('deposit')) return const ApprovalsScreen(start: 'deposits');
    if (text.contains('note')) return const ApprovalsScreen(start: 'notes');
    return const ApprovalsScreen();
  }

  return switch (model) {
    'ff.expense.claim' => const ExpensesScreen(),
    'ff.allowance.claim' || 'ff.da.claim' || 'ff.da' => const AllowanceScreen(),
    'hr.leave' => const LeavesScreen(),
    'ff.demand' || 'sale.order' => const OrdersScreen(),
    'ff.regularisation' => const RegularisationScreen(),
    'ff.beat.app' || 'ff.beat' => const PlanBeatScreen(),
    'res.partner' => const ClientsScreen(),
    'ff.task' => const TasksScreen(),
    _ => switch (true) {
        _ when text.contains('expense') => const ExpensesScreen(),
        _ when text.contains('leave') => const LeavesScreen(),
        _ when text.contains('allowance') || text.contains(' ta') || text.contains(' da') => const AllowanceScreen(),
        _ when text.contains('order') || text.contains('demand') => const OrdersScreen(),
        _ when text.contains('regularis') || text.contains('attendance') => const RegularisationScreen(),
        _ when text.contains('beat') => const PlanBeatScreen(),
        _ when text.contains('outlet') || text.contains('client') || text.contains('contact') => const ClientsScreen(),
        _ when text.contains('task') => const TasksScreen(),
        _ => null,
      },
  };
}
