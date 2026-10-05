import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../core/photos.dart';
import '../../core/format.dart';
import '../../core/geo.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/skeleton.dart';

/// Collect money from a customer, usually during a visit.
class CollectPaymentScreen extends StatefulWidget {
  const CollectPaymentScreen({super.key, required this.client, this.visitId});

  final Map<String, dynamic> client;
  final int? visitId;

  @override
  State<CollectPaymentScreen> createState() => _CollectPaymentScreenState();
}

class _CollectPaymentScreenState extends State<CollectPaymentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  final _note = TextEditingController();
  final String _uuid = const Uuid().v4();
  final List<Uint8List> _photos = [];
  List<Map<String, dynamic>> _modes = [];
  Map<String, dynamic>? _mode;
  DateTime? _instrumentDate;

  /// What this money is paying for. From a distributor it is the company's own
  /// invoices; from an outlet it is that outlet's invoices from its distributor.
  String _kind = 'outlet';
  String _goesTo = 'distributor';
  Map<String, dynamic>? _distributor;
  List<Map<String, dynamic>> _invoices = [];
  final Set<int> _picked = {};
  final Map<int, TextEditingController> _alloc = {};
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadModes();
  }

  @override
  void dispose() {
    _amount.dispose();
    for (final c in _alloc.values) {
      c.dispose();
    }
    _reference.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _loadModes() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = (await Services.api.get('/api/v1/collection-modes') as List).cast<Map<String, dynamic>>();
      await _loadInvoices();
      if (!mounted) return;
      setState(() {
        _modes = list;
        _mode = list.length == 1 ? list.first : null;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  /// The invoices this contact owes, and where the money will end up.
  Future<void> _loadInvoices() async {
    try {
      final data = await Services.api.get('/api/v1/collection/open-invoices',
          query: {'partner_id': widget.client['id']}) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _kind = '${data['kind']}';
        _goesTo = '${data['goes_to']}';
        _distributor = (data['distributor'] as Map?)?.cast<String, dynamic>();
        _invoices = ((data['invoices'] as List?) ?? []).cast<Map<String, dynamic>>();
        _picked.removeWhere((id) => !_invoices.any((i) => i['id'] == id));
      });
    } catch (_) {
      // Without the ledger module the screen collects as it always did.
    }
  }

  double get _collected => double.tryParse(_amount.text.trim()) ?? 0;

  double _pending(Map<String, dynamic> i) => ((i['pending'] as num?) ?? 0).toDouble();

  double _applied(int id) => double.tryParse(_alloc[id]?.text.trim() ?? '') ?? 0;

  double get _appliedTotal => _picked.fold(0.0, (sum, id) => sum + _applied(id));

  TextEditingController _ctl(int id) => _alloc.putIfAbsent(id, TextEditingController.new);

  String _money(double v) => v == v.roundToDouble() ? '${v.toInt()}' : v.toStringAsFixed(2);

  /// Ticking an invoice applies what is left of the collected amount to it, up to what it owes.
  void _toggle(int id, bool on) {
    setState(() {
      if (!on) {
        _picked.remove(id);
        _ctl(id).clear();
        return;
      }
      final invoice = _invoices.firstWhere((i) => i['id'] == id);
      final left = _collected - _appliedTotal;
      _picked.add(id);
      final take = left <= 0 ? 0.0 : (left < _pending(invoice) ? left : _pending(invoice));
      _ctl(id).text = take > 0 ? _money(take) : '';
    });
  }

  /// Spreads the collected amount over the open invoices, oldest first.
  void _fillOldestFirst() {
    setState(() {
      _picked.clear();
      for (final c in _alloc.values) {
        c.clear();
      }
      var left = _collected;
      for (final invoice in _invoices) {
        if (left <= 0) break;
        final id = invoice['id'] as int;
        final take = left < _pending(invoice) ? left : _pending(invoice);
        _picked.add(id);
        _ctl(id).text = _money(take);
        left -= take;
      }
    });
  }

  /// Whatever is wrong with how the money is split, or null.
  List<String> _splitProblems() {
    final bad = <String>[];
    for (final invoice in _invoices.where((i) => _picked.contains(i['id']))) {
      final v = _applied(invoice['id'] as int);
      if (v > _pending(invoice) + 0.005) {
        bad.add('${invoice['number']}: only ${fmtMoney(_pending(invoice), invoice['currency'] as String?)} is pending');
      }
    }
    if (_appliedTotal > _collected + 0.005) {
      bad.add('The invoices add up to ${fmtMoney(_appliedTotal, null)}, more than the ${fmtMoney(_collected, null)} collected');
    }
    return bad;
  }

  /// An outlet's invoice is the distributor's, so nobody but the field has seen
  /// it; it is entered here from the paper copy at the counter.
  Future<void> _addInvoice() async {
    final number = TextEditingController();
    final amount = TextEditingController();
    DateTime? due;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, setSheet) => AlertDialog(
          title: const Text("Enter the distributor's invoice"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: number,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Invoice number'),
              ),
              TextField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Amount'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(due == null ? 'Due date (optional)' : 'Due ${fmtDate(due!)}'),
                trailing: const Icon(Icons.event_rounded),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: dialog,
                    initialDate: DateTime.now(),
                    firstDate: DateTime.now().subtract(const Duration(days: 365)),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) setSheet(() => due = picked);
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Add')),
          ],
        ),
      ),
    );
    final n = number.text.trim();
    final a = double.tryParse(amount.text.trim()) ?? 0;
    number.dispose();
    amount.dispose();
    if (saved != true || !mounted) return;
    try {
      final invoice = await Services.api.post('/api/v1/outlet-invoices', {
        'partner_id': widget.client['id'],
        'number': n,
        'amount': a,
        if (due != null) 'due_date': fmtDate(due!),
        if (_distributor != null) 'distributor_id': _distributor!['id'],
      }) as Map<String, dynamic>;
      await _loadInvoices();
      if (mounted) _toggle(invoice['id'] as int, true);
    } catch (e) {
      if (mounted) showProblem(context, e.toString());
    }
  }

  /// The amount typed against each ticked invoice.
  List<Map<String, dynamic>> _allocations(double amount) => [
        for (final invoice in _invoices.where((i) => _picked.contains(i['id'])))
          if (_applied(invoice['id'] as int) > 0)
            {'invoice_id': invoice['id'], 'amount': _applied(invoice['id'] as int)},
      ];

  Future<void> _addPhoto() async {
    if (_photos.length >= 3) return;
    final bytes = await takePhoto(ImageSource.camera);
    if (bytes == null) return;
    if (mounted) setState(() => _photos.add(bytes));
  }

  /// Says where this money goes, because it is not the same from everyone.
  Widget _goesToCard() {
    final toDistributor = _goesTo == 'distributor';
    final tint = toDistributor ? AppColors.warning : AppColors.success;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(toDistributor ? Icons.local_shipping_rounded : Icons.business_rounded, size: 20, color: tint),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              toDistributor
                  ? 'This is paid to ${_distributor?['name'] ?? 'the distributor'}. '
                      'It is theirs, not the company\'s, so you do not hand it in to the office.'
                  : 'This is the company\'s money. Hand it in to the office with your next deposit.',
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, String value, Color tint) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
          decoration: BoxDecoration(color: tint.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5, color: tint)),
            Text(label, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
          ]),
        ),
      );

  Widget _invoicesCard() {
    if (_invoices.isEmpty && _kind != 'outlet') return const SizedBox.shrink();
    final collected = _collected;
    final applied = _appliedTotal;
    final over = applied > collected + 0.005;
    final onAccount = (collected - applied).clamp(0, double.infinity).toDouble();
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(_invoices.isEmpty ? 'No open invoices' : 'Apply to invoices',
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15.5)),
          ),
          if (_kind == 'outlet')
            TextButton.icon(onPressed: _addInvoice, icon: const Icon(Icons.add_rounded, size: 17), label: const Text('Add invoice')),
        ]),
        if (collected <= 0)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('Enter the amount collected above, then choose the invoices it pays.',
                style: TextStyle(fontSize: 12.5, color: AppColors.muted)),
          )
        else if (_invoices.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('The money is recorded on account. Add the invoice if you have it in front of you.',
                style: TextStyle(fontSize: 12, color: AppColors.muted)),
          )
        else ...[
          Row(children: [
            _chip('Collected', fmtMoney(collected, null), AppColors.primary),
            const SizedBox(width: 8),
            _chip('Applied', fmtMoney(applied, null), over ? AppColors.danger : AppColors.success),
            const SizedBox(width: 8),
            _chip('On account', fmtMoney(onAccount, null), AppColors.muted),
          ]),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _fillOldestFirst,
              icon: const Icon(Icons.auto_fix_high_rounded, size: 16),
              label: const Text('Fill oldest first'),
            ),
          ),
          for (final invoice in _invoices) _invoiceTile(invoice),
          if (over)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('The invoices add up to more than you collected. Lower an amount.',
                  style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700, fontSize: 12.5)),
            ),
        ],
      ]),
    );
  }

  Widget _invoiceTile(Map<String, dynamic> invoice) {
    final id = invoice['id'] as int;
    final on = _picked.contains(id);
    final pending = _pending(invoice);
    final value = _applied(id);
    final tooMuch = value > pending + 0.005;
    final overdue = invoice['overdue'] == true;
    final currency = invoice['currency'] as String?;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(4, 6, 12, 8),
      decoration: BoxDecoration(
        color: on ? AppColors.primary.withValues(alpha: 0.05) : AppColors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tooMuch ? AppColors.danger : (on ? AppColors.primary : Colors.transparent)),
      ),
      child: Column(children: [
        Row(children: [
          Checkbox(value: on, onChanged: (v) => _toggle(id, v == true)),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${invoice['number']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
              Text(
                [if (invoice['due_date'] != null) 'due ${invoice['due_date']}', if (overdue) 'overdue'].join(' · '),
                style: TextStyle(fontSize: 11.5, color: overdue ? AppColors.danger : AppColors.muted),
              ),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(fmtMoney(pending, currency), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
            const Text('pending', style: TextStyle(fontSize: 10.5, color: AppColors.muted)),
          ]),
        ]),
        if (on)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 0, 0),
            child: TextField(
              controller: _ctl(id),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Amount against this invoice',
                prefixText: '₹ ',
                isDense: true,
                errorText: tooMuch ? 'More than the ${fmtMoney(pending, currency)} pending' : null,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ),
      ]),
    );
  }

  Future<void> _submit() async {
    final mode = _mode;
    if (mode == null) {
      showProblem(context, 'Choose how the money was paid.');
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    final split = _splitProblems();
    if (split.isNotEmpty) {
      showProblem(context, split, title: 'Check the invoice amounts');
      return;
    }
    if (mode['requires_photo'] == true && _photos.isEmpty) {
      showSnack(context, 'A photo is required for ${mode['name']}.');
      return;
    }
    if (mode['requires_instrument_date'] == true && _instrumentDate == null) {
      showProblem(context, 'Enter the cheque date.');
      return;
    }
    setState(() => _busy = true);
    try {
      Position? pos;
      try {
        pos = await currentPosition(recentOk: true);
      } catch (_) {
        // Location is a nice-to-have on a receipt.
      }
      final result = await Services.outbox.submit('/api/v1/collections', {
        'partner_id': widget.client['id'],
        'mode_id': mode['id'],
        'amount': double.tryParse(_amount.text.trim()) ?? 0,
        'reference': _reference.text.trim(),
        if (_instrumentDate != null) 'instrument_date': fmtDate(_instrumentDate!),
        'note': _note.text.trim(),
        if (widget.visitId != null) 'visit_id': widget.visitId,
        'photos': _photos.map(base64Encode).toList(),
        'lat': pos?.latitude,
        'lng': pos?.longitude,
        'uuid': _uuid,
        'handed_to': _goesTo,
        if (_distributor != null) 'distributor_id': _distributor!['id'],
        if (_kind == 'outlet')
          'allocations': _allocations(double.tryParse(_amount.text.trim()) ?? 0)
        else
          'invoice_ids': [for (final i in _allocations(_collected)) i['invoice_id']],
      }, label: 'Payment · ${widget.client['name']}');
      final saved = result.queued
          ? <String, dynamic>{'amount': double.tryParse(_amount.text.trim()) ?? 0, 'currency': null}
          : result.map;
      Services.refresh.value++;
      if (!mounted) return;
      showSnack(
          context,
          result.queued
              ? 'Payment of ${fmtMoney(saved['amount'] as num?, null)} saved on the phone · it will sync when you are back online'
              : 'Received ${fmtMoney(saved['amount'] as num?, saved['currency'] as String?)}');
      Navigator.of(context).pop(saved);
    } catch (e) {
      if (mounted) showProblem(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mode = _mode;
    return Scaffold(
      appBar: AppBar(title: const Text('Collect Payment')),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(message: _error!, onRetry: _loadModes)
              : _modes.isEmpty
                  ? const EmptyView(
                      icon: Icons.payments_outlined,
                      text: 'No collection modes yet. Ask the office to set up how you may collect money.')
                  : Form(
                      key: _formKey,
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          SectionCard(
                            title: '${widget.client['name']}',
                            child: Text(asText(widget.client['address']) ?? 'Payment against this account',
                                style: const TextStyle(color: AppColors.muted)),
                          ),
                          const SizedBox(height: 8),
                          _goesToCard(),
                          const SizedBox(height: 8),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final m in _modes)
                                ChoiceChip(
                                  label: Text('${m['name']}'),
                                  selected: mode?['id'] == m['id'],
                                  onSelected: (_) => setState(() => _mode = m),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _amount,
                            onChanged: (_) => setState(() {}),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: InputDecoration(
                              labelText: 'Amount *',
                              helperText: (mode?['max_amount'] as num?) != null
                                  ? 'Maximum ${fmtMoney(mode?['max_amount'] as num?, mode?['currency'] as String?)}'
                                  : null,
                            ),
                            validator: (v) {
                              final value = double.tryParse((v ?? '').trim());
                              if (value == null || value <= 0) return 'Enter the amount';
                              final max = mode?['max_amount'] as num?;
                              if (max != null && value > max) return 'Above the allowed maximum';
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          _invoicesCard(),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _reference,
                            decoration: InputDecoration(
                              labelText:
                                  'Reference / cheque no.${mode?['requires_reference'] == true ? ' *' : ' (optional)'}',
                            ),
                            validator: (v) => mode?['requires_reference'] == true && (v ?? '').trim().isEmpty
                                ? 'Enter the reference'
                                : null,
                          ),
                          if (mode?['requires_instrument_date'] == true)
                            Card(
                              child: ListTile(
                                leading: const Icon(Icons.event_rounded),
                                title: const Text('Cheque date *'),
                                trailing: Text(_instrumentDate == null ? 'Pick' : fmtDate(_instrumentDate!)),
                                onTap: () async {
                                  final now = DateTime.now();
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: _instrumentDate ?? now,
                                    firstDate: now.subtract(const Duration(days: 90)),
                                    lastDate: now.add(const Duration(days: 365)),
                                  );
                                  if (picked != null) setState(() => _instrumentDate = picked);
                                },
                              ),
                            ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _note,
                            maxLines: 2,
                            decoration: const InputDecoration(labelText: 'Note'),
                          ),
                          const SizedBox(height: 16),
                          Text('Photos (${_photos.length}/3)${mode?['requires_photo'] == true ? ' *' : ''}',
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (var i = 0; i < _photos.length; i++)
                                Stack(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: Image.memory(_photos[i], width: 84, height: 84, fit: BoxFit.cover),
                                    ),
                                    Positioned(
                                      right: 0,
                                      child: InkWell(
                                        onTap: () => setState(() => _photos.removeAt(i)),
                                        child: const CircleAvatar(
                                          radius: 11,
                                          backgroundColor: Colors.black54,
                                          child: Icon(Icons.close_rounded, size: 14, color: Colors.white),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              if (_photos.length < 3)
                                InkWell(
                                  onTap: _addPhoto,
                                  child: Container(
                                    width: 84,
                                    height: 84,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: AppColors.muted.withValues(alpha: 0.4)),
                                    ),
                                    child: const Icon(Icons.add_a_photo_outlined, color: AppColors.muted),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          GradientButton(
                            label: 'Save Collection',
                            icon: Icons.payments_rounded,
                            busy: _busy,
                            onPressed: _busy ? null : _submit,
                          ),
                        ],
                      ),
                    ),
    );
  }
}
