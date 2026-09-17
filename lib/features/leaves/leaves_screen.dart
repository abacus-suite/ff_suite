import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import 'team_leaves.dart';

/// My time off: what is left of each type, what I asked for, and its state.
class LeavesScreen extends StatefulWidget {
  const LeavesScreen({super.key});

  @override
  State<LeavesScreen> createState() => _LeavesScreenState();
}

class _LeavesScreenState extends State<LeavesScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final data = await Services.api.get('/api/v1/leaves') as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _data = data;
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

  Future<void> _request() async {
    final types = ((_data?['types'] as List?) ?? []).cast<Map<String, dynamic>>();
    if (types.isEmpty) {
      showSnack(context, 'No leave types are set up yet.');
      return;
    }
    final saved = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => LeaveRequestScreen(types: types)));
    if (saved == true) await _load();
  }

  Future<void> _withdraw(Map<String, dynamic> leave) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Withdraw this request?'),
        content: Text('${leave['type']['name']} · ${leave['from']}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep it')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Withdraw')),
        ],
      ),
    );
    if (sure != true) return;
    try {
      await Services.outbox.submit('/api/v1/leaves/${leave['id']}', {'uuid': const Uuid().v4()});
      if (mounted) showSnack(context, 'Request withdrawn');
      await _load();
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final leaves = ((data?['leaves'] as List?) ?? []).cast<Map<String, dynamic>>();
    final types = ((data?['types'] as List?) ?? []).cast<Map<String, dynamic>>();
    final allocations = ((data?['allocations'] as List?) ?? []).cast<Map<String, dynamic>>();
    final summary = (data?['summary'] as Map?)?.cast<String, dynamic>() ?? {};
    final shown = _filter == 'all'
        ? leaves
        : leaves.where((l) => _filter == 'waiting'
            ? const ['confirm', 'validate1', 'draft'].contains(l['state'])
            : l['state'] == _filter).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Time Off'),
        actions: [
          IconButton(
            tooltip: 'Calendar',
            icon: const Icon(Icons.calendar_month_rounded),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LeaveCalendarScreen())),
          ),
          if (Services.auth.profile?.isManager ?? false)
            IconButton(
              tooltip: 'Team time off',
              icon: const Icon(Icons.groups_rounded),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TeamLeavesScreen())),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _request,
        icon: const Icon(Icons.add),
        label: const Text('Request'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && data == null
              ? ErrorView(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                    children: [
                      Row(
                        children: [
                          _stat('Allocated', fmtQty(summary['allocated'] as num? ?? 0), AppColors.primary),
                          _stat('Used', fmtQty(summary['used'] as num? ?? 0), AppColors.purple),
                          _stat('Pending', fmtQty(summary['pending'] as num? ?? 0), AppColors.warning),
                          _stat('Available', fmtQty(summary['remaining'] as num? ?? 0), AppColors.success),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (types.isNotEmpty)
                        SectionCard(
                          title: 'Balance by type',
                          child: Column(children: [for (final type in types) _typeTile(type)]),
                        ),
                      if (allocations.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        SectionCard(
                          title: 'Allocations',
                          child: Column(
                            children: [
                              for (final a in allocations)
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  dense: true,
                                  leading: const CircleAvatar(
                                    radius: 16,
                                    backgroundColor: Color(0xFFE8EFFF),
                                    child: Icon(Icons.card_giftcard_rounded, size: 17, color: AppColors.primary),
                                  ),
                                  title: Text('${(a['type'] as Map)['name']}',
                                      style: const TextStyle(fontWeight: FontWeight.w700)),
                                  subtitle: Text([
                                    if (a['from'] != null) 'From ${a['from']}',
                                    a['to'] != null ? 'to ${a['to']}' : 'no end date',
                                    if (asText(a['name']) != null) '${a['name']}',
                                  ].join(' · ')),
                                  trailing: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text('${fmtQty(a['days'] as num? ?? 0)} days',
                                          style: const TextStyle(fontWeight: FontWeight.w800)),
                                      if (a['used'] != null)
                                        Text('${fmtQty(a['used'] as num)} used',
                                            style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      SectionCard(
                        title: 'My requests',
                        action: Text('${summary['waiting'] ?? 0} waiting',
                            style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 6,
                              children: [
                                for (final (key, label) in [
                                  ('all', 'All'),
                                  ('waiting', 'Waiting'),
                                  ('validate', 'Approved'),
                                  ('refuse', 'Refused'),
                                ])
                                  ChoiceChip(
                                    label: Text(label),
                                    selected: _filter == key,
                                    onSelected: (_) => setState(() => _filter = key),
                                  ),
                              ],
                            ),
                            for (final leave in shown) _leaveTile(leave),
                            if (shown.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 10),
                                child: Text('Nothing here.', style: TextStyle(color: AppColors.muted)),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _stat(String label, String value, Color colour) => Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(color: colour.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14)),
          child: Column(
            children: [
              Text(value, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: colour)),
              Text(label, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
            ],
          ),
        ),
      );

  Widget _typeTile(Map<String, dynamic> type) {
    final limited = type['requires_allocation'] == true;
    final allocated = (type['allocated'] as num?) ?? 0;
    final used = (type['used'] as num?) ?? 0;
    final pending = (type['pending'] as num?) ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('${type['name']}', style: const TextStyle(fontWeight: FontWeight.w700))),
              Text(limited ? '${fmtQty((type['remaining'] as num?) ?? 0)} available' : 'No limit',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: limited && ((type['remaining'] as num?) ?? 0) <= 0 ? AppColors.danger : AppColors.success)),
            ],
          ),
          if (limited && allocated > 0) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 8,
                child: Row(
                  children: [
                    Expanded(flex: (used * 100).round(), child: Container(color: AppColors.purple)),
                    Expanded(flex: (pending * 100).round(), child: Container(color: AppColors.warning)),
                    Expanded(
                        flex: ((allocated - used - pending).clamp(0, allocated) * 100).round(),
                        child: Container(color: const Color(0xFFE3E9F6))),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            [
              if (limited) 'Allocated ${fmtQty(allocated)}',
              'Used ${fmtQty(used)}',
              if (pending > 0) 'Pending ${fmtQty(pending)}',
              if (asText(type['approval']) != null) '${type['approval']}',
            ].join(' · '),
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
        ],
      ),
    );
  }

  Widget _leaveTile(Map<String, dynamic> leave) {
    final from = asText(leave['from']) ?? '';
    final to = asText(leave['to']) ?? '';
    final approval = (leave['approval'] as Map?)?.cast<String, dynamic>();
    final steps = ((approval?['steps'] as List?) ?? []).cast<Map<String, dynamic>>();
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(left: 8, bottom: 8),
      title: Text('${leave['type']['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text([
        from == to ? from : '$from → $to',
        '${fmtQty(leave['days'] as num? ?? 0)} days',
      ].join(' · ')),
      trailing: StatusBadge('${leave['state']}', label: '${leave['state_label']}'),
      children: [
        if (asText(leave['reason']) != null)
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Reason: ${leave['reason']}', style: const TextStyle(fontSize: 13)),
          ),
        if (asText(approval?['label']) != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('${approval!['label']}',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.muted)),
            ),
          ),
        for (final (i, step) in steps.indexed)
          Row(
            children: [
              Icon(
                step['state'] == 'done'
                    ? Icons.check_circle_rounded
                    : step['state'] == 'rejected'
                        ? Icons.cancel_rounded
                        : Icons.radio_button_unchecked_rounded,
                size: 18,
                color: step['state'] == 'done'
                    ? AppColors.success
                    : step['state'] == 'rejected'
                        ? AppColors.danger
                        : AppColors.muted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text('${i + 1}. ${step['name']}${asText(step['approver']) != null ? ' · ${step['approver']}' : ''}',
                      style: const TextStyle(fontSize: 13)),
                ),
              ),
            ],
          ),
        if (leave['can_cancel'] == true)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _withdraw(leave),
              icon: const Icon(Icons.undo_rounded, size: 18),
              label: const Text('Withdraw'),
            ),
          ),
      ],
    );
  }
}

