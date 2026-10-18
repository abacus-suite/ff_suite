import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';

/// The pages a tap on the Manager's Employee report opens: visits, tasks, and the day-wise lists.
/// They read the same `details` the employee-report endpoint already sends.

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _weekdaysLong = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

String _two(int n) => n.toString().padLeft(2, '0');

String _short(Object? iso) {
  final d = DateTime.tryParse('$iso');
  return d == null ? '$iso' : '${_two(d.day)} ${_months[d.month - 1]}';
}

num _num(Object? v) => (v as num?) ?? 0;

String _hoursText(num h) {
  final minutes = (h * 60).round();
  return '${minutes ~/ 60}h ${_two(minutes % 60)}m';
}

String _clock(Object? v) => v == null ? '–' : fmtTime(v);

Widget _header(String title, String name, String sub) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$title · ${name.toUpperCase()}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
        Text(sub, style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
      ],
    );

Widget _pill(String text, Color c) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(14)),
      child: Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white)),
    );

Widget _summaryBox(IconData icon, Color c, String label, String value) => Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        CircleAvatar(radius: 17, backgroundColor: Colors.white, child: Icon(icon, color: c, size: 18)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, color: AppColors.muted)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
          ]),
        ),
      ]),
    );

Widget _twoColumns(List<Widget> tiles) => Column(children: [
      for (var i = 0; i < tiles.length; i += 2)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            Expanded(child: tiles[i]),
            const SizedBox(width: 8),
            Expanded(child: i + 1 < tiles.length ? tiles[i + 1] : const SizedBox()),
          ]),
        ),
    ]);

// ======================================================================
// Visits
// ======================================================================
class EmployeeVisitsScreen extends StatefulWidget {
  const EmployeeVisitsScreen({super.key, required this.name, required this.rangeText, required this.visits});

  final String name;
  final String rangeText;

  /// Each: `{date, outlet: {name}, done, type?, check_out?, bottles?}`.
  final List<Map<String, dynamic>> visits;

  @override
  State<EmployeeVisitsScreen> createState() => _EmployeeVisitsScreenState();
}

class _EmployeeVisitsScreenState extends State<EmployeeVisitsScreen> {
  String _filter = 'all';

  static String _kind(Map<String, dynamic> v) {
    final t = '${v['type'] ?? v['visit_type'] ?? ''}'.toLowerCase();
    if (t.contains('distributor')) return 'distributor';
    if (t.contains('new')) return 'new';
    if (t.contains('follow')) return 'follow';
    if (t.isEmpty) return '';
    return 'beat';
  }

  static String _kindLabel(String k) => switch (k) {
        'distributor' => 'Distributor Visit',
        'new' => 'New Visit',
        'follow' => 'Follow up',
        'beat' => 'Beat Route',
        _ => '',
      };

  static bool _visited(Map<String, dynamic> v) => v['done'] == true;

  @override
  Widget build(BuildContext context) {
    final all = widget.visits;
    final visited = all.where(_visited).toList();
    final pending = all.where((v) => !_visited(v)).toList();
    final shown = switch (_filter) { 'visited' => visited, 'pending' => pending, _ => all };
    // The four type boxes need the server to say what kind each visit was.
    final typed = all.any((v) => _kind(v).isNotEmpty);

    Widget count(String key, IconData icon, Color c, String label) {
      final of = all.where((v) => _kind(v) == key).toList();
      return _summaryBox(icon, c, label, '${of.where(_visited).length} / ${of.length}');
    }

    Widget chip(String key, String label, int n) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Text('$label ($n)', style: const TextStyle(fontWeight: FontWeight.w700)),
            selected: _filter == key,
            onSelected: (_) => setState(() => _filter = key),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: _header('Visits', widget.name, widget.rangeText)),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
        if (typed)
          _twoColumns([
            count('beat', Icons.event_note_rounded, AppColors.primary, 'Beat Route'),
            count('distributor', Icons.local_shipping_rounded, AppColors.warning, 'Distributor Visit'),
            count('new', Icons.storefront_rounded, AppColors.success, 'New Visits'),
            count('follow', Icons.check_circle_rounded, AppColors.purple, 'Follow up'),
          ]),
        const SizedBox(height: 4),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [chip('all', 'All', all.length), chip('visited', 'Visited', visited.length), chip('pending', 'Pending', pending.length)]),
        ),
        const SizedBox(height: 8),
        if (shown.isEmpty) const Padding(padding: EdgeInsets.all(28), child: Center(child: Text('No visits', style: TextStyle(color: AppColors.muted)))),
        for (final v in shown)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                child: Icon(switch (_kind(v)) { 'distributor' => Icons.local_shipping_rounded, 'new' => Icons.add_business_rounded, 'follow' => Icons.reply_rounded, _ => Icons.storefront_rounded },
                    color: AppColors.primary, size: 20),
              ),
              title: Text('${(v['outlet'] as Map?)?['name'] ?? v['customer'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
              subtitle: Text(
                [
                  _short(v['date']),
                  if (_kindLabel(_kind(v)).isNotEmpty) _kindLabel(_kind(v)),
                  if (v['check_out'] != null) 'Out ${_clock(v['check_out'])}',
                  if (_num(v['bottles']) > 0) 'PO ${fmtQty(_num(v['bottles']))} bottles',
                ].join(' · '),
                style: const TextStyle(fontSize: 11.5),
              ),
              trailing: !_visited(v)
                  ? _pill('Pending', AppColors.warning)
                  : Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: ('${v['visit_type'] ?? v['type']}'.toLowerCase() == 'offsite'
                                ? AppColors.warning
                                : AppColors.success)
                            .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            '${v['visit_type'] ?? v['type']}'.toLowerCase() == 'offsite'
                                ? Icons.wrong_location_rounded
                                : Icons.storefront_rounded,
                            size: 13,
                            color: '${v['visit_type'] ?? v['type']}'.toLowerCase() == 'offsite'
                                ? AppColors.warning
                                : AppColors.success,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${v['visit_type'] ?? v['type']}'.toLowerCase() == 'offsite' ? 'Offsite' : 'Onsite',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: '${v['visit_type'] ?? v['type']}'.toLowerCase() == 'offsite'
                                  ? AppColors.warning
                                  : AppColors.success,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
      ]),
    );
  }
}

