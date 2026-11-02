import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/skeleton.dart';

num _n(dynamic v) => v is num ? v : num.tryParse('$v') ?? 0;

/// My Daily Allowance (DA): worked out from where the day's visits were, grouped by week.
class DailyAllowanceScreen extends StatefulWidget {
  const DailyAllowanceScreen({super.key});

  @override
  State<DailyAllowanceScreen> createState() => _DailyAllowanceScreenState();
}

class _DailyAllowanceScreenState extends State<DailyAllowanceScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  Map<String, dynamic>? _data;
  String? _error;

  String get _key => '${_month.year}-${_month.month.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _data = null;
    });
    try {
      final d = await Services.api.get('/api/v1/da', query: {'month': _key}) as Map<String, dynamic>;
      if (mounted) setState(() => _data = d);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  void _shift(int by) {
    setState(() => _month = DateTime(_month.year, _month.month + by));
    _load();
  }

  Color _tint(String state) => switch (state) {
        'approved' => AppColors.success,
        'rejected' => AppColors.danger,
        'submitted' => AppColors.warning,
        _ => AppColors.muted,
      };

  String _label(String state) => switch (state) {
        'approved' => 'Approved',
        'rejected' => 'Rejected',
        'submitted' => 'With manager',
        _ => 'Calculated',
      };

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final currency = d?['currency'] as String?;
    final rates = (d?['rates'] as Map?)?.cast<String, dynamic>() ?? const {};
    final weeks = ((d?['weeks'] as List?) ?? []).cast<Map<String, dynamic>>();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Daily Allowance (DA)')),
      body: _error != null
          ? ErrorView(message: _error!, onRetry: _load)
          : d == null
              ? const LoadingView()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
                    Row(children: [
                      IconButton(onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left_rounded)),
                      Expanded(
                        child: Center(
                          child: Text('${monthNames[_month.month - 1]} ${_month.year}',
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                        ),
                      ),
                      IconButton(onPressed: () => _shift(1), icon: const Icon(Icons.chevron_right_rounded)),
                    ]),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFF0F766E), Color(0xFF14B8A6)]),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            const Text('This month', style: TextStyle(color: Colors.white70)),
                            Text(fmtMoney(d['total'] as num?, currency),
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 26)),
                          ]),
                        ),
                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text('${rates['designation'] ?? ''}',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                          Text(
                              rates['set'] == true
                                  ? 'Primary ${rates['primary'] == null ? 'NA' : fmtMoney(rates['primary'] as num?, currency)}'
                                      ' · Outside ${fmtMoney(rates['outside'] as num?, currency)}'
                                  : 'No DA rate is set for you yet',
                              style: const TextStyle(color: Colors.white70, fontSize: 12)),
                        ]),
                      ]),
                    ),
                    const SizedBox(height: 6),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(2, 8, 2, 8),
                      child: Text(
                          'Worked out from the outlets and distributors you visit: the outside rate on a day '
                          'you visit outside your primary territory, otherwise the primary rate. Paid every week.',
                          style: TextStyle(fontSize: 12, color: AppColors.muted)),
                    ),
                    if (weeks.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(30),
                        child: Center(child: Text('No allowance for these dates.', style: TextStyle(color: AppColors.muted))),
                      ),
                    for (final w in weeks)
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                        child: Theme(
                          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                          child: ExpansionTile(
                            tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                            title: Text('${w['week_start']} to ${w['week_end']}',
                                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5)),
                            subtitle: Text(
                                '${(w['days'] as List).length} day(s) · ${w['outside_days']} outside territory',
                                style: const TextStyle(fontSize: 12)),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(fmtMoney(w['total'] as num?, currency),
                                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                                Text(_label('${w['state']}'),
                                    style: TextStyle(
                                        fontSize: 11.5, fontWeight: FontWeight.w800, color: _tint('${w['state']}'))),
                              ],
                            ),
                            children: [
                              for (final day in ((w['days'] as List?) ?? []).cast<Map<String, dynamic>>())
                                ListTile(
                                  dense: true,
                                  title: Text('${day['date']}'),
                                  subtitle: Text(
                                      '${day['kind'] == 'outside' ? 'Outside territory' : 'Primary territory'}'
                                      ' · ${day['visits']} visit(s)'
                                      '${_n(day['outside_visits']) > 0 ? ' (${day['outside_visits']} outside)' : ''}'),
                                  trailing: Text(fmtMoney(day['amount'] as num?, currency),
                                      style: const TextStyle(fontWeight: FontWeight.w800)),
                                ),
                            ],
                          ),
                        ),
                      ),
                  ]),
                ),
    );
  }
}