/// Ask for time off: a type, a stretch of days, and why.
class LeaveRequestScreen extends StatefulWidget {
  const LeaveRequestScreen({super.key, required this.types});

  final List<Map<String, dynamic>> types;

  @override
  State<LeaveRequestScreen> createState() => _LeaveRequestScreenState();
}

class _LeaveRequestScreenState extends State<LeaveRequestScreen> {
  final _reason = TextEditingController();
  Map<String, dynamic>? _type;
  DateTime _from = DateTime.now().add(const Duration(days: 1));
  DateTime _to = DateTime.now().add(const Duration(days: 1));
  bool _halfDay = false;
  String _halfPeriod = 'am';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _type = widget.types.first;
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  num get _days => _halfDay ? 0.5 : _to.difference(_from).inDays + 1;

  Future<void> _pick(bool isFrom) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? _from : _to,
      firstDate: now.subtract(const Duration(days: 30)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _from = picked;
        if (_to.isBefore(_from)) _to = _from;
      } else {
        _to = picked;
        if (_to.isBefore(_from)) _from = _to;
      }
    });
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    // Warn about planned route days, tasks or other leave on these days first.
    try {
      final check = await Services.api.get('/api/v1/leaves/check',
          query: {'start': fmtDate(_from), 'end': fmtDate(_halfDay ? _from : _to)}) as Map<String, dynamic>;
      final warnings = ((check['warnings'] as List?) ?? []).cast<Map<String, dynamic>>();
      if (warnings.isNotEmpty && mounted) {
        final go = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('These days are busy'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final w in warnings.take(8))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(
                          w['kind'] == 'beat_plan'
                              ? Icons.route_rounded
                              : w['kind'] == 'task'
                                  ? Icons.task_alt_rounded
                                  : Icons.beach_access_rounded,
                          size: 18,
                          color: AppColors.warning),
                      const SizedBox(width: 8),
                      Expanded(child: Text('${w['message']}')),
                    ]),
                  ),
                if (warnings.length > 8) Text('and ${warnings.length - 8} more'),
                const SizedBox(height: 8),
                const Text('Send the request anyway?', style: TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Change dates')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send anyway')),
            ],
          ),
        );
        if (go != true) {
          if (mounted) setState(() => _busy = false);
          return;
        }
      }
    } catch (_) {
      // Offline or older server: the request still goes.
    }
    try {
      await Services.outbox.submit('/api/v1/leaves', {
        'uuid': const Uuid().v4(),
        'type_id': _type!['id'],
        'from': fmtDate(_from),
        'to': fmtDate(_halfDay ? _from : _to),
        'half_day': _halfDay,
        'half_day_period': _halfPeriod,
        'reason': _reason.text.trim(),
      });
      Services.refresh.value++;
      if (!mounted) return;
      showSnack(context, 'Request sent for approval');
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
      appBar: AppBar(title: const Text('Request Time Off')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final type in widget.types)
                ChoiceChip(
                  label: Text('${type['name']}'),
                  selected: _type?['id'] == type['id'],
                  onSelected: (_) => setState(() => _type = type),
                ),
            ],
          ),
          if (_type != null)
            Card(
              margin: const EdgeInsets.only(top: 10),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _type!['requires_allocation'] == true
                          ? '${fmtQty(_type!['remaining'] as num? ?? 0)} days available · '
                              'allocated ${fmtQty(_type!['allocated'] as num? ?? 0)}, used ${fmtQty(_type!['used'] as num? ?? 0)}'
                              '${((_type!['pending'] as num?) ?? 0) > 0 ? ', pending ${fmtQty(_type!['pending'] as num)}' : ''}'
                          : 'No limit for this type',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (asText(_type!['approval']) != null)
                      Text('Approval: ${_type!['approval']}',
                          style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                    if (_type!['can_request'] == false)
                      const Text('Nothing left to request for this type.',
                          style: TextStyle(color: AppColors.danger, fontSize: 12.5, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.event_rounded),
              title: const Text('From'),
              trailing: Text(fmtDate(_from)),
              onTap: () => _pick(true),
            ),
          ),
          if (!_halfDay)
            Card(
              child: ListTile(
                leading: const Icon(Icons.event_available_rounded),
                title: const Text('To'),
                trailing: Text(fmtDate(_to)),
                onTap: () => _pick(false),
              ),
            ),
          SwitchListTile(
            value: _halfDay,
            onChanged: (value) => setState(() => _halfDay = value),
            title: const Text('Half day'),
            contentPadding: EdgeInsets.zero,
          ),
          if (_halfDay)
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'am', label: Text('Morning'), icon: Icon(Icons.wb_sunny_outlined)),
                ButtonSegment(value: 'pm', label: Text('Afternoon'), icon: Icon(Icons.wb_twilight_rounded)),
              ],
              selected: {_halfPeriod},
              onSelectionChanged: (v) => setState(() => _halfPeriod = v.first),
            ),
          const SizedBox(height: 4),
          TextField(
            controller: _reason,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Reason'),
          ),
          const SizedBox(height: 16),
          Text('${fmtQty(_days)} day${_days == 1 ? '' : 's'}',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 12),
          GradientButton(
            label: 'Send for approval',
            icon: Icons.send_rounded,
            busy: _busy,
            onPressed: _busy || _type == null || _type!['can_request'] == false ? null : _submit,
          ),
        ],
      ),
    );
  }
}
