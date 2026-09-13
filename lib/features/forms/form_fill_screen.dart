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

const _maxPhotosPerQuestion = 5;

/// Renders a server-defined form (12 question types, conditional questions).
/// Pops `true` after a successful submission.
class FormFillScreen extends StatefulWidget {
  const FormFillScreen({super.key, required this.form, this.partnerId, this.visitId});

  final Map<String, dynamic> form;
  final int? partnerId;
  final int? visitId;

  @override
  State<FormFillScreen> createState() => _FormFillScreenState();
}

class _FormFillScreenState extends State<FormFillScreen> {
  final Map<String, dynamic> _answers = {};
  final Map<String, List<Uint8List>> _photos = {};
  final String _uuid = const Uuid().v4();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Questions linked to a customer field start from what the customer record says.
    for (final q in _questions) {
      final value = q['value'];
      if (value != null && q['type'] != 'photo') _answers['${q['key']}'] = value;
    }
  }

  List<Map<String, dynamic>> get _questions =>
      ((widget.form['questions'] as List?) ?? []).cast<Map<String, dynamic>>();

  bool _visible(Map<String, dynamic> q) {
    final condition = q['visible_if'] as Map?;
    if (condition == null) return true;
    final actual = _answers[condition['key']];
    final expected = '${condition['value'] ?? ''}'.trim().toLowerCase();
    if (actual is List) return actual.map((a) => '$a'.toLowerCase()).contains(expected);
    if (actual is bool) return actual ? ['yes', 'true', '1'].contains(expected) : ['no', 'false', '0'].contains(expected);
    return '${actual ?? ''}'.trim().toLowerCase() == expected;
  }

  bool _isEmpty(dynamic value) =>
      value == null || (value is String && value.trim().isEmpty) || (value is List && value.isEmpty);

  void _set(String key, dynamic value) => setState(() => _answers[key] = value);

  Future<void> _submit() async {
    final missing = <String>[];
    final answers = <String, dynamic>{};
    final photos = <String, List<String>>{};
    for (final q in _questions) {
      if (!_visible(q)) continue;
      final key = q['key'] as String;
      if (q['type'] == 'photo') {
        final list = _photos[key] ?? const [];
        if (q['required'] == true && list.isEmpty) missing.add('${q['label']}');
        if (list.isNotEmpty) photos[key] = list.map(base64Encode).toList();
        continue;
      }
      final value = _answers[key];
      if (_isEmpty(value)) {
        if (q['required'] == true) missing.add('${q['label']}');
        continue;
      }
      answers[key] = value;
    }
    if (missing.isNotEmpty) {
      showSnack(context, 'Please answer: ${missing.join(', ')}');
      return;
    }
    setState(() => _busy = true);
    try {
      Position? pos;
      try {
        pos = await currentPosition(recentOk: true);
      } catch (_) {
        // Location is optional for forms.
      }
      await Services.outbox.submit('/api/v1/forms/${widget.form['id']}/responses', {
        'answers': answers,
        'photos': photos,
        if (widget.partnerId != null) 'partner_id': widget.partnerId,
        if (widget.visitId != null) 'visit_id': widget.visitId,
        'lat': pos?.latitude,
        'lng': pos?.longitude,
        'uuid': _uuid,
      }, label: '${widget.form['name']}');
      if (!mounted) return;
      showSnack(context, 'Saved');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final description = widget.form['description'] as String?;
    return Scaffold(
      appBar: AppBar(title: Text('${widget.form['name']}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (description != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(description, style: const TextStyle(color: AixoloColors.muted)),
            ),
          for (final q in _questions)
            if (_visible(q)) KeyedSubtree(key: ValueKey(q['key']), child: _question(q)),
          const SizedBox(height: 16),
          GradientButton(label: 'Submit', icon: Icons.send_rounded, busy: _busy, onPressed: _submit),
        ],
      ),
    );
  }

  Widget _question(Map<String, dynamic> q) {
    final key = q['key'] as String;
    final type = q['type'] as String;
    final options = ((q['options'] as List?) ?? []).map((o) => '$o').toList();
    final Widget input = switch (type) {
      'textarea' => _text(key, maxLines: 4),
      'number' => _text(key, keyboard: TextInputType.number),
      'decimal' => _text(key, keyboard: const TextInputType.numberWithOptions(decimal: true)),
      'phone' => _text(key, keyboard: TextInputType.phone),
      'email' => _text(key, keyboard: TextInputType.emailAddress),
      'date' => _date(key),
      'select' => _select(key, options),
      'multiselect' => _multi(key, options),
      'checkbox' => _yesNo(key),
      'rating' => _rating(key),
      'photo' => _photoInput(key),
      _ => _text(key),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text('${q['label']}${q['required'] == true ? ' *' : ''}',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                if (q['customer_field'] == true)
                  const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: Tooltip(
                      message: 'Saved on the customer',
                      child: Icon(Icons.storefront_rounded, size: 16, color: AixoloColors.success),
                    ),
                  ),
              ],
            ),
            if (q['hint'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('${q['hint']}', style: const TextStyle(color: AixoloColors.muted, fontSize: 12)),
              ),
            const SizedBox(height: 10),
            input,
          ],
        ),
      ),
    );
  }

  Widget _text(String key, {TextInputType? keyboard, int maxLines = 1}) {
    return TextFormField(
      initialValue: _answers[key]?.toString(),
      keyboardType: keyboard,
      maxLines: maxLines,
      decoration: const InputDecoration(hintText: 'Your answer', isDense: true),
      onChanged: (v) => _set(key, v),
    );
  }

  Widget _date(String key) {
    final value = _answers[key] as String?;
    return OutlinedButton.icon(
      onPressed: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value != null ? DateTime.parse(value) : DateTime.now(),
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        if (picked != null) _set(key, fmtDate(picked));
      },
      icon: const Icon(Icons.event_rounded),
      label: Text(value ?? 'Pick a date'),
    );
  }

  Widget _select(String key, List<String> options) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in options)
          ChoiceChip(label: Text(option), selected: _answers[key] == option, onSelected: (_) => _set(key, option)),
      ],
    );
  }

  Widget _multi(String key, List<String> options) {
    final selected = List<String>.from((_answers[key] as List?) ?? const []);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in options)
          FilterChip(
            label: Text(option),
            selected: selected.contains(option),
            onSelected: (on) {
              on ? selected.add(option) : selected.remove(option);
              _set(key, selected);
            },
          ),
      ],
    );
  }

  Widget _yesNo(String key) {
    final value = _answers[key] as bool?;
    return SegmentedButton<bool>(
      segments: const [
        ButtonSegment(value: true, label: Text('Yes'), icon: Icon(Icons.check_rounded)),
        ButtonSegment(value: false, label: Text('No'), icon: Icon(Icons.close_rounded)),
      ],
      selected: value == null ? <bool>{} : {value},
      emptySelectionAllowed: true,
      onSelectionChanged: (s) => _set(key, s.isEmpty ? null : s.first),
    );
  }

  Widget _rating(String key) {
    final value = (_answers[key] as int?) ?? 0;
    return Row(
      children: [
        for (var i = 1; i <= 5; i++)
          IconButton(
            onPressed: () => _set(key, i),
            icon: Icon(i <= value ? Icons.star_rounded : Icons.star_outline_rounded, color: AixoloColors.warning, size: 32),
          ),
      ],
    );
  }

  Widget _photoInput(String key) {
    final list = _photos[key] ?? <Uint8List>[];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var i = 0; i < list.length; i++)
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(list[i], width: 88, height: 88, fit: BoxFit.cover),
              ),
              Positioned(
                right: 0,
                top: 0,
                child: IconButton.filledTonal(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: () => setState(() => list.removeAt(i)),
                ),
              ),
            ],
          ),
        if (list.length < _maxPhotosPerQuestion)
          SizedBox(
            width: 88,
            height: 88,
            child: OutlinedButton(
              onPressed: () async {
                final bytes = await takePhoto(ImageSource.camera);
                if (bytes == null) return;
                setState(() => _photos[key] = [...list, bytes]);
              },
              child: const Icon(Icons.add_a_photo_rounded),
            ),
          ),
      ],
    );
  }
}
