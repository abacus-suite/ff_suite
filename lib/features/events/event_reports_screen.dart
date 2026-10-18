import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/skeleton.dart';

const _bg = Color(0xFFEEF3FB);
const _green = Color(0xFF16A34A);

num _n(dynamic v) => v is num ? v : num.tryParse('$v') ?? 0;
String _q(num v) => fmtQty(v);
List<Map<String, dynamic>> _rows(dynamic v) => ((v as List?) ?? []).cast<Map<String, dynamic>>();

PreferredSizeWidget _bar(String title, String subtitle, {List<Widget>? actions}) => AppBar(
      backgroundColor: _bg,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleSpacing: 0,
      actions: actions,
      title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
        Text(subtitle, style: const TextStyle(fontSize: 11.5, color: AppColors.muted, fontWeight: FontWeight.w500)),
      ]),
    );

Future<void> _openPdf(BuildContext context, int eventId, String kind, {int? distributorId}) async {
  try {
    final r = await Services.api.post('/api/v1/events/$eventId/pdf', {
      'kind': kind,
      if (distributorId != null) 'distributor_id': distributorId,
    }) as Map<String, dynamic>;
    final url = Uri.parse(await Services.api.url('${r['path']}'));
    final opened = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) showSnack(context, 'Could not open the PDF.');
  } catch (e) {
    if (context.mounted) showProblem(context, e.toString());
  }
}

/// The "Cash and coupons for the whole event" page, with the red End the event button.
class EventCashSummaryScreen extends StatefulWidget {
  const EventCashSummaryScreen({super.key, required this.eventId, required this.name});

  final int eventId;
  final String name;

  @override
  State<EventCashSummaryScreen> createState() => _EventCashSummaryScreenState();
}

class _EventCashSummaryScreenState extends State<EventCashSummaryScreen> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await Services.api.get('/api/v1/events/${widget.eventId}/summary') as Map<String, dynamic>;
      if (mounted) setState(() => _data = d);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _end() async {
    setState(() => _busy = true);
    try {
      await Services.api.post('/api/v1/events/${widget.eventId}/complete', {});
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => EventCompletedScreen(eventId: widget.eventId, name: widget.name)));
    } catch (e) {
      if (mounted) showProblem(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final days = _rows(d?['days']);
    final value = _n(d?['coupon_value']);
    return Scaffold(
      backgroundColor: _bg,
      appBar: _bar('Events', 'End of the Event · Cash & Coupons'),
      bottomNavigationBar: d == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                child: FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFDC2626), minimumSize: const Size.fromHeight(52)),
                  onPressed: _busy ? null : _end,
                  child: _busy
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('End the event', style: TextStyle(fontWeight: FontWeight.w900)),
                ),
              ),
            ),
      body: _error != null
          ? ErrorView(message: _error!, onRetry: _load)
          : d == null
              ? const LoadingView()
              : ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                    child: Table(columnWidths: const {0: FlexColumnWidth(1.2)}, children: [
                      const TableRow(children: [
                        Text('Day', style: TextStyle(fontSize: 11, color: AppColors.muted)),
                        Text('Cash received', style: TextStyle(fontSize: 11, color: AppColors.muted)),
                        Text('Coupons', style: TextStyle(fontSize: 11, color: AppColors.muted)),
                      ]),
                      for (final (i, day) in days.indexed)
                        TableRow(children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Text('Day ${i + 1}${i == days.length - 1 ? ' (today)' : ''}',
                                style: const TextStyle(fontWeight: FontWeight.w800)),
                          ),
                          Text(fmtMoney(day['cash'] as num?, 'INR'), style: const TextStyle(fontWeight: FontWeight.w700)),
                          Text('${day['coupons']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                        ]),
                    ]),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                    child: Column(children: [
                      Row(children: [
                        const Expanded(child: Text('Cash received till now', style: TextStyle(fontWeight: FontWeight.w800))),
                        Text(fmtMoney(d['cash_total'] as num?, 'INR'), style: const TextStyle(fontWeight: FontWeight.w900)),
                      ]),
                      const Divider(height: 20),
                      Row(children: [
                        const Expanded(child: Text('Coupons used till now', style: TextStyle(fontWeight: FontWeight.w800))),
                        Text('${d['coupons_total']} × ₹${_q(value)}',
                            style: const TextStyle(fontWeight: FontWeight.w900)),
                      ]),
                    ]),
                  ),
                ]),
    );
  }
}