// ======================================================================
// Tasks
// ======================================================================
class EmployeeTasksScreen extends StatelessWidget {
  const EmployeeTasksScreen({
    super.key,
    required this.name,
    required this.rangeText,
    required this.tasks,
    required this.visitsDone,
    required this.visitsTotal,
  });

  final String name;
  final String rangeText;

  /// Each: `{name, state, due?, type?}`.
  final List<Map<String, dynamic>> tasks;
  final num visitsDone;
  final num visitsTotal;

  static bool _done(Map<String, dynamic> t) => t['state'] == 'done';

  static String _type(Map<String, dynamic> t) {
    final v = t['type'] ?? t['kind'] ?? t['category'];
    if (v is Map) return '${v['name']}';
    return v == null || '$v'.isEmpty ? 'Adhoc Task' : '$v';
  }

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final t in tasks) {
      groups.putIfAbsent(_type(t), () => []).add(t);
    }
    final doneTasks = tasks.where(_done).length;
    return Scaffold(
      appBar: AppBar(title: _header('Tasks', name, rangeText)),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
        _twoColumns([
          for (final (i, e) in groups.entries.indexed)
            _summaryBox(i.isEven ? Icons.payments_rounded : Icons.check_circle_rounded, i.isEven ? AppColors.success : AppColors.primary, e.key,
                '${e.value.where(_done).length} / ${e.value.length}'),
        ]),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text('Total tasks (visits + tasks): ${fmtQty(visitsDone + doneTasks)} / ${fmtQty(visitsTotal + tasks.length)}',
              style: const TextStyle(fontSize: 11.5, fontStyle: FontStyle.italic, color: AppColors.muted)),
        ),
        if (tasks.isEmpty) const Padding(padding: EdgeInsets.all(28), child: Center(child: Text('No tasks', style: TextStyle(color: AppColors.muted)))),
        for (final t in tasks)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border(left: BorderSide(color: _done(t) ? AppColors.success : AppColors.warning, width: 4)),
            ),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${t['name']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                  Text(t['due'] != null ? 'Due ${_short(t['due'])}' : '', style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                ]),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _pill(_done(t) ? 'Done' : 'Pending', _done(t) ? AppColors.success : AppColors.warning),
                  if (t['visit_type'] != null || t['type'] != null) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: ('${t['visit_type'] ?? t['type']}'.toLowerCase() == 'onsite'
                                ? AppColors.success
                                : AppColors.muted)
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${t['visit_type'] ?? t['type']}'.toLowerCase() == 'onsite' ? 'Onsite' : 'Offsite',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: '${t['visit_type'] ?? t['type']}'.toLowerCase() == 'onsite'
                              ? AppColors.success
                              : AppColors.muted,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ]),
          ),
      ]),
    );
  }
}

// ======================================================================
// Day-wise lists: days worked, distance, hours (a table) and late days
// ======================================================================
class DaysTableScreen extends StatelessWidget {
  const DaysTableScreen({super.key, required this.title, required this.name, required this.rangeText, required this.days, this.sortBy});

  final String title;
  final String name;
  final String rangeText;

  /// Each: `{date, in_at, out_at, hours, km}`.
  final List<Map<String, dynamic>> days;

  /// 'km' or 'hours' to put the biggest first; null keeps the newest day on top.
  final String? sortBy;

