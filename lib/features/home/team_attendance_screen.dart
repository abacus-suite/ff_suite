import 'package:flutter/material.dart';

import '../../core/geo.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/skeleton.dart';
import '../team/timeline_screen.dart';

/// The page behind a tap on Present / Late / Absent / On Leave: the people in that box with their
/// check-in time, place and a call button. The calendar beside the title picks another day.
class TeamAttendanceScreen extends StatefulWidget {
  const TeamAttendanceScreen({super.key, required this.members, required this.initialTab});

  /// Today's people, as the dashboard already loaded them.
  final List<Map<String, dynamic>> members;
  final String initialTab; // present | late | absent | leave

  @override
  State<TeamAttendanceScreen> createState() => _TeamAttendanceScreenState();
}

class _TeamAttendanceScreenState extends State<TeamAttendanceScreen> {
  static const _tabs = [('present', 'Present'), ('late', 'Late'), ('absent', 'Absent'), ('leave', 'On Leave')];

  late String _tab = widget.initialTab;
  late List<Map<String, dynamic>> _members = widget.members;
  DateTime _day = DateTime.now();
  bool _loading = false;
  String? _error;

  bool get _isToday {
    final n = DateTime.now();
    return _day.year == n.year && _day.month == n.month && _day.day == n.day;
  }

  String _iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String get _dayLabel => _isToday ? 'Today' : '${_day.day}/${_day.month}/${_day.year}';

  bool _inTab(Map<String, dynamic> m, String tab) => switch (tab) {
        'present' => m['state'] == 'in' || m['state'] == 'out',
        'late' => (m['late_minutes'] as num? ?? 0) > 0,
        'absent' => m['state'] == 'absent',
        _ => m['state'] == 'leave',
      };

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    setState(() {
      _day = picked;
      _loading = true;
      _error = null;
    });
    if (_isToday) {
      setState(() {
        _members = widget.members;
        _loading = false;
      });
      return;
    }
    try {
      final data = await Services.api.get('/api/v1/team/dashboard', query: {'period': 'today', 'date': _iso(picked)}) as Map<String, dynamic>;
      if (mounted) setState(() => _members = ((data['members'] as List?) ?? []).cast<Map<String, dynamic>>());
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static String _time(Object? v) {
    if (v == null) return '';
    final s = '$v';
    final t = DateTime.tryParse(s);
    if (t == null) return s;
    final l = t.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  String? _phone(Map<String, dynamic> m) {
    final e = (m['employee'] as Map).cast<String, dynamic>();
    for (final v in [e['phone'], e['mobile'], e['mobile_phone'], m['phone'], m['mobile']]) {
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }

  String _detail(Map<String, dynamic> m) {
    final inAt = _time(m['check_in'] ?? m['punched_in_at'] ?? m['first_in']);
    final outAt = _time(m['check_out'] ?? m['punched_out_at']);
    final place = (m['at_client'] as Map?)?['name'] ?? m['location'];
    final parts = <String>[
      if (m['state'] == 'leave') 'On leave' else if (m['state'] == 'absent') 'Not in',
      if (inAt.isNotEmpty) 'In $inAt',
      if (outAt.isNotEmpty) 'Out $outAt',
      if (place != null && '$place'.isNotEmpty) '$place',
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final rows = _members.where((m) => _inTab(m, _tab)).toList();
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${_tabs.firstWhere((t) => t.$1 == _tab).$2} (${rows.length})', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          Text('$_dayLabel · tap a name for his day', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
        ]),
        actions: [IconButton(onPressed: _pickDay, icon: const Icon(Icons.calendar_month_rounded))],
      ),
      body: Column(children: [
        SizedBox(
          height: 48,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), children: [
            for (final (key, label) in _tabs)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text('$label ${_members.where((m) => _inTab(m, key)).length}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  selected: _tab == key,
                  onSelected: (_) => setState(() => _tab = key),
                ),
              ),
          ]),
        ),
        Expanded(
          child: _loading
              ? const LoadingView()
              : _error != null
                  ? ErrorView(message: _error!, onRetry: _pickDay)
                  : rows.isEmpty
                      ? const Center(child: Text('Nobody here.', style: TextStyle(color: AppColors.muted)))
                      : ListView(padding: const EdgeInsets.fromLTRB(12, 4, 12, 24), children: [
                          for (final m in rows) _row(m),
                        ]),
        ),
      ]),
    );
  }

  Widget _row(Map<String, dynamic> m) {
    final e = (m['employee'] as Map).cast<String, dynamic>();
    final name = '${e['name']}';
    final phone = _phone(m);
    final late = (m['late_minutes'] as num? ?? 0) > 0;
    final initials = name.trim().split(RegExp(r'\s+')).take(2).map((w) => w.isEmpty ? '' : w[0].toUpperCase()).join();
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => TimelineScreen(employeeId: e['id'] as int, employeeName: name))),
        leading: CircleAvatar(
          backgroundColor: AppColors.primary.withValues(alpha: 0.1),
          child: Text(initials, style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.primary, fontSize: 13)),
        ),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(_detail(m), style: const TextStyle(fontSize: 12)),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (late)
            Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(10)),
              child: const Text('Late', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.warning)),
            ),
          IconButton.filledTonal(
            onPressed: phone == null ? null : () => callPhone(phone),
            icon: const Icon(Icons.call_rounded, size: 18),
          ),
        ]),
      ),
    );
  }
}
