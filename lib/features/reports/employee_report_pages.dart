import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/skeleton.dart';

/// The pages a tap on the Employee report opens: visits, tasks, and the day-wise lists.

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _weekdaysLong = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

String _two(int n) => n.toString().padLeft(2, '0');

String _short(String iso) {
  final d = DateTime.tryParse(iso);
  return d == null ? iso : '${_two(d.day)} ${_months[d.month - 1]}';
}

num _num(Object? v) => (v as num?) ?? 0;

Widget _header(String title, String name, String sub) => Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$title · ${name.toUpperCase()}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
        Text(sub, style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
      ]),
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
  const EmployeeVisitsScreen({super.key, required this.name, required this.rangeText, required this.visits, required this.orders});

  final String name;
  final String rangeText;
  final List<Map<String, dynamic>> visits;
  final List<Map<String, dynamic>> orders;

  @override
  State<EmployeeVisitsScreen> createState() => _EmployeeVisitsScreenState();
}

class _EmployeeVisitsScreenState extends State<EmployeeVisitsScreen> {
  String _filter = 'all';

  static String _kind(Map<String, dynamic> v) {
    final t = '${v['visit_type'] ?? v['type'] ?? ''}'.toLowerCase();
    if (t.contains('distributor')) return 'distributor';
    if (t.contains('new')) return 'new';
    if (t.contains('follow')) return 'follow';
    return 'beat';
  }

  static String _kindLabel(String k) => switch (k) {
        'distributor' => 'Distributor Visit',
        'new' => 'New Visit',
        'follow' => 'Follow up',
        _ => 'Beat Route',
      };

  static bool _pending(Map<String, dynamic> v) =>
      '${v['status'] ?? v['state'] ?? v['plan_status'] ?? ''}'.toLowerCase() == 'pending';

  String _po(Map<String, dynamic> v) {
    final bottles = v['bottles'];
    if (bottles != null && _num(bottles) > 0) return 'PO ${fmtQty(_num(bottles))} bottles';
    final same = widget.orders.where((o) => o['customer'] == v['customer'] && o['date'] == v['date']);
    return same.isEmpty ? '' : 'PO ${same.length}';
  }

  @override
  Widget build(BuildContext context) {
    final all = widget.visits;
    final visited = all.where((v) => !_pending(v)).toList();
    final pending = all.where(_pending).toList();
    final shown = switch (_filter) { 'visited' => visited, 'pending' => pending, _ => all };

    Widget count(String key, IconData icon, Color c, String label) {
      final of = all.where((v) => _kind(v) == key).toList();
      return _summaryBox(icon, c, label, '${of.where((v) => !_pending(v)).length} / ${of.length}');
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
              title: Text('${v['customer'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
              subtitle: Text(
                [
                  _short('${v['date']}'),
                  _kindLabel(_kind(v)),
                  if (v['check_out'] != null) 'Out ${v['check_out']}',
                  if (_po(v).isNotEmpty) _po(v),
                ].join(' · '),
                style: const TextStyle(fontSize: 11.5),
              ),
              trailing: _pill(_pending(v) ? 'Pending' : 'Visited', _pending(v) ? AppColors.warning : AppColors.success),
            ),
          ),
      ]),
    );
  }
}

// ======================================================================
// Tasks
// ======================================================================
class EmployeeTasksScreen extends StatefulWidget {
  const EmployeeTasksScreen({
    super.key,
    required this.memberId,
    required this.name,
    required this.rangeText,
    required this.start,
    required this.end,
    required this.visitsDone,
    required this.visitsTotal,
  });

  final String memberId;
  final String name;
  final String rangeText;
  final DateTime start;
  final DateTime end;
  final num visitsDone;
  final num visitsTotal;

  @override
  State<EmployeeTasksScreen> createState() => _EmployeeTasksScreenState();
}

class _EmployeeTasksScreenState extends State<EmployeeTasksScreen> {
  List<Map<String, dynamic>>? _tasks;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await Services.api.get('/api/v1/tasks', query: {
        'scope': 'team',
        'member': widget.memberId,
        'start': fmtDate(widget.start),
        'end': fmtDate(widget.end),
      }) as Map<String, dynamic>;
      if (mounted) setState(() => _tasks = ((d['tasks'] as List?) ?? []).cast<Map<String, dynamic>>());
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  static bool _done(Map<String, dynamic> t) => t['state'] == 'done';