/// After the event ends: one line per distributor and the final report.
class EventCompletedScreen extends StatefulWidget {
  const EventCompletedScreen({super.key, required this.eventId, required this.name});

  final int eventId;
  final String name;

  @override
  State<EventCompletedScreen> createState() => _EventCompletedScreenState();
}

class _EventCompletedScreenState extends State<EventCompletedScreen> {
  Map<String, dynamic>? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await Services.api.get('/api/v1/events/${widget.eventId}/distributors') as Map<String, dynamic>;
      if (mounted) setState(() => _data = d);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows(_data?['distributors']);
    return Scaffold(
      backgroundColor: _bg,
      appBar: _bar('Events', '${widget.name} · Completed'),
      body: _error != null
          ? ErrorView(message: _error!, onRetry: _load)
          : _data == null
              ? const LoadingView()
              : ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
                  Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _green.withValues(alpha: 0.35)),
                    ),
                    child: const Text('Event completed. Distributor-wise report and the final report are ready.',
                        style: TextStyle(fontSize: 12.5, color: Color(0xFF166534))),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text('Distributor-wise report', style: TextStyle(fontWeight: FontWeight.w900)),
                  ),
                  for (final r in rows)
                    InkWell(
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => DistributorReportScreen(
                              eventId: widget.eventId, name: widget.name, row: r))).then((_) => _load()),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                        child: Row(children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('${(r['distributor'] as Map)['name']}',
                                  style: const TextStyle(fontWeight: FontWeight.w800)),
                              // The figures from the server's totals: open, add and ret (net is the number on the right).
                              Builder(builder: (_) {
                                final t = (r['totals'] as Map).cast<String, dynamic>();
                                const label = TextStyle(fontSize: 11.5, color: AppColors.muted);
                                const value = TextStyle(fontSize: 12.5, color: AppColors.text, fontWeight: FontWeight.w800);
                                return Text.rich(TextSpan(style: label, children: [
                                  const TextSpan(text: 'Opening '),
                                  TextSpan(text: _q(_n(t['open'])), style: value),
                                  const TextSpan(text: '  +  Added '),
                                  TextSpan(text: _q(_n(t['add'])), style: value),
                                  const TextSpan(text: '  −  Returned '),
                                  TextSpan(text: _q(_n(t['ret'])), style: value),
                                ]));
                              }),
                            ]),
                          ),
                          Text('${_q(_n((r['totals'] as Map)['net']))} btl',
                              style: const TextStyle(fontWeight: FontWeight.w900)),
                        ]),
                      ),
                    ),
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => FinalReportScreen(eventId: widget.eventId, name: widget.name))),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                      child: Row(children: [
                        const CircleAvatar(
                            backgroundColor: _green, child: Icon(Icons.bar_chart_rounded, color: Colors.white)),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('Final report', style: TextStyle(fontWeight: FontWeight.w800)),
                            Text('Sales, coupons, cash and UPI', style: TextStyle(fontSize: 11.5, color: AppColors.muted)),
                          ]),
                        ),
                        const Icon(Icons.chevron_right_rounded),
                      ]),
                    ),
                  ),
                ]),
    );
  }
}

/// One distributor: Flav / Open / Add / Ret / Net, Share PDF, and the debit note request.
class DistributorReportScreen extends StatefulWidget {
  const DistributorReportScreen({super.key, required this.eventId, required this.name, required this.row});

  final int eventId;
  final String name;
  final Map<String, dynamic> row;

  @override
  State<DistributorReportScreen> createState() => _DistributorReportScreenState();
}

class _DistributorReportScreenState extends State<DistributorReportScreen> {
  late bool _requested = widget.row['debit_requested'] == true;
  bool _busy = false;

