import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/format.dart';
import '../../core/geo.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

const _stateWords = {'todo': 'To do', 'in_progress': 'In progress', 'done': 'Done', 'cancelled': 'Cancelled'};
const _priorityWords = {'0': 'Normal', '1': 'High', '2': 'Urgent'};

Color taskStateColour(Map<String, dynamic> task) {
  if (task['is_overdue'] == true) return AixoloColors.danger;
  return switch (task['state']) {
    'done' => AixoloColors.success,
    'in_progress' => AixoloColors.primary,
    'cancelled' => AixoloColors.muted,
    _ => AixoloColors.warning,
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

  bool get _isManager => Services.auth.profile!.isManager;

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

  Future<void> _newTask() async {
    final created = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const NewTaskScreen()));
    if (created == true) {
      setState(() => _scope = 'team');
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tasks = ((_data?['tasks'] as List?) ?? []).cast<Map<String, dynamic>>();
    final summary = (_data?['summary'] as Map?)?.cast<String, dynamic>() ?? const {};
    return Scaffold(
      appBar: AppBar(title: const Text('Tasks')),
      floatingActionButton: _isManager
          ? FloatingActionButton.extended(
              onPressed: _newTask,
              icon: const Icon(Icons.add_task_rounded),
              label: const Text('Give a task'),
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
                          style: const TextStyle(color: AixoloColors.muted, fontSize: 12.5)),
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
                            Icon(Icons.task_alt_rounded, size: 56, color: AixoloColors.muted),
                            SizedBox(height: 10),
                            Center(child: Text('No tasks here', style: TextStyle(color: AixoloColors.muted))),
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
    final customer = (task['customer'] as Map?)?['name'];
    final employee = (task['employee'] as Map?)?['name'];
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(width: 4, height: 44, decoration: BoxDecoration(color: colour, borderRadius: BorderRadius.circular(4))),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        if (task['priority'] != '0')
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Icon(Icons.flag_rounded,
                                size: 16, color: task['priority'] == '2' ? AixoloColors.danger : AixoloColors.warning),
                          ),
                        Expanded(
                          child: Text('${task['name']}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (showEmployee && employee != null) employee,
                        if (customer != null) customer,
                        if (task['due'] != null) 'Due ${task['due']}',
                      ].join(' · '),
                      style: const TextStyle(color: AixoloColors.muted, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(color: colour.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                child: Text(taskStateWord(task), style: TextStyle(color: colour, fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ],
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
    final image = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 1280, imageQuality: 65);
    if (image == null) return;
    final bytes = await image.readAsBytes();
    if (mounted) setState(() => _photo = bytes);
  }

  Future<void> _act(String action) async {
    if (action == 'done' && _task['requires_photo'] == true && _photo == null) {
      showSnack(context, 'Take a photo to finish this task.');
      return;
    }
    setState(() => _busy = true);
    try {
      final body = <String, dynamic>{};
      if (action == 'done') {
        body['note'] = _note.text.trim();
        if (_photo != null) body['photo'] = base64Encode(_photo!);
        try {
          final pos = await currentPosition();
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
      Services.refresh.value++;
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final task = _task;
    final colour = taskStateColour(task);
    final open = task['state'] == 'todo' || task['state'] == 'in_progress';
    final details = <(IconData, String, String?)>[
      (Icons.person_rounded, 'Assigned to', (task['employee'] as Map?)?['name'] as String?),
      (Icons.storefront_rounded, 'Customer', (task['customer'] as Map?)?['name'] as String?),
      (Icons.event_rounded, 'Due', task['due'] as String?),
      (Icons.flag_rounded, 'Priority', _priorityWords[task['priority']]),
      (Icons.supervisor_account_rounded, 'Given by', task['assigned_by'] as String?),
      (Icons.check_circle_rounded, 'Finished', task['done_at'] == null ? null : fmtTime(task['done_at'])),
      (Icons.notes_rounded, 'Completion note', task['done_note'] as String?),
    ];
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Task')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text('${task['name']}', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration:
                              BoxDecoration(color: colour.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                          child: Text(taskStateWord(task),
                              style: TextStyle(color: colour, fontSize: 12.5, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                    if (task['description'] != null) ...[
                      const SizedBox(height: 10),
                      Text('${task['description']}', style: const TextStyle(height: 1.4)),
                    ],
                  ],
                ),
              ),
            ),
            Card(
              child: Column(
                children: [
                  for (final d in details)
                    if ((d.$3 ?? '').isNotEmpty)
                      ListTile(
                        dense: true,
                        leading: Icon(d.$1, color: AixoloColors.primary),
                        title: Text(d.$2, style: const TextStyle(color: AixoloColors.muted, fontSize: 12)),
                        subtitle: Text(d.$3!, style: const TextStyle(color: AixoloColors.text, fontSize: 14.5)),
                      ),
                ],
              ),
            ),
            if (widget.canAct && open) ...[
              const SizedBox(height: 8),
              if (task['state'] == 'todo')
                GradientButton(label: 'Start task', icon: Icons.play_arrow_rounded, busy: _busy, onPressed: () => _act('start'))
              else ...[
                TextField(
                  controller: _note,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'What was done? (optional)'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _takePhoto,
                  icon: Icon(_photo == null ? Icons.photo_camera_rounded : Icons.check_rounded),
                  label: Text(_photo == null
                      ? (task['requires_photo'] == true ? 'Take photo (required)' : 'Add a photo')
                      : 'Photo added · retake'),
                ),
                const SizedBox(height: 10),
                GradientButton(
                  label: 'Finish task',
                  icon: Icons.task_alt_rounded,
                  gradient: AixoloColors.successGradient,
                  busy: _busy,
                  onPressed: () => _act('done'),
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
  DateTime? _due;
  String _priority = '0';
  bool _photo = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    Services.api.get('/api/v1/reports').then((data) {
      final members = (((data as Map)['members'] as List?) ?? []).cast<Map<String, dynamic>>();
      if (mounted) setState(() => _members = members);
    }).catchError((Object e) {
      if (mounted) showSnack(context, e.toString());
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
        if (_due != null) 'date_deadline': fmtDate(_due!),
        'priority': _priority,
        'requires_photo': _photo,
      });
      if (!mounted) return;
      showSnack(context, 'Task sent');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Give a task')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Task *'),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _employeeId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Assign to *'),
              items: [
                for (final m in _members) DropdownMenuItem(value: m['id'] as int, child: Text('${m['name']}')),
              ],
              onChanged: (v) => setState(() => _employeeId = v),
              validator: (v) => v == null ? 'Choose someone' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _description,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Details'),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_rounded, color: AixoloColors.primary),
              title: Text(_due == null ? 'No due date' : 'Due ${fmtDate(_due!)}'),
              trailing: TextButton(
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
            ),
            const SizedBox(height: 4),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: '0', label: Text('Normal')),
                ButtonSegment(value: '1', label: Text('High')),
                ButtonSegment(value: '2', label: Text('Urgent')),
              ],
              selected: {_priority},
              onSelectionChanged: (v) => setState(() => _priority = v.first),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _photo,
              onChanged: (v) => setState(() => _photo = v),
              title: const Text('Photo needed to finish'),
            ),
            const SizedBox(height: 12),
            GradientButton(label: 'Send task', icon: Icons.send_rounded, busy: _busy, onPressed: _save),
          ],
        ),
      ),
    );
  }
}
