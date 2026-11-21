import 'dart:convert';
import '../../widgets/report_download.dart';

import 'package:flutter/material.dart';
import 'assign_target_screen.dart';
import 'package:uuid/uuid.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/photos.dart';
import '../../core/format.dart';
import '../../core/geo.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../clients/clients_screen.dart';

const _stateWords = {'todo': 'To do', 'in_progress': 'In progress', 'done': 'Done', 'cancelled': 'Cancelled'};
const _priorityWords = {'0': 'Normal', '1': 'High', '2': 'Urgent'};

Color taskStateColour(Map<String, dynamic> task) {
  if (task['is_overdue'] == true) return AppColors.danger;
  return switch (task['state']) {
    'done' => AppColors.success,
    'in_progress' => AppColors.primary,
    'cancelled' => AppColors.muted,
    _ => AppColors.warning,
  };
}

String taskStateWord(Map<String, dynamic> task) =>
    task['is_overdue'] == true ? 'Overdue' : (_stateWords[task['state']] ?? '${task['state']}');

/// My tasks, and my team's when I have one.
class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  String _scope = 'mine';
  bool _openOnly = true;
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true;

  /// Team view and assigning are for manager mode; working as an employee shows only the person's own tasks.
  bool get _isManager => Services.auth.profile!.isManager && Services.managerMode.value;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await Services.api.get('/api/v1/tasks', query: {
        'scope': _scope,
        if (_openOnly) 'state': 'todo,in_progress',
      }) as Map<String, dynamic>;
      if (mounted) setState(() => _data = data);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(Map<String, dynamic> task) async {
    final changed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => TaskDetailScreen(task: task, canAct: _scope == 'mine')));
    if (changed == true) _load();
  }

  /// "Choose what to assign": a task, or a target for bottles and outlets onboarded.
  Future<void> _assign() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.add_task_rounded, color: AppColors.primary, size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Assign Work', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                      SizedBox(height: 2),
                      Text('Choose what to assign to your team', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _assignOptionCard(
                icon: Icons.assignment_turned_in_rounded,
                iconColor: AppColors.success,
                iconBg: const Color(0xFFDCFCE7),
                title: 'Assign Task',
                subtitle: 'Give a specific task, audit, or customer visit to an employee',
                onTap: () => Navigator.pop(sheet, 'task'),
              ),
              const SizedBox(height: 12),
              _assignOptionCard(
                icon: Icons.track_changes_rounded,
                iconColor: AppColors.purple,
                iconBg: const Color(0xFFEDE8FF),
                title: 'Assign Target',
                subtitle: 'Set monthly or weekly targets for bottles and outlets onboarded',
                onTap: () => Navigator.pop(sheet, 'target'),
              ),
            ],
          ),
        ),
      ),
    );
    if (choice == 'task') {
      await _newTask();
    } else if (choice == 'target' && mounted) {
      final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const AssignTargetScreen()));
      // The Team Target card on Home reads the new target.
      if (saved == true) Services.refresh.value++;
    }
  }

  Widget _assignOptionCard({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(14)),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    const SizedBox(height: 3),
                    Text(subtitle, style: const TextStyle(fontSize: 12.5, color: AppColors.muted, height: 1.25)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded, color: AppColors.muted, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _newTask() async {
    final created = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const NewTaskScreen()));
    if (created == true) {
      if (_isManager) setState(() => _scope = 'team');
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tasks = ((_data?['tasks'] as List?) ?? []).cast<Map<String, dynamic>>();
    final summary = (_data?['summary'] as Map?)?.cast<String, dynamic>() ?? const {};
    return Scaffold(
      appBar: AppBar(title: const Text('Tasks'), actions: [const ReportDownloadButton(reportKey: 'tasks', title: 'Tasks')]),
      // Lifted above the bottom bar (the app's bar sits over the page) and centred, clear of the chat bar on the right.
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: _isManager
          ? Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
              child: FloatingActionButton.extended(
                onPressed: _assign,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Assign'),
              ),
            )
          : null,
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_isManager)
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'mine', label: Text('Mine'), icon: Icon(Icons.person_rounded)),
                      ButtonSegment(value: 'team', label: Text('My team'), icon: Icon(Icons.groups_rounded)),
                    ],
                    selected: {_scope},
                    onSelectionChanged: (value) {
                      setState(() => _scope = value.first);
                      _load();
                    },
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    FilterChip(
                      label: const Text('Open only'),
                      selected: _openOnly,
                      onSelected: (value) {
                        setState(() => _openOnly = value);
                        _load();
                      },
                    ),
                    const Spacer(),
                    if (summary.isNotEmpty)
                      Text('${summary['open']} open · ${summary['overdue']} overdue',
                          style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                  ],
                ),
              ],
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: _error != null
                ? ErrorView(message: _error!, onRetry: _load)
                : RefreshIndicator(
                    onRefresh: _load,
                    child: tasks.isEmpty && !_loading
                        ? ListView(children: const [
                            SizedBox(height: 120),
                            Icon(Icons.task_alt_rounded, size: 56, color: AppColors.muted),
                            SizedBox(height: 10),
                            Center(child: Text('No tasks here', style: TextStyle(color: AppColors.muted))),
                          ])
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 90),
                            itemCount: tasks.length,
                            itemBuilder: (context, i) => _TaskTile(
                              task: tasks[i],
                              showEmployee: _scope == 'team',
                              onTap: () => _open(tasks[i]),
                            ),
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({required this.task, required this.showEmployee, required this.onTap});

  final Map<String, dynamic> task;
  final bool showEmployee;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colour = taskStateColour(task);
    final state = '${task['state']}';
    final isOverdue = task['is_overdue'] == true;
    final customer = (task['customer'] as Map?)?['name'] as String?;
    final employee = (task['employee'] as Map?)?['name'] as String?;
    final priority = '${task['priority']}';
    final hasHighPriority = priority == '1' || priority == '2';

    final IconData leadingIcon = state == 'done'
        ? Icons.check_circle_rounded
        : (state == 'in_progress'
            ? Icons.play_circle_fill_rounded
            : (isOverdue
                ? Icons.assignment_late_rounded
                : (customer != null ? Icons.storefront_rounded : Icons.assignment_rounded)));

    final iconColor = isOverdue && state != 'done' ? AppColors.danger : colour;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isOverdue ? AppColors.danger.withValues(alpha: 0.35) : AppColors.border,
          width: isOverdue ? 1.2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: iconColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(leadingIcon, color: iconColor, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (hasHighPriority) ...[
                                Container(
                                  margin: const EdgeInsets.only(right: 6),
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: (priority == '2' ? AppColors.danger : AppColors.warning).withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.flag_rounded,
                                        size: 11,
                                        color: priority == '2' ? AppColors.danger : AppColors.warning,
                                      ),
                                      const SizedBox(width: 2),
                                      Text(
                                        priority == '2' ? 'Urgent' : 'High',
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w700,
                                          color: priority == '2' ? AppColors.danger : AppColors.warning,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              Expanded(
                                child: Text(
                                  '${task['name']}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.text),
                                ),
                              ),
                            ],
                          ),
                          if (customer != null && customer.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(Icons.storefront_rounded, size: 13, color: AppColors.primary),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    customer,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: colour.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        taskStateWord(task),
                        style: TextStyle(color: colour, fontSize: 11.5, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.only(top: 8),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: Color(0xFFF1F5F9), width: 1)),
                  ),
                  child: Row(
                    children: [
                      if (showEmployee && employee != null) ...[
                        const Icon(Icons.person_outline_rounded, size: 14, color: AppColors.muted),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            employee,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w500),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      if (task['due'] != null) ...[
                        Icon(
                          Icons.event_outlined,
                          size: 14,
                          color: isOverdue ? AppColors.danger : AppColors.muted,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Due ${task['due']}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isOverdue ? FontWeight.w700 : FontWeight.w500,
                            color: isOverdue ? AppColors.danger : AppColors.muted,
                          ),
                        ),
                      ],
                      const Spacer(),
                      const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.muted),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One task: what it is, and Start / Finish for its assignee.
