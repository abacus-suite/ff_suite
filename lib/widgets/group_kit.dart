import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/theme.dart';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String prettyDay(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

/// The everyday periods, shared by every screen with a date filter.
class Periods {
  static const choices = [
    ('today', 'Today'),
    ('yesterday', 'Yesterday'),
    ('week', 'This week'),
    ('last_week', 'Last week'),
    ('month', 'This month'),
    ('last_month', 'Last month'),
    ('year', 'This year'),
    ('custom', 'Custom…'),
  ];

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTimeRange range(String key) {
    final today = _day(DateTime.now());
    final monday = today.subtract(Duration(days: today.weekday - 1));
    return switch (key) {
      'today' => DateTimeRange(start: today, end: today),
      'yesterday' => DateTimeRange(
          start: today.subtract(const Duration(days: 1)), end: today.subtract(const Duration(days: 1))),
      'week' => DateTimeRange(start: monday, end: today),
      'last_week' => DateTimeRange(
          start: monday.subtract(const Duration(days: 7)), end: monday.subtract(const Duration(days: 1))),
      'last_month' => DateTimeRange(
          start: DateTime(today.year, today.month - 1, 1), end: DateTime(today.year, today.month, 0)),
      'year' => DateTimeRange(start: DateTime(today.year, 1, 1), end: today),
      _ => DateTimeRange(start: DateTime(today.year, today.month, 1), end: today),
    };
  }
}

/// Horizontal period chips; "Custom…" opens a date-range picker.
class PeriodChips extends StatelessWidget {
  const PeriodChips({super.key, required this.period, required this.range, required this.onChanged});

  final String period;
  final DateTimeRange range;
  final void Function(String period, DateTimeRange range) onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        children: [
          for (final p in Periods.choices)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(p.$1 == 'custom' && period == 'custom'
                    ? '${prettyDay(range.start)} – ${prettyDay(range.end)}'
                    : p.$2),
                selected: period == p.$1,
                onSelected: (_) async {
                  if (p.$1 != 'custom') {
                    onChanged(p.$1, Periods.range(p.$1));
                    return;
                  }
                  final picked = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                    initialDateRange: range,
                  );
                  if (picked != null) onChanged('custom', picked);
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// A way of grouping rows: a label and how to read the group key of a row.
class GroupOption {
  const GroupOption(this.key, this.label, this.icon);

  final String key;
  final String label;
  final IconData icon;
}

const dateGroups = [
  GroupOption('day', 'Day', Icons.today_rounded),
  GroupOption('week', 'Week', Icons.view_week_rounded),
  GroupOption('month', 'Month', Icons.calendar_month_rounded),
  GroupOption('year', 'Year', Icons.event_note_rounded),
];

/// The group a date falls in, for day / week / month / year; sortable key first, label second.
(String, String) dateBucket(DateTime date, String by) {
  String two(int n) => n.toString().padLeft(2, '0');
  switch (by) {
    case 'year':
      return ('${date.year}', '${date.year}');
    case 'month':
      return ('${date.year}-${two(date.month)}', '${_months[date.month - 1]} ${date.year}');
    case 'week':
      final monday = DateTime(date.year, date.month, date.day).subtract(Duration(days: date.weekday - 1));
      return (fmtDate(monday), 'Week of ${prettyDay(monday)}');
    default:
      return (fmtDate(date), prettyDay(date));
  }
}

/// "Group by" chip that opens a sheet of options. [value] 'none' means no grouping.
class GroupByChip extends StatelessWidget {
  const GroupByChip({super.key, required this.value, required this.options, required this.onChanged});

  final String value;
  final List<GroupOption> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final current = options.where((o) => o.key == value).firstOrNull;
    return ActionChip(
      avatar: Icon(current?.icon ?? Icons.layers_rounded, size: 16, color: AppColors.primary),
      label: Text(current == null ? 'Group by' : 'By ${current.label.toLowerCase()}'),
      onPressed: () async {
        final picked = await showModalBottomSheet<String>(
          context: context,
          showDragHandle: true,
          builder: (sheet) => SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.layers_clear_rounded),
                    title: const Text('No grouping'),
                    trailing: value == 'none' ? const Icon(Icons.check_rounded, color: AppColors.primary) : null,
                    onTap: () => Navigator.pop(sheet, 'none'),
                  ),
                  for (final o in options)
                    ListTile(
                      leading: Icon(o.icon, color: AppColors.primary),
                      title: Text(o.label),
                      trailing: value == o.key ? const Icon(Icons.check_rounded, color: AppColors.primary) : null,
                      onTap: () => Navigator.pop(sheet, o.key),
                    ),
                ],
              ),
            ),
          ),
        );
        if (picked != null) onChanged(picked);
      },
    );
  }
}

/// A group header: name, how many, and the totals that matter.
class GroupHeader extends StatelessWidget {
  const GroupHeader({super.key, required this.title, required this.count, this.totals = const [], this.expanded = true, this.onTap});

  final String title;
  final int count;
  final List<String> totals;
  final bool expanded;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(top: 10, bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: const Color(0xFFE8EFFF), borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            Icon(expanded ? Icons.expand_more_rounded : Icons.chevron_right_rounded, color: AppColors.primary),
            const SizedBox(width: 4),
            Expanded(
              child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800), overflow: TextOverflow.ellipsis),
            ),
            Text('$count', style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700)),
            for (final t in totals) ...[
              const SizedBox(width: 10),
              Text(t, style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.primary)),
            ],
          ],
        ),
      ),
    );
  }
}
