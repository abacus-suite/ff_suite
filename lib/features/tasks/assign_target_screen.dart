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
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.75),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: AppColors.purple.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.group_add_rounded, color: AppColors.purple, size: 20),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Assign to Team Members', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
                            SizedBox(height: 1),
                            Text('Select employees to receive this target',
                                style: TextStyle(color: AppColors.muted, fontSize: 12)),
                          ],
                        ),
                      ),
                      if (_team.isNotEmpty)
                        TextButton(
                          onPressed: () {
                            set(() {
                              if (chosen.length == _team.length) {
                                chosen.clear();
                              } else {
                                chosen.addAll(_team.map((m) => m['id'] as int));
                              }
                            });
                          },
                          child: Text(chosen.length == _team.length ? 'Clear all' : 'Select all'),
                        ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    shrinkWrap: true,
                    children: [
                      for (final m in _team)
                        CheckboxListTile(
                          value: chosen.contains(m['id']),
                          activeColor: AppColors.purple,
                          secondary: CircleAvatar(
                            backgroundColor: AppColors.purple.withValues(alpha: 0.14),
                            child: Text(
                              '${m['name']}'.isNotEmpty ? '${m['name']}'[0].toUpperCase() : '?',
                              style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.purple),
                            ),
                          ),
                          title: Text('${m['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                          onChanged: (v) =>
                              set(() => v == true ? chosen.add(m['id'] as int) : chosen.remove(m['id'])),
                        ),
                      if (_team.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(
                            child: Text('No team members found.', style: TextStyle(color: AppColors.muted)),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: GradientButton(
                    label: 'Done (${chosen.length} selected)',
                    icon: Icons.check_circle_rounded,
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ),
              ],
            ),
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
    // One request per group of people with the same numbers, in the shape the server already takes:
    // {employee_ids, period: month|week, week?, month: first of the month, bottles, outlets}.
    final groups = <({List<int> ids, num bottles, num outlets})>[];
    if (_same) {
      final b = n(_bottles);
      final o = n(_outlets);
      if (b == null || b <= 0 || o == null || o <= 0) return showSnack(context, 'Enter the number of bottles and of outlets.');
      groups.add((ids: _picked.toList(), bottles: b, outlets: o));
    } else {
      for (final id in _picked) {
        final b = n(_eachBottles[id] ??= TextEditingController());
        final o = n(_eachOutlets[id] ??= TextEditingController());
        if (b == null || b <= 0 || o == null || o <= 0) return showSnack(context, 'Fill in both targets for ${_name(id)}.');
        groups.add((ids: [id], bottles: b, outlets: o));
      }
    }
    setState(() => _busy = true);
    var saved = 0;
    try {
      for (final g in groups) {
        await Services.api.post('/api/v1/targets/assign', {
          'employee_ids': g.ids,
          'period': _weekly ? 'week' : 'month',
          if (_weekly) 'week': _week,
          'month': fmtDate(_month),
          'bottles': g.bottles,
          'outlets': g.outlets,
        });
        saved += g.ids.length;
      }
      if (!mounted) return;
      showSnack(context, 'Target assigned');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        // Some people may already have theirs if the targets were sent one by one.
        showProblem(context, saved == 0 ? e.toString() : '$saved of ${_picked.length} people got their target before this failed: $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _card({required String title, required IconData icon, required List<Widget> children, Widget? trailing}) {
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
              Icon(icon, size: 18, color: AppColors.purple),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
              if (trailing != null) ...[
                const Spacer(),
                trailing,
              ],
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Widget _targetField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required Color iconColor,
    required String suffix,
  }) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        suffixText: suffix,
        prefixIcon: Icon(icon, color: iconColor),
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
          borderSide: const BorderSide(color: AppColors.purple, width: 1.5),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Assign Target', style: TextStyle(fontWeight: FontWeight.w900))),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: GradientButton(
            label: 'Assign target',
            icon: Icons.check_circle_rounded,
            busy: _busy,
            onPressed: _save,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          // Header Banner
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.purple.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.purple.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.track_changes_rounded, color: AppColors.purple, size: 22),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Performance Targets', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                      SizedBox(height: 2),
                      Text('Set bottle volume and outlet goals for your team',
                          style: TextStyle(fontSize: 12, color: AppColors.muted)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Card 1: Team Members
          _card(
            title: 'Team Members',
            icon: Icons.people_alt_rounded,
            trailing: _picked.isNotEmpty
                ? TextButton.icon(
                    icon: const Icon(Icons.edit_rounded, size: 16),
                    label: const Text('Edit'),
                    onPressed: _pickPeople,
                  )
                : null,
            children: [
              if (_picked.isEmpty)
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: _pickPeople,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.person_add_rounded, color: AppColors.purple, size: 20),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Choose Team Members *',
                                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                              SizedBox(height: 2),
                              Text('Tap to select who receives this target',
                                  style: TextStyle(fontSize: 12, color: AppColors.muted)),
                            ],
                          ),
                        ),
                        Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.muted),
                      ],
                    ),
                  ),
                )
              else ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final id in _picked)
                      Chip(
                        backgroundColor: AppColors.purple.withValues(alpha: 0.08),
                        side: BorderSide(color: AppColors.purple.withValues(alpha: 0.2)),
                        avatar: CircleAvatar(
                          backgroundColor: AppColors.purple.withValues(alpha: 0.2),
                          child: Text(
                            _name(id).isNotEmpty ? _name(id)[0].toUpperCase() : '?',
                            style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.purple),
                          ),
                        ),
                        label: Text(_name(id), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                        deleteIcon: const Icon(Icons.close_rounded, size: 16),
                        onDeleted: () => setState(() => _picked.remove(id)),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${_picked.length} team member${_picked.length == 1 ? '' : 's'} selected',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w600),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),

          // Card 2: Period
          _card(
            title: 'Target Period',
            icon: Icons.calendar_month_rounded,
            children: [
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Monthly'), icon: Icon(Icons.calendar_month_rounded, size: 18)),
                    ButtonSegment(value: true, label: Text('Weekly'), icon: Icon(Icons.view_week_rounded, size: 18)),
                  ],
                  selected: {_weekly},
                  onSelectionChanged: (v) => setState(() => _weekly = v.first),
                ),
              ),
              const SizedBox(height: 12),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _pickMonth,
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
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppColors.purple.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.event_rounded, color: AppColors.purple, size: 18),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Month', style: TextStyle(fontSize: 11.5, color: AppColors.muted)),
                            const SizedBox(height: 1),
                            Text(
                              '${_months[_month.month - 1]} ${_month.year}',
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: _pickMonth,
                        child: const Text('Change'),
                      ),
                    ],
                  ),
                ),
              ),
              if (_weekly) ...[
                const SizedBox(height: 12),
                const Text('Select Week', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (var w = 1; w <= 4; w++)
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(right: w == 4 ? 0 : 8),
                          child: ChoiceChip(
                            label: Center(child: Text('W$w')),
                            selected: _week == w,
                            selectedColor: AppColors.purple.withValues(alpha: 0.18),
                            onSelected: (_) => setState(() => _week = w),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),

          // Card 3: Target Goals
          _card(
            title: 'Target Goals',
            icon: Icons.flag_rounded,
            children: [
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _same,
                  onChanged: (v) => setState(() => _same = v),
                  title: const Text('Same target for all members',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                  subtitle: const Text('Apply identical targets to each selected employee',
                      style: TextStyle(fontSize: 11.5)),
                ),
              ),
              if (_same) ...[
                _targetField(
                  controller: _bottles,
                  label: 'No. of Bottles *',
                  hint: 'e.g. 200',
                  icon: Icons.liquor_rounded,
                  iconColor: AppColors.primary,
                  suffix: 'bottles',
                ),
                const SizedBox(height: 12),
                _targetField(
                  controller: _outlets,
                  label: 'No. of Outlets Onboarded *',
                  hint: 'e.g. 15',
                  icon: Icons.storefront_rounded,
                  iconColor: AppColors.success,
                  suffix: 'outlets',
                ),
              ] else ...[
                if (_picked.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: Text('Select team members above to configure individual targets.',
                          style: TextStyle(color: AppColors.muted, fontSize: 13)),
                    ),
                  )
                else
                  for (final id in _picked)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 14,
                                backgroundColor: AppColors.purple.withValues(alpha: 0.2),
                                child: Text(
                                  _name(id).isNotEmpty ? _name(id)[0].toUpperCase() : '?',
                                  style: const TextStyle(
                                      fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.purple),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(_name(id),
                                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: _targetField(
                                  controller: _eachBottles[id] ??= TextEditingController(),
                                  label: 'Bottles',
                                  hint: '0',
                                  icon: Icons.liquor_rounded,
                                  iconColor: AppColors.primary,
                                  suffix: 'btl',
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _targetField(
                                  controller: _eachOutlets[id] ??= TextEditingController(),
                                  label: 'Outlets',
                                  hint: '0',
                                  icon: Icons.storefront_rounded,
                                  iconColor: AppColors.success,
                                  suffix: 'out',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
