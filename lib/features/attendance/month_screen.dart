import 'package:flutter/material.dart';
import '../../widgets/report_download.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../leaves/leaves_screen.dart';
import 'overtime_screen.dart';
import 'regularisation_screen.dart';

const _statusStyle = <String, (String, Color)>{
  'present': ('Present', Colors.green),
  'late': ('Late', Colors.orange),
  'half_day': ('Half Day', Colors.amber),
  'absent': ('Absent', Colors.red),
  'week_off': ('Week Off', Colors.blueGrey),
  'holiday': ('Holiday', Colors.purple),
  'leave': ('Leave', Colors.teal),
  'not_punched': ('Not Punched', Colors.indigo),
  'upcoming': ('Upcoming', Colors.transparent),
};

class MonthScreen extends StatefulWidget {
  const MonthScreen({super.key});

  @override
  State<MonthScreen> createState() => _MonthScreenState();
}

class _MonthScreenState extends State<MonthScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = false;

  /// The status whose days are highlighted and listed under the calendar.
  String? _selected;

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
      final data = await Services.api.get('/api/v1/attendance/month',
          query: {'year': _month.year, 'month': _month.month}) as Map<String, dynamic>;
      setState(() => _data = data);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _shift(int months) {
    setState(() => _month = DateTime(_month.year, _month.month + months));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isCurrent = _month.year == now.year && _month.month == now.month;
    return Scaffold(
      appBar: AppBar(title: const Text('My Attendance'), actions: [const ReportDownloadButton(reportKey: 'attendance', title: 'Attendance')]),
      body: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left)),
              Text('${monthNames[_month.month - 1]} ${_month.year}', style: Theme.of(context).textTheme.titleMedium),
              IconButton(onPressed: isCurrent ? null : () => _shift(1), icon: const Icon(Icons.chevron_right)),
            ],
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null) Padding(padding: const EdgeInsets.all(16), child: Text(_error!)),
          if (_data != null) Expanded(child: _calendar(context, _data!)),
        ],
      ),
    );
  }

  Widget _calendar(BuildContext context, Map<String, dynamic> data) {
    final days = (data['days'] as List).cast<Map<String, dynamic>>();
    final summary = (data['summary'] as Map).cast<String, dynamic>();
    final leading = DateTime(_month.year, _month.month, 1).weekday - 1; // Monday first
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(
          children: const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
              .map((d) => Expanded(child: Center(child: Text(d, style: TextStyle(fontWeight: FontWeight.bold)))))
              .toList(),
        ),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
          children: [
            for (var i = 0; i < leading; i++) const SizedBox.shrink(),
            for (final day in days) _DayCell(day: day, dim: _selected != null && day['status'] != _selected),
          ],
        ),
        const SizedBox(height: 14),
        // The month so far, by the working schedule: hours worked against the hours expected, and the overtime.
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
          child: Row(children: [
            for (final (label, value, tint) in [
              ('Worked', data['worked_hours'], AppColors.primary),
              ('Expected', data['expected_hours'], AppColors.text),
              ('Overtime', data['overtime_hours'], Colors.deepOrange),
            ])
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_hrs(((value as num?) ?? 0).toDouble()),
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: tint)),
                  Text(label, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                ]),
              ),
          ]),
        ),
        const SizedBox(height: 4),
        const Padding(
          padding: EdgeInsets.fromLTRB(2, 2, 2, 6),
          child: Text('This month till today, by your working schedule. Week offs, holidays and leave are not expected.',
              style: TextStyle(fontSize: 11.5, color: AppColors.muted)),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in _statusStyle.entries)
              if (entry.key != 'upcoming' && (summary[entry.key] ?? 0) > 0)
                ChoiceChip(
                  avatar: CircleAvatar(backgroundColor: entry.value.$2, radius: 6),
                  label: Text('${entry.value.$1}: ${summary[entry.key]}'),
                  selected: _selected == entry.key,
                  onSelected: (_) => setState(() => _selected = _selected == entry.key ? null : entry.key),
                ),
          ],
        ),
        if (_selected != null) ...[
          const SizedBox(height: 12),
          for (final day in days.where((d) => d['status'] == _selected))
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(_longDate(day['date'] as String), style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                  (day['first_in'] == null && day['last_out'] == null)
                      ? 'No check-in'
                      : 'In ${fmtTime(day['first_in'])} \u00B7 Out ${fmtTime(day['last_out'])} \u00B7 ${fmtHours(day['worked_hours'] as num?)}',
                ),
                trailing: Text(_statusStyle[_selected]!.$1,
                    style: TextStyle(fontWeight: FontWeight.w800, color: _statusStyle[_selected]!.$2)),
              ),
            ),
        ],
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OvertimeScreen())),
          style: OutlinedButton.styleFrom(fixedSize: const Size.fromHeight(52)),
          icon: const Icon(Icons.more_time_rounded),
          label: const Text('Overtime'),
        ),
        const SizedBox(height: 10),
        // Below the calendar there are only two ways on.
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const RegularisationScreen())),
                style: OutlinedButton.styleFrom(fixedSize: const Size.fromHeight(52), padding: const EdgeInsets.symmetric(horizontal: 10)),
                icon: const Icon(Icons.edit_calendar_rounded),
                label: const FittedBox(fit: BoxFit.scaleDown, child: Text('Attendance Correction', maxLines: 1)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () =>
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LeavesScreen())),
                style: OutlinedButton.styleFrom(fixedSize: const Size.fromHeight(52), padding: const EdgeInsets.symmetric(horizontal: 10)),
                icon: const Icon(Icons.beach_access_rounded),
                label: const FittedBox(fit: BoxFit.scaleDown, child: Text('My Leaves', maxLines: 1)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({required this.day, this.dim = false});

  final Map<String, dynamic> day;

  /// Another status is selected: this day fades back.
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final status = day['status'] as String;
    final style = _statusStyle[status] ?? ('', Colors.grey);
    final number = int.parse((day['date'] as String).substring(8));
    final worked = ((day['worked_hours'] as num?) ?? 0).toDouble();
    final extra = ((day['overtime_hours'] as num?) ?? 0).toDouble();
    return Opacity(
      opacity: dim ? 0.3 : 1,
      child: InkWell(
      onTap: status == 'upcoming'
          ? null
          : () => showSnack(context,
              '${day['date']}: ${style.$1} · In ${fmtTime(day['first_in'])} · Out ${fmtTime(day['last_out'])} · ${fmtHours(day['worked_hours'] as num?)}'),
      child: Container(
        decoration: BoxDecoration(
          color: style.$2.withValues(alpha: status == 'upcoming' ? 0 : 0.2),
          border: Border.all(color: style.$2 == Colors.transparent ? Colors.black12 : style.$2),
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('$number'),
            // The hours worked that day, and what was beyond the working schedule.
            if (worked > 0)
              Text(_hrs(worked), style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, height: 1.1)),
            if (extra > 0)
              Text('+${_hrs(extra)}',
                  style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: Colors.deepOrange, height: 1.1)),
          ]),
        ),
      ),
      ),
    );
  }
}

/// 8.5 -> "8h30", 9 -> "9h", 0.25 -> "15m".
String _hrs(double hours) {
  final minutes = (hours * 60).round();
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '${m}m';
  return m == 0 ? '${h}h' : '${h}h${m.toString().padLeft(2, '0')}';
}

String _longDate(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${days[d.weekday - 1]}, ${d.day.toString().padLeft(2, '0')} ${months[d.month - 1]}';
}
