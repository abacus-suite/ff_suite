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

  /// A specific day selected on the calendar for details / correction.
  Map<String, dynamic>? _selectedDay;

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
      appBar: AppBar(
        title: const Text('My Attendance'),
        actions: [
          IconButton(
            tooltip: 'Correction history',
            icon: const Icon(Icons.history_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const RegularisationScreen()),
            ),
          ),
          const ReportDownloadButton(reportKey: 'attendance', title: 'Attendance'),
        ],
      ),
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

  Future<void> _openCorrection([DateTime? date]) async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => RegularisationForm(initialDate: date)),
    );
    if (created == true) _load();
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
            for (final day in days)
              _DayCell(
                day: day,
                dim: _selected != null && day['status'] != _selected,
                isSelected: _selectedDay?['date'] == day['date'],
                onTap: () => setState(() => _selectedDay = _selectedDay?['date'] == day['date'] ? null : day),
              ),
          ],
        ),
        if (_selectedDay != null) ...[
          const SizedBox(height: 10),
          Card(
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: AppColors.primary, width: 1.5),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _longDate(_selectedDay!['date'] as String),
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                        decoration: BoxDecoration(
                          color: (_statusStyle[_selectedDay!['status']]?.$2 ?? Colors.grey).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _statusStyle[_selectedDay!['status']]?.$1 ?? '${_selectedDay!['status']}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _statusStyle[_selectedDay!['status']]?.$2 ?? Colors.grey,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    (_selectedDay!['first_in'] == null && _selectedDay!['last_out'] == null)
                        ? 'No check-in recorded'
                        : 'In: ${fmtTime(_selectedDay!['first_in'])} · Out: ${fmtTime(_selectedDay!['last_out'])} · Worked: ${fmtHours(_selectedDay!['worked_hours'] as num?)}',
                    style: const TextStyle(fontSize: 13, color: AppColors.muted),
                  ),
                  const SizedBox(height: 10),
                  Builder(builder: (_) {
                    final dayDate = DateTime.tryParse('${_selectedDay!['date']}');
                    final now = DateTime.now();
                    final todayDate = DateTime(now.year, now.month, now.day);
                    final isFuture = dayDate != null && DateTime(dayDate.year, dayDate.month, dayDate.day).isAfter(todayDate);
                    final hasPending = _selectedDay!['has_pending'] == true;

                    if (isFuture) {
                      return Container(
                        margin: const EdgeInsets.only(top: 10),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.muted.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.info_outline_rounded, size: 16, color: AppColors.muted),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Attendance correction is not available for future dates.',
                                style: TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    if (hasPending) {
                      return Container(
                        margin: const EdgeInsets.only(top: 10),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.amber.shade700.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.hourglass_top_rounded, size: 18, color: Colors.amber.shade800),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Correction request already pending for this day. Please wait until approved or rejected.',
                                style: TextStyle(fontSize: 12, color: Color(0xFF78350F), fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    return Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: FilledButton.icon(
                        onPressed: () => _openCorrection(dayDate),
                        icon: const Icon(Icons.edit_calendar_rounded, size: 18),
                        label: Text('Correct ${(_selectedDay!['date'] as String).substring(5)} Attendance'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(42),
                          backgroundColor: AppColors.primary,
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        ],
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
        // Below the calendar: hide Attendance Correction if a day is already selected above
        Row(
          children: [
            if (_selectedDay == null) ...[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const RegularisationScreen()),
                  ),
                  style: OutlinedButton.styleFrom(fixedSize: const Size.fromHeight(52), padding: const EdgeInsets.symmetric(horizontal: 10)),
                  icon: const Icon(Icons.history_rounded),
                  label: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'Attendance Correction',
                      maxLines: 1,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
            ],
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
  const _DayCell({
    required this.day,
    this.dim = false,
    this.isSelected = false,
    this.onTap,
  });

  final Map<String, dynamic> day;

  /// Another status is selected: this day fades back.
  final bool dim;

  /// Selected for details / correction.
  final bool isSelected;

  final VoidCallback? onTap;

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
      onTap: status == 'upcoming' ? null : onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          color: style.$2.withValues(alpha: status == 'upcoming' ? 0 : 0.2),
          border: Border.all(
            color: isSelected
                ? AppColors.primary
                : (style.$2 == Colors.transparent ? Colors.black12 : style.$2),
            width: isSelected ? 2.5 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.35),
                    blurRadius: 4,
                    spreadRadius: 1,
                  )
                ]
              : null,
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
