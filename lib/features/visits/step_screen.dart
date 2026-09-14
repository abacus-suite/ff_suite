import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/photos.dart';
import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

const _maxPhotos = 5;

/// One visit step: notes, photo or confirmation. Pops `true` when recorded.
class StepScreen extends StatefulWidget {
  const StepScreen({super.key, this.visitId, required this.step, this.visitUuid});

  final int? visitId;

  /// Set for a check-in made offline, which has no id on the phone yet.
  final String? visitUuid;
  final Map<String, dynamic> step;

  @override
  State<StepScreen> createState() => _StepScreenState();
}

class _StepScreenState extends State<StepScreen> {
  final _note = TextEditingController();
  final List<Uint8List> _photos = [];
  bool _busy = false;

  String get _type => widget.step['type'] as String;
  bool get _noteRequired => _type == 'note';
  bool get _photoRequired => _type == 'photo';

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _addPhoto() async {
    if (_photos.length >= _maxPhotos) return;
    final bytes = await takePhoto(ImageSource.camera);
    if (bytes == null) return;
    setState(() => _photos.add(bytes));
  }

  Future<void> _send(Map<String, dynamic> payload) async {
    setState(() => _busy = true);
    try {
      await Services.outbox.submit('/api/v1/visits/${widget.visitId ?? 0}/steps/${widget.step['id']}', {
        ...payload,
        if (widget.visitUuid != null) 'visit_uuid': widget.visitUuid,
      }, label: '${widget.step['name']}');
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (_noteRequired && _note.text.trim().isEmpty) {
      showSnack(context, 'Please write the notes.');
      return;
    }
    if (_photoRequired && _photos.isEmpty) {
      showSnack(context, 'Please take a photo.');
      return;
    }
    await _send({
      'note': _note.text.trim(),
      'photos': _photos.map(base64Encode).toList(),
    });
  }

  Future<void> _skip() async {
    final reasonController = TextEditingController();
    final reasonNeeded = widget.step['skip_reason_required'] == true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Skip "${widget.step['name']}"?'),
        content: TextField(
          controller: reasonController,
          autofocus: true,
          decoration: InputDecoration(labelText: reasonNeeded ? 'Reason *' : 'Reason (optional)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Skip')),
        ],
      ),
    );
    final reason = reasonController.text.trim();
    // Disposed after the dialog's closing animation: the field is still on screen until then.
    WidgetsBinding.instance.addPostFrameCallback((_) => Future.delayed(const Duration(milliseconds: 400), reasonController.dispose));
    if (confirmed != true) return;
    if (reasonNeeded && reason.isEmpty) {
      if (mounted) showSnack(context, 'A reason is needed to skip this step.');
      return;
    }
    await _send({'skip': true, 'skip_reason': reason});
  }

  @override
  Widget build(BuildContext context) {
    final step = widget.step;
    return Scaffold(
      appBar: AppBar(
        title: Text('${step['name']}'),
        actions: [
          if (step['allow_skip'] == true)
            TextButton(onPressed: _busy ? null : _skip, child: const Text('Skip')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (step['instruction'] != null)
            Card(
              color: const Color(0xFFEAF3FF),
              child: ListTile(
                leading: const Icon(Icons.info_outline_rounded, color: AppColors.primary),
                title: Text('${step['instruction']}'),
              ),
            ),
          if (_type != 'photo') ...[
            const SizedBox(height: 8),
            TextField(
              controller: _note,
              maxLines: 5,
              autofocus: _noteRequired,
              decoration: InputDecoration(
                labelText: _noteRequired ? 'Notes *' : 'Notes',
                hintText: 'e.g. Owner not available, come back Friday',
              ),
            ),
          ],
          const SizedBox(height: 16),
          Text('Photos (${_photos.length}/$_maxPhotos)${_photoRequired ? ' *' : ''}',
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
                      child: Image.memory(_photos[i], width: 92, height: 92, fit: BoxFit.cover),
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
                  width: 92,
                  height: 92,
                  child: OutlinedButton(onPressed: _addPhoto, child: const Icon(Icons.add_a_photo_rounded)),
                ),
            ],
          ),
          const SizedBox(height: 24),
          GradientButton(label: 'Save step', icon: Icons.check_rounded, busy: _busy, onPressed: _submit),
        ],
      ),
    );
  }
}
