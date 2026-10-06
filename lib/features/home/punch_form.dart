import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/photos.dart';
import '../../core/theme.dart';
import '../../core/format.dart';
import '../beat/plan_day_screen.dart';
import '../../core/services.dart';
import 'punch_extras.dart';

/// What the person filled in before punching.
class PunchInput {
  const PunchInput(
      {this.selfie, this.vehicle, this.vehicleNote, this.odometerPhoto, this.odometer, this.earlyReason});

  final Uint8List? selfie;
  final String? vehicle;

  /// What "Other" was, in the person's own words.
  final String? vehicleNote;
  final Uint8List? odometerPhoto;
  final double? odometer;

  /// Why the day is being ended before the shift does.
  final String? earlyReason;
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
    this.vehicle,
    this.shiftEndsAt,
    this.askEarlyReason = false,
    this.odometerIn,
    this.odometerLast,
    this.planBeat = false,
  });

  final bool punchIn;
  final bool needSelfie;
  final bool needVehicle;
  final bool needOdometer;

  /// The vehicle chosen at check-in, so check-out knows whether to ask for the meter.
  final String? vehicle;

  /// When today's shift is due to end, in the person's own time.
  final DateTime? shiftEndsAt;

  /// The office asks for a reason when the day ends early.
  final bool askEarlyReason;

  /// At check-out: the reading entered at check-in. At check-in: the last reading on record.
  final double? odometerIn;
  final double? odometerLast;

  /// At check-in the first step is choosing today's beat, when nothing is planned yet.
  final bool planBeat;

  @override
  State<PunchFormScreen> createState() => _PunchFormScreenState();
}

class _PunchFormScreenState extends State<PunchFormScreen> {
  Uint8List? _selfie;
  Uint8List? _odometerPhoto;
  late String? _vehicle = widget.vehicle;
  final _reading = TextEditingController();
  final _note = TextEditingController();
  final _early = TextEditingController();
  bool _tried = false;
  bool _busy = false;

  /// The steps, one at a time: which of them there are comes from the office's settings.
  int _step = 0;
  bool _autoSent = false;

  /// Choosing today's beat: still being looked up, needed, or not needed (planned, no beats, done or skipped).
  String _beat = 'checking';

  @override
  void initState() {
    super.initState();
    if (widget.planBeat && widget.punchIn) {
      _checkBeat();
    } else {
      _beat = 'done';
    }
  }

  Future<void> _checkBeat() async {
    try {
      final today = fmtDate(DateTime.now());
      final planned = await Services.api.get('/api/v1/route-plan/days', query: {'start': today, 'end': today}) as List;
      final routes = planned.isEmpty ? await Services.api.get('/api/v1/route-plan/routes') as List : const [];
      if (mounted) setState(() => _beat = planned.isEmpty && routes.isNotEmpty ? 'needed' : 'done');
    } catch (_) {
      // Offline or no planning: the check-in is not held up by it.
      if (mounted) setState(() => _beat = 'done');
    }
  }

  List<String> get _steps => [
        if (_beat != 'done') 'beat',
        if (_isEarly) 'early',
        if (widget.needSelfie) 'selfie',
        if (widget.needVehicle) 'vehicle',
        if (_hasMeter) 'meter',
      ];

  static const _stepTitle = {
    'beat': 'Choose today\'s beat',
    'early': 'Leaving early',
    'selfie': 'Selfie',
    'vehicle': 'Your vehicle',
    'meter': 'Odometer',
  };

  /// What is missing on this step, or null when it is complete.
  String? _stepProblem(String key) => switch (key) {
        'early' => _early.text.trim().isEmpty ? 'Please say why you are leaving early.' : null,
        'selfie' => _selfie == null ? 'Take the selfie to go on.' : null,
        'vehicle' => _vehicle == null
            ? 'Choose how you are travelling.'
            : (_vehicle == 'other' && _note.text.trim().isEmpty ? 'Say what vehicle it is.' : null),
        'meter' => _meterProblem ??
            (_odometerPhoto == null
                ? 'Take the photo of the meter.'
                : ((_odometer ?? 0) <= 0 ? 'Type the number on the meter.' : null)),
        _ => null,
      };

  void _next() {
    final steps = _steps;
    final key = steps[_step.clamp(0, steps.length - 1)];
    final problem = _stepProblem(key);
    setState(() => _tried = true);
    if (problem != null) {
      showSnack(context, problem);
      return;
    }
    setState(() {
      _tried = false;
      _step++;
    });
  }

