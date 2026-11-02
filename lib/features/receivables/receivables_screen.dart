import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../collections/ledger_share.dart';
import '../orders/demand_send.dart';

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

  /// Outlets or Distributors only; null shows both.
  String? _kind;
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
        if (_kind != null) 'kind': _kind,
        if (_search.text.trim().isNotEmpty) 'q': _search.text.trim(),
      }) as Map<String, dynamic>;
      if (mounted) setState(() => _data = data);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _sendingLedger = false;

  Future<void> _sendLedgerOnWhatsApp() async {
    if (widget.partnerId == null) return;
    setState(() => _sendingLedger = true);
    try {
      Map<String, dynamic>? client;
      try {
        client = await Services.api.get('/api/v1/clients/${widget.partnerId}') as Map<String, dynamic>?;
      } catch (_) {}

      final clientName = widget.partnerName ?? client?['name'] ?? 'Customer';
      final pocPhone = (client?['accounts_poc_phone'] as String?)?.trim().isNotEmpty == true
          ? (client!['accounts_poc_phone'] as String).trim()
          : (client?['phone'] as String?)?.trim().isNotEmpty == true
              ? (client!['phone'] as String).trim()
              : (client?['poc_phone'] as String?)?.trim().isNotEmpty == true
                  ? (client!['poc_phone'] as String).trim()
                  : null;
      final pocName = (client?['accounts_poc_name'] as String?)?.trim().isNotEmpty == true
          ? (client!['accounts_poc_name'] as String).trim()
          : (client?['poc_name'] as String?)?.trim().isNotEmpty == true
              ? (client!['poc_name'] as String).trim()
              : null;

      // The ledger itself, as a PDF, into the accounts contact's WhatsApp chat.
      if (!mounted) return;
      final sentPdf = await sendLedgerToContact(
        context,
        {...?client, 'id': widget.partnerId, 'name': clientName},
        phone: pocPhone,
        contactName: pocName,
      );
      if (sentPdf) return;

      // No statement from the server: the summary goes as a message instead, as before.
      final currency = _data?['currency'] as String?;
      final totalFmt = fmtMoney(_data?['total'] as num?, currency);
      final overdueFmt = fmtMoney(_data?['overdue'] as num?, currency);
      final count = _data?['count'] ?? 0;
      final invoices = ((_data?['invoices'] as List?) ?? []).cast<Map<String, dynamic>>();

      final buffer = StringBuffer();
      if (pocName != null && pocName.isNotEmpty) {
        buffer.writeln('Hello $pocName,');
      } else {
        buffer.writeln('Hello,');
      }
      buffer.writeln('Here is the outstanding statement for $clientName:');
      buffer.writeln('• Total Outstanding: $totalFmt');
      buffer.writeln('• Overdue: $overdueFmt');
      buffer.writeln('• Invoices: $count');
      if (invoices.isNotEmpty) {
        buffer.writeln('\nInvoices:');
        for (final inv in invoices.take(6)) {
          final invNum = inv['number'];
          final res = fmtMoney(inv['residual'] as num?, currency);
          final due = _prettyDate(inv['due_date'] as String?);
          buffer.writeln('• $invNum: $res (Due $due)');
        }
        if (invoices.length > 6) {
          buffer.writeln('... and ${invoices.length - 6} more invoice(s)');
        }
      }
      buffer.writeln('\nPlease arrange payment at your earliest convenience. Thank you!');

      final launched = await openWhatsApp(pocPhone, buffer.toString());
      if (!launched && mounted) {
        showSnack(context, 'Could not open WhatsApp');
      }
    } catch (e) {
      if (mounted) showSnack(context, 'Error: $e');
    } finally {
      if (mounted) setState(() => _sendingLedger = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final currency = data?['currency'] as String?;
    final invoices = ((data?['invoices'] as List?) ?? []).cast<Map<String, dynamic>>();
    final customers = ((data?['customers'] as List?) ?? []).cast<Map<String, dynamic>>();
    final ageing = ((data?['ageing'] as List?) ?? []).cast<Map<String, dynamic>>();
    return Scaffold(
      appBar: AppBar(
        actions: [
          if (widget.partnerId != null)
            IconButton(
              tooltip: 'Statement of account',
              icon: const Icon(Icons.receipt_long_rounded),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => StatementScreen(partnerId: widget.partnerId!, name: widget.partnerName ?? ''))),
            ),
        ],
        title: widget.partnerName != null
            ? Text('Invoices \u00B7 ${widget.partnerName}')
            : Row(
                children: [
                  const Text('Receivables'),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 38,
                      child: TextField(
                        controller: _search,
                        onChanged: (_) {
                          _debounce?.cancel();
                          _debounce = Timer(const Duration(milliseconds: 450), _load);
                        },
                        style: const TextStyle(fontSize: 14),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search_rounded, size: 20),
                          hintText: 'Search...',
                          isDense: true,
                          filled: true,
                          fillColor: AppColors.background,
                          contentPadding: EdgeInsets.zero,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
            child: Column(
              children: [
                if (widget.partnerId == null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        _kindButton('Outlet', 'outlet', Icons.storefront_rounded),
                        _kindButton('Distributors', 'distributor', Icons.local_shipping_rounded),
                      ],
                    ),
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
          // The summary stays where it is while the invoices scroll under it.
          if (data != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _figure('Outstanding', fmtMoney(data['total'] as num?, currency), AppColors.primary),
                          ),
                          Expanded(
                            child: _figure('Overdue', fmtMoney(data['overdue'] as num?, currency), AppColors.danger),
                          ),
                          Expanded(child: _figure('Invoices', '${data['count']}', AppColors.text)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      for (final a in ageing)
                        if ((a['amount'] as num? ?? 0) != 0)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              children: [
                                Container(
                                    width: 9,
                                    height: 9,
                                    decoration: BoxDecoration(color: _bucketColours[a['key']], shape: BoxShape.circle)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text('${a['label']}',
                                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                                ),
                                Text(fmtMoney(a['amount'] as num?, currency),
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                              ],
                            ),
                          ),
                    ],
                  ),
                ),
              ),
            ),
          Expanded(
            child: _error != null
                ? ErrorView(message: _error!, onRetry: _load)
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
                      children: [
                        // First the contacts and what each owes; a contact opens its invoices.
                        if (widget.partnerId == null)
                          for (final c in customers)
                            Card(
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                                    builder: (_) => ReceivablesScreen(
                                        partnerId: (c['customer'] as Map)['id'] as int,
                                        partnerName: '${(c['customer'] as Map)['name']}'))),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(children: [
                                    Container(
                                      width: 4,
                                      height: 46,
                                      decoration: BoxDecoration(
                                          color: _bucketColours[c['bucket']], borderRadius: BorderRadius.circular(4)),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                        Text('${(c['customer'] as Map)['name']}',
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(fontWeight: FontWeight.w700)),
                                        Text('${c['count']} invoice${c['count'] == 1 ? '' : 's'}',
                                            style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                                      ]),
                                    ),
                                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                      Text(fmtMoney(c['total'] as num?, currency),
                                          style: const TextStyle(fontWeight: FontWeight.w800)),
                                      if ((c['overdue'] as num? ?? 0) > 0)
                                        Text('${fmtMoney(c['overdue'] as num?, currency)} overdue',
                                            style: TextStyle(
                                                fontSize: 12, fontWeight: FontWeight.w700, color: _bucketColours[c['bucket']]))
                                      else
                                        const Text('Not due',
                                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.success)),
                                    ]),
                                    const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
                                  ]),
                                ),
                              ),
                            ),
                        if (data != null && invoices.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(40),
                            child: Column(
                              children: [
                                const Text('Nothing outstanding here',
                                    style: TextStyle(color: AppColors.muted)),
                                // An invoice still in draft is not money owed yet,
                                // and is the usual reason this looks empty.
                                if ((data['draft_count'] as num? ?? 0) > 0) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    '${data['draft_count']} '
                                    '${(data['draft_count'] as num) == 1 ? 'invoice is' : 'invoices are'} '
                                    'still a draft in the office and will appear once confirmed.',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 12.5, color: AppColors.warning),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        if (widget.partnerId != null)
                        for (final inv in invoices)
                          Card(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                                  builder: (_) => InvoiceDetailScreen(
                                  id: inv['id'] as int, number: '${inv['number']}', source: '${inv['source'] ?? 'move'}'))),
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
                                                'Invoiced ${_prettyDate(inv['date'] as String?)}',
                                                'Due ${_prettyDate(inv['due_date'] as String?)}',
                                                if (inv['salesperson'] != null) '${inv['salesperson']}',
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
      bottomNavigationBar: widget.partnerId == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF25D366),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                      elevation: 0,
                    ),
                    onPressed: _sendingLedger ? null : _sendLedgerOnWhatsApp,
                    child: _sendingLedger
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text(
                            'Send Ledger on WhatsApp',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
              ),
            ),
    );
  }

  /// Outlet / Distributors: a pill, filled blue while chosen.
  Widget _kindButton(String label, String kind, IconData icon) {
    final on = _kind == kind;
    return InkWell(
      borderRadius: BorderRadius.circular(26),
      onTap: () {
        setState(() => _kind = on ? null : kind);
        _load();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
        decoration: BoxDecoration(
          color: on ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: on ? AppColors.primary : AppColors.border),
        ),
        child: Text(label,
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, color: on ? Colors.white : AppColors.text)),
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


/// One invoice: who it is to, the dates and payment terms, every item, the taxes, and what has been paid.
class InvoiceDetailScreen extends StatefulWidget {
  const InvoiceDetailScreen({super.key, required this.id, required this.number, this.source = 'move'});

  final int id;
  final String number;

  /// 'move' for an accounting invoice, 'outlet' for an invoice an outlet owes through the demand flow.
  final String source;

  @override
  State<InvoiceDetailScreen> createState() => _InvoiceDetailScreenState();
}

class _InvoiceDetailScreenState extends State<InvoiceDetailScreen> {
  Map<String, dynamic>? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await Services.api.get(
          widget.source == 'outlet' ? '/api/v1/receivables/outlet-invoice/${widget.id}' : '/api/v1/receivables/invoice/${widget.id}') as Map<String, dynamic>;
      if (mounted) setState(() => _data = d);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final currency = d?['currency'] as String?;
    String money(Object? v) => fmtMoney(v as num?, currency);
    Widget line(String label, String value, {bool bold = false, Color? colour}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Text(label, style: TextStyle(color: bold ? AppColors.text : AppColors.muted, fontWeight: bold ? FontWeight.w800 : FontWeight.w500))),
            const SizedBox(width: 12),
            Flexible(child: Text(value, textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w800, color: colour))),
          ]),
        );
    Widget box(List<Widget> children) => Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
        );
    return Scaffold(
      appBar: AppBar(title: Text(widget.number)),
      body: _error != null
          ? ErrorView(message: _error!, onRetry: _load)
          : d == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(padding: const EdgeInsets.all(12), children: [
                  box([
                    Text('${(d['customer'] as Map)['name']}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                    if ((d['billed_to'] as Map)['id'] != (d['customer'] as Map)['id'])
                      line('Billed to', '${(d['billed_to'] as Map)['name']}'),
                    line('Invoice date', _prettyDate(d['date'] as String?)),
                    line('Due date', _prettyDate(d['due_date'] as String?)),
                    line('Payment terms', '${d['payment_terms'] ?? 'Immediate payment'}'),
                    if ((d['days_overdue'] as num? ?? 0) > 0)
                      line('Overdue', '${d['days_overdue']} days', colour: AppColors.danger),
                    if (d['order'] != null) line('Order', '${d['order']}'),
                    if (d['reference'] != null) line('Reference', '${d['reference']}'),
                    if (d['salesperson'] != null) line('Sales employee', '${d['salesperson']}'),
                  ]),
                  box([
                    const Text('Items', style: TextStyle(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 6),
                    for (final l in ((d['lines'] as List?) ?? []).cast<Map<String, dynamic>>())
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('${l['product']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                              Text(
                                  [
                                    '${fmtQty(l['qty'] as num)}${l['uom'] != null ? ' ${l['uom']}' : ''} × ${money(l['price_unit'])}',
                                    if ((l['discount'] as num? ?? 0) > 0) '${fmtQty(l['discount'] as num)}% off',
                                    if (((l['taxes'] as List?) ?? []).isNotEmpty) (l['taxes'] as List).join(', '),
                                  ].join(' · '),
                                  style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                            ]),
                          ),
                          Text(money(l['subtotal']), style: const TextStyle(fontWeight: FontWeight.w800)),
                        ]),
                      ),
                  ]),
                  box([
                    line('Untaxed amount', money(d['untaxed'])),
                    line('Tax', money(d['tax'])),
                    line('Total', money(d['total']), bold: true),
                    if ((d['paid'] as num? ?? 0) != 0) line('Paid', '− ${money(d['paid'])}', colour: AppColors.success),
                    const Divider(),
                    line('Amount due', money(d['residual']), bold: true, colour: AppColors.danger),
                  ]),
                  if (((d['payments'] as List?) ?? []).isNotEmpty)
                    box([
                      const Text('Payments', style: TextStyle(fontWeight: FontWeight.w900)),
                      for (final p in ((d['payments'] as List).cast<Map<String, dynamic>>()))
                        line([_prettyDate(p['date'] as String?), if (p['name'] != null) '${p['name']}'].join(' · '), money(p['amount'])),
                    ]),
                ]),
    );
  }
}
