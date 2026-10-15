import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../leaves/leaves_screen.dart';
import 'regularisation_screen.dart';

const _statusStyle = <String, (String, Color)>{
  'present': ('Present', Colors.green),
  'late': ('Late', Colors.orange),
  'half_day': ('Half Day', Colors.amber),
  'absent': ('Absent', Colors.red),
  'week_off': ('Week Off', Colors.blueGrey),
  'holiday': ('Holiday', Colors.purple),
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
      appBar: AppBar(title: const Text('My Attendance')),
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
        const SizedBox(height: 16),
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
        // Below the calendar there are only two ways on.
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const RegularisationScreen())),
                icon: const Icon(Icons.edit_calendar_rounded),
                label: const Text('Attendance Correction'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () =>
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LeavesScreen())),
                icon: const Icon(Icons.beach_access_rounded),
                label: const Text('My Leaves'),
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
        child: Text('$number'),
      ),
      ),
    );
  }
}

String _longDate(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${days[d.weekday - 1]}, ${d.day.toString().padLeft(2, '0')} ${months[d.month - 1]}';
}