class TaskDetailScreen extends StatefulWidget {
  const TaskDetailScreen({super.key, required this.task, required this.canAct});

  final Map<String, dynamic> task;
  final bool canAct;

  @override
  State<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen> {
  late Map<String, dynamic> _task = widget.task;
  final _note = TextEditingController();
  List<int>? _photo;
  bool _busy = false;
  bool _changed = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _takePhoto() async {
    final bytes = await takePhoto(ImageSource.camera);
    if (bytes == null) return;
    if (mounted) setState(() => _photo = bytes);
  }

  Future<void> _act(String action) async {
    if (action == 'done' && _task['requires_photo'] == true && _photo == null) {
      showProblem(context, 'Take a photo to finish this task.');
      return;
    }
    setState(() => _busy = true);
    try {
      final body = <String, dynamic>{};
      if (action == 'done') {
        body['note'] = _note.text.trim();
        if (_photo != null) body['photo'] = base64Encode(_photo!);
        try {
          final pos = await currentPosition(recentOk: true);
          body['lat'] = pos.latitude;
          body['lng'] = pos.longitude;
        } catch (_) {
          // Location is a nice-to-have on a finished task, not a blocker.
        }
      }
      final result = await Services.outbox.submit('/api/v1/tasks/${_task['id']}/$action', body,
          label: '${action == 'done' ? 'Finish' : 'Start'} task · ${_task['name']}');
      final task = result.queued
          ? {..._task, 'state': action == 'done' ? 'done' : 'in_progress', 'is_overdue': false}
          : result.map;
      if (!mounted) return;
      setState(() {
        _task = task;
        _changed = true;
      });
      final word = action == 'done' ? 'Task finished' : 'Task started';
      showSnack(context, result.queued ? '$word · Saved on the phone · it will sync when you are back online' : word);
      settleAndRefresh();
    } catch (e) {
      if (mounted) showProblem(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final task = _task;
    final colour = taskStateColour(task);
    final open = task['state'] == 'todo' || task['state'] == 'in_progress';
    final customer = (task['customer'] as Map?)?['name'] as String?;
    final employee = (task['employee'] as Map?)?['name'] as String?;
    final priority = '${task['priority']}';
    final hasHighPriority = priority == '1' || priority == '2';

    final details = <(IconData, Color, String, String?)>[
      (Icons.person_rounded, AppColors.purple, 'Assigned to', employee),
      (Icons.storefront_rounded, AppColors.primary, 'Customer', customer),
      (Icons.event_rounded, colour, 'Due date', task['due'] as String?),
      (Icons.flag_rounded, priority == '2' ? AppColors.danger : AppColors.warning, 'Priority', _priorityWords[task['priority']]),
      (Icons.supervisor_account_rounded, const Color(0xFF0284C7), 'Given by', task['assigned_by'] as String?),
      (Icons.check_circle_rounded, AppColors.success, 'Finished at', task['done_at'] == null ? null : fmtTime(task['done_at'])),
      (Icons.notes_rounded, AppColors.muted, 'Completion note', task['done_note'] as String?),
    ];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Task Details')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 36),
          children: [
            // Modern Header Card
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.border),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 2)),
                ],
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: colour.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          taskStateWord(task),
                          style: TextStyle(color: colour, fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (hasHighPriority) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: (priority == '2' ? AppColors.danger : AppColors.warning).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.flag_rounded,
                                size: 12,
                                color: priority == '2' ? AppColors.danger : AppColors.warning,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                priority == '2' ? 'Urgent' : 'High',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: priority == '2' ? AppColors.danger : AppColors.warning,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${task['name']}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.text, height: 1.3),
                  ),
                  if (customer != null && customer.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.storefront_rounded, size: 16, color: AppColors.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              customer,
                              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.primary),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (task['description'] != null && '${task['description']}'.trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.subject_rounded, size: 15, color: AppColors.muted),
                              SizedBox(width: 6),
                              Text('Description', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.muted)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text('${task['description']}', style: const TextStyle(fontSize: 13.5, height: 1.4, color: AppColors.text)),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Modern Information Card
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.border),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 2)),
                ],
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.info_outline_rounded, size: 17, color: AppColors.primary),
                      SizedBox(width: 8),
                      Text('Task Details', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.text)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  for (final (i, d) in details.where((d) => (d.$4 ?? '').isNotEmpty).toList().indexed) ...[
                    if (i > 0) const Divider(height: 16, color: Color(0xFFF1F5F9)),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: d.$2.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(d.$1, size: 17, color: d.$2),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(d.$3, style: const TextStyle(fontSize: 11.5, color: AppColors.muted, fontWeight: FontWeight.w500)),
                              const SizedBox(height: 2),
                              Text(d.$4!, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.text)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            if (widget.canAct && open) ...[
              const SizedBox(height: 16),
              if (task['state'] == 'todo')
                GradientButton(
                  label: 'Start task',
                  icon: Icons.play_arrow_rounded,
                  busy: _busy,
                  onPressed: () => _act('start'),
                )
              else ...[
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.border),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 2)),
                    ],
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.task_alt_rounded, size: 17, color: AppColors.success),
                          SizedBox(width: 8),
                          Text('Complete Task', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.text)),
                        ],
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _note,
                        maxLines: 3,
                        decoration: InputDecoration(
                          labelText: 'What was done? (optional)',
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.border)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.border)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: _takePhoto,
                        icon: Icon(_photo == null ? Icons.photo_camera_rounded : Icons.check_circle_rounded,
                            color: _photo == null ? AppColors.primary : AppColors.success),
                        label: Text(_photo == null
                            ? (task['requires_photo'] == true ? 'Take photo (required)' : 'Add a photo')
                            : 'Photo added · retake'),
                      ),
                      const SizedBox(height: 14),
                      GradientButton(
                        label: 'Finish task',
                        icon: Icons.check_circle_rounded,
                        gradient: AppColors.successGradient,
                        busy: _busy,
                        onPressed: () => _act('done'),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// A manager gives a task to someone in their team.
class NewTaskScreen extends StatefulWidget {
  const NewTaskScreen({super.key});

  @override
  State<NewTaskScreen> createState() => _NewTaskScreenState();
}

class _NewTaskScreenState extends State<NewTaskScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();
  List<Map<String, dynamic>> _members = [];
  int? _employeeId;
  int? _partnerId;
  String? _partnerName;
  DateTime? _due;
  String _priority = '0';
  bool _photo = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    Services.api.get('/api/v1/reports').then((data) {
      final members = (((data as Map)['members'] as List?) ?? []).cast<Map<String, dynamic>>().toList()
        ..sort((a, b) => '${a['name']}'.toLowerCase().compareTo('${b['name']}'.toLowerCase()));
      if (mounted) setState(() => _members = members);
    }).catchError((Object e) {
      if (mounted) showProblem(context, e.toString());
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await Services.outbox.submit('/api/v1/tasks', {
        'uuid': const Uuid().v4(),
        'name': _name.text.trim(),
        'description': _description.text.trim(),
        'employee_id': _employeeId,
        if (_partnerId != null) 'partner_id': _partnerId,
        if (_due != null) 'date_deadline': fmtDate(_due!),
        'priority': _priority,
        'requires_photo': _photo,
      });
      if (!mounted) return;
      showSnack(context, 'Task sent');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showProblem(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Give a task', style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: GradientButton(
            label: 'Send task',
            icon: Icons.send_rounded,
            busy: _busy,
            onPressed: _save,
          ),
        ),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            // Header Info Banner
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.assignment_add, color: AppColors.primary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('New Task Assignment', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                        SizedBox(height: 2),
                        Text('Assign field tasks or customer visits to team members',
                            style: TextStyle(fontSize: 12, color: AppColors.muted)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Card 1: Task Information
            _formCard(
              title: 'Task Details',
              icon: Icons.edit_note_rounded,
              children: [
                TextFormField(
                  controller: _name,
                  decoration: InputDecoration(
                    labelText: 'Task Title *',
                    hintText: 'e.g. Audit display, Collect payment',
                    prefixIcon: const Icon(Icons.title_rounded, color: AppColors.primary),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                    ),
                  ),
                  validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _description,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: 'Instructions / Notes',
                    hintText: 'Optional instructions or checklist for the employee',
                    alignLabelWithHint: true,
                    prefixIcon: const Padding(
                      padding: EdgeInsets.only(bottom: 48),
                      child: Icon(Icons.notes_rounded, color: AppColors.muted),
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Card 2: Assignment & Customer
            _formCard(
              title: 'Assignment',
              icon: Icons.people_alt_rounded,
              children: [
                DropdownButtonFormField<int>(
                  initialValue: _employeeId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Assign to Employee *',
                    prefixIcon: const Icon(Icons.person_rounded, color: AppColors.primary),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                    ),
                  ),
                  items: [
                    for (final m in _members)
                      DropdownMenuItem(
                        value: m['id'] as int,
                        child: Text('${m['name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                  ],
                  onChanged: (v) => setState(() => _employeeId = v),
                  validator: (v) => v == null ? 'Choose someone' : null,
                ),
                const SizedBox(height: 12),
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () async {
                    final client = await Navigator.of(context).push<Map<String, dynamic>>(
                      MaterialPageRoute(
                        builder: (_) => const ClientsScreen(pickMode: true, title: 'Choose customer'),
                      ),
                    );
                    if (client != null) {
                      setState(() {
                        _partnerId = client['id'] as int;
                        _partnerName = '${client['name']}';
                      });
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: _partnerId != null ? AppColors.primary.withValues(alpha: 0.06) : const Color(0xFFF8FAFC),
                      border: Border.all(
                        color: _partnerId != null ? AppColors.primary.withValues(alpha: 0.3) : AppColors.border,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: _partnerId != null
                                ? AppColors.primary.withValues(alpha: 0.12)
                                : Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.storefront_rounded,
                            color: _partnerId != null ? AppColors.primary : AppColors.muted,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _partnerName ?? 'Link Customer (Optional)',
                                style: TextStyle(
                                  fontWeight: _partnerName != null ? FontWeight.w700 : FontWeight.w600,
                                  fontSize: 14,
                                  color: _partnerName != null ? AppColors.text : AppColors.muted,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _partnerName != null
                                    ? 'Tap to change associated customer'
                                    : 'Attach an outlet or distributor to this task',
                                style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
                              ),
                            ],
                          ),
                        ),
                        if (_partnerId != null)
                          IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 20, color: AppColors.muted),
                            tooltip: 'Remove customer',
                            onPressed: () => setState(() {
                              _partnerId = null;
                              _partnerName = null;
                            }),
                          )
                        else
                          const Icon(Icons.chevron_right_rounded, color: AppColors.muted, size: 20),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Card 3: Schedule, Priority & Proof
            _formCard(
              title: 'Schedule & Priority',
              icon: Icons.tune_rounded,
              children: [
                // Date picker box
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      firstDate: DateTime.now().subtract(const Duration(days: 1)),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                      initialDate: _due ?? DateTime.now(),
                    );
                    if (picked != null) setState(() => _due = picked);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.calendar_today_rounded, color: AppColors.primary, size: 18),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Due Date', style: TextStyle(fontSize: 11.5, color: AppColors.muted)),
                              const SizedBox(height: 1),
                              Text(
                                _due == null ? 'No due date set' : 'Due ${fmtDate(_due!)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: _due == null ? AppColors.muted : AppColors.text,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_due != null)
                          IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 20, color: AppColors.muted),
                            tooltip: 'Remove due date',
                            onPressed: () => setState(() => _due = null),
                          )
                        else
                          TextButton(
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                firstDate: DateTime.now().subtract(const Duration(days: 1)),
                                lastDate: DateTime.now().add(const Duration(days: 365)),
                                initialDate: _due ?? DateTime.now(),
                              );
                              if (picked != null) setState(() => _due = picked);
                            },
                            child: const Text('Pick date'),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Priority
                const Text('Priority Level', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: '0', label: Text('Normal')),
                      ButtonSegment(value: '1', label: Text('High')),
                      ButtonSegment(value: '2', label: Text('Urgent')),
                    ],
                    selected: {_priority},
                    onSelectionChanged: (v) => setState(() => _priority = v.first),
                  ),
                ),
                const SizedBox(height: 12),

                // Photo requirement
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _photo,
                    onChanged: (v) => setState(() => _photo = v),
                    secondary: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: _photo ? AppColors.primary.withValues(alpha: 0.12) : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.camera_alt_rounded,
                          color: _photo ? AppColors.primary : AppColors.muted, size: 18),
                    ),
                    title: const Text('Photo Proof Required', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                    subtitle: const Text('Must attach a photo to complete task', style: TextStyle(fontSize: 11.5)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _formCard({required String title, required IconData icon, required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}
