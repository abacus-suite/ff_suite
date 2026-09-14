import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

const _bucketColours = {
  'not_due': AppColors.success,
  '1_30': AppColors.warning,
  '31_60': Color(0xFFEA580C),
  '61_90': AppColors.danger,
  '90_plus': Color(0xFF991B1B),
};

String _prettyDate(String? iso) {
  if (iso == null) return '–';
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}

/// Open invoices for the customers I can see: all, overdue or due this week, with ageing.
class ReceivablesScreen extends StatefulWidget {
  const ReceivablesScreen({super.key, this.partnerId, this.partnerName});

  final int? partnerId;
  final String? partnerName;

  @override
  State<ReceivablesScreen> createState() => _ReceivablesScreenState();
}

class _ReceivablesScreenState extends State<ReceivablesScreen> {
  String _filter = 'open';
  final _search = TextEditingController();
  Timer? _debounce;
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await Services.api.get('/api/v1/receivables', query: {
        'filter': _filter,
        if (widget.partnerId != null) 'partner_id': widget.partnerId,
        if (_search.text.trim().isNotEmpty) 'q': _search.text.trim(),
      }) as Map<String, dynamic>;
      if (mounted) setState(() => _data = data);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final currency = data?['currency'] as String?;
    final invoices = ((data?['invoices'] as List?) ?? []).cast<Map<String, dynamic>>();
    final ageing = ((data?['ageing'] as List?) ?? []).cast<Map<String, dynamic>>();
    return Scaffold(
      appBar: AppBar(title: Text(widget.partnerName == null ? 'Receivables' : 'Invoices · ${widget.partnerName}')),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
            child: Column(
              children: [
                if (widget.partnerId == null)
                  TextField(
                    controller: _search,
                    onChanged: (_) {
                      _debounce?.cancel();
                      _debounce = Timer(const Duration(milliseconds: 450), _load);
                    },
                    decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search_rounded), hintText: 'Search customer or code', isDense: true),
                  ),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'open', label: Text('All open')),
                    ButtonSegment(value: 'overdue', label: Text('Overdue')),
                    ButtonSegment(value: 'due_soon', label: Text('Due in 7 days')),
                  ],
                  selected: {_filter},
                  onSelectionChanged: (v) {
                    setState(() => _filter = v.first);
                    _load();
                  },
                ),
              ],
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: _error != null
                ? ErrorView(message: _error!, onRetry: _load)
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
                      children: [
                        if (data != null)
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _figure('Outstanding', fmtMoney(data['total'] as num?, currency),
                                            AppColors.primary),
                                      ),
                                      Expanded(
                                        child: _figure('Overdue', fmtMoney(data['overdue'] as num?, currency),
                                            AppColors.danger),
                                      ),
                                      Expanded(child: _figure('Invoices', '${data['count']}', AppColors.text)),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  for (final a in ageing)
                                    if ((a['amount'] as num? ?? 0) != 0)
                                      Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 2),
                                        child: Row(
                                          children: [
                                            Container(
                                                width: 10,
                                                height: 10,
                                                decoration: BoxDecoration(
                                                    color: _bucketColours[a['key']], shape: BoxShape.circle)),
                                            const SizedBox(width: 8),
                                            Expanded(child: Text('${a['label']}')),
                                            Text(fmtMoney(a['amount'] as num?, currency),
                                                style: const TextStyle(fontWeight: FontWeight.w700)),
                                          ],
                                        ),
                                      ),
                                ],
                              ),
                            ),
                          ),
                        if (data != null && invoices.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(40),
                            child: Center(child: Text('Nothing outstanding here', style: TextStyle(color: AppColors.muted))),
                          ),
                        for (final inv in invoices)
                          Card(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: widget.partnerId != null
                                  ? null
                                  : () => Navigator.of(context).push(MaterialPageRoute(
                                      builder: (_) => StatementScreen(
                                          partnerId: (inv['customer'] as Map)['id'] as int,
                                          name: '${(inv['customer'] as Map)['name']}'))),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 4,
                                      height: 46,
                                      decoration: BoxDecoration(
                                          color: _bucketColours[inv['bucket']], borderRadius: BorderRadius.circular(4)),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                              widget.partnerId == null
                                                  ? '${(inv['customer'] as Map)['name']}'
                                                  : '${inv['number']}',
                                              style: const TextStyle(fontWeight: FontWeight.w700)),
                                          Text(
                                              [
                                                if (widget.partnerId == null) inv['number'],
                                                'Due ${_prettyDate(inv['due_date'] as String?)}',
                                              ].join(' · '),
                                              style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(fmtMoney(inv['residual'] as num?, currency),
                                            style: const TextStyle(fontWeight: FontWeight.w800)),
                                        Text(
                                          (inv['days_overdue'] as num? ?? 0) > 0
                                              ? '${inv['days_overdue']} days late'
                                              : inv['is_refund'] == true
                                                  ? 'Credit note'
                                                  : 'Not due',
                                          style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: _bucketColours[inv['bucket']]),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _figure(String label, String value, Color colour) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: colour)),
          ),
        ],
      );
}

