import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/photos.dart';
import '../../core/theme.dart';
import '../../core/format.dart';
import 'punch_extras.dart';

/// What the person filled in before punching.
class PunchInput {
  const PunchInput({this.selfie, this.vehicle, this.odometerPhoto, this.odometer});

  final Uint8List? selfie;
  final String? vehicle;
  final Uint8List? odometerPhoto;
  final double? odometer;
}

/// One form for the whole punch: the selfie, the vehicle and the odometer,
/// whichever the office asked for. Everything is filled in first and checked,
/// then one Submit does the check-in or check-out.
class PunchFormScreen extends StatefulWidget {
  const PunchFormScreen({
    super.key,
    required this.punchIn,
    this.needSelfie = false,
    this.needVehicle = false,
    this.needOdometer = false,
  });

  final bool punchIn;
  final bool needSelfie;
  final bool needVehicle;
  final bool needOdometer;

  @override
  State<PunchFormScreen> createState() => _PunchFormScreenState();
}

class _PunchFormScreenState extends State<PunchFormScreen> {
  Uint8List? _selfie;
  Uint8List? _odometerPhoto;
  String? _vehicle;
  final _reading = TextEditingController();
  bool _tried = false;
  bool _busy = false;

  @override
  void dispose() {
    _reading.dispose();
    super.dispose();
  }

  String get _word => widget.punchIn ? 'Check In' : 'Check Out';

  Future<void> _shoot({required bool selfie}) async {
    setState(() => _busy = true);
    final bytes = await takePhoto(ImageSource.camera, selfie: selfie);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (bytes != null) {
        if (selfie) {
          _selfie = bytes;
        } else {
          _odometerPhoto = bytes;
        }
      }
    });
  }

  double? get _odometer => double.tryParse(_reading.text.trim());

  bool get _ready =>
      (!widget.needSelfie || _selfie != null) &&
      (!widget.needVehicle || _vehicle != null) &&
      (!widget.needOdometer || (_odometerPhoto != null && (_odometer ?? 0) > 0));

  void _submit() {
    setState(() => _tried = true);
    if (!_ready) {
      showSnack(context, 'Fill in everything above first.');
      return;
    }
    Navigator.of(context).pop(PunchInput(
      selfie: _selfie,
      vehicle: _vehicle,
      odometerPhoto: _odometerPhoto,
      odometer: widget.needOdometer ? _odometer : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_word)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
        children: [
          Text(
            widget.punchIn
                ? 'A few things before your day starts.'
                : 'A few things before you close the day.',
            style: const TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 12),
          if (widget.needSelfie)
            _photoField(
              title: 'Selfie',
              hint: 'Taken with the place and time on it.',
              icon: Icons.person_rounded,
              photo: _selfie,
              missing: _tried && _selfie == null,
              onTap: () => _shoot(selfie: true),
            ),
          if (widget.needVehicle) _vehicleField(),
          if (widget.needOdometer) ...[
            _photoField(
              title: 'Odometer photo',
              hint: 'Point at the meter so the numbers can be read.',
              icon: Icons.speed_rounded,
              photo: _odometerPhoto,
              missing: _tried && _odometerPhoto == null,
              onTap: () => _shoot(selfie: false),
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
                child: TextField(
                  controller: _reading,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Odometer reading',
                    suffixText: 'km',
                    errorText: _tried && (_odometer ?? 0) <= 0 ? 'Type the number on the meter.' : null,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: _busy ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: widget.punchIn ? AppColors.primary : AppColors.danger,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
              ),
              icon: const Icon(Icons.check_rounded),
              label: Text('Submit and $_word', style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _photoField({
    required String title,
    required String hint,
    required IconData icon,
    required Uint8List? photo,
    required bool missing,
    required VoidCallback onTap,
  }) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: missing ? AppColors.danger : Colors.transparent),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _busy ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: photo != null
                    ? Image.memory(photo, width: 72, height: 72, fit: BoxFit.cover)
                    : Container(
                        width: 72,
                        height: 72,
                        color: AppColors.background,
                        child: Icon(icon, color: AppColors.primary),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    const SizedBox(height: 3),
                    Text(photo != null ? 'Taken · tap to take it again' : hint,
                        style: TextStyle(
                            fontSize: 12.5, color: photo != null ? AppColors.success : AppColors.muted)),
                  ],
                ),
              ),
              Icon(photo != null ? Icons.check_circle_rounded : Icons.camera_alt_rounded,
                  color: photo != null ? AppColors.success : AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _vehicleField() {
    final missing = _tried && _vehicle == null;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: missing ? AppColors.danger : Colors.transparent),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('How are you travelling today?',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 2),
            const Text('Your travel allowance is worked out from this.',
                style: TextStyle(fontSize: 12.5, color: AppColors.muted)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (code, label, icon) in vehicleChoices)
                  ChoiceChip(
                    avatar: Icon(icon, size: 18, color: _vehicle == code ? Colors.white : AppColors.primary),
                    label: Text(label),
                    selected: _vehicle == code,
                    onSelected: (_) => setState(() => _vehicle = code),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
