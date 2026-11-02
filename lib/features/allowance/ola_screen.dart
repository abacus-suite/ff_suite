import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/skeleton.dart';

num _n(dynamic v) => v is num ? v : num.tryParse('$v') ?? 0;

/// OLA: a month amount over 26 days, paid in full, half or not at all by the hours worked each day.
class OlaScreen extends StatefulWidget {
  const OlaScreen({super.key});

  @override
  State<OlaScreen> createState() => _OlaScreenState();
}

class _OlaScreenState extends State<OlaScreen> {
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
      final d = await Services.api.get('/api/v1/ola', query: {'month': _key}) as Map<String, dynamic>;
      if (mounted) setState(() => _data = d);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  void _shift(int by) {
    setState(() => _month = DateTime(_month.year, _month.month + by));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final currency = d?['currency'] as String?;
    final days = ((d?['days'] as List?) ?? []).cast<Map<String, dynamic>>();
    const kinds = {'full': 'Full', 'half': 'Half', 'none': 'No allowance'};
    Color tint(String kind) => kind == 'full' ? AppColors.success : kind == 'half' ? AppColors.warning : AppColors.muted;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('OLA')),
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
                        gradient: const LinearGradient(colors: [Color(0xFF7C3AED), Color(0xFF8B5CF6)]),
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
                          Text('${fmtMoney(d['monthly'] as num?, currency)} a month',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                          Text('${fmtMoney(d['per_day'] as num?, currency)} a full day',
                              style: const TextStyle(color: Colors.white70, fontSize: 12)),
                        ]),
                      ]),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(2, 10, 2, 10),
                      child: Text(
                          d['applicable'] == true
                              ? 'Under ${_n(d['half_hours'])} hours: no allowance. ${_n(d['half_hours'])} to under '
                                  '${_n(d['full_hours'])} hours: half. ${_n(d['full_hours'])} hours or more: full. '
                                  'Paid monthly with salary.'
                              : 'OLA is not set up for you. Ask the office if it applies to you.',
                          style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                    ),
                    if (days.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(30),
                        child: Center(child: Text('No days this month yet.', style: TextStyle(color: AppColors.muted))),
                      ),
                    for (final day in days)
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                        child: Row(children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('${day['date']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                              Text('${_n(day['hours'])} hours worked',
                                  style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                            ]),
                          ),
                          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Text(fmtMoney(day['amount'] as num?, currency),
                                style: const TextStyle(fontWeight: FontWeight.w900)),
                            Text(kinds['${day['kind']}'] ?? '',
                                style: TextStyle(
                                    fontSize: 11.5, fontWeight: FontWeight.w800, color: tint('${day['kind']}'))),
                          ]),
                        ]),
                      ),
                  ]),
                ),
    );
  }
}