/// Statement of account: opening balance, invoices, credit notes and payments, running balance.
class StatementScreen extends StatefulWidget {
  const StatementScreen({super.key, required this.partnerId, required this.name});

  final int partnerId;
  final String name;

  @override
  State<StatementScreen> createState() => _StatementScreenState();
}

class _StatementScreenState extends State<StatementScreen> {
  late DateTimeRange _range;
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _range = DateTimeRange(start: DateTime(today.year, today.month - 3, 1), end: today);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await Services.api.get('/api/v1/clients/${widget.partnerId}/soa',
          query: {'start': fmtDate(_range.start), 'end': fmtDate(_range.end)}) as Map<String, dynamic>;
      if (mounted) setState(() => _data = data);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _range,
    );
    if (picked == null) return;
    setState(() => _range = picked);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final currency = data?['currency'] as String?;
    final lines = ((data?['lines'] as List?) ?? []).cast<Map<String, dynamic>>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Statement of account'),
        actions: [
          IconButton(
            tooltip: 'Open invoices',
            icon: const Icon(Icons.receipt_long_rounded),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => ReceivablesScreen(partnerId: widget.partnerId, partnerName: widget.name))),
          ),
        ],
      ),
      body: _error != null
          ? ErrorView(message: _error!, onRetry: _load)
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                          TextButton.icon(
                            onPressed: _pickRange,
                            icon: const Icon(Icons.date_range_rounded),
                            label: Text('${_prettyDate(fmtDate(_range.start))} – ${_prettyDate(fmtDate(_range.end))}'),
                          ),
                          if (data != null)
                            Row(
                              children: [
                                Expanded(child: _pair('Opening', fmtMoney(data['opening'] as num?, currency))),
                                Expanded(child: _pair('Billed', fmtMoney(data['debit'] as num?, currency))),
                                Expanded(child: _pair('Received', fmtMoney(data['credit'] as num?, currency))),
                                Expanded(
                                    child: _pair('Closing', fmtMoney(data['closing'] as num?, currency),
                                        colour: AppColors.primary)),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (_loading) const LinearProgressIndicator(minHeight: 2),
                  if (data != null && lines.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(child: Text('No entries in this period', style: TextStyle(color: AppColors.muted))),
                    ),
                  if (lines.isNotEmpty)
                    Card(
                      clipBehavior: Clip.antiAlias,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          headingRowColor: const WidgetStatePropertyAll(Color(0xFFE8EFFF)),
                          columnSpacing: 18,
                          horizontalMargin: 12,
                          columns: const [
                            DataColumn(label: Text('Date')),
                            DataColumn(label: Text('Entry')),
                            DataColumn(label: Text('Reference')),
                            DataColumn(label: Text('Debit'), numeric: true),
                            DataColumn(label: Text('Credit'), numeric: true),
                            DataColumn(label: Text('Balance'), numeric: true),
                          ],
                          rows: [
                            for (final l in lines)
                              DataRow(cells: [
                                DataCell(Text(_prettyDate(l['date'] as String?))),
                                DataCell(Text('${l['kind']} ${l['number']}')),
                                DataCell(Text('${l['reference'] ?? ''}', overflow: TextOverflow.ellipsis)),
                                DataCell(Text((l['debit'] as num? ?? 0) == 0 ? '' : fmtMoney(l['debit'] as num?, currency))),
                                DataCell(Text((l['credit'] as num? ?? 0) == 0 ? '' : fmtMoney(l['credit'] as num?, currency))),
                                DataCell(Text(fmtMoney(l['balance'] as num?, currency),
                                    style: const TextStyle(fontWeight: FontWeight.w700))),
                              ]),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _pair(String label, String value, {Color colour = AppColors.text}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
          FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: colour))),
        ],
      );
}
