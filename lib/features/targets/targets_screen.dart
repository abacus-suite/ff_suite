import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

String _value(Map<String, dynamic> m, String key, String? currency) =>
    m['money'] == true ? fmtMoney((m[key] as num?) ?? 0, currency) : fmtQty((m[key] as num?) ?? 0);

/// This month's leaderboard, and - for anyone who owns a target - splitting it down.
class TargetsScreen extends StatefulWidget {
  const TargetsScreen({super.key});

  @override
  State<TargetsScreen> createState() => _TargetsScreenState();
}

class _TargetsScreenState extends State<TargetsScreen> {
  Map<String, dynamic>? _board;
  Map<String, dynamic>? _split;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        Services.api.get('/api/v1/targets/leaderboard', query: {'limit': 50}),
        Services.api.get('/api/v1/targets/splittable').catchError((_) => <String, dynamic>{}),
      ]);
      if (mounted) {
        setState(() {
          _board = results[0] as Map<String, dynamic>;
          _split = results[1] as Map<String, dynamic>;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final splittable = ((_split?['targets'] as List?) ?? []).cast<Map<String, dynamic>>();
    return DefaultTabController(
      length: splittable.isEmpty ? 1 : 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Targets'),
          bottom: splittable.isEmpty
              ? null
              : const TabBar(tabs: [Tab(text: 'Leaderboard'), Tab(text: 'Split my targets')]),
        ),
        body: _error != null
            ? ErrorView(message: _error!, onRetry: _load)
            : _board == null
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(children: [
                    _leaderboard(),
                    if (splittable.isNotEmpty) _splitList(splittable),
                  ]),
      ),
    );
  }

  Widget _leaderboard() {
    final rows = ((_board!['rows'] as List?) ?? []).cast<Map<String, dynamic>>();
    final currency = _board!['currency'] as String?;
    final me = _board!['me'] as Map<String, dynamic>?;
    const medals = [Color(0xFFF5B301), Color(0xFF9AA5B1), Color(0xFFCD7F32)];
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
        children: [
          if (me != null)
            Card(
              color: const Color(0xFFE8EFFF),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: AixoloColors.primary,
                  child: Text('#${me['rank']}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                ),
                title: const Text('Your position', style: TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text(me['achievement'] == null ? 'No target set this month' : '${me['achievement']}% achieved'),
              ),
            ),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: Text('Nobody to rank yet', style: TextStyle(color: AixoloColors.muted))),
            ),
          for (final row in rows)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: (row['rank'] as int) <= 3 ? medals[(row['rank'] as int) - 1] : AixoloColors.border,
                      child: Text('${row['rank']}',
                          style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: (row['rank'] as int) <= 3 ? Colors.white : AixoloColors.text)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('${row['employee']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                          const SizedBox(height: 3),
                          Wrap(
                            spacing: 10,
                            children: [
                              for (final m in ((row['metrics'] as List?) ?? []).cast<Map<String, dynamic>>())
                                if ((m['actual'] as num? ?? 0) > 0 || (m['target'] as num? ?? 0) > 0)
                                  Text('${m['label']} ${_value(m, 'actual', currency)}',
                                      style: const TextStyle(fontSize: 12, color: AixoloColors.muted)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (row['achievement'] != null)
                      Text('${row['achievement']}%',
                          style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                              color: (row['achievement'] as num) >= 100 ? AixoloColors.success : AixoloColors.primary)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _splitList(List<Map<String, dynamic>> targets) {
    final currency = _split!['currency'] as String?;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
        children: [
          for (final t in targets)
            Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () async {
                  final saved = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(builder: (_) => SplitTargetScreen(target: t, currency: currency)));
                  if (saved == true) _load();
                },
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                              child: Text('${t['name']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
                          const Icon(Icons.call_split_rounded, color: AixoloColors.primary),
                        ],
                      ),
                      const SizedBox(height: 6),
                      for (final m in ((t['metrics'] as List?) ?? []).cast<Map<String, dynamic>>())
                        Text('${m['label']}: ${_value(m, 'allocated', currency)} of ${_value(m, 'target', currency)} split',
                            style: const TextStyle(color: AixoloColors.muted, fontSize: 13)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Divide one target among the teams and people under it.
class SplitTargetScreen extends StatefulWidget {
  const SplitTargetScreen({super.key, required this.target, this.currency});

  final Map<String, dynamic> target;
  final String? currency;

  @override
  State<SplitTargetScreen> createState() => _SplitTargetScreenState();
}

class _SplitTargetScreenState extends State<SplitTargetScreen> {
  late final List<Map<String, dynamic>> _metrics =
      ((widget.target['metrics'] as List?) ?? []).cast<Map<String, dynamic>>();
  late final List<Map<String, dynamic>> _options =
      ((widget.target['options'] as List?) ?? []).cast<Map<String, dynamic>>();
  final Map<String, TextEditingController> _fields = {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    for (final o in _options) {
      for (final m in _metrics) {
        final v = (o[m['key']] as num?) ?? 0;
        _fields['${o['scope']}-${o['id']}-${m['key']}'] = TextEditingController(text: v == 0 ? '' : fmtQty(v));
      }
    }
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  double _given(String key) =>
      _options.fold(0.0, (sum, o) => sum + (double.tryParse(_fields['${o['scope']}-${o['id']}-$key']!.text) ?? 0));

  void _evenly() {
    setState(() {
      for (final m in _metrics) {
        final share = ((m['target'] as num) / _options.length);
        for (final o in _options) {
          _fields['${o['scope']}-${o['id']}-${m['key']}']!.text =
              m['money'] == true ? share.toStringAsFixed(0) : share.floor().toString();
        }
      }
    });
  }

  Future<void> _save() async {
    for (final m in _metrics) {
      if (_given(m['key'] as String) > (m['target'] as num) + 0.01) {
        showSnack(context, '${m['label']} adds up to more than the target.');
        return;
      }
    }
    setState(() => _busy = true);
    try {
      await Services.outbox.submit('/api/v1/targets/${widget.target['id']}/split', {
        'allocations': [
          for (final o in _options)
            {
              'scope': o['scope'],
              'id': o['id'],
              for (final m in _metrics)
                m['key']: double.tryParse(_fields['${o['scope']}-${o['id']}-${m['key']}']!.text) ?? 0,
            },
        ],
      }, label: 'Split target · ${widget.target['name']}');
      if (!mounted) return;
      showSnack(context, 'Targets sent');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.target['name']}'),
        actions: [TextButton(onPressed: _evenly, child: const Text('Split evenly'))],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: GradientButton(label: 'Save split', icon: Icons.check_rounded, busy: _busy, onPressed: _save),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          Card(
            color: const Color(0xFFE8EFFF),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  for (final m in _metrics)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Expanded(child: Text('${m['label']}', style: const TextStyle(fontWeight: FontWeight.w700))),
                          Text(
                            '${m['money'] == true ? fmtMoney(_given(m['key'] as String), widget.currency) : fmtQty(_given(m['key'] as String))}'
                            ' / ${_value(m, 'target', widget.currency)}',
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: _given(m['key'] as String) > (m['target'] as num) + 0.01
                                    ? AixoloColors.danger
                                    : AixoloColors.primary),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          for (final o in _options)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(o['scope'] == 'employee' ? Icons.person_rounded : Icons.groups_rounded,
                            color: AixoloColors.primary, size: 20),
                        const SizedBox(width: 8),
                        Expanded(child: Text('${o['name']}', style: const TextStyle(fontWeight: FontWeight.w700))),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final m in _metrics)
                          SizedBox(
                            width: 150,
                            child: TextField(
                              controller: _fields['${o['scope']}-${o['id']}-${m['key']}'],
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              onChanged: (_) => setState(() {}),
                              decoration: InputDecoration(labelText: '${m['label']}', isDense: true),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
