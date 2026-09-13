import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/services.dart';

const _statusStyle = <String, (String, Color)>{
  'present': ('Present', Colors.green),
  'late': ('Late', Colors.orange),
  'half_day': ('Half Day', Colors.amber),
  'absent': ('Absent', Colors.red),
  'week_off': ('Week Off', Colors.blueGrey),
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
            for (final day in days) _DayCell(day: day),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in _statusStyle.entries)
              if (entry.key != 'upcoming' && (summary[entry.key] ?? 0) > 0)
                Chip(
                  avatar: CircleAvatar(backgroundColor: entry.value.$2, radius: 6),
                  label: Text('${entry.value.$1}: ${summary[entry.key]}'),
                ),
          ],
        ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({required this.day});

  final Map<String, dynamic> day;

  @override
  Widget build(BuildContext context) {
    final status = day['status'] as String;
    final style = _statusStyle[status] ?? ('', Colors.grey);
    final number = int.parse((day['date'] as String).substring(8));
    return InkWell(
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
    );
  }
}