  @override
  void dispose() {
    _reading.dispose();
    _note.dispose();
    _early.dispose();
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

  /// Ending the day before the shift does, with the office asking why.
  bool get _isEarly {
    final ends = widget.shiftEndsAt;
    return !widget.punchIn && widget.askEarlyReason && ends != null && DateTime.now().isBefore(ends);
  }

  String get _earlyBy {
    final ends = widget.shiftEndsAt;
    if (ends == null) return '';
    final left = ends.difference(DateTime.now());
    final hours = left.inHours;
    final minutes = left.inMinutes % 60;
    return hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m';
  }

  /// Only a two- or four-wheeler has a meter to photograph. On foot, in a bus
  /// or when the office does not ask for the vehicle at all, nothing is asked.
  bool get _hasMeter =>
      widget.needOdometer &&
      (widget.needVehicle || widget.vehicle != null
          ? const ['two_wheeler', 'four_wheeler'].contains(_vehicle)
          : true);

  /// The reading to stay at or above: check-in's own at check-out, the last one on record at check-in.
  double? get _floor => widget.punchIn ? widget.odometerLast : widget.odometerIn;

  /// What is wrong with the typed reading, or null when it is fine.
  String? get _meterProblem {
    final value = _odometer;
    final floor = _floor;
    if (!_hasMeter || value == null || floor == null || floor <= 0) return null;
    if (value < floor) {
      return widget.punchIn
          ? 'Below the last reading on record (${fmtQty(floor)}). Enter the correct reading.'
          : 'Below the check-in reading (${fmtQty(floor)}). Enter the correct reading.';
    }
    return null;
  }

  /// Today's distance by the meter, once check-out has a reading to subtract from.
  double? get _meterKm {
    final value = _odometer;
    final start = widget.odometerIn;
    if (widget.punchIn || !_hasMeter || value == null || start == null || value < start) return null;
    return value - start;
  }

  bool get _ready =>
      _meterProblem == null &&
      (!widget.needSelfie || _selfie != null) &&
      (!widget.needVehicle || (_vehicle != null && (_vehicle != 'other' || _note.text.trim().isNotEmpty))) &&
      (!_hasMeter || (_odometerPhoto != null && (_odometer ?? 0) > 0)) &&
      (!_isEarly || _early.text.trim().isNotEmpty);

  void _submit() {
    setState(() => _tried = true);
    if (!_ready) {
      showProblem(context, 'Fill in everything above first.');
      return;
    }
    Navigator.of(context).pop(PunchInput(
      selfie: _selfie,
      vehicle: _vehicle,
      vehicleNote: _vehicle == 'other' ? _note.text.trim() : null,
      odometerPhoto: _hasMeter ? _odometerPhoto : null,
      odometer: _hasMeter ? _odometer : null,
      earlyReason: _isEarly ? _early.text.trim() : null,
    ));
  }

  /// The progress along the top: a dot per step, the current one stretched.
  Widget _progress(int count, int at) => Row(children: [
        for (var i = 0; i < count; i++)
          Expanded(
            child: Container(
              height: 5,
              margin: EdgeInsets.only(right: i == count - 1 ? 0 : 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: i <= at ? (widget.punchIn ? AppColors.primary : AppColors.danger) : AppColors.border,
              ),
            ),
          ),
      ]);

  Widget _stepBody(String key) {
    switch (key) {
      case 'early':
        return Card(
          color: const Color(0xFFFFF6E5),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.schedule_rounded, size: 18, color: AppColors.warning),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('You are ending the day $_earlyBy before your shift ends.',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                  ),
                ]),
                TextField(
                  controller: _early,
                  onChanged: (_) => setState(() {}),
                  textCapitalization: TextCapitalization.sentences,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'Why are you leaving early?',
                    hintText: 'Not well, family matter, work finished early...',
                    errorText: _tried && _early.text.trim().isEmpty ? 'Please say why.' : null,
                  ),
                ),
              ],
            ),
          ),
        );
      case 'selfie':
        return _photoField(
          title: 'Selfie',
          hint: 'Taken with the place and time on it.',
          icon: Icons.person_rounded,
          photo: _selfie,
          missing: _tried && _selfie == null,
          onTap: () => _shoot(selfie: true),
        );
      case 'vehicle':
        return _vehicleField();
      case 'meter':
        return Column(children: [
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
                  errorText: _meterProblem ?? (_tried && (_odometer ?? 0) <= 0 ? 'Type the number on the meter.' : null),
                  helperText: _meterKm != null
                      ? 'Distance today by the meter: ${_meterKm!.toStringAsFixed(1)} km (check-in ${fmtQty(widget.odometerIn!)})'
                      : 'Only asked when you ride your own two- or four-wheeler.',
                ),
              ),
            ),
          ),
        ]);
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final steps = _steps;
    final checking = _beat == 'checking';
    // Nothing to ask at all (and the beat is settled): go straight through.
    if (!checking && steps.isEmpty && !_autoSent) {
      _autoSent = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _submit();
      });
    }
    final at = steps.isEmpty ? 0 : _step.clamp(0, steps.length - 1);
    final key = steps.isEmpty ? '' : steps[at];
    final last = at >= steps.length - 1;
    return Scaffold(
      appBar: AppBar(title: Text(_word)),
      body: checking
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _progress(steps.length, at),
                  const SizedBox(height: 10),
                  Text('Step ${at + 1} of ${steps.length}',
                      style: const TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w700)),
                  Text(_stepTitle[key] ?? '', style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
                ]),
              ),
              Expanded(
                child: key == 'beat'
                    ? PlanDayScreen(
                        atCheckIn: true,
                        embedded: true,
                        onDone: (_) => setState(() {
                          _beat = 'done';
                          _step = 0;
                        }),
                        onUnneeded: () => setState(() => _beat = 'done'),
                      )
                    : ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [_stepBody(key)]),
              ),
              if (key != 'beat')
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(children: [
                      if (at > 0)
                        Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: SizedBox(
                            height: 52,
                            child: OutlinedButton(
                              onPressed: _busy ? null : () => setState(() => _step = at - 1),
                              style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26))),
                              child: const Icon(Icons.arrow_back_rounded),
                            ),
                          ),
                        ),
                      Expanded(
                        child: SizedBox(
                          height: 52,
                          child: FilledButton.icon(
                            onPressed: _busy ? null : (last ? _submit : _next),
                            style: FilledButton.styleFrom(
                              backgroundColor: widget.punchIn ? AppColors.primary : AppColors.danger,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                            ),
                            icon: Icon(last ? Icons.check_rounded : Icons.arrow_forward_rounded),
                            label: Text(last ? 'Submit and $_word' : 'Next',
                                style: const TextStyle(fontWeight: FontWeight.w800)),
                          ),
                        ),
                      ),
                    ]),
                  ),
                ),
            ]),
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

  static const _vehicleHints = {
    'two_wheeler': 'Bike or scooter',
    'four_wheeler': 'Car or jeep',
    'public': 'Bus, train or auto',
    'walk': 'On foot',
    'other': 'Something else',
  };

  Widget _vehicleField() {
    final missing = _tried && _vehicle == null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(18)),
        child: const Row(children: [
          Icon(Icons.info_outline_rounded, color: AppColors.primary, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text('Your travel allowance is worked out from how you travel today.',
                style: TextStyle(fontSize: 13, color: Color(0xFF334155), fontWeight: FontWeight.w600)),
          ),
        ]),
      ),
      const SizedBox(height: 14),
      LayoutBuilder(builder: (context, box) {
        final width = (box.maxWidth - 12) / 2;
        return Wrap(spacing: 12, runSpacing: 12, children: [
          for (final (code, label, icon) in vehicleChoices)
            SizedBox(
              width: code == 'other' && vehicleChoices.length.isOdd ? box.maxWidth : width,
              child: _vehicleTile(code, label, icon),
            ),
        ]);
      }),
      if (missing)
        const Padding(
          padding: EdgeInsets.only(top: 10),
          child: Text('Choose how you are travelling.', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700)),
        ),
      if (_vehicle == 'other')
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: TextField(
            controller: _note,
            onChanged: (_) => setState(() {}),
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'What are you travelling by?',
              hintText: 'A lift with a colleague, a hired vehicle, the company van...',
              errorText: _tried && _note.text.trim().isEmpty ? 'Say it in a few words.' : null,
            ),
          ),
        ),
    ]);
  }

  Widget _vehicleTile(String code, String label, IconData icon) {
    final on = _vehicle == code;
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: () => setState(() => _vehicle = code),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
        decoration: BoxDecoration(
          gradient: on ? const LinearGradient(colors: [Color(0xFF2563EB), Color(0xFF06B6D4)], begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
          color: on ? null : Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: on ? Colors.transparent : AppColors.border, width: 1.4),
          boxShadow: [
            BoxShadow(
              color: (on ? const Color(0xFF2563EB) : const Color(0xFF1B3A7A)).withValues(alpha: on ? 0.3 : 0.06),
              blurRadius: on ? 16 : 10,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: on ? Colors.white.withValues(alpha: 0.25) : AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(icon, color: on ? Colors.white : AppColors.primary, size: 25),
            ),
            const Spacer(),
            Icon(on ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                color: on ? Colors.white : AppColors.border, size: 22),
          ]),
          const SizedBox(height: 14),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15.5, color: on ? Colors.white : const Color(0xFF0F172A))),
          const SizedBox(height: 2),
          Text(_vehicleHints[code] ?? '',
              style: TextStyle(fontSize: 12, color: on ? Colors.white : const Color(0xFF475569), fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}
