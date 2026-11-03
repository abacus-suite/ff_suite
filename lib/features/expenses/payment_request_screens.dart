import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/skeleton.dart';
import '../tasks/task_widgets.dart';

/// Expense Payment Request: the company pays the vendor directly, with a tax invoice or a quotation.
/// With a quotation, accounts pay and set a due date for the tax invoice; the request is completed only
/// once the tax invoice is uploaded, with a reminder till then.
///
/// Server calls (to be added in Odoo; until then the screens say so plainly):
///   POST /api/v1/expense-requests             {uuid, category_id, sub_category_id, date, amount, document, photo}
///   GET  /api/v1/expense-requests             {requests: [{id, category, sub_category, amount, state,
///                                               document, paid_on, invoice_due}]}
///   POST /api/v1/expense-requests/{id}/invoice {photo}
/// state: requested (with accounts) · invoice_pending (paid, tax invoice still to come) · completed.

const _purple = Color(0xFF7C3AED);
const _orange = Color(0xFFD97706);

/// "24-Oct-2026".
String _day(DateTime d) => '${d.day.toString().padLeft(2, '0')}-${monthNames[d.month - 1].substring(0, 3)}-${d.year}';

/// "31-Oct" from a server date, or '' when there is none.
String _short(dynamic iso) {
  final d = DateTime.tryParse('${iso ?? ''}');
  return d == null ? '' : '${d.day.toString().padLeft(2, '0')}-${monthNames[d.month - 1].substring(0, 3)}';
}

String _notYet(Object e) => e is ApiException && e.status == 404
    ? 'Expense payment requests are not switched on yet. Please ask the office.'
    : e.toString();

/// "Event · Stall Fees".
String requestTitle(Map<String, dynamic> r) => [
      asText((r['category'] as Map?)?['name']),
      asText((r['sub_category'] as Map?)?['name'])?.split(' / ').last.trim(),
    ].whereType<String>().join(' · ');

Widget _pageTitle(String title, String subtitle) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
      Text(subtitle, style: const TextStyle(fontSize: 11.5, color: AppColors.muted, fontWeight: FontWeight.w500)),
    ]);

// ==================================================================== the new request
class PaymentRequestFormScreen extends StatefulWidget {
  const PaymentRequestFormScreen({super.key});

  @override
  State<PaymentRequestFormScreen> createState() => _PaymentRequestFormScreenState();
}

class _PaymentRequestFormScreenState extends State<PaymentRequestFormScreen> {
  final _amount = TextEditingController();
  final String _uuid = const Uuid().v4();
  final List<Uint8List> _photos = [];
  List<Map<String, dynamic>> _categories = [];
  Map<String, dynamic>? _category;
  Map<String, dynamic>? _sub;
  DateTime _date = DateTime.now();

  /// Tax invoice, or a quotation (paid first, the tax invoice follows).
  String _document = 'quotation';
  bool _loaded = false;
  bool _busy = false;

  List<Map<String, dynamic>> get _children => ((_category?['children'] as List?) ?? []).cast<Map<String, dynamic>>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  /// Only the categories set for this person, from the approved list.
  Future<void> _load() async {
    try {
      final data = await Services.api.get('/api/v1/expense-categories') as Map<String, dynamic>;
      if (mounted) setState(() => _categories = ((data['categories'] as List?) ?? []).cast<Map<String, dynamic>>());
    } catch (e) {
      if (mounted) await showProblem(context, e.toString());
    } finally {
      if (mounted) setState(() => _loaded = true);
    }
  }

  String get _docName => _document == 'quotation' ? 'quotation' : 'tax invoice';

