import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

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
      await Services.api.post('/api/v1/leaves/${leave['id']}', const {});
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
    return Scaffold(
      appBar: AppBar(title: const Text('My Time Off')),
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
                      if (types.isNotEmpty)
                        SectionCard(
                          title: 'Balance',
                          child: Column(
                            children: [
                              for (final type in types)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Row(
                                    children: [
                                      Expanded(child: Text('${type['name']}')),
                                      Text(
                                        type['requires_allocation'] == true
                                            ? '${fmtQty(type['remaining'] as num? ?? 0)} left'
                                            : 'No limit',
                                        style: const TextStyle(fontWeight: FontWeight.w700),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 12),
                      SectionCard(
                        title: 'My requests',
                        action: Text(
                          '${(data?['summary'] as Map?)?['waiting'] ?? 0} waiting',
                          style: const TextStyle(color: AixoloColors.muted, fontSize: 12),
                        ),
                        child: Column(
                          children: [
                            for (final leave in leaves) _leaveTile(leave),
                            if (leaves.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 10),
                                child: Text('No time off requested yet.',
                                    style: TextStyle(color: AixoloColors.muted)),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _leaveTile(Map<String, dynamic> leave) {
    final from = asText(leave['from']) ?? '';
    final to = asText(leave['to']) ?? '';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text('${leave['type']['name']}'),
      subtitle: Text([
        from == to ? from : '$from → $to',
        '${fmtQty(leave['days'] as num? ?? 0)} days',
        if (asText(leave['reason']) != null) '${leave['reason']}',
      ].join(' · ')),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          StatusBadge('${leave['state']}', label: '${leave['state_label']}'),
          if (leave['can_cancel'] == true)
            TextButton(
              onPressed: () => _withdraw(leave),
              style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 24)),
              child: const Text('Withdraw', style: TextStyle(fontSize: 11)),
            ),
        ],
      ),
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

  int get _days => _halfDay ? 1 : _to.difference(_from).inDays + 1;

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
    try {
      await Services.api.post('/api/v1/leaves', {
        'type_id': _type!['id'],
        'from': fmtDate(_from),
        'to': fmtDate(_halfDay ? _from : _to),
        'half_day': _halfDay,
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
          if (_type?['requires_allocation'] == true)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('${fmtQty(_type?['remaining'] as num? ?? 0)} days left of this type',
                  style: const TextStyle(color: AixoloColors.muted, fontSize: 12)),
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
          const SizedBox(height: 4),
          TextField(
            controller: _reason,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Reason'),
          ),
          const SizedBox(height: 16),
          Text('$_days day${_days == 1 ? '' : 's'}',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 12),
          GradientButton(
            label: 'Send for approval',
            icon: Icons.send_rounded,
            busy: _busy,
            onPressed: _busy || _type == null ? null : _submit,
          ),
        ],
      ),
    );
  }
}
