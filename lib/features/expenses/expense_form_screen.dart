import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../core/format.dart';
import '../../core/photos.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../tasks/task_widgets.dart';
import '../../widgets/skeleton.dart';

const _maxPictures = 5;

/// One form for both kinds of expense. A claim (own money) may be saved without
/// a picture; a company card expense must have one and needs the card used.
/// With [existing] it edits a claim that has not been sent yet.
class ExpenseFormScreen extends StatefulWidget {
  const ExpenseFormScreen({super.key, required this.kind, this.existing});

  final String kind;
  final Map<String, dynamic>? existing;

  @override
  State<ExpenseFormScreen> createState() => _ExpenseFormScreenState();
}

class _ExpenseFormScreenState extends State<ExpenseFormScreen> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  final List<Uint8List> _pictures = [];
  final String _uuid = const Uuid().v4();
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _cards = [];
  Map<String, dynamic>? _category;
  Map<String, dynamic>? _sub;
  Map<String, dynamic>? _card;
  DateTime _date = DateTime.now();
  bool _busy = false;
  bool _loaded = false;

  bool get _isCard => widget.kind == 'card';
  bool get _editing => widget.existing != null;
  int get _have => ((widget.existing?['receipt_count'] as num?) ?? 0).toInt();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _children => ((_category?['children'] as List?) ?? []).cast<Map<String, dynamic>>();

  Future<void> _load() async {
    try {
      final data = await Services.api.get('/api/v1/expense-categories') as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _categories = ((data['categories'] as List?) ?? []).cast<Map<String, dynamic>>();
        _cards = ((data['cards'] as List?) ?? []).cast<Map<String, dynamic>>();
        final e = widget.existing;
        if (e != null) {
          final cid = (e['category'] as Map?)?['id'];
          _category = _categories.where((c) => c['id'] == cid).cast<Map<String, dynamic>?>().firstOrNull;
          final sid = (e['sub_category'] as Map?)?['id'];
          _sub = _children.where((c) => c['id'] == sid).cast<Map<String, dynamic>?>().firstOrNull;
          _amount.text = '${e['amount']}';
          _note.text = '${e['note'] ?? ''}';
          _date = DateTime.tryParse('${e['date']}') ?? _date;
        }
        _loaded = true;
      });
    } catch (e) {
      if (mounted) await showProblem(context, e.toString());
    }
  }

  Future<void> _addPicture(ImageSource source) async {
    if (_pictures.length + _have >= _maxPictures) return;
    final bytes = await takePhoto(source, stamp: source == ImageSource.camera);
    if (bytes == null) return;
    setState(() => _pictures.add(bytes));
  }

  Future<void> _picturePicker() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
              leading: const Icon(Icons.photo_camera_rounded),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(sheet, ImageSource.camera)),
          ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('Gallery'),
              onTap: () => Navigator.pop(sheet, ImageSource.gallery)),
        ]),
      ),
    );
    if (source != null) await _addPicture(source);
  }

  Future<void> _save() async {
    final problems = <String>[];
    if (_category == null) problems.add('Expense category');
    if (_category != null && _children.isNotEmpty && _sub == null) problems.add('Sub category');
    final amount = double.tryParse(_amount.text.trim());
    if (amount == null || amount <= 0) problems.add('Amount');
    final max = _category?['max_amount'] as num?;
    if (amount != null && max != null && amount > max) problems.add('Amount: above the allowed maximum of $max');
    if (_isCard && _card == null) problems.add('Payment mode (card)');
    if (_isCard && _pictures.isEmpty) problems.add('Picture of the bill');
    if (problems.isNotEmpty) {
      await showProblem(context, problems, title: 'Still needed');
      return;
    }
    setState(() => _busy = true);
    try {
      final payload = {
        'kind': widget.kind,
        'category_id': _category!['id'],
        if (_sub != null) 'sub_category_id': _sub!['id'],
        'amount': amount,
        'date': fmtDate(_date),
        'note': _note.text.trim(),
        if (_isCard) 'payment_mode_id': _card!['id'],
        'receipts': _pictures.map(base64Encode).toList(),
      };
      if (_editing) {
        await Services.api.post('/api/v1/expenses/${widget.existing!['id']}/update', payload);
        if (mounted) showSnack(context, 'Saved');
      } else {
        final result = await Services.outbox.submit('/api/v1/expenses', {...payload, 'uuid': _uuid},
            label: 'Expense · ${_category!['name']}');
        if (mounted) {
          showSnack(
              context,
              result.queued
                  ? 'Saved on the phone. It will sync when you are back online'
                  : _isCard
                      ? 'Recorded'
                      : 'Saved to My Expenses');
        }
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) await showProblem(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _dropdown(String label, Map<String, dynamic>? value, List<Map<String, dynamic>> items,
      ValueChanged<Map<String, dynamic>?> onChanged) {
    return DropdownButtonFormField<int>(
      initialValue: value?['id'] as int?,
      isExpanded: true,
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: AppColors.background,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      ),
      hint: Text('Choose'),
      items: [for (final c in items) DropdownMenuItem(value: c['id'] as int, child: Text('${c['name']}'))],
      onChanged: (id) => onChanged(items.where((c) => c['id'] == id).firstOrNull),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = _isCard ? 'Expense Submission' : 'Expense Claiming';
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(_editing ? 'Edit expense' : title)),
      body: !_loaded
          ? const LoadingView()
          : ListView(
              padding: const EdgeInsets.all(14),
              children: [
                if (_isCard)
                  Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(16)),
                    child: const Text(
                        'Not a claim. This records what the company paid on your behalf, for reconciliation.',
                        style: TextStyle(fontSize: 12.5)),
                  ),
                StepCard(
                  title: 'Expense category *',
                  child: _dropdown('Category', _category, _categories, (c) => setState(() {
                        _category = c;
                        _sub = null;
                      })),
                ),
                if (_category != null && _children.isNotEmpty)
                  StepCard(
                    title: 'Sub category *',
                    child: _dropdown('Sub category', _sub, _children, (c) => setState(() => _sub = c)),
                  ),
                StepCard(
                  title: 'Date *',
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.event_rounded),
                    label: Text(fmtDate(_date)),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _date,
                        firstDate: DateTime.now().subtract(const Duration(days: 90)),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) setState(() => _date = picked);
                    },
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
                if (_isCard)
                  StepCard(
                    title: 'Payment mode (card) *',
                    child: _dropdown('Card', _card, _cards, (c) => setState(() => _card = c)),
                  ),
                StepCard(
                  title: 'Description',
                  note: 'Optional',
                  child: TextAnswer(controller: _note, hint: 'What was it for?', lines: 3),
                ),
                StepCard(
                  title: _isCard ? 'Pictures *' : 'Pictures',
                  note: _isCard
                      ? 'Up to $_maxPictures. A picture of the bill is needed.'
                      : 'Up to $_maxPictures. Optional now: the bill may come later, but it is needed to send for approval.',
                  child: Wrap(spacing: 8, runSpacing: 8, children: [
                    if (_have > 0)
                      Container(
                        width: 92,
                        height: 92,
                        decoration: BoxDecoration(
                            color: AppColors.success.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          const Icon(Icons.photo_library_rounded, color: AppColors.success),
                          Text('$_have saved', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                        ]),
                      ),
                    for (var i = 0; i < _pictures.length; i++)
                      Stack(children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.memory(_pictures[i], width: 92, height: 92, fit: BoxFit.cover),
                        ),
                        Positioned(
                          right: 0,
                          top: 0,
                          child: IconButton.filledTonal(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.close, size: 16),
                            onPressed: () => setState(() => _pictures.removeAt(i)),
                          ),
                        ),
                      ]),
                    if (_pictures.length + _have < _maxPictures)
                      SizedBox(
                        width: 92,
                        height: 92,
                        child: OutlinedButton(
                          onPressed: _picturePicker,
                          style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            const Icon(Icons.add_a_photo_rounded),
                            Text('${_pictures.length + _have}/$_maxPictures', style: const TextStyle(fontSize: 11)),
                          ]),
                        ),
                      ),
                  ]),
                ),
                const SizedBox(height: 6),
                GradientButton(
                  label: _editing ? 'Save' : (_isCard ? 'Submit' : 'Save Expense'),
                  icon: Icons.check_rounded,
                  busy: _busy,
                  onPressed: _save,
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}
