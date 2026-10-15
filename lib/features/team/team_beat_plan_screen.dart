import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/skeleton.dart';
import '../home/manager_home.dart' show initials;

const _bg = Color(0xFFEEF3FB);
const _blue = Color(0xFF1D4ED8);
const _green = Color(0xFF16A34A);
const _orange = Color(0xFFEA580C);
const _red = Color(0xFFDC2626);

List<Map<String, dynamic>> _rows(dynamic v) => ((v as List?) ?? []).cast<Map<String, dynamic>>();

/// Team Beat Plan: the day's (or week's, or month's) totals, each person, and one person's outlets.
class TeamBeatPlanScreen extends StatefulWidget {
  const TeamBeatPlanScreen({super.key});

  @override
  State<TeamBeatPlanScreen> createState() => _TeamBeatPlanScreenState();
}

class _TeamBeatPlanScreenState extends State<TeamBeatPlanScreen> {
  String _range = 'today';
  DateTime? _custom;
  int? _member;
  String _status = 'all';
  Map<String, dynamic>? _data;
  String? _error;

  (DateTime, DateTime) get _dates {
    final today = DateUtils.dateOnly(DateTime.now());
    if (_custom != null) return (_custom!, _custom!);
    return switch (_range) {
      'week' => (today.subtract(Duration(days: today.weekday - 1)), today),
      'month' => (DateTime(today.year, today.month, 1), today),
      _ => (today, today),
    };
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    final (from, to) = _dates;
    try {
      final d = await Services.api.get('/api/v1/team/beat-plan', query: {
        'start': fmtDate(from),
        'end': fmtDate(to),
        if (_member != null) 'member': _member,
      }) as Map<String, dynamic>;
      if (mounted) setState(() => _data = d);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _custom ?? DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 60)),
    );
    if (picked != null) {
      setState(() => _custom = picked);
      _load();
    }
  }

  Widget _summaryCard(String title, Map<String, dynamic> s) {
    final planned = ((s['planned'] as num?) ?? 0).toInt();
    Widget tile(String label, String key, Color tint, Color bg, {bool first = false}) {
      final v = ((s[key] as num?) ?? 0).toInt();
      return Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Align(
                alignment: Alignment.centerRight,
                child: Text('${first ? 100 : (planned == 0 ? 0 : (v * 100 / planned).round())}%',
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: tint))),
            Text('$v', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
            Text(label, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                  value: first ? 1 : (planned == 0 ? 0 : v / planned),
                  minHeight: 4, color: tint, backgroundColor: tint.withValues(alpha: 0.18)),
            ),
          ]),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.event_note_rounded, color: _blue, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15))),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          tile('Planned', 'planned', _blue, const Color(0xFFDBEAFE), first: true),
          tile('Visited', 'visited', _green, const Color(0xFFDCFCE7)),
          tile('Pending', 'pending', _orange, const Color(0xFFFFEDD5)),
          tile('Cancelled', 'cancelled', _red, const Color(0xFFFEE2E2)),
        ]),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final members = _rows(d?['members']);
    final people = _rows(d?['people']);
    final outlets = _rows(d?['outlets']);
    final summary = (d?['summary'] as Map?)?.cast<String, dynamic>() ?? const {};
    Map<String, dynamic>? picked;
    for (final m in members) {
      if (m['id'] == _member) picked = m;
    }
    final outletsShown = outlets.where((o) => _status == 'all' || o['status'] == _status).toList();
    final peopleShown = people.where((p) {
      if (_status == 'all') return true;
      final n = ((p[_status] as num?) ?? 0).toInt();
      return n > 0;
    }).toList();
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Team Beat Plan', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          Text(_member == null ? 'Opened from the summary' : 'Employee selected',
              style: const TextStyle(fontSize: 11.5, color: AppColors.muted, fontWeight: FontWeight.w500)),
        ]),
      ),
      body: _error != null
          ? ErrorView(message: _error!, onRetry: _load)
          : d == null
              ? const LoadingView()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: [
                        InkWell(
                          onTap: _pickDate,
                          child: Container(
                            width: 38,
                            height: 38,
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              color: _custom != null ? const Color(0xFFDBEAFE) : Colors.white,
                              borderRadius: BorderRadius.circular(19),
                              border: Border.all(color: _custom != null ? _blue : const Color(0xFFD5DEEE)),
                            ),
                            child: const Icon(Icons.calendar_month_rounded, size: 19, color: _blue),
                          ),
                        ),
                        for (final (k, label) in [('today', 'Today'), ('week', 'This week'), ('month', 'This month')])
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(_custom == null && _range == k ? '✓ $label' : label,
                                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                              selected: _custom == null && _range == k,
                              showCheckmark: false,
                              selectedColor: const Color(0xFFDBEAFE),
                              onSelected: (_) {
                                setState(() {
                                  _range = k;
                                  _custom = null;
                                });
                                _load();
                              },
                            ),
                          ),
                      ]),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<int?>(
                      initialValue: _member,
                      isExpanded: true,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      items: [
                        const DropdownMenuItem<int?>(value: null, child: Text('All employees')),
                        for (final m in members) DropdownMenuItem<int?>(value: m['id'] as int, child: Text('${m['name']}')),
                      ],
                      onChanged: (v) {
                        setState(() {
                          _member = v;
                          _data = null;
                        });
                        _load();
                      },
                    ),
                    const SizedBox(height: 12),
                    _summaryCard(picked != null ? '${picked['name']}' : 'All employees', summary),
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: [
                        for (final (k, label) in [
                          ('all', 'All'), ('visited', 'Visited'), ('pending', 'Pending'), ('cancelled', 'Cancelled')
                        ])
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                              selected: _status == k,
                              showCheckmark: false,
                              selectedColor: const Color(0xFFDBEAFE),
                              onSelected: (_) => setState(() => _status = k),
                            ),
                          ),
                      ]),
                    ),
                    const SizedBox(height: 10),
                    if (_member == null)
                      for (final p in peopleShown) _personCard(p)
                    else
                      for (final o in outletsShown) _outletCard(o),
                    if ((_member == null ? peopleShown : outletsShown).isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(30),
                        child: Center(child: Text('Nothing here.', style: TextStyle(color: AppColors.muted))),
                      ),
                  ]),
                ),
    );
  }

  Widget _personCard(Map<String, dynamic> p) {
    final who = (p['employee'] as Map).cast<String, dynamic>();
    final planned = ((p['planned'] as num?) ?? 0).toInt();
    final visited = ((p['visited'] as num?) ?? 0).toInt();
    final ratio = planned == 0 ? 0.0 : (visited / planned).clamp(0.0, 1.0);
    return InkWell(
      onTap: () {
        setState(() {
          _member = who['id'] as int;
          _data = null;
        });
        _load();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          CircleAvatar(
            backgroundColor: const Color(0xFFDBEAFE),
            child: Text(initials('${who['name']}'),
                style: const TextStyle(fontWeight: FontWeight.w900, color: _blue, fontSize: 13)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${who['name']}', style: const TextStyle(fontWeight: FontWeight.w800)),
              Text('${p['territory'] ?? p['job'] ?? ''}', style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                    value: ratio, minHeight: 5, color: _orange, backgroundColor: AppColors.border.withValues(alpha: 0.5)),
              ),
            ]),
          ),
          const SizedBox(width: 12),
          Text('$visited/$planned visits', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
        ]),
      ),
    );
  }

  Widget _outletCard(Map<String, dynamic> o) {
    final status = '${o['status']}';
    final tint = status == 'visited' ? _green : status == 'cancelled' ? _red : _orange;
    final label = status == 'visited' ? 'Visited' : status == 'cancelled' ? 'Cancelled' : 'Pending';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: tint, width: 4)),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${(o['outlet'] as Map)['name']}', style: const TextStyle(fontWeight: FontWeight.w800)),
            Text(
                status == 'visited' && o['visited_at'] != null
                    ? 'Visited ${fmtTime(o['visited_at'])}'
                    : status == 'cancelled' ? 'Cancelled' : 'Not visited yet',
                style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          ]),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(14)),
          child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11.5)),
        ),
      ]),
    );
  }
}
