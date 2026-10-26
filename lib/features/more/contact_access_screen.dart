import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/skeleton.dart';

/// Contacts outside one's own list: ask the manager for a territory, beat or
/// city between two dates, and (for a manager) decide what the team asked.
class ContactAccessScreen extends StatefulWidget {
  const ContactAccessScreen({super.key});

  @override
  State<ContactAccessScreen> createState() => _ContactAccessScreenState();
}

class _ContactAccessScreenState extends State<ContactAccessScreen> {
  bool _loading = true;
  String? _error;
  List _mine = [];
  List _toDecide = [];
  List _given = [];
  bool _canDecide = false;

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
      final data = await Services.api.get('/api/v1/contact-access') as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _mine = (data['mine'] as List?) ?? [];
        _toDecide = (data['to_decide'] as List?) ?? [];
        _given = (data['given'] as List?) ?? [];
        _canDecide = data['can_decide'] == true;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _decide(Map r, bool approve) async {
    try {
      await Services.api.post('/api/v1/contact-access/${r['id']}/decide', {'approve': approve});
      if (mounted) showSnack(context, approve ? 'Approved' : 'Rejected');
      _load();
    } catch (e) {
      if (mounted) showProblem(context, e.toString());
    }
  }

  /// A manager gives somebody in the team access, for a day or a stretch, with no request to wait for.
  Future<void> _assign() async {
    final done = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _RequestSheet(assign: true),
    );
    if (done == true) {
      if (mounted) showSnack(context, 'Access given');
      _load();
    }
  }

  Future<void> _new() async {
    final done = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _RequestSheet(),
    );
    if (done == true) {
      if (mounted) showSnack(context, 'Sent to your manager');
      _load();
    }
  }

  Color _tint(String s) => switch (s) {
        'active' => AppColors.success,
        'pending' || 'upcoming' => AppColors.sky,
        _ => AppColors.danger,
      };

  String _label(String s) => switch (s) {
        'pending' => 'Waiting',
        'upcoming' => 'Starts later',
        'active' => 'Active',
        'expired' => 'Expired',
        _ => 'Rejected',
      };

  Widget _row(Map r, {bool decide = false, bool who = false}) {
    final status = '${r['status']}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(
                  '${r['target']} (${r['scope_type']})',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
              Chip(
                label: Text(_label(status), style: TextStyle(color: _tint(status), fontWeight: FontWeight.w700)),
                visualDensity: VisualDensity.compact,
              ),
            ]),
            if (decide || who)
              Text('${(r['employee'] as Map?)?['name'] ?? ''}${r['source'] == 'assigned' ? ' · assigned by a manager' : ''}',
                  style: const TextStyle(fontSize: 12.5)),
            Text('${r['date_from']}  to  ${r['date_to']}', style: const TextStyle(color: AppColors.muted)),
            if ((r['reason'] ?? '').toString().isNotEmpty) Text('${r['reason']}'),
            if ((r['decision_note'] ?? '').toString().isNotEmpty)
              Text('${r['decision_note']}', style: const TextStyle(color: AppColors.danger)),
            if (decide)
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(onPressed: () => _decide(r, false), child: const Text('Reject')),
                FilledButton(onPressed: () => _decide(r, true), child: const Text('Approve')),
              ]),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Contact Access')),
      floatingActionButton: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
        if (_canDecide) ...[
          FloatingActionButton.extended(
            heroTag: 'assign',
            onPressed: _assign,
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: const Text('Assign to team'),
          ),
          const SizedBox(height: 10),
        ],
        FloatingActionButton.extended(
          heroTag: 'request',
          onPressed: _new,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Request access'),
        ),
      ]),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                    children: [
                      if (_canDecide && _toDecide.isNotEmpty) ...[
                        const Text('Waiting for you', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                        for (final r in _toDecide) _row(r as Map, decide: true),
                        const SizedBox(height: 12),
                      ],
                      if (_canDecide && _given.isNotEmpty) ...[
                        const Text('Given to my team', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                        for (final r in _given) _row(r as Map, decide: false, who: true),
                        const SizedBox(height: 12),
                      ],
                      const Text('My requests', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                      if (_mine.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('Nothing asked for yet. Need contacts outside your list? Request access.',
                              style: TextStyle(color: AppColors.muted)),
                        ),
                      for (final r in _mine) _row(r as Map),
                    ],
                  ),
                ),
    );
  }
}

