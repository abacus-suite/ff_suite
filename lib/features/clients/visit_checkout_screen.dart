import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/format.dart';
import '../../core/geo.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../forms/form_fill_screen.dart';

/// Used when the server has no outcome master configured.
const legacyOutcomes = <String, String>{
  'met': 'Met client',
  'order': 'Order taken',
  'not_available': 'Client not available',
  'closed': 'Shop closed',
  'other': 'Other',
};

const _maxPhotos = 3;

class VisitCheckoutScreen extends StatefulWidget {
  const VisitCheckoutScreen({super.key, required this.visit});

  final Map<String, dynamic> visit;

  @override
  State<VisitCheckoutScreen> createState() => _VisitCheckoutScreenState();
}

class _VisitCheckoutScreenState extends State<VisitCheckoutScreen> {
  List<Map<String, dynamic>> _outcomes = [];
  Map<String, dynamic>? _selected;
  String _legacy = 'met';
  List<Map<String, dynamic>> _missingForms = [];
  final _note = TextEditingController();
  final List<Uint8List> _photos = [];
  bool _loading = true;
  bool _busy = false;

  int get _clientId => (widget.visit['client'] as Map)['id'] as int;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final formsOn = Services.auth.profile!.feature('forms');
    final results = await Future.wait<dynamic>([
      Services.api.get('/api/v1/visit-outcomes', query: {'partner_id': _clientId}).catchError((_) => <dynamic>[]),
      formsOn
          ? Services.api.get('/api/v1/forms', query: {
              'trigger': 'visit',
              'visit_id': widget.visit['id'],
              'partner_id': _clientId,
            }).catchError((_) => <dynamic>[])
          : Future<dynamic>.value(<dynamic>[]),
    ]);
    if (!mounted) return;
    setState(() {
      _outcomes = (results[0] as List).cast<Map<String, dynamic>>();
      _missingForms = (results[1] as List)
          .cast<Map<String, dynamic>>()
          .where((f) => f['mandatory'] == true && f['filled'] != true)
          .toList();
      _loading = false;
    });
  }

  Future<void> _addPhoto() async {
    if (_photos.length >= _maxPhotos) return;
    final image = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 1280, imageQuality: 65);
    if (image == null) return;
    final bytes = await image.readAsBytes();
    setState(() => _photos.add(bytes));
  }

  Future<void> _fillForm(Map<String, dynamic> form) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => FormFillScreen(form: form, partnerId: _clientId, visitId: widget.visit['id'] as int),
    ));
    if (saved == true) _load();
  }

  Future<void> _submit() async {
    final outcome = _selected;
    if (_missingForms.isNotEmpty) {
      showSnack(context, 'Fill the required forms first.');
      return;
    }
    if (_outcomes.isNotEmpty && outcome == null) {
      showSnack(context, 'Choose an outcome.');
      return;
    }
    if (outcome?['requires_note'] == true && _note.text.trim().isEmpty) {
      showSnack(context, 'Add a note for "${outcome!['name']}".');
      return;
    }
    if (outcome?['requires_photo'] == true && _photos.isEmpty) {
      showSnack(context, 'Add a photo for "${outcome!['name']}".');
      return;
    }
    setState(() => _busy = true);
    try {
      Position? pos;
      try {
        pos = await currentPosition();
      } catch (_) {
        // Check-out still works without a fresh fix.
      }
      await Services.api.post('/api/v1/visits/${widget.visit['id']}/check-out', {
        'lat': pos?.latitude,
        'lng': pos?.longitude,
        if (outcome != null) 'outcome_id': outcome['id'] else 'outcome': _legacy,
        'note': _note.text.trim(),
        'photos': _photos.map(base64Encode).toList(),
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final client = widget.visit['client'] as Map;
    final outcome = _selected;
    return Scaffold(
      appBar: AppBar(title: Text('Check out · ${client['name']}')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Checked in at ${fmtTime(widget.visit['check_in_at'])}', style: const TextStyle(color: AixoloColors.muted)),
                if (_missingForms.isNotEmpty)
                  Card(
                    color: const Color(0xFFFFF5E5),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Required before check-out', style: TextStyle(fontWeight: FontWeight.w700)),
                          for (final form in _missingForms)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.assignment_late_rounded, color: AixoloColors.warning),
                              title: Text('${form['name']}'),
                              trailing: TextButton(onPressed: () => _fillForm(form), child: const Text('Fill now')),
                            ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                const Text('Outcome', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _outcomes.isNotEmpty
                      ? [
                          for (final o in _outcomes)
                            ChoiceChip(
                              label: Text('${o['name']}'),
                              selected: outcome?['id'] == o['id'],
                              onSelected: (_) => setState(() => _selected = o),
                            ),
                        ]
                      : [
                          for (final entry in legacyOutcomes.entries)
                            ChoiceChip(
                              label: Text(entry.value),
                              selected: _legacy == entry.key,
                              onSelected: (_) => setState(() => _legacy = entry.key),
                            ),
                        ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _note,
                  maxLines: 3,
                  decoration: InputDecoration(labelText: outcome?['requires_note'] == true ? 'Notes *' : 'Notes'),
                ),
                const SizedBox(height: 16),
                Text('Photos (${_photos.length}/$_maxPhotos)${outcome?['requires_photo'] == true ? ' *' : ''}',
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
                            borderRadius: BorderRadius.circular(12),
                            child: Image.memory(_photos[i], width: 96, height: 96, fit: BoxFit.cover),
                          ),
                          Positioned(
                            right: 0,
                            top: 0,
                            child: IconButton.filledTonal(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.close, size: 16),
                              onPressed: () => setState(() => _photos.removeAt(i)),
                            ),
                          ),
                        ],
                      ),
                    if (_photos.length < _maxPhotos)
                      SizedBox(
                        width: 96,
                        height: 96,
                        child: OutlinedButton(onPressed: _addPhoto, child: const Icon(Icons.add_a_photo_rounded)),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                GradientButton(label: 'Complete visit', icon: Icons.check_rounded, busy: _busy, onPressed: _submit),
              ],
            ),
    );
  }
}