  Future<void> _request() async {
    final d = widget.row['distributor'] as Map;
    setState(() => _busy = true);
    try {
      await Services.api.post('/api/v1/events/${widget.eventId}/debit-note', {'distributor_id': d['id']});
      if (mounted) setState(() => _requested = true);
    } catch (e) {
      if (mounted) showProblem(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.row;
    final d = (r['distributor'] as Map).cast<String, dynamic>();
    final flavours = _rows(r['flavours']);
    final totals = (r['totals'] as Map).cast<String, dynamic>();
    Widget cell(String t, {bool head = false, bool bold = false, Color? colour, TextAlign align = TextAlign.right}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Text(t,
              textAlign: align,
              style: TextStyle(
                  fontSize: head ? 11 : 13,
                  color: head ? AppColors.muted : colour,
                  fontWeight: head || bold ? FontWeight.w800 : FontWeight.w500)),
        );
    return Scaffold(
      backgroundColor: _bg,
      appBar: _bar('${d['name']}', widget.name),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
          child: Table(columnWidths: const {0: FlexColumnWidth(1.3)}, children: [
            TableRow(children: [
              cell('Flav', head: true, align: TextAlign.left),
              for (final h in ['Open', 'Add', 'Ret', 'Net']) cell(h, head: true),
            ]),
            for (final f in flavours)
              TableRow(children: [
                cell('${f['code']}', bold: true, align: TextAlign.left),
                for (final k in ['open', 'add', 'ret']) cell(_q(_n(f[k]))),
                cell(_q(_n(f['net'])), bold: true),
              ]),
            TableRow(decoration: const BoxDecoration(color: Color(0xFFEEF3FB)), children: [
              cell('Total', bold: true, align: TextAlign.left),
              for (final k in ['open', 'add', 'ret']) cell(_q(_n(totals[k])), bold: true),
              cell(_q(_n(totals['net'])), bold: true),
            ]),
          ]),
        ),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: () => _openPdf(context, widget.eventId, 'distributor', distributorId: d['id'] as int),
              icon: const Icon(Icons.picture_as_pdf_rounded),
              label: const Text('Share PDF'),
            ),
          ),
          if (r['is_company'] != true) ...[
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: (_requested || _busy) ? null : _request,
                child: Text(_requested ? 'Requested' : 'Request Debit Note'),
              ),
            ),
          ],
        ]),
        if (_requested)
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _green.withValues(alpha: 0.35)),
            ),
            child: Text(
                'Debit note request sent to ${d['name']} for ${_q(_n(totals['net']))} bottles – ${widget.name}.',
                style: const TextStyle(fontSize: 12.5, color: Color(0xFF166534))),
          ),
      ]),
    );
  }
}

/// Sales amount down to UPI received, flavour-wise, for a day or for all days.
class FinalReportScreen extends StatefulWidget {
  const FinalReportScreen({super.key, required this.eventId, required this.name});

  final int eventId;
  final String name;

  @override
  State<FinalReportScreen> createState() => _FinalReportScreenState();
}

