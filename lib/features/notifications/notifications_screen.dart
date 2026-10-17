import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../allowance/allowance_screen.dart';
import '../approvals/approvals_screen.dart';
import '../expenses/expenses_screen.dart';
import '../leaves/leaves_screen.dart';
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
    if (row['read'] != true) {
      await Services.notifications.markRead(ids: [row['id'] as int]);
    }
    if (!mounted) return;
    final model = asText(row['model']);
    final approval = row['kind'] == 'approval';
    final screen = approval
        ? const ApprovalsScreen()
        : switch (model) {
            'ff.expense.claim' => const ExpensesScreen(),
            'ff.allowance.claim' => const AllowanceScreen(),
            'hr.leave' => const LeavesScreen(),
            _ => null,
          };
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
    if (model.contains('distributor') || text.contains('distributor')) return 'distributor';
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
        'distributor' => Icons.local_shipping_rounded,
        'approval' => Icons.how_to_reg_rounded,
        'decision' => Icons.task_alt_rounded,
        _ => Icons.notifications_rounded,
      };

  Color _colour(String topic) => switch (topic) {
        'task' => const Color(0xFF16A34A),
        'leave' => const Color(0xFF2563EB),
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

  Widget _tile(Map<String, dynamic> row) {
    final topic = _topic(row);
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
    );
  }
}