class _RequestSheet extends StatefulWidget {
  const _RequestSheet({this.assign = false});

  /// A manager giving access to somebody in the team, rather than asking for it.
  final bool assign;

  @override
  State<_RequestSheet> createState() => _RequestSheetState();
}

class _RequestSheetState extends State<_RequestSheet> {
  String _scope = 'beat';
  Map<String, dynamic> _options = {};
  int? _target;
  DateTime _from = DateUtils.dateOnly(DateTime.now());
  DateTime? _to;
  final _reason = TextEditingController();
  bool _busy = false;
  List _members = [];
  int? _member;
  bool _planDay = true;

  @override
  void initState() {
    super.initState();
    if (widget.assign) {
      Services.api.get('/api/v1/team/members').then((d) {
        if (mounted) setState(() => _members = ((d as Map)['members'] as List?) ?? []);
      }).catchError((_) {});
    }
    Services.api.get('/api/v1/contact-access/options').then((d) {
      if (mounted) setState(() => _options = d as Map<String, dynamic>);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  List get _choices => (_options[{'territory': 'territories', 'beat': 'beats', 'city': 'cities'}[_scope]] as List?) ?? [];

  Future<void> _pick(bool from) async {
    final d = await showDatePicker(
      context: context,
      initialDate: (from ? _from : _to) ?? _from,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d != null) setState(() => from ? _from = d : _to = d);
  }

  Future<void> _send() async {
    if (widget.assign && _member == null) {
      showProblem(context, 'Choose who it is for');
      return;
    }
    if (_target == null || (_to == null && !widget.assign)) {
      showProblem(context, 'Choose what you need and until when');
      return;
    }
    setState(() => _busy = true);
    try {
      await Services.api.post(widget.assign ? '/api/v1/contact-access/assign' : '/api/v1/contact-access', {
        if (widget.assign) 'employee_id': _member,
        if (widget.assign && _scope == 'beat') 'plan_day': _planDay,
        'scope_type': _scope,
        'target_id': _target,
        'date_from': fmtDate(_from),
        'date_to': fmtDate(_to ?? _from),
        'reason': _reason.text,
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showProblem(context, e.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.assign ? 'Assign contact access' : 'Request contact access',
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            const SizedBox(height: 12),
            if (widget.assign) ...[
              DropdownButtonFormField<int>(
                initialValue: _member,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Who is it for', border: OutlineInputBorder()),
                items: [
                  for (final m in _members)
                    DropdownMenuItem(value: (m as Map)['id'] as int, child: Text('${m['name']}', overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() => _member = v),
              ),
              const SizedBox(height: 12),
            ],
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'city', label: Text('City')),
                ButtonSegment(value: 'territory', label: Text('Territory')),
                ButtonSegment(value: 'beat', label: Text('Beat')),
              ],
              selected: {_scope},
              onSelectionChanged: (s) => setState(() {
                _scope = s.first;
                _target = null;
              }),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _target,
              isExpanded: true,
              decoration: InputDecoration(labelText: 'Which $_scope', border: const OutlineInputBorder()),
              items: [
                for (final c in _choices)
                  DropdownMenuItem(value: (c as Map)['id'] as int, child: Text('${c['name']}', overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => _target = v),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: OutlinedButton(onPressed: () => _pick(true), child: Text('From ${fmtDate(_from)}')),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                    onPressed: () => _pick(false),
                    child: Text(_to == null ? (widget.assign ? 'To (same day)' : 'To date') : 'To ${fmtDate(_to!)}')),
              ),
            ]),
            if (widget.assign && _scope == 'beat')
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _planDay,
                onChanged: (v) => setState(() => _planDay = v ?? false),
                title: const Text('Also plan this beat for them on the first day'),
                subtitle: const Text('Their check-in then finds it ready'),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _reason,
              maxLines: 2,
              decoration: InputDecoration(labelText: widget.assign ? 'Note (optional)' : 'Why do you need it?', border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy ? null : _send,
                child: _busy
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(widget.assign ? 'Give access' : 'Send to my manager'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
