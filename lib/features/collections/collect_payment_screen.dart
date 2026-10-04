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

  num get _pickedTotal => _invoices
      .where((i) => _picked.contains(i['id']))
      .fold<num>(0, (sum, i) => sum + ((i['pending'] as num?) ?? 0));

  /// Ticking invoices fills the amount with what they add up to.
  void _toggle(int id, bool on) {
    setState(() {
      on ? _picked.add(id) : _picked.remove(id);
      final total = _pickedTotal;
      _amount.text = total == 0 ? '' : fmtQty(total);
    });
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
      if (mounted) showSnack(context, e.toString());
    }
  }

  /// Splits the amount down the ticked invoices, oldest first, none beyond what is owed.
  List<Map<String, dynamic>> _allocations(double amount) {
    var left = amount;
    final rows = <Map<String, dynamic>>[];
    for (final invoice in _invoices.where((i) => _picked.contains(i['id']))) {
      if (left <= 0) break;
      final pending = ((invoice['pending'] as num?) ?? 0).toDouble();
      final take = left < pending ? left : pending;
      rows.add({'invoice_id': invoice['id'], 'amount': take});
      left -= take;
    }
    return rows;
  }

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

  Widget _invoicesCard() {
    if (_invoices.isEmpty && _kind != 'outlet') return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                    _invoices.isEmpty ? 'No open invoices' : 'Pay these invoices',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
              ),
              if (_kind == 'outlet')
                TextButton.icon(
                  onPressed: _addInvoice,
                  icon: const Icon(Icons.add_rounded, size: 17),
                  label: const Text('Add invoice'),
                ),
            ],
          ),
          if (_invoices.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('The money is recorded on account. Add the invoice if you have it in front of you.',
                  style: TextStyle(fontSize: 12, color: AppColors.muted)),
            ),
          for (final invoice in _invoices)
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _picked.contains(invoice['id']),
              onChanged: (on) => _toggle(invoice['id'] as int, on == true),
              title: Text('${invoice['number']}',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
              subtitle: Text(
                [
                  if (invoice['due_date'] != null) 'due ${invoice['due_date']}',
                  if (invoice['overdue'] == true) 'overdue',
                ].join(' · '),
                style: TextStyle(
                    fontSize: 11.5,
                    color: invoice['overdue'] == true ? AppColors.danger : AppColors.muted),
              ),
              secondary: Text(fmtMoney(invoice['pending'] as num?, invoice['currency'] as String?),
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
            ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final mode = _mode;
    if (mode == null) {
      showSnack(context, 'Choose how the money was paid.');
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    if (mode['requires_photo'] == true && _photos.isEmpty) {
      showSnack(context, 'A photo is required for ${mode['name']}.');
      return;
    }
    if (mode['requires_instrument_date'] == true && _instrumentDate == null) {
      showSnack(context, 'Enter the cheque date.');
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
          'invoice_ids': _picked.toList(),
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
      if (mounted) showSnack(context, e.toString());
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
          ? const Center(child: CircularProgressIndicator())
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
                          _invoicesCard(),
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