  static String _type(Map<String, dynamic> t) {
    final v = t['type'] ?? t['kind'] ?? t['category'];
    if (v is Map) return '${v['name']}';
    return v == null || '$v'.isEmpty ? 'Adhoc Task' : '$v';
  }

  @override
  Widget build(BuildContext context) {
    final tasks = _tasks;
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final t in tasks ?? const <Map<String, dynamic>>[]) {
      groups.putIfAbsent(_type(t), () => []).add(t);
    }
    final doneTasks = (tasks ?? const []).where(_done).length;
    return Scaffold(
      appBar: AppBar(title: _header('Tasks', widget.name, widget.rangeText)),
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
          : tasks == null
              ? const LoadingView()
              : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
                  _twoColumns([
                    for (final (i, e) in groups.entries.indexed)
                      _summaryBox(i.isEven ? Icons.payments_rounded : Icons.check_circle_rounded, i.isEven ? AppColors.success : AppColors.primary, e.key,
                          '${e.value.where(_done).length} / ${e.value.length}'),
                  ]),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text('Total tasks (visits + tasks): ${fmtQty(widget.visitsDone + doneTasks)} / ${fmtQty(widget.visitsTotal + tasks.length)}',
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
                            Text(
                              _done(t) && t['done_at'] != null ? '${_short('${t['done_at']}'.split('T').first.split(' ').first)}${t['done_note'] != null ? ' · ${t['done_note']}' : ''}' : 'Due ${t['due'] ?? ''}',
                              style: const TextStyle(fontSize: 11, color: AppColors.muted),
                            ),
                          ]),
                        ),
                        _pill(_done(t) ? 'Done' : 'Pending', _done(t) ? AppColors.success : AppColors.warning),
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
  final List<Map<String, dynamic>> days;

  /// 'km' or 'hours' to put the biggest first; null keeps the newest day on top.
  final String? sortBy;

  static String _time(Object? v) {
    if (v == null) return '–';
    final t = DateTime.tryParse('$v');
    if (t == null) return '$v';
    final l = t.toLocal();
    return '${_two(l.hour)}:${_two(l.minute)}';
  }

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
                    Text(_time(d['check_in'] ?? d['first_in']), style: cell, textAlign: TextAlign.center),
                    Text(_time(d['check_out'] ?? d['last_out']), style: cell, textAlign: TextAlign.center),
                    Text(fmtHours(d['hours'] as num?), style: cell, textAlign: TextAlign.center),
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

class LateDaysScreen extends StatelessWidget {
  const LateDaysScreen({super.key, required this.name, required this.rangeText, required this.days});

  final String name;
  final String rangeText;
  final List<Map<String, dynamic>> days;

  @override
  Widget build(BuildContext context) {
    final rows = days.where((d) => _num(d['late']) > 0 || _num(d['late_minutes']) > 0).toList()..sort((a, b) => '${b['date']}'.compareTo('${a['date']}'));
    return Scaffold(
      appBar: AppBar(title: _header('Late days', name, '$rangeText · ${rows.length} day${rows.length == 1 ? '' : 's'}')),
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
                        return t == null ? '${d['date']}' : '${_two(t.day)} ${_months[t.month - 1]} ${t.year} · ${_weekdaysLong[t.weekday - 1]}';
                      }(),
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                  Text(
                    [
                      if (d['check_in'] != null) 'Checked in ${DaysTableScreen._time(d['check_in'])}',
                      if (d['place'] != null || d['location'] != null) '${d['place'] ?? d['location']}',
                    ].join(' · '),
                    style: const TextStyle(fontSize: 11, color: AppColors.muted),
                  ),
                ]),
              ),
              if (_num(d['late_minutes']) > 0) _pill('${_num(d['late_minutes']).round()} min late', const Color(0xFFC2410C)),
            ]),
          ),
      ]),
    );
  }
}
