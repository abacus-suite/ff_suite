import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/geo_camera.dart';
import '../../core/format.dart';
import '../../core/local_state.dart';
import '../../core/geo.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../forms/form_fill_screen.dart';
import '../visits/stock_count_screen.dart';
import '../visits/visit_purpose.dart';
import '../../widgets/skeleton.dart';

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
  const VisitCheckoutScreen({
    super.key,
    required this.visit,
    this.note = '',
    this.photos = const [],
    this.stockDone = false,
  });

  final Map<String, dynamic> visit;

  /// Written and taken at the counter, on the customer's screen. This form
  /// only carries them to the server.
  final String note;
  final List<Uint8List> photos;

  /// The stock was counted during this visit. Checked against the server too,
  /// for a check-out reached from somewhere other than the customer's screen.
  final bool stockDone;

  @override
  State<VisitCheckoutScreen> createState() => _VisitCheckoutScreenState();
}

class _VisitCheckoutScreenState extends State<VisitCheckoutScreen> {
  List<Map<String, dynamic>> _outcomes = [];
  Map<String, dynamic>? _selected;
  String _legacy = 'met';
  List<Map<String, dynamic>> _forms = [];
  final _note = TextEditingController();
  final List<Uint8List> _photos = [];
  bool _loading = true;
  bool _busy = false;

  /// Which of the three the visit was. Settled at check-in, shown here.
  String? _purpose;

  /// The chiller count has been taken during this check-out.
  bool _stockDone = false;

  int get _clientId => (widget.visit['client'] as Map)['id'] as int;

  String get _clientName => '${(widget.visit['client'] as Map)['name']}';

  bool get _needsNote => _purpose == 'client_visit';

  bool get _needsStock => _purpose == 'chiller_update';

  /// Both kinds of visit end with a photo; the chiller one only after counting.
  bool get _needsPhoto => _purpose == 'client_visit' || _purpose == 'chiller_update';

  bool get _photoReady => !_needsStock || _stockDone;

  List<Map<String, dynamic>> get _openForms =>
      _forms.where((f) => f['filled'] != true).toList();

  /// Everything still standing between this visit and its check-out.
  List<String> get _pending => [
        if (_needsNote && _note.text.trim().isEmpty) 'Write the visit notes',
        if (_needsStock && !_stockDone) 'Count the stock',
        if (_needsPhoto && _photos.isEmpty) 'Take the closing photo',
        for (final form in _openForms.where((f) => f['mandatory'] == true)) 'Fill "${form['name']}"',
      ];

