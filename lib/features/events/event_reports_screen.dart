import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/busy.dart';
import '../../widgets/common.dart';
import '../../widgets/skeleton.dart';

const _bg = Color(0xFFEEF3FB);
const _green = Color(0xFF16A34A);
const _whatsApp = Color(0xFF25A244);

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

/// The end-of-event items shared on this phone: 'd' + the distributor id, and 'final'. The server knows the
/// debit note requests; that a report was shared only this phone knows.
class _Shared {
  static String _key(int eventId) => 'event_shared_$eventId';

  static Future<Set<String>> read(int eventId) async {
    try {
      final raw = await Services.storage.read(_key(eventId));
      return raw == null ? {} : (jsonDecode(raw) as List).map((e) => '$e').toSet();
    } catch (_) {
      return {};
    }
  }

  static Future<void> mark(int eventId, String item) async {
    final items = await read(eventId)..add(item);
    await Services.storage.write(_key(eventId), jsonEncode(items.toList()));
  }
}

/// The event finished on this phone today: the Dashboard says "Lulu Mall Sampling – event completed. Task closed."
/// where the running event's card was.
final eventJustCompleted = ValueNotifier<({String name, String day})?>(null);

/// Back on the Dashboard, with every screen refreshed.
void _toDashboard(BuildContext context) {
  Navigator.of(context).popUntil((r) => r.isFirst);
  Services.refresh.value++;
}

/// Shares the report PDF straight into WhatsApp (the phone's share sheet), as the ledger statement does:
/// the file is fetched to the phone's temporary folder, never downloaded. True once it was shared.
Future<bool> _sharePdf(BuildContext context, int eventId, String kind,
    {int? distributorId, required String title}) async {
  try {
    final file = await withBusy(context, 'Preparing the report…', () async {
      final r = await Services.api.post('/api/v1/events/$eventId/pdf', {
        'kind': kind,
        if (distributorId != null) 'distributor_id': distributorId,
      }) as Map<String, dynamic>;
      final response =
          await http.get(Uri.parse(await Services.api.url('${r['path']}')), headers: await Services.api.authHeaders());
      if (response.statusCode != 200) throw Exception('The report could not be prepared (${response.statusCode}).');
      final dir = await getTemporaryDirectory();
      final safe = title.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      final path = File('${dir.path}/$safe.pdf');
      await path.writeAsBytes(response.bodyBytes);
      return path;
    });
    if (!context.mounted) return false;
    final result = await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'application/pdf')],
      subject: title,
      text: title,
    ));
    return result.status != ShareResultStatus.dismissed;
  } catch (e) {
    if (context.mounted) await showProblem(context, e.toString());
    return false;
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
      // From here there is no way back: only the end-of-event items, then Finish.
      await Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => EventCompletedScreen(eventId: widget.eventId, name: widget.name, justEnded: true)));
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
  const EventCompletedScreen({super.key, required this.eventId, required this.name, this.justEnded = false});

  final int eventId;
  final String name;

  /// Opened by "End the event": no back option, every item is mandatory, then Finish.
  /// Opened from the events list to look at a finished event, it is an ordinary page.
  final bool justEnded;

  @override
  State<EventCompletedScreen> createState() => _EventCompletedScreenState();
}

class _EventCompletedScreenState extends State<EventCompletedScreen> {
  Map<String, dynamic>? _data;
  String? _error;
  Set<String> _shared = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await Services.api.get('/api/v1/events/${widget.eventId}/distributors') as Map<String, dynamic>;
      final shared = await _Shared.read(widget.eventId);
      if (mounted) setState(() => (_data = d, _shared = shared));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  /// A distributor's item is done once its report is shared and, except Kumbayah, the debit note is requested (when
  /// it supplied more than it got back) and the invoice raised (when it got back more than it supplied).
  bool _rowDone(Map<String, dynamic> r) {
    final t = (r['totals'] as Map).cast<String, dynamic>();
    final company = r['is_company'] == true;
    final needsDebit = !company && (t.containsKey('debit_qty') ? _n(t['debit_qty']) > 0 : true);
    final needsInvoice = !company && r['invoice_needed'] == true;
    return _shared.contains('d${(r['distributor'] as Map)['id']}') &&
        (!needsDebit || r['debit_requested'] == true) &&
        (!needsInvoice || r['invoice_requested'] == true);
  }

