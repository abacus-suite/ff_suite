import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

/// A manager gives the people under them a target for a month or a week of it:
/// bottles sold and outlets onboarded. These feed Team Target on Home.
class AssignTargetScreen extends StatefulWidget {
  const AssignTargetScreen({super.key});

  @override
  State<AssignTargetScreen> createState() => _AssignTargetScreenState();
}

class _AssignTargetScreenState extends State<AssignTargetScreen> {
  static const _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

  List<Map<String, dynamic>> _team = [];
  final Set<int> _picked = {};
  bool _weekly = false;
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  int _week = 1;
  final _bottles = TextEditingController();
  final _outlets = TextEditingController();
  final Map<int, TextEditingController> _eachBottles = {};
  final Map<int, TextEditingController> _eachOutlets = {};
  bool _same = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    Services.api.get('/api/v1/team/members').then((d) {
      if (!mounted) return;
      setState(() => _team = (((d as Map)['members'] as List?) ?? []).cast<Map<String, dynamic>>());
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _bottles.dispose();
    _outlets.dispose();
    for (final c in [..._eachBottles.values, ..._eachOutlets.values]) {
      c.dispose();
    }
    super.dispose();
  }

  String _name(int id) => '${_team.firstWhere((m) => m['id'] == id, orElse: () => {'name': '#$id'})['name']}';

  Future<void> _pickPeople() async {
    final chosen = {..._picked};
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Padding(padding: EdgeInsets.all(8), child: Text('Assign to', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17))),
              Flexible(
                child: ListView(shrinkWrap: true, children: [
                  for (final m in _team)
                    CheckboxListTile(
                      value: chosen.contains(m['id']),
                      title: Text('${m['name']}'),
                      onChanged: (v) => set(() => v == true ? chosen.add(m['id'] as int) : chosen.remove(m['id'])),
                    ),
                  if (_team.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('No team members found.')),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: GradientButton(label: 'Done', onPressed: () => Navigator.pop(ctx)),
              ),
            ]),
          ),
        ),
      ),
    );
    setState(() {
      _picked
        ..clear()
        ..addAll(chosen);
    });
  }

  Future<void> _pickMonth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _month,
      firstDate: DateTime(now.year, now.month),
      lastDate: DateTime(now.year + 1, 12),
      helpText: 'Pick any day in the month',
    );
    if (picked != null) setState(() => _month = DateTime(picked.year, picked.month));
  }

  Future<void> _save() async {
    if (_picked.isEmpty) return showSnack(context, 'Choose who the target is for.');
    num? n(TextEditingController c) => num.tryParse(c.text.trim());
    final rows = <Map<String, dynamic>>[];
    for (final id in _picked) {
      final b = n(_same ? _bottles : (_eachBottles[id] ??= TextEditingController()));
      final o = n(_same ? _outlets : (_eachOutlets[id] ??= TextEditingController()));
      if (b == null || o == null) return showSnack(context, 'Fill in both targets${_same ? '' : ' for ${_name(id)}'}.');
      rows.add({'employee_id': id, 'bottles': b, 'outlets_onboarded': o});
    }
    setState(() => _busy = true);
    try {
      await Services.api.post('/api/v1/targets/assign', {
        'period': _weekly ? 'weekly' : 'monthly',
        'month': '${_month.year}-${_month.month.toString().padLeft(2, '0')}',
        if (_weekly) 'week': _week,
        'targets': rows,
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

  Widget _label(String t, {bool required = false}) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6),
        child: Text(required ? '$t *' : t, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
      );

  Widget _number(TextEditingController c, {String? hint}) => TextField(
        controller: c,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(hintText: hint, filled: true, fillColor: Colors.white),
      );

  Widget _box(Widget child, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
          child: child,
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Assign Target', style: TextStyle(fontWeight: FontWeight.w900))),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: GradientButton(label: 'Assign target', busy: _busy, onPressed: _save),
        ),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
        _label('Assign to', required: true),
        _box(
          Row(children: [
            Expanded(
              child: Text(_picked.isEmpty ? 'Choose employees' : _picked.map(_name).join(', '),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: _picked.isEmpty ? AppColors.muted : AppColors.text)),
            ),
            const Icon(Icons.keyboard_arrow_down_rounded),
          ]),
          _pickPeople,
        ),
        const Padding(padding: EdgeInsets.only(top: 18), child: Text('Period', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15))),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<bool>(
            segments: const [ButtonSegment(value: false, label: Text('Monthly')), ButtonSegment(value: true, label: Text('Weekly'))],
            selected: {_weekly},
            onSelectionChanged: (v) => setState(() => _weekly = v.first),
          ),
        ),
        const SizedBox(height: 10),
        _box(
          Row(children: [
            const Icon(Icons.calendar_month_rounded, size: 20, color: AppColors.primary),
            const SizedBox(width: 10),
            Text('${_months[_month.month - 1]} ${_month.year}'),
          ]),
          _pickMonth,
        ),
        if (_weekly) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 8, children: [
            for (var w = 1; w <= 5; w++) ChoiceChip(label: Text('Week $w'), selected: _week == w, onSelected: (_) => setState(() => _week = w)),
          ]),
        ],
        if (_same) ...[
          _label('No. of bottles', required: true),
          _number(_bottles, hint: 'e.g. 200'),
          _label('No. of outlets onboarded', required: true),
          _number(_outlets, hint: 'e.g. 15'),
        ] else
          for (final id in _picked) ...[
            _label(_name(id)),
            Row(children: [
              Expanded(child: _number(_eachBottles[id] ??= TextEditingController(), hint: 'Bottles')),
              const SizedBox(width: 10),
              Expanded(child: _number(_eachOutlets[id] ??= TextEditingController(), hint: 'Outlets onboarded')),
            ]),
          ],
        const SizedBox(height: 14),
        Row(children: [
          const Expanded(child: Text('Same target for each selected employee', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700))),
          Switch(value: _same, onChanged: (v) => setState(() => _same = v)),
        ]),
      ]),
    );
  }
}
