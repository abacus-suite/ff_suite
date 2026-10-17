import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/skeleton.dart';
import '../receivables/receivables_screen.dart';

/// Where the Home Overdue card leads: the team's overdue money, outlet by outlet or distributor by distributor.
class OverdueScreen extends StatefulWidget {
  const OverdueScreen({super.key, this.initialType = 'outlet'});

  final String initialType; // outlet | distributor

  @override
  State<OverdueScreen> createState() => _OverdueScreenState();
}

class _OverdueScreenState extends State<OverdueScreen> {
  late String _type = widget.initialType;
  final Map<String, Map<String, dynamic>> _data = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = !_data.containsKey(_type);
      _error = null;
    });
    final type = _type;
    try {
      final d = await Services.api.get('/api/v1/receivables', query: {'filter': 'overdue', 'kind': type}) as Map<String, dynamic>;
      if (mounted) setState(() => _data[type] = d);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  /// The invoices of one list, gathered per customer: what they owe, how late, how many invoices.
  List<_Row> _rows() {
    final invoices = ((_data[_type]?['invoices'] as List?) ?? []).cast<Map<String, dynamic>>();
    final byCustomer = <int, _Row>{};
    for (final inv in invoices) {
      final c = (inv['customer'] as Map?)?.cast<String, dynamic>();
      if (c == null) continue;
      final id = c['id'] as int;
      final row = byCustomer.putIfAbsent(id, () => _Row(id, '${c['name']}', _owner(inv, c)));
      row.amount += (inv['residual'] as num?) ?? 0;
      row.invoices += 1;
      final days = (inv['days_overdue'] as num?)?.toInt() ?? 0;
      if (days > row.days) row.days = days;
    }
    return byCustomer.values.toList()..sort((a, b) => b.amount.compareTo(a.amount));
  }

  String _owner(Map<String, dynamic> inv, Map<String, dynamic> c) {
    for (final v in [inv['employee'], inv['salesperson'], c['employee'], c['salesperson']]) {
      if (v is Map && v['name'] != null) return '${v['name']}';
      if (v is String && v.isNotEmpty) return v;
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final currency = _data[_type]?['currency'] as String?;
    final rows = _rows();
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Overdue', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          Text('Team · as on ${now.day.toString().padLeft(2, '0')} ${_months[now.month - 1]}', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
        ]),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<String>(
              showSelectedIcon: true,
              segments: const [
                ButtonSegment(value: 'outlet', label: Text('Outlets')),
                ButtonSegment(value: 'distributor', label: Text('Distributors')),
              ],
              selected: {_type},
              onSelectionChanged: (v) {
                setState(() => _type = v.first);
                _load();
              },
            ),
          ),
        ),
        Expanded(
          child: _loading
              ? const LoadingView()
              : _error != null && !_data.containsKey(_type)
                  ? ErrorView(message: _error!, onRetry: _load)
                  : rows.isEmpty
                      ? const Center(child: Text('Nothing overdue.', style: TextStyle(color: AppColors.muted)))
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
                            for (final r in rows)
                              Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                child: ListTile(
                                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                                      builder: (_) => ReceivablesScreen(partnerId: r.id, partnerName: r.name))),
                                  title: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                                  subtitle: Text([if (r.owner.isNotEmpty) r.owner, '${r.days} days'].join(' · '), style: const TextStyle(fontSize: 11.5)),
                                  trailing: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.center, children: [
                                    Text(fmtMoney(r.amount, currency), style: const TextStyle(fontWeight: FontWeight.w900)),
                                    Text('${r.invoices} invoice${r.invoices == 1 ? '' : 's'}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.danger)),
                                  ]),
                                ),
                              ),
                          ]),
                        ),
        ),
      ]),
    );
  }
}

class _Row {
  _Row(this.id, this.name, this.owner);

  final int id;
  final String name;
  final String owner;
  num amount = 0;
  int invoices = 0;
  int days = 0;
}
