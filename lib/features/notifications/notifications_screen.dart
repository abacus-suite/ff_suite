import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../allowance/allowance_screen.dart';
import '../approvals/approvals_screen.dart';
import '../expenses/expenses_screen.dart';
import '../leaves/leaves_screen.dart';

/// The bell, with however many are unread.
class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key, this.colour = AixoloColors.text});

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
                  color: AixoloColors.danger,
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
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _markAllRead() async {
    await Services.notifications.markRead();
    await _load();
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

  IconData _icon(String kind) => switch (kind) {
        'approval' => Icons.how_to_reg_rounded,
        'decision' => Icons.task_alt_rounded,
        _ => Icons.info_outline_rounded,
      };

  Color _colour(String kind) => switch (kind) {
        'approval' => AixoloColors.warning,
        'decision' => AixoloColors.success,
        _ => AixoloColors.primary,
      };

  @override
  Widget build(BuildContext context) {
    final unread = _rows.where((row) => row['read'] != true).length;
    return Scaffold(
      appBar: AppBar(
        title: Text(unread == 0 ? 'Notifications' : 'Notifications ($unread)'),
        actions: [
          if (unread > 0)
            TextButton(onPressed: _markAllRead, child: const Text('Mark all read')),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
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
    final read = row['read'] == true;
    final kind = '${row['kind']}';
    return Card(
      color: read ? null : const Color(0xFFF2F7FF),
      child: ListTile(
        onTap: () => _open(row),
        leading: CircleAvatar(
          backgroundColor: _colour(kind).withValues(alpha: 0.12),
          child: Icon(_icon(kind), color: _colour(kind), size: 20),
        ),
        title: Text('${row['title']}',
            style: TextStyle(fontWeight: read ? FontWeight.w600 : FontWeight.w800)),
        subtitle: Text(asText(row['body']) ?? '', maxLines: 3, overflow: TextOverflow.ellipsis),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(fmtTime(row['at']), style: const TextStyle(fontSize: 11, color: AixoloColors.muted)),
            if (!read)
              Container(
                margin: const EdgeInsets.only(top: 4),
                width: 8,
                height: 8,
                decoration: const BoxDecoration(color: AixoloColors.primary, shape: BoxShape.circle),
              ),
          ],
        ),
      ),
    );
  }
}