  @override
  void initState() {
    super.initState();
    _purpose = widget.visit['purpose'] as String?;
    _note.text = widget.note;
    _photos.addAll(widget.photos);
    _stockDone = widget.stockDone;
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
      _forms = (results[1] as List).cast<Map<String, dynamic>>();
      _loading = false;
    });
    if (_needsStock && !_stockDone) await _checkStockTaken();
  }

  /// Was the stock counted during this visit? The count is saved to the server
  /// the moment it is taken, so the server is the one that knows.
  Future<void> _checkStockTaken() async {
    try {
      final last = await Services.api.get('/api/v1/stock/last', query: {'partner_id': _clientId})
          as Map<String, dynamic>?;
      final taken = parseServerTime(last?['date']);
      final since = parseServerTime(widget.visit['check_in_at']);
      if (taken == null || since == null) return;
      // A minute's grace: the phone's clock and the server's are never quite level.
      if (!taken.isBefore(since.subtract(const Duration(minutes: 1))) && mounted) {
        setState(() => _stockDone = true);
      }
    } catch (_) {
      // Only a convenience: the count button is still there to be pressed.
    }
  }

  Future<void> _addPhoto() async {
    if (_photos.length >= _maxPhotos) return;
    // The geo-tagged camera: the closing photo carries where and when it was taken.
    final bytes = await openGeoCamera(title: 'Closing photo');
    if (bytes == null) return;
    setState(() => _photos.add(bytes));
  }

  Future<void> _countStock() async {
    final done = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => StockCountScreen(
        clientId: _clientId,
        visitId: widget.visit['id'] as int?,
        visitUuid: widget.visit['uuid'] as String?,
      ),
    ));
    if (done == true && mounted) setState(() => _stockDone = true);
  }

  Future<void> _fillForm(Map<String, dynamic> form) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => FormFillScreen(form: form, partnerId: _clientId, visitId: widget.visit['id'] as int?),
    ));
    if (saved == true) _load();
  }

  Future<void> _submit() async {
    final outcome = _selected;
    if (_pending.isNotEmpty) {
      showSnack(context, _pending.first);
      return;
    }
    if (outcome?['requires_note'] == true && _note.text.trim().isEmpty) {
      showProblem(context, 'Add a note for "${outcome!['name']}".');
      return;
    }
    if (outcome?['requires_photo'] == true && _photos.isEmpty) {
      showProblem(context, 'Add a photo for "${outcome!['name']}".');
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
      final result = await Services.outbox.submit('/api/v1/visits/check-out', {
        if (widget.visit['id'] != null) 'visit_id': widget.visit['id'],
        if (widget.visit['uuid'] != null) 'visit_uuid': widget.visit['uuid'],
        'lat': pos?.latitude,
        'lng': pos?.longitude,
        'purpose': _purpose,
        if (outcome != null) 'outcome_id': outcome['id'] else 'outcome': _legacy,
        'note': _note.text.trim(),
        'photos': _photos.map(base64Encode).toList(),
      }, label: 'Check out · $_clientName');
      if (result.queued) {
        await LocalState.visitClosed();
        if (mounted) showSnack(context, 'Checked out · Saved on the phone · it will sync when you are back online');
      }
      Services.refresh.value++;
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showProblem(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = _pending.isEmpty;
    return Scaffold(
      appBar: AppBar(title: Text('Check out · $_clientName')),
      bottomNavigationBar: _loading
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!ready)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            const Icon(Icons.lock_outline_rounded, size: 15, color: AppColors.muted),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(_pending.first,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                            ),
                          ],
                        ),
                      ),
                    GradientButton(
                      label: 'Complete visit',
                      icon: Icons.check_rounded,
                      busy: _busy,
                      onPressed: ready && !_busy ? _submit : null,
                    ),
                  ],
                ),
              ),
            ),
      body: _loading
          ? const LoadingView()
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              children: [
                _purposeCard(),
                if (_purpose != null) ...[
                  const SizedBox(height: 14),
                  ..._tasks(),
                  if (_outcomes.isNotEmpty || _purpose == 'other') ...[
                    const SizedBox(height: 14),
                    _outcomeCard(),
                  ],
                  // Forms come after the work itself, not before it.
                  if (_forms.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    _formsCard(),
                  ],
                ],
              ],
            ),
    );
  }

  /// What the visit was for, settled on the way in and shown here.
  Widget _purposeCard() {
    final purpose = purposeOf(_purpose);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12)),
              child: Icon(purpose?.icon ?? Icons.storefront_rounded,
                  size: 19, color: AppColors.primary),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(purpose?.name ?? 'Visit',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                  Text('In since ${fmtTime(widget.visit['check_in_at'])}',
                      style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// What this purpose asks for, in the order it has to happen.
  List<Widget> _tasks() {
    if (_purpose == 'other') {
      return [
        _taskCard(
          title: 'Nothing required',
          done: true,
          child: const Text('Add a note or a photo if it helps; neither is asked for.',
              style: TextStyle(fontSize: 12.5, color: AppColors.muted)),
          trailing: null,
        ),
        const SizedBox(height: 12),
        _noteField(optional: true),
        const SizedBox(height: 12),
        _photoCard(optional: true),
      ];
    }
    if (_needsStock) {
      return [
        _taskCard(
          title: 'Stock count',
          done: _stockDone,
          child: Text(
            _stockDone ? 'Counted and saved.' : 'Count what is in the chiller before you leave.',
            style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
          ),
          trailing: FilledButton.icon(
            onPressed: _countStock,
            icon: Icon(_stockDone ? Icons.edit_rounded : Icons.inventory_rounded, size: 17),
            label: Text(_stockDone ? 'Edit' : 'Count'),
          ),
        ),
        const SizedBox(height: 12),
        _photoCard(),
        const SizedBox(height: 12),
        _noteField(optional: true),
      ];
    }
    return [
      _noteField(),
      const SizedBox(height: 12),
      _photoCard(),
    ];
  }

  Widget _taskCard({required String title, required bool done, required Widget child, Widget? trailing}) => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: done ? AppColors.success.withValues(alpha: 0.4) : AppColors.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                size: 21, color: done ? AppColors.success : AppColors.border),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                  const SizedBox(height: 2),
                  child,
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing],
          ],
        ),
      );

  Widget _noteField({bool optional = false}) => _taskCard(
        title: optional ? 'Notes' : 'Visit notes',
        done: optional || _note.text.trim().isNotEmpty,
        child: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: TextField(
            controller: _note,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: optional
                  ? 'Anything worth remembering'
                  : 'What was discussed, what was agreed, what to do next',
              isDense: true,
            ),
          ),
        ),
      );

  Widget _photoCard({bool optional = false}) {
    final locked = !optional && !_photoReady;
    return _taskCard(
      title: optional ? 'Photos' : 'Closing photo',
      done: optional || _photos.isNotEmpty,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            locked
                ? 'Count the stock first, then photograph it.'
                : '${_photos.length} of $_maxPhotos · taken with the place and time on it',
            style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
          ),
          if (_photos.isNotEmpty) ...[
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
                        child: Image.memory(_photos[i], width: 84, height: 84, fit: BoxFit.cover),
                      ),
                      Positioned(
                        right: 0,
                        top: 0,
                        child: IconButton.filledTonal(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.close, size: 15),
                          onPressed: () => setState(() => _photos.removeAt(i)),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ],
          if (_photos.length < _maxPhotos) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: locked ? null : _addPhoto,
              icon: const Icon(Icons.add_a_photo_rounded, size: 17),
              label: Text(_photos.isEmpty ? 'Take photo' : 'Add another'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _outcomeCard() => Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('How did it go?', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _outcomes.isNotEmpty
                    ? [
                        for (final o in _outcomes)
                          ChoiceChip(
                            label: Text('${o['name']}'),
                            selected: _selected?['id'] == o['id'],
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
            ],
          ),
        ),
      );

  Widget _formsCard() => Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Forms', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              const Text('Filled once the visit itself is done.',
                  style: TextStyle(fontSize: 11.5, color: AppColors.muted)),
              for (final form in _forms)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFFEDE8FF),
                    child: Icon(
                        form['filled'] == true ? Icons.assignment_turned_in_rounded : Icons.assignment_rounded,
                        color: AppColors.purple),
                  ),
                  title: Text('${form['name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(form['filled'] == true
                      ? 'Filled'
                      : form['mandatory'] == true
                          ? 'Required'
                          : 'Optional'),
                  trailing: form['filled'] == true
                      ? const StatusBadge('filled')
                      : TextButton(onPressed: () => _fillForm(form), child: const Text('Fill now')),
                ),
            ],
          ),
        ),
      );
}
