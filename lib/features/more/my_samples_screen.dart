import 'package:flutter/material.dart';

import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/member_picker.dart';

/// Samples in my hands: what I took, what I gave away and what is left.
class MySamplesScreen extends StatefulWidget {
  const MySamplesScreen({super.key});

  @override
  State<MySamplesScreen> createState() => _MySamplesScreenState();
}

class _MySamplesScreenState extends State<MySamplesScreen> {
  Map<String, dynamic>? _data;
  String? _error;
  String _member = 'me';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await Services.api.get('/api/v1/field-tasks/samples', query: {'member': _member}) as Map<String, dynamic>;
      _error = null;
      if (mounted) setState(() => _data = d);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  String _n(num? v) => (v ?? 0) == (v ?? 0).roundToDouble() ? '${(v ?? 0).toInt()}' : '${v ?? 0}';

  Widget _stat(String label, num? v, Color c) => Expanded(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Column(children: [
              Text(_n(v), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 24, color: c)),
              Text(label, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final onHand = ((d?['on_hand'] as List?) ?? []).cast<Map>();
    final moves = ((d?['moves'] as List?) ?? []).cast<Map>();
    final inHand = onHand.fold<double>(0, (s, r) => s + ((r['quantity'] as num?) ?? 0));
    return Scaffold(
      appBar: AppBar(title: Text(_member == 'me' ? 'My Samples' : 'Samples')),
      body: d == null
          ? Center(child: _error != null ? Text(_error!) : const CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (Services.auth.profile?.isManager ?? false)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: MemberPicker(
                          value: _member,
                          onChanged: (v) {
                            setState(() {
                              _member = v;
                              _data = null;
                            });
                            _load();
                          },
                        ),
                      ),
                    ),
                  Row(children: [
                    _stat('Taken', d['taken'] as num?, AppColors.sky),
                    _stat('Given', d['given'] as num?, AppColors.purple),
                    _stat('In hand', inHand, AppColors.success),
                  ]),
                  const SizedBox(height: 8),
                  if (d['team'] is List) ...[
                    const Text('By person', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                    for (final row in (d['team'] as List).cast<Map>())
                      ExpansionTile(
                        title: Text('${(row['employee'] as Map)['name']}'),
                        subtitle: Text('Taken ${_n(row['taken'] as num?)} · Given ${_n(row['given'] as num?)}'),
                        children: [
                          for (final r in (row['on_hand'] as List).cast<Map>())
                            ListTile(
                              dense: true,
                              title: Text('${(r['product'] as Map)['name']}'),
                              trailing: Text(_n(r['quantity'] as num?),
                                  style: const TextStyle(fontWeight: FontWeight.w900)),
                            ),
                          if ((row['on_hand'] as List).isEmpty)
                            const ListTile(dense: true, title: Text('Nothing in hand')),
                        ],
                      ),
                    const SizedBox(height: 12),
                  ],
                  const Text('In hand', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                  if (onHand.isEmpty)
                    const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('Nothing in hand.', style: TextStyle(color: AppColors.muted))),
                  for (final r in onHand)
                    ListTile(
                      dense: true,
                      title: Text('${(r['product'] as Map)['name']}'),
                      trailing: Text(_n(r['quantity'] as num?),
                          style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: ((r['quantity'] as num?) ?? 0) < 0 ? AppColors.danger : AppColors.success)),
                    ),
                  const SizedBox(height: 12),
                  const Text('Movements', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                  for (final m in moves)
                    ListTile(
                      dense: true,
                      leading: Icon(m['direction'] == 'in' ? Icons.south_west_rounded : Icons.north_east_rounded,
                          color: m['direction'] == 'in' ? AppColors.sky : AppColors.purple),
                      title: Text('${m['product']}  ×  ${_n(m['quantity'] as num?)}'),
                      subtitle: Text(
                          '${m['direction'] == 'in' ? 'From ${m['source_type'] ?? ''}' : 'Given to'} '
                          '${m['contact'] ?? ''}  ·  ${'${m['date']}'.split('T').first}'),
                    ),
                ],
              ),
            ),
    );
  }
}