  Future<void> _send() async {
    final problems = <String>[
      if (_category == null) 'Expense category',
      if (_category != null && _children.isNotEmpty && _sub == null) 'Sub category',
      if ((double.tryParse(_amount.text.trim()) ?? 0) <= 0) 'Amount',
      if (_photos.isEmpty) 'Photo of the $_docName',
    ];
    if (problems.isNotEmpty) {
      await showProblem(context, problems, title: 'Still needed');
      return;
    }
    setState(() => _busy = true);
    try {
      await Services.api.post('/api/v1/expense-requests', {
        'uuid': _uuid,
        'category_id': _category!['id'],
        if (_sub != null) 'sub_category_id': _sub!['id'],
        'date': fmtDate(_date),
        'amount': double.parse(_amount.text.trim()),
        'document': _document,
        'photo': base64Encode(_photos.first),
      });
      if (!mounted) return;
      showSnack(context, 'Request sent to accounts');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) await showProblem(context, _notYet(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _dropdown(Map<String, dynamic>? value, List<Map<String, dynamic>> items, bool sub,
          ValueChanged<Map<String, dynamic>?> onChanged) =>
      DropdownButtonFormField<int>(
        key: ValueKey('${sub ? 's' : 'c'}${_category?['id']}'),
        initialValue: value?['id'] as int?,
        isExpanded: true,
        hint: const Text('Choose'),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: AppColors.background,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        ),
        items: [
          for (final c in items)
            DropdownMenuItem(
                value: c['id'] as int, child: Text(sub ? '${c['name']}'.split(' / ').last.trim() : '${c['name']}')),
        ],
        onChanged: (id) => onChanged(items.where((c) => c['id'] == id).firstOrNull),
      );

  /// Tax invoice | Quotation, as two halves of one pill.
  Widget _documentSwitch() {
    Widget half(String code, String text) {
      final on = _document == code;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => setState(() {
            _document = code;
            _photos.clear();
          }),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? AppColors.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(text,
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: on ? Colors.white : AppColors.text)),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(23),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(children: [half('tax_invoice', 'Tax invoice'), half('quotation', 'Quotation')]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: _pageTitle('Expense Payment Request', 'New request')),
      bottomNavigationBar: !_loaded
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                child: GradientButton(label: 'Send request', busy: _busy, onPressed: _busy ? null : _send),
              ),
            ),
      body: !_loaded
          ? const LoadingView()
          : ListView(padding: const EdgeInsets.all(14), children: [
              StepCard(
                title: 'Expense category *',
                child: _dropdown(_category, _categories, false, (c) => setState(() {
                      _category = c;
                      _sub = null;
                    })),
              ),
              if (_category != null && _children.isNotEmpty)
                StepCard(
                  title: 'Sub category *',
                  child: _dropdown(_sub, _children, true, (c) => setState(() => _sub = c)),
                ),
              StepCard(
                title: 'Date *',
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime.now().subtract(const Duration(days: 90)),
                      lastDate: DateTime.now().add(const Duration(days: 90)),
                    );
                    if (picked != null) setState(() => _date = picked);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(14)),
                    child: Row(children: [
                      const Icon(Icons.calendar_month_rounded, color: AppColors.muted, size: 20),
                      const SizedBox(width: 10),
                      Text(_day(_date), style: const TextStyle(fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ),
              ),
              StepCard(
                title: 'Amount *',
                child: TextField(
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    prefixText: '₹ ',
                    isDense: true,
                    filled: true,
                    fillColor: AppColors.background,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                ),
              ),
              StepCard(
                title: 'Document *',
                note: _document == 'quotation'
                    ? 'Accounts pay on the quotation and set a due date for the tax invoice.'
                    : 'Accounts pay on the tax invoice.',
                child: _documentSwitch(),
              ),
              StepCard(
                child: PhotoSlot(
                  key: ValueKey(_document),
                  label: 'Photo of the $_docName',
                  photos: _photos,
                  onChanged: () => setState(() {}),
                  max: 1,
                ),
              ),
            ]),
    );
  }
}

// ==================================================================== My Expense · Payment requests
class PaymentRequestsScreen extends StatefulWidget {
  const PaymentRequestsScreen({super.key});

  @override
  State<PaymentRequestsScreen> createState() => _PaymentRequestsScreenState();
}

class _PaymentRequestsScreenState extends State<PaymentRequestsScreen> {
  List<Map<String, dynamic>>? _rows;
  String? _note;

  /// Reminders closed with ×: they come back the next time the list opens, till the invoice is uploaded.
  final Set<Object?> _hidden = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await Services.api.get('/api/v1/expense-requests') as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _rows = ((data['requests'] as List?) ?? []).cast<Map<String, dynamic>>();
          _note = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => (_rows = const [], _note = _notYet(e)));
    }
  }

  Future<void> _open(Map<String, dynamic> r) async {
    final changed = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => PaymentRequestDetailScreen(request: r)));
    if (changed == true) _load();
  }

  Future<void> _new() async {
    final sent =
        await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const PaymentRequestFormScreen()));
    if (sent == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final pending = (rows ?? const []).where((r) => r['state'] == 'invoice_pending' && !_hidden.contains(r['id']));
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Payment Request', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22))),
      floatingActionButton: FloatingActionButton(
        tooltip: 'New payment request',
        onPressed: _new,
        child: const Icon(Icons.add_rounded),
      ),
      body: rows == null
          ? const LoadingView()
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.fromLTRB(14, 8, 14, 96), children: [
                if (_note != null)
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(_note!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
                  )
                else if (rows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(30),
                    child: Text('No payment requests yet.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
                  ),
                for (final r in rows) ...[
                  _tile(r),
                  // The reminder sits right under the request it is about, till the invoice is in.
                  if (pending.contains(r)) _reminder(r),
                ],
              ]),
            ),
    );
  }

  (Color, String, String) _look(Map<String, dynamic> r) => switch ('${r['state']}') {
        'completed' => (AppColors.success, 'Completed', 'Tax invoice uploaded'),
        'approval' => (_orange, 'With manager', 'Waiting for your manager to approve'),
        'requested' when r['invoice_uploaded'] == true && r['document'] == 'quotation' => (
            AppColors.primary, 'With accounts', 'Tax invoice uploaded · waiting for accounts to pay'),
        'invoice_pending' => (
            _orange,
            'Invoice pending',
            ['Paid by accounts', if (_short(r['invoice_due']).isNotEmpty) 'invoice due ${_short(r['invoice_due'])}'].join(' · ')
          ),
        _ => (AppColors.primary, 'With accounts', 'Waiting for accounts to pay'),
      };

  Widget _tile(Map<String, dynamic> r) {
    final (tint, status, line) = _look(r);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _open(r),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: 5, color: tint),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(requestTitle(r), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                      const SizedBox(height: 2),
                      Text(line, style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(fmtMoney(r['amount'] as num?), style: const TextStyle(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 2),
                    Text(status, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: tint)),
                  ]),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  /// "Upload the tax invoice · Stall Fees ₹15,000 · due 31-Oct", with × to put it away for now.
  Widget _reminder(Map<String, dynamic> r) {
    final sub = asText((r['sub_category'] as Map?)?['name'])?.split(' / ').last.trim() ?? requestTitle(r);
    final due = _short(r['invoice_due']);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _open(r),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          child: Row(children: [
            Stack(clipBehavior: Clip.none, children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: _purple.withValues(alpha: 0.12),
                child: const Icon(Icons.receipt_long_rounded, color: _purple, size: 20),
              ),
              Positioned(
                right: -1,
                top: -1,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                      color: AppColors.primary, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                ),
              ),
            ]),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Upload the tax invoice', style: TextStyle(fontWeight: FontWeight.w800)),
                Text(
                    [sub, fmtMoney(r['amount'] as num?), if (due.isNotEmpty) 'due $due'].join(' · ')
                        .replaceFirst(' · ₹', ' ₹'),
                    style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
              ]),
            ),
            IconButton(
              tooltip: 'Remind me later',
              onPressed: () => setState(() => _hidden.add(r['id'])),
              icon: const Icon(Icons.close_rounded, color: AppColors.muted),
            ),
          ]),
        ),
      ),
    );
  }
}

