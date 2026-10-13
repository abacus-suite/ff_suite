import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

/// Team Target: each person against their month or week target, and each person's share of the team's.
num _n(dynamic v) => v is num ? v : num.tryParse('$v') ?? 0;

class TeamTargetScreen extends StatefulWidget {
  const TeamTargetScreen({super.key});

  @override
  State<TeamTargetScreen> createState() => _TeamTargetScreenState();
}

class _TeamTargetScreenState extends State<TeamTargetScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  String _view = 'month';
  String _metric = 'bottles';
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;

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
      final data = await Services.api.get('/api/v1/team/target', query: {
        'month': fmtDate(_month),
        'view': _view,
      }) as Map<String, dynamic>;
      if (mounted) setState(() => _data = data);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _month,
      firstDate: DateTime(2024),
      lastDate: DateTime(DateTime.now().year + 1, 12),
      helpText: 'Choose a day in the month',
    );
    if (picked != null) {
      setState(() => _month = DateTime(picked.year, picked.month));
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final rows = ((data?['rows'] as List?) ?? []).cast<Map<String, dynamic>>();
    final bottles = _metric == 'bottles';
    final teamTarget = ((data?[bottles ? 'bottle_target' : 'outlet_target'] as num?) ?? 0).toInt();
    final teamActual = ((data?[bottles ? 'bottles' : 'outlets'] as num?) ?? 0).toInt();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Team Target'),
        actions: [IconButton(onPressed: _pickMonth, icon: const Icon(Icons.calendar_month_rounded))],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
          children: [
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _view,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Achieved out of', isDense: true),
                  items: const [
                    DropdownMenuItem(value: 'month', child: Text('Month target')),
                    DropdownMenuItem(value: '1', child: Text('Week 1')),
                    DropdownMenuItem(value: '2', child: Text('Week 2')),
                    DropdownMenuItem(value: '3', child: Text('Week 3')),
                    DropdownMenuItem(value: '4', child: Text('Week 4')),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _view = v);
                    _load();
                  },
                ),
              ),
              const SizedBox(width: 10),
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'bottles', label: Text('Bottles')),
                  ButtonSegment(value: 'outlets', label: Text('Outlets')),
                ],
                selected: {_metric},
                onSelectionChanged: (v) => setState(() => _metric = v.first),
              ),
            ]),
            if (_loading) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator(minHeight: 2)),
            if (_error != null) ErrorView(message: _error!, onRetry: _load),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${monthNames[_month.month - 1]} ${_month.year}',
                          style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                      Text('$teamActual of $teamTarget ${bottles ? 'bottles' : 'outlets'}',
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                    ]),
                  ),
                  Text(teamTarget == 0 ? '-' : '${(teamActual * 100 / teamTarget).round()}%',
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 24, color: AppColors.primary)),
                ]),
              ),
            ),
            const SizedBox(height: 6),
            const Text('Ranking', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
            const SizedBox(height: 6),
            for (final (i, r) in rows.indexed)
              Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                    child: Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.primary)),
                  ),
                  title: Text('${(r['employee'] as Map)['name']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(
                      '${r[bottles ? 'bottles' : 'outlets']} / ${r[bottles ? 'bottle_target' : 'outlet_target']}'),
                  trailing: Text('${r[bottles ? 'bottle_percent' : 'outlet_percent']}%',
                      style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.primary)),
                ),
              ),
            if (bottles && teamTarget > 0) ...[
              const SizedBox(height: 12),
              const Text('Contribution to the team target',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
              const SizedBox(height: 4),
              Text('Each % is the person\'s bottles divided by the team target.',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted)),
              const SizedBox(height: 6),
              for (final (i, r) in rows.take(5).indexed)
                Card(
                  child: ListTile(
                    dense: true,
                    leading: Text('${i + 1}.', style: const TextStyle(fontWeight: FontWeight.w800)),
                    title: Text('${(r['employee'] as Map)['name']}'),
                    trailing: Text('${r['share']}%  ·  ${r['bottles']} btl',
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
              if (rows.length > 5)
                Card(
                  child: ListTile(
                    dense: true,
                    leading: const Text('6.', style: TextStyle(fontWeight: FontWeight.w800)),
                    title: Text('Others (${rows.length - 5})'),
                    trailing: Text(
                        '${rows.skip(5).fold<num>(0, (a, r) => a + _n(r['share'])).toStringAsFixed(1)}%  ·  '
                        '${rows.skip(5).fold<num>(0, (a, r) => a + _n(r['bottles']))} btl',
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