  bool get _allDone =>
      _rows(_data?['distributors']).every(_rowDone) && _shared.contains('final');

  Widget _tick() => const CircleAvatar(
      radius: 16, backgroundColor: _green, child: Icon(Icons.check_rounded, color: Colors.white, size: 18));

  /// "Mandatory" until the item is done, then "Done".
  Widget _status(bool done) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: (done ? _green : const Color(0xFFD97706)).withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(done ? 'Done' : 'Mandatory',
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w800, color: done ? _green : const Color(0xFFB45309))),
      );

  @override
  Widget build(BuildContext context) {
    final page = _page(context);
    if (!widget.justEnded) return page;
    // After "End the event": no back arrow and no back gesture; Finish is the only way out.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) showSnack(context, 'Complete all the items, then tap Finish event.');
      },
      child: page,
    );
  }

  Widget _page(BuildContext context) {
    final rows = _rows(_data?['distributors']);
    final locked = widget.justEnded;
    return Scaffold(
      backgroundColor: _bg,
      appBar: locked
          ? AppBar(
              backgroundColor: _bg,
              elevation: 0,
              scrolledUnderElevation: 0,
              automaticallyImplyLeading: false,
              title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Events', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                Text(_data != null && _allDone ? 'End of the Event · all done' : 'End of the Event · complete all to finish',
                    style: const TextStyle(fontSize: 11.5, color: AppColors.muted, fontWeight: FontWeight.w500)),
              ]),
            )
          : _bar('Events', '${widget.name} · Completed'),
      bottomNavigationBar: !locked || _data == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                child: _allDone
                    ? FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: _whatsApp, minimumSize: const Size.fromHeight(52)),
                        onPressed: () {
                          eventJustCompleted.value = (name: widget.name, day: fmtDate(DateTime.now()));
                          _toDashboard(context);
                        },
                        child: const Text('Finish event', style: TextStyle(fontWeight: FontWeight.w900)),
                      )
                    : OutlinedButton(
                        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                        onPressed: null,
                        child: const Text('Finish event (locked)', style: TextStyle(fontWeight: FontWeight.w800)),
                      ),
              ),
            ),
      body: _error != null
          ? ErrorView(message: _error!, onRetry: _load)
          : _data == null
              ? const LoadingView()
              : ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
                  if (locked && !_allDone)
                    Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7ED),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFBD5B0)),
                      ),
                      child: const Text(
                          'No back option from here. All items are mandatory before the event can be finished.',
                          style: TextStyle(fontSize: 12.5, color: Color(0xFF9A3412))),
                    )
                  else if (locked)
                    const SizedBox.shrink()
                  else
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
                        decoration: BoxDecoration(
                          color: locked && _rowDone(r) ? _green.withValues(alpha: 0.07) : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(children: [
                          if (locked && _rowDone(r)) ...[_tick(), const SizedBox(width: 10)],
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
                              if (locked)
                                Builder(builder: (_) {
                                  final t = (r['totals'] as Map).cast<String, dynamic>();
                                  final company = r['is_company'] == true;
                                  final debit = !company && (t.containsKey('debit_qty') ? _n(t['debit_qty']) > 0 : true);
                                  final invoice = !company && r['invoice_needed'] == true;
                                  final todo = [
                                    'Share report on WhatsApp',
                                    if (debit) 'Request Debit Note',
                                    if (invoice) 'Raise Invoice',
                                  ].join(' + ');
                                  final done = [
                                    'WhatsApp shared',
                                    if (debit) 'Debit Note requested',
                                    if (invoice) 'Invoice raised',
                                  ].join(' · ');
                                  return Text(_rowDone(r) ? done : todo,
                                      style: const TextStyle(fontSize: 11.5, color: AppColors.muted));
                                }),
                            ]),
                          ),
                          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                            // A minus is a distributor that got back more than it supplied: it is invoiced for that.
                            Text('${_q(_n((r['totals'] as Map)['net']))} btl',
                                style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    color: _n((r['totals'] as Map)['net']) < 0 ? AppColors.danger : null)),
                            if (r['invoice_needed'] == true)
                              const Text('to invoice', style: TextStyle(fontSize: 10.5, color: AppColors.danger)),
                            if (locked) ...[const SizedBox(height: 4), _status(_rowDone(r))],
                          ]),
                        ]),
                      ),
                    ),
                  if (_rows(_data?['invoices']).isNotEmpty) ...[
                    Container(
                      margin: const EdgeInsets.only(top: 4, bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Invoice summary', style: TextStyle(fontWeight: FontWeight.w900)),
                        const Text('Distributors that got back more than they supplied',
                            style: TextStyle(fontSize: 11.5, color: AppColors.muted)),
                        const SizedBox(height: 8),
                        for (final i in _rows(_data?['invoices']))
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(children: [
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text('${(i['distributor'] as Map)['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                                  Text(i['raised'] == true ? '${i['number'] ?? 'Invoice raised'}' : 'Not raised yet',
                                      style: TextStyle(fontSize: 11.5, color: i['raised'] == true ? AppColors.success : AppColors.danger)),
                                ]),
                              ),
                              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                Text('${_q(_n(i['quantity']))} btl', style: const TextStyle(fontWeight: FontWeight.w800)),
                                if (i['amount'] != null)
                                  Text(fmtMoney(_n(i['amount']), 'INR'), style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
                              ]),
                            ]),
                          ),
                      ]),
                    ),
                  ],
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(
                            builder: (_) => FinalReportScreen(eventId: widget.eventId, name: widget.name)))
                        .then((_) => _load()),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: locked && _shared.contains('final') ? _green.withValues(alpha: 0.07) : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(children: [
                        if (locked && _shared.contains('final'))
                          _tick()
                        else
                          const CircleAvatar(
                              backgroundColor: _green, child: Icon(Icons.bar_chart_rounded, color: Colors.white)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            const Text('Final report', style: TextStyle(fontWeight: FontWeight.w800)),
                            Text(
                                locked
                                    ? (_shared.contains('final') ? 'WhatsApp shared' : 'Share on WhatsApp')
                                    : 'Sales, coupons, cash and UPI',
                                style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
                          ]),
                        ),
                        if (locked) _status(_shared.contains('final')) else const Icon(Icons.chevron_right_rounded),
                      ]),
                    ),
                  ),
                  if (locked && _allDone)
                    Container(
                      margin: const EdgeInsets.only(top: 14),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _green.withValues(alpha: 0.35)),
                      ),
                      child: const Text('All mandatory steps done. Finish the event to complete the task.',
                          style: TextStyle(fontSize: 12.5, color: Color(0xFF166534))),
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
  late bool _invoiced = widget.row['invoice_requested'] == true;
  late String? _invoiceNumber = asText(widget.row['invoice_number']);
  bool _busy = false;
  bool _shared = false;

  Map<String, dynamic> get _d => (widget.row['distributor'] as Map).cast<String, dynamic>();

  @override
  void initState() {
    super.initState();
    _Shared.read(widget.eventId).then((items) {
      if (mounted) setState(() => _shared = items.contains('d${_d['id']}'));
    });
  }

  /// Mandatory: the report goes on WhatsApp as a PDF file (sent, not downloaded).
  Future<void> _share() async {
    final ok = await _sharePdf(context, widget.eventId, 'distributor',
        distributorId: _d['id'] as int, title: '${_d['name']} - ${widget.name}');
    if (!ok) return;
    await _Shared.mark(widget.eventId, 'd${_d['id']}');
    if (mounted) setState(() => _shared = true);
  }

  /// The invoice for what this distributor got back beyond what it supplied.
  Future<void> _raiseInvoice() async {
    final d = widget.row['distributor'] as Map;
    setState(() => _busy = true);
    try {
      final result = await Services.api.post('/api/v1/events/${widget.eventId}/invoice', {'distributor_id': d['id']})
          as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _invoiced = true;
          _invoiceNumber = asText(result['number']);
        });
      }
    } catch (e) {
      if (mounted) showProblem(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

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
    // Kumbayah Foods Pvt Ltd: the WhatsApp share only, no debit note.
    final company = r['is_company'] == true;
    // A debit note for what it supplied beyond what came back; an invoice for what came back beyond what it supplied.
    final needsDebit = !company && (totals.containsKey('debit_qty') ? _n(totals['debit_qty']) > 0 : true);
    final needsInvoice = !company && r['invoice_needed'] == true;
    Color netColour(Object? v) => _n(v) < 0 ? AppColors.danger : _green;
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
                cell(flavourLabel(f), bold: true, align: TextAlign.left),
                for (final k in ['open', 'add', 'ret']) cell(_q(_n(f[k]))),
                // Net = Opening + Added - Returned, by flavour. A minus: it got back more than it supplied.
                cell(_q(_n(f['net'])), bold: true, colour: netColour(f['net'])),
              ]),
            TableRow(decoration: const BoxDecoration(color: Color(0xFFEEF3FB)), children: [
              cell('Total', bold: true, align: TextAlign.left),
              for (final k in ['open', 'add', 'ret']) cell(_q(_n(totals[k])), bold: true),
              cell(_q(_n(totals['net'])), bold: true, colour: netColour(totals['net'])),
            ]),
          ]),
        ),
        if (needsInvoice)
          Container(
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
            ),
            child: Text(
                '${d['name']} got back ${_q(_n(totals['invoice_qty']))} bottles more than it supplied: invoice it for them.'
                '${needsDebit ? ' It also supplied ${_q(_n(totals['debit_qty']))} bottles that did not come back: a debit note.' : ''}',
                style: const TextStyle(fontSize: 12.5, color: Color(0xFF9A1B1B))),
          ),
        // What became of the stock the event took from this distributor, flavour by flavour, with its sales and coupons.
        if (totals.containsKey('sold')) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('What became of it', style: TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Table(columnWidths: const {0: FlexColumnWidth(1.3)}, children: [
                TableRow(children: [
                  cell('Flav', head: true, align: TextAlign.left),
                  for (final h in ['Samp', 'Dmg', 'Close', 'Sold']) cell(h, head: true),
                ]),
                for (final f in flavours)
                  TableRow(children: [
                    cell(flavourLabel(f), bold: true, align: TextAlign.left),
                    for (final k in ['samples', 'damage', 'closing']) cell(_q(_n(f[k]))),
                    cell(_q(_n(f['sold'])), bold: true, colour: _green),
                  ]),
                TableRow(decoration: const BoxDecoration(color: Color(0xFFEEF3FB)), children: [
                  cell('Total', bold: true, align: TextAlign.left),
                  for (final k in ['samples', 'damage', 'closing']) cell(_q(_n(totals[k])), bold: true),
                  cell(_q(_n(totals['sold'])), bold: true, colour: _green),
                ]),
              ]),
              const Divider(height: 22),
              for (final (label, value, bold) in [
                ('Sales', fmtMoney(_n(totals['sales']), 'INR'), false),
                ('Coupons used (${_q(_n(totals['coupons']))})', '- ${fmtMoney(_n(totals['coupon_amount']), 'INR')}', false),
                ('Net sales', fmtMoney(_n(totals['net_sales']), 'INR'), true),
              ])
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    Expanded(child: Text(label, style: TextStyle(fontWeight: bold ? FontWeight.w900 : FontWeight.w500))),
                    Text(value, style: TextStyle(fontWeight: bold ? FontWeight.w900 : FontWeight.w700)),
                  ]),
                ),
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                    'Samples, damage and sales are worked out for each distributor from the stock it had at the event each day; '
                    'returns are exact.',
                    style: TextStyle(fontSize: 11, color: AppColors.muted)),
              ),
            ]),
          ),
        ],
        const SizedBox(height: 14),
        // What is still to do: share on WhatsApp, the debit note, and the invoice when it is owed.
        if (!_shared || (needsDebit && !_requested) || (needsInvoice && !_invoiced))
          Column(children: [
            if (!_shared)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: _whatsApp, minimumSize: const Size.fromHeight(48)),
                  onPressed: _share,
                  icon: const Icon(Icons.chat_rounded, size: 20),
                  label: const Text('Share on WhatsApp', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            if (needsDebit && !_requested) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  onPressed: _busy ? null : _request,
                  child: _busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Request Debit Note', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ],
            if (needsInvoice && !_invoiced) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.danger, minimumSize: const Size.fromHeight(48)),
                  onPressed: _busy ? null : _raiseInvoice,
                  icon: const Icon(Icons.receipt_long_rounded, size: 20),
                  label: const Text('Raise Invoice', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ]),
        if (_invoiced)
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _green.withValues(alpha: 0.35)),
            ),
            child: Text(
                'Invoice ${_invoiceNumber ?? ''} raised to ${d['name']} for ${_q(_n(totals['invoice_qty']))} bottles – ${widget.name}.',
                style: const TextStyle(fontSize: 12.5, color: Color(0xFF166534))),
          ),
        if (_shared) _sharedCard(),
        if (_requested && needsDebit) ...[
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _green.withValues(alpha: 0.35)),
            ),
            child: Text(
                'Debit note request sent to ${d['name']} for ${_q(_n(totals.containsKey('debit_qty') ? totals['debit_qty'] : totals['net']))} bottles – ${widget.name}.',
                style: const TextStyle(fontSize: 12.5, color: Color(0xFF166534))),
          ),
          _debitCard('${d['name']}'),
        ],
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
          child: GradientButton(label: 'Done – back to checklist', onPressed: () => Navigator.of(context).pop()),
        ),
      ),
    );
  }

  /// "Report shared on WhatsApp · PDF sent – not downloaded", with Done; tapping it shares again.
  Widget _sharedCard() => Material(
        color: _green.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _share,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              const CircleAvatar(radius: 16, backgroundColor: _green, child: Icon(Icons.check_rounded, color: Colors.white, size: 18)),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Report shared on WhatsApp', style: TextStyle(fontWeight: FontWeight.w800)),
                  Text('PDF sent – not downloaded · tap to share again', style: TextStyle(fontSize: 11.5, color: AppColors.muted)),
                ]),
              ),
              _chip('Done', _green),
            ]),
          ),
        ),
      );

  /// "Debit note · Distributor → Kumbayah Foods Pvt Ltd", Requested.
  Widget _debitCard(String from) => Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Debit note', style: TextStyle(fontWeight: FontWeight.w800)),
              Text('$from → Kumbayah Foods Pvt Ltd', style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
            ]),
          ),
          _chip('Requested', const Color(0xFFD97706)),
        ]),
      );

  Widget _chip(String text, Color colour) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: colour.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(14)),
        child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: colour)),
      );
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
                              DataCell(Text(flavourLabel(r), style: const TextStyle(fontWeight: FontWeight.w800))),
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
                    onPressed: () async {
                      if (await _sharePdf(context, widget.eventId, 'final', title: 'Final report - ${widget.name}')) {
                        await _Shared.mark(widget.eventId, 'final');
                      }
                    },
                    icon: const Icon(Icons.chat_rounded),
                    label: const Text('Share on WhatsApp'),
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