  @override
  Widget build(BuildContext context) {
    final rows = [...days];
    if (sortBy != null) {
      rows.sort((a, b) => _num(b[sortBy]).compareTo(_num(a[sortBy])));
    } else {
      rows.sort((a, b) => '${b['date']}'.compareTo('${a['date']}'));
    }
    const head = TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.muted);
    const cell = TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700);
    return Scaffold(
      appBar: AppBar(title: _header(title, name, '$rangeText · ${rows.length} day${rows.length == 1 ? '' : 's'}')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
        if (rows.isEmpty)
          const Padding(padding: EdgeInsets.all(28), child: Center(child: Text('Nothing in these dates.', style: TextStyle(color: AppColors.muted)))),
        if (rows.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
            child: Table(
              columnWidths: const {0: FlexColumnWidth(2.2), 1: FlexColumnWidth(1.2), 2: FlexColumnWidth(1.2), 3: FlexColumnWidth(1.4), 4: FlexColumnWidth(1)},
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                const TableRow(children: [
                  Padding(padding: EdgeInsets.only(bottom: 8), child: Text('Date', style: head)),
                  Text('In', style: head, textAlign: TextAlign.center),
                  Text('Out', style: head, textAlign: TextAlign.center),
                  Text('Hours', style: head, textAlign: TextAlign.center),
                  Text('km', style: head, textAlign: TextAlign.right),
                ]),
                for (final d in rows)
                  TableRow(children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      child: Text(
                          () {
                            final t = DateTime.tryParse('${d['date']}');
                            return t == null ? '${d['date']}' : '${_two(t.day)} ${_months[t.month - 1]} ${_weekdays[t.weekday - 1]}';
                          }(),
                          style: cell),
                    ),
                    Text(_clock(d['in_at']), style: cell, textAlign: TextAlign.center),
                    Text(_clock(d['out_at']), style: cell, textAlign: TextAlign.center),
                    Text(_hoursText(_num(d['hours'])), style: cell, textAlign: TextAlign.center),
                    Text(_num(d['km']).toStringAsFixed(1), style: cell, textAlign: TextAlign.right),
                  ]),
              ],
            ),
          ),
        if (sortBy != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text('Sorted by ${sortBy == 'km' ? 'distance' : 'hours'}.', style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: AppColors.muted)),
          ),
      ]),
    );
  }
}

/// The late days of one employee. The minutes come with each check-in on that day's timeline; they are looked up
/// for days where the report did not already say.
class LateDaysScreen extends StatefulWidget {
  const LateDaysScreen({super.key, required this.name, required this.rangeText, required this.days, this.memberId});

  final String name;
  final String rangeText;
  final List<Map<String, dynamic>> days;

  /// The employee, for looking up how late each day was.
  final String? memberId;

  @override
  State<LateDaysScreen> createState() => _LateDaysScreenState();
}

class _LateDaysScreenState extends State<LateDaysScreen> {
  /// date -> minutes late
  final Map<String, num> _minutes = {};

  @override
  void initState() {
    super.initState();
    for (final d in widget.days) {
      final known = _num(d['late_minutes']);
      if (known > 0) _minutes['${d['date']}'] = known;
    }
    _lookUp();
  }

  Future<void> _lookUp() async {
    final id = widget.memberId;
    if (id == null) return;
    for (final d in widget.days) {
      final date = '${d['date']}';
      if (_minutes.containsKey(date)) continue;
      try {
        final data = await Services.api.get('/api/v1/team/$id/timeline', query: {'date': date}) as Map<String, dynamic>;
        final rows = ((data['attendance'] as List?) ?? []).cast<Map<String, dynamic>>();
        // The first check-in of the day is the one that is late.
        final late = rows.isEmpty ? 0 : _num(rows.first['late_minutes']);
        if (late > 0 && mounted) setState(() => _minutes[date] = late);
      } catch (_) {
        // No minutes for that day: the card just shows the day.
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = [...widget.days]..sort((a, b) => '${b['date']}'.compareTo('${a['date']}'));
    return Scaffold(
      appBar: AppBar(title: _header('Late days', widget.name, '${widget.rangeText} \u00B7 ${rows.length} day${rows.length == 1 ? '' : 's'}')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
        if (rows.isEmpty)
          const Padding(padding: EdgeInsets.all(28), child: Center(child: Text('No late days.', style: TextStyle(color: AppColors.muted)))),
        for (final d in rows)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: const Border(left: BorderSide(color: AppColors.warning, width: 4)),
            ),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                      () {
                        final t = DateTime.tryParse('${d['date']}');
                        return t == null ? '${d['date']}' : '${_two(t.day)} ${_months[t.month - 1]} ${t.year} \u00B7 ${_weekdaysLong[t.weekday - 1]}';
                      }(),
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                  Text(
                    [
                      if (d['in_at'] != null) 'Checked in ${_clock(d['in_at'])}',
                      if (d['place'] != null || d['location'] != null) '${d['place'] ?? d['location']}',
                    ].join(' \u00B7 '),
                    style: const TextStyle(fontSize: 11, color: AppColors.muted),
                  ),
                ]),
              ),
              if ((_minutes['${d['date']}'] ?? 0) > 0) _pill('${_minutes['${d['date']}']!.round()} min late', const Color(0xFFC2410C)),
            ]),
          ),
      ]),
    );
  }
}
