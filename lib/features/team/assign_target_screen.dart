import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

/// Assign Target: bottles and outlets onboarded, to one or more people, for a month or a week of it.
class AssignTargetScreen extends StatefulWidget {
  const AssignTargetScreen({super.key});

  @override
  State<AssignTargetScreen> createState() => _AssignTargetScreenState();
}

class _AssignTargetScreenState extends State<AssignTargetScreen> {
  List<Map<String, dynamic>> _members = [];
  final Set<int> _chosen = {};
  String _period = 'month';
  int _week = 1;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  final _bottles = TextEditingController();
  final _outlets = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  @override
  void dispose() {
    _bottles.dispose();
    _outlets.dispose();
    super.dispose();
  }

  Future<void> _loadMembers() async {
    try {
      final data = await Services.api.get('/api/v1/team/members') as Map<String, dynamic>;
      if (mounted) setState(() => _members = ((data['members'] as List?) ?? []).cast<Map<String, dynamic>>());
    } catch (_) {}
  }

  Future<void> _save() async {
    final bottles = int.tryParse(_bottles.text.trim()) ?? 0;
    final outlets = int.tryParse(_outlets.text.trim()) ?? 0;
    if (_chosen.isEmpty) {
      showProblem(context, 'Choose at least one person.');
      return;
    }
    if (bottles <= 0 || outlets <= 0) {
      showProblem(context, 'Enter the number of bottles and of outlets.');
      return;
    }
    setState(() => _busy = true);
    try {
      await Services.api.post('/api/v1/targets/assign', {
        'employee_ids': _chosen.toList(),
        'period': _period,
        if (_period == 'week') 'week': _week,
        'month': fmtDate(_month),
        'bottles': bottles,
        'outlets': outlets,
      });
      if (!mounted) return;
      showSnack(context, 'Target assigned');
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
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Assign Target')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Assign to *', style: TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 6, children: [
                  for (final m in _members)
                    FilterChip(
                      label: Text('${m['name']}'),
                      selected: _chosen.contains(m['id']),
                      onSelected: (v) => setState(() => v ? _chosen.add(m['id'] as int) : _chosen.remove(m['id'])),
                    ),
                ]),
              ]),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Period', style: TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'month', label: Text('Monthly')),
                    ButtonSegment(value: 'week', label: Text('Weekly')),
                  ],
                  selected: {_period},
                  onSelectionChanged: (v) => setState(() => _period = v.first),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _month,
                          firstDate: DateTime(2024),
                          lastDate: DateTime(DateTime.now().year + 1, 12),
                          helpText: 'Choose a day in the month',
                        );
                        if (picked != null) setState(() => _month = DateTime(picked.year, picked.month));
                      },
                      icon: const Icon(Icons.calendar_month_rounded),
                      label: Text('${monthNames[_month.month - 1]} ${_month.year}'),
                    ),
                  ),
                  if (_period == 'week') ...[
                    const SizedBox(width: 10),
                    DropdownButton<int>(
                      value: _week,
                      items: [for (var w = 1; w <= 4; w++) DropdownMenuItem(value: w, child: Text('Week $w'))],
                      onChanged: (v) => setState(() => _week = v ?? 1),
                    ),
                  ],
                ]),
              ]),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(children: [
                TextField(
                  controller: _bottles,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'No. of bottles *'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _outlets,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'No. of outlets onboarded *'),
                ),
                const SizedBox(height: 6),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('The same target is given to each selected person.',
                      style: TextStyle(fontSize: 12, color: AppColors.muted)),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 6),
          GradientButton(label: 'Assign target', icon: Icons.flag_rounded, busy: _busy, onPressed: _busy ? null : _save),
        ],
      ),
    );
  }
}
