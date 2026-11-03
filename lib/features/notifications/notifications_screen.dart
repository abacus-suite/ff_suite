import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../allowance/allowance_screen.dart';
import '../approvals/approvals_screen.dart';
import '../attendance/overtime_screen.dart';
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

  /// Notifications removed with ×, kept on the phone: the server has no way to delete one.
  Set<int> _removed = {};

  static String get _removedKey => 'removed_notifications_${Services.auth.profile?.employeeId ?? 0}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<Set<int>> _readRemoved() async {
    try {
      final raw = await Services.storage.read(_removedKey);
      return raw == null ? {} : (jsonDecode(raw) as List).whereType<int>().toSet();
    } catch (_) {
      return {};
    }
  }

  /// × on a seen notification: it leaves the list for good on this phone.
  Future<void> _remove(Map<String, dynamic> row) async {
    final id = row['id'];
    if (id is! int) return;
    setState(() {
      _removed.add(id);
      _rows.removeWhere((r) => r['id'] == id);
    });
    // The newest 500 are plenty: older ones have long left the server's list.
    final keep = _removed.toList()..sort();
    await Services.storage.write(_removedKey, jsonEncode(keep.length > 500 ? keep.sublist(keep.length - 500) : keep));
    // Removed on the server too, where it can: it is then gone from every phone. Hidden here either way.
    try {
      await Services.notifications.remove(ids: [id]);
    } catch (_) {
      // An older server has no call for it: the notice stays hidden on this phone.
    }
    if (mounted) showSnack(context, 'Notification removed.');
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final rows = await Services.notifications.list();
      _removed = await _readRemoved();
      if (!mounted) return;
      setState(() {
        _rows = rows.where((r) => !_removed.contains(r['id'])).toList();
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
    // Sent by a distributor: that wins over what the text happens to mention (an order, a delivery).
    if (model.contains('distributor') || row['from_distributor'] == true) return 'distributor';
    if (model.contains('leave') || text.contains('leave')) return 'leave';
    if (model.contains('demand') || text.contains('demand')) return 'demand';
    if (model.contains('sale') || text.contains('order')) return 'order';
    if (text.contains('distributor') || text.contains('delivery')) return 'distributor';
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

  /// A notification: unread ones carry a blue dot; a seen one is greyed and can be removed with ×.
  Widget _tile(Map<String, dynamic> row) {
    final topic = _topic(row);
    final unread = row['read'] != true;
    return Container(
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
          padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
          child: Row(children: [
            Stack(clipBehavior: Clip.none, children: [
              _badge(topic),
              if (unread)
                Positioned(
                  right: -1,
                  top: -1,
                  child: Container(
                    width: 11,
                    height: 11,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
            ]),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${row['title']}',
                    style: TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 14.5, color: unread ? AppColors.text : AppColors.muted)),
                if (asText(row['body']) != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(asText(row['body'])!,
                        maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
                  ),
              ]),
            ),
            if (row['id'] is int)
              IconButton(
                tooltip: 'Remove',
                onPressed: () => _remove(row),
                icon: const Icon(Icons.close_rounded, color: AppColors.muted),
              ),
          ]),
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
      'ff.overtime' => 'overtime',
      'ff.expense.request' => 'requests',
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
    if (text.contains('overtime')) return const ApprovalsScreen(start: 'overtime');
    if (text.contains('payment request')) return const ApprovalsScreen(start: 'requests');
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
    'ff.overtime' => const OvertimeScreen(),
    'ff.demand' || 'sale.order' => const OrdersScreen(),
    'ff.regularisation' => const RegularisationScreen(),
    'ff.beat.app' || 'ff.beat' => const PlanBeatScreen(),
    'res.partner' => const ClientsScreen(),
    'ff.task' => const TasksScreen(),
    _ => switch (true) {
        _ when text.contains('expense') => const ExpensesScreen(),
        _ when text.contains('leave') => const LeavesScreen(),
        _ when text.contains('overtime') => const OvertimeScreen(),
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
