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

  Future<void> _addPhoto() async {
    if (_photos.length >= 3) return;
    final bytes = await takePhoto(ImageSource.camera);
    if (bytes == null) return;
    if (mounted) setState(() => _photos.add(bytes));
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
                                style: const TextStyle(color: AixoloColors.muted)),
                          ),
                          const SizedBox(height: 8),
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
                                      border: Border.all(color: AixoloColors.muted.withValues(alpha: 0.4)),
                                    ),
                                    child: const Icon(Icons.add_a_photo_outlined, color: AixoloColors.muted),
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
