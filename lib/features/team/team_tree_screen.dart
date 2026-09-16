import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../beat/plan_beat_screen.dart';
import '../reports/summary_drill.dart';

/// The team by level: the people under a head, their figures, and a way down.
/// Tap a person to see who is under them; "Expand all" opens every level at once.
class TeamTreeScreen extends StatefulWidget {
  const TeamTreeScreen({super.key, this.rootId, this.rootName});

  final int? rootId;
  final String? rootName;

  @override
  State<TeamTreeScreen> createState() => _TeamTreeScreenState();
}

class _TeamTreeScreenState extends State<TeamTreeScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  bool _expandAll = false;
  String? _error;
  String _period = 'month';
  String _find = '';

  DateTimeRange get _range {
    final today = DateUtils.dateOnly(DateTime.now());
    return switch (_period) {
      'today' => DateTimeRange(start: today, end: today),
      'week' => DateTimeRange(start: today.subtract(Duration(days: today.weekday - 1)), end: today),
      _ => DateTimeRange(start: DateTime(today.year, today.month, 1), end: today),
    };
  }

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
      final data = await Services.api.get('/api/v1/team/tree', query: {
        if (widget.rootId != null) 'root': widget.rootId,
        'start': fmtDate(_range.start),
        'end': fmtDate(_range.end),
        if (_expandAll) 'expand': 1,
      }) as Map<String, dynamic>;
      if (mounted) setState(() => _data = data);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _currency => '${_data?['currency'] ?? 'INR'}';

  void _drill(Map<String, dynamic> person) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TeamTreeScreen(rootId: person['id'] as int, rootName: '${person['name']}'),
    ));
  }

  void _reports(Map<String, dynamic> person) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => EmployeeReportScreen(
        memberId: '${person['id']}',
        name: '${person['name']}',
        start: _range.start,
        end: _range.end,
      ),
    ));
  }

  /// Everyone in the tree as (person, depth), for the expanded list and the search.
  List<(Map<String, dynamic>, int)> _flatten(Map<String, dynamic> node, int depth) {
    final out = <(Map<String, dynamic>, int)>[];
    for (final child in ((node['children'] as List?) ?? []).cast<Map<String, dynamic>>()) {
      out.add((child, depth));
      out.addAll(_flatten(child, depth + 1));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final root = (_data?['root'] as Map?)?.cast<String, dynamic>();
    final path = ((_data?['path'] as List?) ?? []).cast<Map<String, dynamic>>();
    final needle = _find.trim().toLowerCase();
    var rows = root == null ? <(Map<String, dynamic>, int)>[] : _flatten(root, 0);
    if (needle.isNotEmpty) {
      rows = rows
          .where((r) => '${r.$1['name']} ${r.$1['code'] ?? ''} ${r.$1['job'] ?? ''}'.toLowerCase().contains(needle))
          .toList();
    }
    return Scaffold(
      appBar: AppBar(title: Text(widget.rootName ?? 'Team')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            if (path.length > 1)
              SizedBox(
                height: 32,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final (i, p) in path.indexed) ...[
                      if (i > 0) const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.muted),
                      Center(
                        child: Text('${p['name']}',
                            style: TextStyle(
                                fontSize: 12.5,
                                color: i == path.length - 1 ? AppColors.text : AppColors.muted,
                                fontWeight: i == path.length - 1 ? FontWeight.w800 : FontWeight.w500)),
                      ),
                    ],
                  ],
                ),
              ),
            Wrap(
              spacing: 6,
              children: [
                for (final (key, label) in [('today', 'Today'), ('week', 'This week'), ('month', 'This month')])
                  ChoiceChip(
                    label: Text(label),
                    selected: _period == key,
                    onSelected: (_) {
                      setState(() => _period = key);
                      _load();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (_loading && root == null)
              const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
            if (_error != null && root == null) ErrorView(message: _error!, onRetry: _load),
            if (root != null) ...[
              _headCard(root),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _expandAll ? 'Everyone under ${root['name']}' : 'Directly under ${root['name']}',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      setState(() => _expandAll = !_expandAll);
                      _load();
                    },
                    icon: Icon(_expandAll ? Icons.unfold_less_rounded : Icons.unfold_more_rounded),
                    label: Text(_expandAll ? 'Collapse' : 'Expand all'),
                  ),
                ],
              ),
              if (_expandAll)
                TextField(
                  onChanged: (v) => setState(() => _find = v),
                  decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search_rounded), hintText: 'Search name, code or role', isDense: true),
                ),
              if (rows.isEmpty)
                const EmptyView(icon: Icons.groups_rounded, text: 'Nobody reports here yet'),
              for (final (person, depth) in rows) _personCard(person, _expandAll ? depth : 0),
            ],
          ],
        ),
      ),
    );
  }

  Widget _headCard(Map<String, dynamic> p) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _avatar(p, 26),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${p['name']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                      Text([if (p['job'] != null) p['job'], if (p['code'] != null) p['code']].join(' · '),
                          style: const TextStyle(color: AppColors.muted)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _figure('Team', '${p['team_count']}', AppColors.primary),
                _figure('Working now', '${p['punched_in_count']}', AppColors.success),
                _figure('Visits', '${p['team_visits']}', AppColors.purple),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _figure('Team sales', fmtMoney((p['team_sales'] as num?) ?? 0, _currency), AppColors.primary),
                _figure('Collected', fmtMoney((p['team_collections'] as num?) ?? 0, _currency), AppColors.success),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _reports(p),
                    icon: const Icon(Icons.bar_chart_rounded),
                    label: const Text('Reports'),
                  ),
                ),
                if (widget.rootId != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => PlannedDaysScreen(
                            member: '${p['id']}', memberName: '${p['name']}', start: DateUtils.dateOnly(DateTime.now())),
                      )),
                      icon: const Icon(Icons.event_note_rounded),
                      label: const Text('Beat plan'),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _personCard(Map<String, dynamic> p, int depth) {
    final hasTeam = (p['direct_count'] as num? ?? 0) > 0;
    return Padding(
      padding: EdgeInsets.only(left: depth * 16.0, top: 8),
      child: Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => hasTeam ? _drill(p) : _reports(p),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
            child: Row(
              children: [
                _avatar(p, 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${p['name']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                      Text([if (p['job'] != null) p['job'], if (hasTeam) '${p['team_count']} under'].join(' · '),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                      const SizedBox(height: 4),
                      Text(
                        'Visits ${hasTeam ? p['team_visits'] : p['visits']} · '
                        '${fmtMoney(((hasTeam ? p['team_sales'] : p['sales']) as num?) ?? 0, _currency)}',
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Reports',
                  icon: const Icon(Icons.bar_chart_rounded, color: AppColors.primary),
                  onPressed: () => _reports(p),
                ),
                if (hasTeam) const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _avatar(Map<String, dynamic> p, double radius) {
    final name = '${p['name']}';
    return Stack(
      children: [
        CircleAvatar(
          radius: radius,
          backgroundColor: AppColors.primary.withValues(alpha: 0.1),
          child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: radius * 0.8)),
        ),
        Positioned(
          right: 0,
          bottom: 0,
          child: Container(
            width: radius * 0.5,
            height: radius * 0.5,
            decoration: BoxDecoration(
              color: p['punched_in'] == true ? AppColors.success : const Color(0xFFCBD5E1),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
        ),
      ],
    );
  }

  Widget _figure(String label, String value, Color colour) => Expanded(
        child: Container(
          margin: const EdgeInsets.only(right: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(color: colour.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: colour)),
              ),
            ],
          ),
        ),
      );
}
