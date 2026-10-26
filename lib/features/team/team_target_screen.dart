import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

/// Team Target: each person against their month or week target, and each person's share of the team's.
num _n(dynamic v) => v is num ? v : num.tryParse('$v') ?? 0;

String _nameOf(Map<String, dynamic> r) {
  final e = r['employee'];
  return asText(e is Map ? e['name'] : (r['employee_name'] ?? r['name'])) ?? '—';
}

class TeamTargetScreen extends StatefulWidget {
  const TeamTargetScreen({super.key});

  @override
  State<TeamTargetScreen> createState() => _TeamTargetScreenState();
}

class _TeamTargetScreenState extends State<TeamTargetScreen> {
  static const _blue = Color(0xFF1D4ED8);

  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  /// 'month' (the month's target) or 'week' (one of Week 1 to 4).
  String _kind = 'month';
  int _week = 1;
  String _metric = 'bottles';
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;

  String get _view => _kind == 'month' ? 'month' : '$_week';

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

  /// Green from 90%, orange from 50%, red below.
  Color _tone(num percent) => percent >= 90 ? const Color(0xFF16A34A) : (percent >= 50 ? const Color(0xFFF59E0B) : const Color(0xFFDC2626));

  Widget _bar(num fraction, Color colour, {double height = 7}) => ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LinearProgressIndicator(
          value: fraction.clamp(0, 1).toDouble(),
          minHeight: height,
          color: colour,
          backgroundColor: const Color(0xFFE5EAF3),
        ),
      );

  Widget _card(Widget child) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final rows = ((data?['rows'] as List?) ?? []).cast<Map<String, dynamic>>();
    final bottles = _metric == 'bottles';
    final unit = bottles ? 'btl' : 'outlets';
    final span = _kind == 'month' ? 'Month' : 'Week $_week';

    num actualOf(Map<String, dynamic> r) => _n(r[bottles ? 'bottles' : 'outlets']);
    num targetOf(Map<String, dynamic> r) => _n(r[bottles ? 'bottle_target' : 'outlet_target']);
    // Team totals from the server; if it leaves them out, add up everyone's own figures.
    final sentTarget = _n(data?[bottles ? 'bottle_target' : 'outlet_target']);
    final sentActual = _n(data?[bottles ? 'bottles' : 'outlets']);
    final teamTarget = (sentTarget > 0 ? sentTarget : rows.fold<num>(0, (a, r) => a + targetOf(r))).round();
    final teamActual = (sentActual > 0 ? sentActual : rows.fold<num>(0, (a, r) => a + actualOf(r))).round();
    final teamPercent = teamTarget == 0 ? 0 : teamActual * 100 / teamTarget;
    num shareOf(Map<String, dynamic> r) => teamTarget == 0 ? 0 : actualOf(r) * 100 / teamTarget;
    num percentOf(Map<String, dynamic> r) => targetOf(r) == 0 ? 0 : actualOf(r) * 100 / targetOf(r);

    // Ranking: each person against their own target, best first (ties go to whoever sold more).
    final ranked = [...rows]..sort((a, b) {
        final byPercent = percentOf(b).compareTo(percentOf(a));
        return byPercent != 0 ? byPercent : actualOf(b).compareTo(actualOf(a));
      });
    // Contribution: biggest share of the team target first.
    final byShare = [...rows]..sort((a, b) => actualOf(b).compareTo(actualOf(a)));
    final top = byShare.take(5).toList();
    final others = byShare.skip(5).toList();
    final othersShare = others.fold<num>(0, (a, r) => a + shareOf(r));
    final othersActual = others.fold<num>(0, (a, r) => a + actualOf(r));
    final peakShare = [for (final r in rows) shareOf(r), othersShare].fold<num>(0, (a, b) => b > a ? b : a);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Team Target', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 19)),
          Text('By employee', style: const TextStyle(fontSize: 11.5, color: AppColors.muted, fontWeight: FontWeight.w500)),
        ]),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
          children: [
            Row(children: [
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _pickMonth,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
                  child: const Icon(Icons.calendar_month_rounded, color: AppColors.muted),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _kind,
                      isExpanded: true,
                      icon: const Icon(Icons.keyboard_arrow_down_rounded, color: _blue),
                      selectedItemBuilder: (_) => [
                        for (final label in const ['Month target', 'Week target'])
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text('Achieved out of: $label',
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: _blue)),
                          ),
                      ],
                      items: const [
                        DropdownMenuItem(value: 'month', child: Text('Month target')),
                        DropdownMenuItem(value: 'week', child: Text('Week target')),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _kind = v);
                        _load();
                      },
                    ),
                  ),
                ),
              ),
            ]),
            if (_kind == 'week') ...[
              const SizedBox(height: 10),
              Wrap(spacing: 8, children: [
                for (var w = 1; w <= 4; w++)
                  ChoiceChip(
                    label: Text('Week $w', style: const TextStyle(fontWeight: FontWeight.w700)),
                    selected: _week == w,
                    onSelected: (_) {
                      setState(() => _week = w);
                      _load();
                    },
                  ),
              ]),
            ],
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<String>(
                showSelectedIcon: true,
                segments: const [
                  ButtonSegment(value: 'bottles', label: Text('No. of bottles')),
                  ButtonSegment(value: 'outlets', label: Text('Outlets onboarded')),
                ],
                selected: {_metric},
                onSelectionChanged: (v) => setState(() => _metric = v.first),
              ),
            ),
            if (_loading) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator(minHeight: 2)),
            if (_error != null) ErrorView(message: _error!, onRetry: _load),
            const SizedBox(height: 12),
            _card(Column(children: [
              if (rows.isEmpty && !_loading && _error == null)
                const Padding(padding: EdgeInsets.all(18), child: Text('No targets set for this period.', style: TextStyle(color: AppColors.muted))),
              for (final (i, r) in ranked.indexed)
                Builder(builder: (_) {
                  final percent = percentOf(r);
                  final colour = _tone(percent);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(children: [
                      Row(children: [
                        Expanded(
                          flex: 5,
                          child: Text('${i + 1}. ${_nameOf(r)}',
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text('${percent.round()}%', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5, color: colour)),
                        ),
                        Text('${actualOf(r).round()} / ${targetOf(r).round()}',
                            style: const TextStyle(fontSize: 11.5, color: AppColors.muted, fontWeight: FontWeight.w600)),
                      ]),
                      const SizedBox(height: 4),
                      _bar(percent / 100, colour),
                    ]),
                  );
                }),
            ])),
            if (rows.isNotEmpty && teamTarget > 0) ...[
              _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Contribution to team target – $span', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 10),
                  child: Text(
                      'Team ${_kind == 'month' ? 'month' : 'week'} target $teamTarget ${bottles ? 'bottles' : 'outlets'} · team achieved ${teamPercent.round()}%',
                      style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                ),
                for (final (i, r) in top.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(children: [
                      Row(children: [
                        Expanded(
                          flex: 5,
                          child: Text('${i + 1}. ${_nameOf(r)}',
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text('${shareOf(r).toStringAsFixed(1)}%', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5, color: _blue)),
                        ),
                        Text('${actualOf(r).round()} $unit', style: const TextStyle(fontSize: 11.5, color: AppColors.muted, fontWeight: FontWeight.w600)),
                      ]),
                      const SizedBox(height: 4),
                      _bar(peakShare == 0 ? 0 : shareOf(r) / peakShare, _blue, height: 6),
                    ]),
                  ),
                if (others.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(children: [
                      Row(children: [
                        Expanded(
                          flex: 5,
                          child: Text('${top.length + 1}. Others (${others.length})',
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text('${othersShare.toStringAsFixed(1)}%', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5, color: _blue)),
                        ),
                        Text('${othersActual.round()} $unit', style: const TextStyle(fontSize: 11.5, color: AppColors.muted, fontWeight: FontWeight.w600)),
                      ]),
                      const SizedBox(height: 4),
                      _bar(peakShare == 0 ? 0 : othersShare / peakShare, const Color(0xFF94A3B8), height: 6),
                    ]),
                  ),
              ])),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                    'Each % = employee\'s ${bottles ? 'bottles' : 'outlets'} ÷ team target. Together = ${teamPercent.round()}%.',
                    style: const TextStyle(fontSize: 11.5, fontStyle: FontStyle.italic, color: AppColors.muted)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
