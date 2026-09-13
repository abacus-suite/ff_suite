import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

const _basisLabels = {
  'gps': 'GPS distance',
  'client': 'Client to client',
  'route': 'Route to route',
  'fixed': 'Fixed per day',
};

/// Daily travel allowance calculated by the server, with the journey legs.
class AllowanceScreen extends StatefulWidget {
  const AllowanceScreen({super.key});

  @override
  State<AllowanceScreen> createState() => _AllowanceScreenState();
}

class _AllowanceScreenState extends State<AllowanceScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;
  final Set<int> _busy = {};

  String get _monthKey => '${_month.year}-${_month.month.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await Services.api.get('/api/v1/allowances', query: {'month': _monthKey}) as Map<String, dynamic>;
      if (mounted) setState(() => (_data = data, _error = null));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _shiftMonth(int months) {
    setState(() => _month = DateTime(_month.year, _month.month + months));
    _load();
  }

  Future<void> _submit(int id) async {
    setState(() => _busy.add(id));
    try {
      await Services.outbox.submit('/api/v1/allowances/$id/submit', {'uuid': const Uuid().v4()});
      if (mounted) showSnack(context, 'Sent for approval');
      await _load();
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  Future<void> _showLegs(int id) async {
    try {
      final claim = await Services.api.get('/api/v1/allowances/$id') as Map<String, dynamic>;
      final legs = ((claim['legs'] as List?) ?? []).cast<Map<String, dynamic>>();
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (_) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          shrinkWrap: true,
          children: [
            Text('${claim['date']} · ${_basisLabels[claim['basis']] ?? claim['basis']}',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const Divider(),
            if (legs.isEmpty) const Text('No journey legs recorded.'),
            for (final leg in legs)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(leg['estimated'] == true ? Icons.help_outline_rounded : Icons.check_circle_outline_rounded,
                    color: leg['estimated'] == true ? AixoloColors.warning : AixoloColors.success, size: 20),
                title: Text('${leg['name']}'),
                trailing: Text('${(leg['km'] as num?)?.toStringAsFixed(1) ?? '0'} km'),
              ),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Total'),
              trailing: Text('${claim['distance_km']} km · ${fmtMoney(claim['amount'] as num?, claim['currency'] as String?)}',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final claims = ((data?['claims'] as List?) ?? []).cast<Map<String, dynamic>>();
    final currency = data?['currency'] as String?;
    final now = DateTime.now();
    final isCurrent = _month.year == now.year && _month.month == now.month;
    return Scaffold(
      appBar: AppBar(title: const Text('Travel Allowance')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            Card(
              child: Row(
                children: [
                  IconButton(onPressed: () => _shiftMonth(-1), icon: const Icon(Icons.chevron_left_rounded)),
                  Expanded(
                    child: Center(
                      child: Text('${monthNames[_month.month - 1]} ${_month.year}',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                  IconButton(
                    onPressed: isCurrent ? null : () => _shiftMonth(1),
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ),
            ),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null) ErrorView(message: _error!, onRetry: _load),
            if (data != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Column(
                        children: [
                          Text('${data['total_km']}',
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                          const Text('km', style: TextStyle(color: AixoloColors.muted, fontSize: 12)),
                        ],
                      ),
                      Column(
                        children: [
                          Text(fmtMoney(data['total_amount'] as num?, currency),
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                          const Text('Claimed', style: TextStyle(color: AixoloColors.muted, fontSize: 12)),
                        ],
                      ),
                      Column(
                        children: [
                          Text(fmtMoney(data['approved_amount'] as num?, currency),
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AixoloColors.success)),
                          const Text('Approved', style: TextStyle(color: AixoloColors.muted, fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            if (claims.isEmpty && !_loading)
              const EmptyView(icon: Icons.route_rounded, text: 'No travel allowance this month yet'),
            for (final claim in claims)
              Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AixoloColors.purple.withValues(alpha: 0.12),
                    child: const Icon(Icons.local_gas_station_rounded, color: AixoloColors.purple),
                  ),
                  title: Text('${claim['date']} · ${claim['distance_km']} km',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text([
                    _basisLabels[claim['basis']] ?? '${claim['basis']}',
                    '${claim['visit_count']} visits',
                    if (claim['estimated'] == true) 'estimated',
                  ].join(' · ')),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(fmtMoney(claim['amount'] as num?, currency),
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      if (claim['state'] == 'draft')
                        SizedBox(
                          height: 26,
                          child: TextButton(
                            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                            onPressed: _busy.contains(claim['id']) ? null : () => _submit(claim['id'] as int),
                            child: const Text('Submit', style: TextStyle(fontSize: 12)),
                          ),
                        )
                      else
                        StatusBadge('${claim['state']}'),
                    ],
                  ),
                  onTap: () => _showLegs(claim['id'] as int),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