class _FinalReportScreenState extends State<FinalReportScreen> {
  Map<String, dynamic>? _data;
  String? _day;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await Services.api.get('/api/v1/events/${widget.eventId}/final',
          query: {if (_day != null) 'day': _day!}) as Map<String, dynamic>;
      if (mounted) setState(() => _data = d);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final e = (d?['event'] as Map?)?.cast<String, dynamic>() ?? const {};
    final rows = _rows(d?['rows']);
    final days = ((d?['days'] as List?) ?? []).cast<String>();
    final totals = (d?['totals'] as Map?)?.cast<String, dynamic>() ?? const {};
    final dayTable = _rows(d?['day_table']);
    final dayTotalSold = dayTable.fold<num>(0, (s, t) => s + _n(t['sold']));
    final dayTotalSales = dayTable.fold<num>(0, (s, t) => s + (t['sales'] as num? ?? 0));
    final dayTotalCoupons = dayTable.fold<num>(0, (s, t) => s + (t['coupons_amount'] as num? ?? 0));
    final dayTotalNet = dayTable.fold<num>(0, (s, t) => s + (t['net_sales'] as num? ?? 0));
    final dayTotalCash = dayTable.fold<num>(0, (s, t) => s + (t['cash'] as num? ?? 0));
    final dayTotalUpi = dayTable.fold<num>(0, (s, t) => s + (t['upi'] as num? ?? 0));
    Widget line(String label, String value, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Expanded(child: Text(label, style: TextStyle(fontWeight: bold ? FontWeight.w900 : FontWeight.w600))),
            Text(value, style: TextStyle(fontWeight: FontWeight.w900, fontSize: bold ? 16 : 14)),
          ]),
        );
    return Scaffold(
      backgroundColor: _bg,
      appBar: _bar('Final Report',
          '${widget.name} · ${(e['price_category'] as Map?)?['name'] ?? ''} category'),
      body: _error != null
          ? ErrorView(message: _error!, onRetry: _load)
          : d == null
              ? const LoadingView()
              : ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 28), children: [
                  Wrap(spacing: 8, children: [
                    for (var i = 0; i < days.length; i++)
                      ChoiceChip(
                        label: Text('Day ${i + 1}'),
                        selected: _day == days[i],
                        onSelected: (_) {
                          setState(() {
                            _day = days[i];
                            _data = null;
                          });
                          _load();
                        },
                      ),
                    ChoiceChip(
                      label: const Text('All days'),
                      selected: _day == null,
                      onSelected: (_) {
                        setState(() {
                          _day = null;
                          _data = null;
                        });
                        _load();
                      },
                    ),
                  ]),
                  const SizedBox(height: 12),
                  const Text('Flavour-wise sales', style: TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columnSpacing: 14,
                        headingRowHeight: 36,
                        dataRowMinHeight: 34,
                        dataRowMaxHeight: 40,
                        columns: const [
                          DataColumn(label: Text('Flavour')),
                          DataColumn(label: Text('Opening'), numeric: true),
                          DataColumn(label: Text('Added'), numeric: true),
                          DataColumn(label: Text('Samples'), numeric: true),
                          DataColumn(label: Text('Damage'), numeric: true),
                          DataColumn(label: Text('Returned'), numeric: true),
                          DataColumn(label: Text('Sold'), numeric: true),
                          DataColumn(label: Text('MRP'), numeric: true),
                          DataColumn(label: Text('Sales ₹'), numeric: true),
                        ],
                        rows: [
                          for (final r in rows)
                            DataRow(cells: [
                              DataCell(Text('${r['code']}', style: const TextStyle(fontWeight: FontWeight.w800))),
                              DataCell(Text(_q(_n(r['opening'])))),
                              DataCell(Text(_q(_n(r['added'])))),
                              DataCell(Text(_q(_n(r['samples'])))),
                              DataCell(Text(_q(_n(r['damage'])))),
                              DataCell(Text(_q(_n(r['returned'])))),
                              DataCell(Text(_q(_n(r['sold'])),
                                  style: const TextStyle(fontWeight: FontWeight.w900, color: _green))),
                              DataCell(Text('₹${_q(_n(r['mrp']))}')),
                              DataCell(Text(fmtMoney(r['sales'] as num?, 'INR'))),
                            ]),
                          DataRow(
                            color: WidgetStateProperty.all(const Color(0xFFEEF3FB)),
                            cells: [
                              const DataCell(Text('Total', style: TextStyle(fontWeight: FontWeight.w900))),
                              DataCell(Text(_q(_n(totals['opening'])), style: const TextStyle(fontWeight: FontWeight.w900))),
                              DataCell(Text(_q(_n(totals['added'])), style: const TextStyle(fontWeight: FontWeight.w900))),
                              DataCell(Text(_q(_n(totals['samples'])), style: const TextStyle(fontWeight: FontWeight.w900))),
                              DataCell(Text(_q(_n(totals['damage'])), style: const TextStyle(fontWeight: FontWeight.w900))),
                              DataCell(Text(_q(_n(totals['returned'])), style: const TextStyle(fontWeight: FontWeight.w900))),
                              DataCell(Text(_q(_n(totals['sold'])),
                                  style: const TextStyle(fontWeight: FontWeight.w900, color: _green))),
                              const DataCell(Text('')),
                              DataCell(Text(fmtMoney(d['sales'] as num?, 'INR'),
                                  style: const TextStyle(fontWeight: FontWeight.w900))),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text('Sold = Opening + Added − Samples − Damage − Returned',
                      style: TextStyle(fontSize: 12, color: AppColors.muted)),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                    child: Column(children: [
                      line('Sales amount flavour-wise total', fmtMoney(d['sales'] as num?, 'INR')),
                      line('Less: Coupons ${d['coupons']} × ₹${_q(_n(d['coupon_value']))}',
                          '− ${fmtMoney(d['coupon_amount'] as num?, 'INR')}'),
                      const Divider(),
                      line('Net sales', fmtMoney(d['net_sales'] as num?, 'INR'), bold: true),
                      line('Less: Cash received ${_day == null ? 'all days' : 'this day'}',
                          '− ${fmtMoney(d['cash'] as num?, 'INR')}'),
                      const Divider(),
                      // UPI received sits in a light green box, like the bank-check note under it.
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE6F7EC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF86D9A3)),
                        ),
                        child: line('UPI received', fmtMoney(d['upi'] as num?, 'INR'), bold: true),
                      ),
                    ]),
                  ),
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE6F7EC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFBFE8CC)),
                    ),
                    child: const Text('Match UPI received with the bank credit for the same day(s).',
                        style: TextStyle(fontSize: 12, color: Color(0xFF166534), fontWeight: FontWeight.w600)),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    onPressed: () => _openPdf(context, widget.eventId, 'final'),
                    icon: const Icon(Icons.picture_as_pdf_rounded),
                    label: const Text('Share PDF'),
                  ),
                  const SizedBox(height: 18),
                  const Text('Day-wise reconciliation', style: TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columnSpacing: 14,
                        headingRowHeight: 36,
                        dataRowMinHeight: 34,
                        dataRowMaxHeight: 40,
                        columns: const [
                          DataColumn(label: Text('Day')),
                          DataColumn(label: Text('Sold'), numeric: true),
                          DataColumn(label: Text('Sales'), numeric: true),
                          DataColumn(label: Text('Coupons'), numeric: true),
                          DataColumn(label: Text('Net'), numeric: true),
                          DataColumn(label: Text('Cash'), numeric: true),
                          DataColumn(label: Text('UPI'), numeric: true),
                        ],
                        rows: [
                          for (final (i, t) in dayTable.indexed)
                            DataRow(cells: [
                              DataCell(Text('Day ${i + 1}')),
                              DataCell(Text(_q(_n(t['sold'])))),
                              DataCell(Text(fmtMoney(t['sales'] as num?, 'INR'))),
                              DataCell(Text(t['coupons_amount'] != null && _n(t['coupons_amount']) > 0
                                  ? '− ${fmtMoney(t['coupons_amount'] as num?, 'INR')}'
                                  : '₹0')),
                              DataCell(Text(fmtMoney(t['net_sales'] as num?, 'INR'))),
                              DataCell(Text(t['cash'] != null && _n(t['cash']) > 0
                                  ? '− ${fmtMoney(t['cash'] as num?, 'INR')}'
                                  : '₹0')),
                              DataCell(Text(fmtMoney(t['upi'] as num?, 'INR'),
                                  style: const TextStyle(fontWeight: FontWeight.w900))),
                            ]),
                          if (dayTable.isNotEmpty)
                            DataRow(
                              color: WidgetStateProperty.all(const Color(0xFFEEF3FB)),
                              cells: [
                                const DataCell(Text('Total', style: TextStyle(fontWeight: FontWeight.w900))),
                                DataCell(Text(_q(dayTotalSold), style: const TextStyle(fontWeight: FontWeight.w900))),
                                DataCell(Text(fmtMoney(dayTotalSales, 'INR'), style: const TextStyle(fontWeight: FontWeight.w900))),
                                DataCell(Text(dayTotalCoupons > 0 ? '− ${fmtMoney(dayTotalCoupons, 'INR')}' : '₹0',
                                    style: const TextStyle(fontWeight: FontWeight.w900))),
                                DataCell(Text(fmtMoney(dayTotalNet, 'INR'), style: const TextStyle(fontWeight: FontWeight.w900))),
                                DataCell(Text(dayTotalCash > 0 ? '− ${fmtMoney(dayTotalCash, 'INR')}' : '₹0',
                                    style: const TextStyle(fontWeight: FontWeight.w900))),
                                DataCell(Text(fmtMoney(dayTotalUpi, 'INR'),
                                    style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF166534)))),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text('UPI ₹ for each day should match the bank credit for that day.',
                      style: TextStyle(fontSize: 12, color: AppColors.muted)),
                ]),
    );
  }
}
