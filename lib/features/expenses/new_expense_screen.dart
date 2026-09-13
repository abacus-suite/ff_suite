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
import '../../widgets/common.dart';
import '../clients/clients_screen.dart';

const _maxReceipts = 5;

class NewExpenseScreen extends StatefulWidget {
  const NewExpenseScreen({super.key, this.visitId, this.client});

  final int? visitId;
  final Map<String, dynamic>? client;

  @override
  State<NewExpenseScreen> createState() => _NewExpenseScreenState();
}

class _NewExpenseScreenState extends State<NewExpenseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  final List<Uint8List> _receipts = [];
  final String _uuid = const Uuid().v4();
  List<Map<String, dynamic>> _categories = [];
  Map<String, dynamic>? _category;
  Map<String, dynamic>? _client;
  DateTime _date = DateTime.now();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _client = widget.client;
    _loadCategories();
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    try {
      final list = (await Services.api.get('/api/v1/expense-categories') as List).cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        _categories = list;
        if (list.length == 1) _category = list.first;
      });
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
    }
  }

  Future<void> _addReceipt() async {
    if (_receipts.length >= _maxReceipts) return;
    final bytes = await takePhoto(ImageSource.camera);
    if (bytes == null) return;
    setState(() => _receipts.add(bytes));
  }

  Future<void> _pickClient() async {
    final client = await Navigator.of(context)
        .push<Map<String, dynamic>>(MaterialPageRoute(builder: (_) => const ClientsScreen(pickMode: true)));
    if (client != null) setState(() => _client = client);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final category = _category;
    if (category == null) {
      showSnack(context, 'Choose an expense type.');
      return;
    }
    if (category['requires_receipt'] == true && _receipts.isEmpty) {
      showSnack(context, 'A receipt photo is required for ${category['name']}.');
      return;
    }
    if (category['requires_client'] == true && _client == null) {
      showSnack(context, 'Choose the contact for ${category['name']}.');
      return;
    }
    setState(() => _busy = true);
    try {
      Position? pos;
      try {
        pos = await currentPosition(recentOk: true);
      } catch (_) {
        // Location is optional for a claim.
      }
      final result = await Services.outbox.submit('/api/v1/expenses', {
        'category_id': category['id'],
        'amount': double.tryParse(_amount.text.trim()) ?? 0,
        'date': fmtDate(_date),
        'note': _note.text.trim(),
        if (_client != null) 'partner_id': _client!['id'],
        if (widget.visitId != null) 'visit_id': widget.visitId,
        'receipts': _receipts.map(base64Encode).toList(),
        'lat': pos?.latitude,
        'lng': pos?.longitude,
        'uuid': _uuid,
      }, label: 'Expense · ${category['name']}');
      if (!mounted) return;
      showSnack(context, result.queued ? 'Claim saved on the phone · it will sync when you are back online' : 'Claim sent for approval');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final category = _category;
    final currency = category?['currency'] as String?;
    return Scaffold(
      appBar: AppBar(title: const Text('New Expense Claim')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            DropdownButtonFormField<int>(
              initialValue: category?['id'] as int?,
              decoration: const InputDecoration(labelText: 'Expense type *'),
              items: [
                for (final c in _categories) DropdownMenuItem(value: c['id'] as int, child: Text('${c['name']}')),
              ],
              onChanged: (value) => setState(() => _category = _categories.firstWhere((c) => c['id'] == value)),
              validator: (v) => v == null ? 'Choose an expense type' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Amount *',
                helperText: (category?['max_amount'] as num?) != null
                    ? 'Maximum ${fmtMoney(category?['max_amount'] as num?, currency)}'
                    : null,
              ),
              validator: (v) {
                final value = double.tryParse((v ?? '').trim());
                if (value == null || value <= 0) return 'Enter the amount';
                final max = category?['max_amount'] as num?;
                if (max != null && value > max) return 'Above the allowed maximum';
                return null;
              },
            ),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.event_rounded),
                title: const Text('Date'),
                trailing: Text(fmtDate(_date)),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime.now().subtract(const Duration(days: 60)),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) setState(() => _date = picked);
                },
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.storefront_rounded),
                title: Text(_client == null
                    ? 'Contact${category?['requires_client'] == true ? ' *' : ' (optional)'}'
                    : '${_client!['name']}'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: _pickClient,
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _note,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'What was it for?'),
            ),
            const SizedBox(height: 16),
            Text('Receipts (${_receipts.length}/$_maxReceipts)${category?['requires_receipt'] == true ? ' *' : ''}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < _receipts.length; i++)
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(_receipts[i], width: 92, height: 92, fit: BoxFit.cover),
                      ),
                      Positioned(
                        right: 0,
                        top: 0,
                        child: IconButton.filledTonal(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.close, size: 16),
                          onPressed: () => setState(() => _receipts.removeAt(i)),
                        ),
                      ),
                    ],
                  ),
                if (_receipts.length < _maxReceipts)
                  SizedBox(
                    width: 92,
                    height: 92,
                    child: OutlinedButton(onPressed: _addReceipt, child: const Icon(Icons.add_a_photo_rounded)),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            GradientButton(label: 'Send for approval', icon: Icons.send_rounded, busy: _busy, onPressed: _submit),
          ],
        ),
      ),
    );
  }
}