// ==================================================================== one request
class PaymentRequestDetailScreen extends StatefulWidget {
  const PaymentRequestDetailScreen({super.key, required this.request});

  final Map<String, dynamic> request;

  @override
  State<PaymentRequestDetailScreen> createState() => _PaymentRequestDetailScreenState();
}

class _PaymentRequestDetailScreenState extends State<PaymentRequestDetailScreen> {
  final List<Uint8List> _invoice = [];
  bool _busy = false;

  Map<String, dynamic> get _r => widget.request;

  Future<void> _submit() async {
    if (_invoice.isEmpty) {
      await showProblem(context, 'Take the photo of the tax invoice.');
      return;
    }
    setState(() => _busy = true);
    try {
      await Services.api
          .post('/api/v1/expense-requests/${_r['id']}/invoice', {'photo': base64Encode(_invoice.first)});
      if (!mounted) return;
      showSnack(context, _r['state'] == 'invoice_pending'
          ? 'Tax invoice submitted. The request is completed.'
          : 'Tax invoice submitted. Accounts will pay the request.');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) await showProblem(context, _notYet(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(children: [
          Expanded(child: Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 13))),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final state = '${_r['state']}';
    // A quotation's tax invoice can go in as soon as the request is sent, before accounts have paid.
    final waitingInvoice = _r['document'] == 'quotation' &&
        (state == 'invoice_pending' || state == 'requested' || state == 'approval') &&
        _r['invoice_uploaded'] != true;
    final paid = DateTime.tryParse('${_r['paid_on'] ?? ''}');
    final due = DateTime.tryParse('${_r['invoice_due'] ?? ''}');
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: _pageTitle(requestTitle(_r), 'Payment request')),
      bottomNavigationBar: !waitingInvoice
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                child: GradientButton(label: 'Submit tax invoice', busy: _busy, onPressed: _busy ? null : _submit),
              ),
            ),
      body: ListView(padding: const EdgeInsets.all(14), children: [
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Request', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
            const SizedBox(height: 4),
            _row('Amount', fmtMoney(_r['amount'] as num?)),
            _row('Paid by accounts', paid == null ? 'Not yet' : _day(paid)),
            if (due != null) _row('Invoice due', _day(due)),
          ]),
        ),
        const SizedBox(height: 12),
        if (waitingInvoice)
          StepCard(
            child: PhotoSlot(label: 'Photo of the tax invoice', photos: _invoice, onChanged: () => setState(() {}), max: 1),
          )
        else if (state == 'completed')
          _banner('Completed · tax invoice uploaded.', AppColors.success)
        else if (state == 'approval')
          _banner('With your manager. It goes to accounts once it is approved.', _orange)
        else if (state == 'requested' && _r['invoice_uploaded'] == true)
          _banner('Tax invoice uploaded. With accounts: you will be told when it is paid.', AppColors.primary)
        else
          _banner('With accounts. You will be told when it is paid.', AppColors.primary),
      ]),
    );
  }

  Widget _banner(String text, Color tint) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: tint.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: tint.withValues(alpha: 0.3)),
        ),
        child: Text(text, style: TextStyle(fontSize: 12.5, color: tint, fontWeight: FontWeight.w600)),
      );
}
