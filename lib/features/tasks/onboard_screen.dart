import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/draft_store.dart';
import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/busy.dart';
import '../../widgets/common.dart';
import 'task_widgets.dart';

final _gstin = RegExp(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$');
final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
final _phone = RegExp(r'^[0-9]{10}$');
final _pin = RegExp(r'\b[0-9]{6}\b');

/// A scheme option as people read it: a plain number is a percentage.
String schemeLabel(Object? name) {
  final text = '$name'.trim();
  return RegExp(r'^\d+(\.\d+)?$').hasMatch(text) ? '$text%' : text;
}

/// A lead that said yes becomes an outlet or a distributor, here, in four steps: GST and billing, the delivery
/// address, the outlet details, and the contacts with the delivery apps. Returns the updated contact, or null
/// when left without finishing.
class OnboardScreen extends StatefulWidget {
  const OnboardScreen({super.key, required this.client});

  final Map<String, dynamic> client;

  @override
  State<OnboardScreen> createState() => _OnboardScreenState();
}

class _OnboardScreenState extends State<OnboardScreen> {
  int _step = 0;
  String _kind = 'outlet';
  Map<String, dynamic> _options = {};
  final _c = <String, TextEditingController>{};

  // Step 1
  bool _hasGst = true;
  bool _sameAsBilling = false;
  Map<String, dynamic>? _gstInfo;

  // Step 2: what the PIN code says
  Map<String, dynamic> _pinInfo = {};
  String? _city;
  String? _area;

  // Step 3
  String? _mrp;
  String? _category;
  String? _scheme;
  String? _chillerModel;
  bool? _chiller;
  Map<String, dynamic>? _distributor;
  DateTime _onboardedOn = DateUtils.dateOnly(DateTime.now());

  // Step 4
  bool? _swiggy;
  bool? _zomato;

  bool _busy = false;
  bool _saved = false;

  static const _titles = ['GST & billing', 'Delivery address', 'Outlet details', 'Contacts & delivery apps'];

  String get _draftKey => 'onboard-${widget.client['id']}';
  final Map<String, String> _starting = {};

  bool get _filled =>
      _c.entries.any((e) => e.value.text.trim().isNotEmpty && e.value.text.trim() != _starting[e.key]) ||
      _swiggy != null || _zomato != null || _chiller != null || _mrp != null || _category != null ||
      _scheme != null || _chillerModel != null || _distributor != null;

  Map<String, dynamic> _toDraft() => {
        'kind': _kind, 'step': _step, 'has_gst': _hasGst, 'same': _sameAsBilling,
        'text': {for (final e in _c.entries) e.key: e.value.text},
        'swiggy': _swiggy, 'zomato': _zomato, 'chiller': _chiller, 'mrp': _mrp, 'category': _category,
        'scheme': _scheme, 'chiller_model': _chillerModel, 'distributor': _distributor,
        'city': _city, 'area': _area, 'date': fmtDate(_onboardedOn),
      };

  Future<void> _restore() async {
    final d = await DraftStore.read(_draftKey);
    if (d == null || !mounted) return;
    setState(() {
      _kind = '${d['kind'] ?? _kind}';
      _step = (d['step'] as num?)?.toInt() ?? 0;
      _hasGst = d['has_gst'] as bool? ?? true;
      _sameAsBilling = d['same'] as bool? ?? false;
      for (final e in ((d['text'] as Map?) ?? {}).entries) {
        _t('${e.key}').text = '${e.value}';
      }
      _swiggy = d['swiggy'] as bool?;
      _zomato = d['zomato'] as bool?;
      _chiller = d['chiller'] as bool?;
      _mrp = d['mrp'] as String?;
      _category = d['category'] as String?;
      _scheme = d['scheme'] as String?;
      _chillerModel = d['chiller_model'] as String?;
      _distributor = (d['distributor'] as Map?)?.cast<String, dynamic>();
      _city = d['city'] as String?;
      _area = d['area'] as String?;
      _onboardedOn = DateTime.tryParse('${d['date']}') ?? _onboardedOn;
    });
    showSnack(context, 'The details you filled earlier are back.');
    if (_v('zip').length == 6) _lookupPin();
  }

  Timer? _autosave;

  /// Saved every few seconds while there is something filled, so closing the app does not lose it.
  void _startAutosave() {
    _autosave = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!_saved && _filled) DraftStore.write(_draftKey, _toDraft());
    });
  }

  /// Going back with details filled in: Yes clears the form and leaves; No keeps the form as it is.
  Future<void> _leave() async {
    if (_saved || !_filled) {
      Navigator.of(context).pop();
      return;
    }
    final clear = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Clear this form?'),
        content: const Text('You have filled in some of it. Going back will clear what you entered. Clear it?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('No, keep it')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Yes, clear it')),
        ],
      ),
    );
    if (clear != true || !mounted) return;
    _autosave?.cancel();
    _saved = true;
    await DraftStore.remove(_draftKey);
    if (mounted) Navigator.of(context).pop();
  }

  TextEditingController _t(String key, [String? initial]) =>
      _c.putIfAbsent(key, () => TextEditingController(text: initial ?? ''));

  @override
  void initState() {
    super.initState();
    final c = widget.client;
    _t('gstin', '${c['gst'] ?? ''}');
    _t('street_name', '${c['street'] ?? ''}');
    _t('zip', '${c['zip'] ?? ''}');
    _t('poc_phone', '${c['phone'] ?? ''}');
    _t('poc_email', '${c['email'] ?? ''}');
    for (final e in _c.entries) {
      _starting[e.key] = e.value.text.trim();
    }
    _restore();
    _startAutosave();
    Services.api.get('/api/v1/onboarding/options').then((d) {
      if (mounted) setState(() => _options = d as Map<String, dynamic>);
    }).catchError((_) {});
    if (_v('zip').length == 6) _lookupPin();
  }

  @override
  void dispose() {
    _autosave?.cancel();
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _v(String k) => (_c[k]?.text ?? '').trim();
  List<Map<String, dynamic>> _list(String k) => ((_options[k] as List?) ?? []).cast<Map<String, dynamic>>();

  bool get _outlet => _kind == 'outlet';
  bool get _categoryNeedsNote =>
      _list('outlet_categories').any((o) => o['code'] == _category && o['needs_note'] == true);

  // ------------------------------------------------------------------ the two free lookups

  /// A 15-character GSTIN is checked, and its state shown. (The registered name and address are typed for now.)
  Future<void> _checkGst() async {
    final text = _v('gstin').toUpperCase();
    if (text.length != 15) {
      if (_gstInfo != null) setState(() => _gstInfo = null);
      return;
    }
    try {
      final data = await Services.api.get('/api/v1/gst/check', query: {'gstin': text}) as Map<String, dynamic>;
      if (mounted && _v('gstin').toUpperCase() == text) setState(() => _gstInfo = data);
    } catch (_) {
      if (mounted) setState(() => _gstInfo = null);
    }
  }

  /// The PIN code gives the state and district, and the towns and areas to choose from.
  Future<void> _lookupPin() async {
    final pin = _v('zip');
    if (pin.length != 6) return;
    try {
      final data = await Services.api.get('/api/v1/geo/pincode', query: {'pin': pin}) as Map<String, dynamic>;
      if (!mounted || _v('zip') != pin) return;
      setState(() {
        _pinInfo = data;
        final cities = ((data['cities'] as List?) ?? []).map((e) => '$e').toList();
        final areas = ((data['areas'] as List?) ?? []).map((e) => '$e').toList();
        if (_city != null && !cities.contains(_city) && cities.isNotEmpty) _city = null;
        if (_area != null && !areas.contains(_area) && areas.isNotEmpty) _area = null;
        if (cities.length == 1) _city ??= cities.first;
        if (areas.length == 1) _area ??= areas.first;
      });
    } catch (_) {
      if (mounted) setState(() => _pinInfo = {});
    }
  }

  /// "Delivery address same as billing": the billing address and its PIN code fill the delivery ones.
  void _sameChanged(bool on) {
    setState(() {
      _sameAsBilling = on;
      if (!on) return;
      final billing = _v('billing_address');
      if (billing.isNotEmpty) {
        _t('street_name').text = billing.split(RegExp(r'[\n,]')).first.trim();
        final pin = _pin.firstMatch(billing)?.group(0);
        if (pin != null) _t('zip').text = pin;
      }
    });
    if (on && _v('zip').length == 6) _lookupPin();
  }

  // ------------------------------------------------------------------ checks

  List<String> _checkStep(int step) {
    final bad = <String>[];
    switch (step) {
      case 0:
        if (_hasGst) {
          if (!_gstin.hasMatch(_v('gstin').toUpperCase())) bad.add('GSTIN: enter a valid 15-character GSTIN');
          if (_v('gst_name').isEmpty) bad.add('Name as per GST');
        }
        if (_v('billing_address').isEmpty) bad.add('Billing address');
      case 1:
        if (_v('zip').length != 6) bad.add('PIN code: 6 digits');
        if ((_city ?? _v('city_text')).isEmpty) bad.add('City');
        if ((_area ?? _v('area_text')).isEmpty) bad.add('Area');
        if (_v('street_name').isEmpty) bad.add('Street name');
        if (_v('door').isEmpty) bad.add('Door / TC No.');
      case 2:
        if (_outlet) {
          if (_category == null) bad.add('Outlet category');
          if (_categoryNeedsNote && _v('outlet_category_note').isEmpty) bad.add('Outlet category: describe it');
        }
        if (_mrp == null) bad.add('MRP');
        if (_outlet && _distributor == null) bad.add('Distributor');
        if (_scheme == null) bad.add('Scheme');
        if (int.tryParse(_v('credit_days')) == null) bad.add('Credit days');
        if (double.tryParse(_v('margin')) == null) bad.add('Margin');
        if (_outlet) {
          if (_chiller == null) {
            bad.add('Chiller from Kumbayah: yes or no');
          } else if (_chiller == true) {
            if (_v('chiller_serial').isEmpty) bad.add('Chiller serial number');
            if (_chillerModel == null) bad.add('Chiller model');
          }
        }
      default:
        final who = _outlet ? 'POC' : 'Sales POC';
        if (_v('poc_name').isEmpty) bad.add('$who name');
        if (!_phone.hasMatch(_v('poc_phone'))) bad.add('$who contact number: 10 digits');
        if (_v('poc_email').isNotEmpty && !_email.hasMatch(_v('poc_email'))) bad.add('$who email: not a valid email');
        if (!_outlet) {
          if (_v('accounts_poc_name').isEmpty) bad.add('Accounts POC name');
          if (!_phone.hasMatch(_v('accounts_poc_phone'))) bad.add('Accounts POC contact number: 10 digits');
          if (!_email.hasMatch(_v('accounts_poc_email'))) bad.add('Accounts email: enter a valid email');
        }
        if (_swiggy == null) bad.add('Swiggy: yes or no');
        if (_zomato == null) bad.add('Zomato: yes or no');
    }
    return bad;
  }

  Future<void> _next() async {
    final problems = _checkStep(_step);
    if (problems.isNotEmpty) {
      await showProblem(context, problems, title: 'Still needed on this step');
      return;
    }
    if (_step < 3) {
      setState(() => _step++);
      return;
    }
    await _save();
  }

  Future<void> _save() async {
    for (var step = 0; step < 4; step++) {
      final problems = _checkStep(step);
      if (problems.isNotEmpty) {
        setState(() => _step = step);
        if (mounted) await showProblem(context, problems, title: 'Still needed to onboard');
        return;
      }
    }
    setState(() => _busy = true);
    try {
      final city = _city ?? _v('city_text');
      final area = _area ?? _v('area_text');
      final result = await withBusy(context, 'Saving…', () async => await Services.api.post(
            '/api/v1/clients/${widget.client['id']}/onboard',
            {
              'kind': _kind,
              'has_gst': _hasGst,
              if (_hasGst) 'gstin': _v('gstin').toUpperCase(),
              'gst_name': _v('gst_name'),
              'billing_address': _v('billing_address'),
              'street': [_v('door'), _v('street_name')].where((e) => e.isNotEmpty).join(', '),
              'street2': area,
              'city': city,
              'zip': _v('zip'),
              if (_pinInfo['state'] != null) 'state': _pinInfo['state'],
              if (_pinInfo['district'] != null) 'district': _pinInfo['district'],
              'poc_name': _v('poc_name'),
              'poc_phone': _v('poc_phone'),
              'poc_email': _v('poc_email'),
              'accounts_poc_name': _v('accounts_poc_name'),
              'accounts_poc_phone': _v('accounts_poc_phone'),
              'accounts_poc_email': _v('accounts_poc_email'),
              'outlet_category': _category,
              'outlet_category_note': _v('outlet_category_note'),
              'mrp': _mrp,
              'scheme': _scheme,
              'distributor_id': _distributor?['id'],
              'swiggy': _swiggy == true,
              'swiggy_id': _v('swiggy_id'),
              'zomato': _zomato == true,
              'zomato_id': _v('zomato_id'),
              'has_chiller': _chiller == true,
              'chiller_serial': _v('chiller_serial'),
              'chiller_model': _chillerModel,
              'credit_days': _v('credit_days'),
              'margin': _v('margin'),
              'onboarded_date': fmtDate(_onboardedOn),
            },
          ));
      _saved = true;
      _autosave?.cancel();
      await DraftStore.remove(_draftKey);
      if (mounted) Navigator.of(context).pop(result as Map<String, dynamic>);
    } catch (e) {
      if (mounted) await showProblem(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ------------------------------------------------------------------ small widgets

  InputDecoration _decoration(String label, {String? helper, bool required = false}) => InputDecoration(
        labelText: required ? '$label *' : label,
        helperText: helper,
        counterText: '',
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.border)),
      );

  Widget _field(String key, String label,
      {TextInputType? type, int? maxLength, bool required = false, int lines = 1, String? helper, ValueChanged<String>? onChanged}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: _t(key),
        keyboardType: type,
        maxLength: maxLength,
        maxLines: lines,
        onChanged: (v) {
          onChanged?.call(v);
          setState(() {});
        },
        textCapitalization: key == 'gstin' ? TextCapitalization.characters : TextCapitalization.sentences,
        decoration: _decoration(label, helper: helper, required: required),
      ),
    );
  }

  Widget _drop(String label, List<(String, String)> items, String? value, ValueChanged<String?> onChanged,
      {bool required = true, String? helper}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DropdownButtonFormField<String>(
        initialValue: items.any((i) => i.$1 == value) ? value : null,
        isExpanded: true,
        decoration: _decoration(label, helper: helper, required: required),
        items: [for (final i in items) DropdownMenuItem(value: i.$1, child: Text(i.$2, maxLines: 1, overflow: TextOverflow.ellipsis))],
        onChanged: onChanged,
      ),
    );
  }

  Widget _readOnly(String label, String value, {String? tag}) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              ]),
            ),
            if (tag != null) Text(tag, style: const TextStyle(fontSize: 10.5, color: AppColors.muted)),
          ]),
        ),
      );

  Widget _label(String text, {bool required = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text.rich(TextSpan(text: text, children: [
          if (required) const TextSpan(text: ' *', style: TextStyle(color: AppColors.danger)),
        ]), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
      );

  /// A two-part pill, the selected half filled: GSTIN | No GST, Yes | No.
  Widget _pill(List<(String, bool)> halves, bool value, ValueChanged<bool> onChanged) => Container(
        padding: const EdgeInsets.all(3),
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(26), border: Border.all(color: AppColors.border)),
        child: Row(children: [
          for (final (text, on) in halves)
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(23),
                onTap: () => onChanged(on),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: value == on ? AppColors.primary : Colors.transparent, borderRadius: BorderRadius.circular(23)),
                  child: Text(text, style: TextStyle(fontWeight: FontWeight.w800, color: value == on ? Colors.white : AppColors.text)),
                ),
              ),
            ),
        ]),
      );

  Widget _yesNo(bool? value, ValueChanged<bool> onChanged) => Row(children: [
        for (final (text, on) in const [('Yes', true), ('No', false)])
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: on ? 8 : 0),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => onChanged(on),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: value == on ? AppColors.primary : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: value == on ? AppColors.primary : AppColors.border),
                  ),
                  child: Text(text, style: TextStyle(fontWeight: FontWeight.w800, color: value == on ? Colors.white : AppColors.text)),
                ),
              ),
            ),
          ),
      ]);

  Widget _same() => Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
        child: CheckboxListTile(
          value: _sameAsBilling,
          controlAffinity: ListTileControlAffinity.leading,
          onChanged: (v) => _sameChanged(v == true),
          title: const Text('Delivery address same as billing', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        ),
      );

  // ------------------------------------------------------------------ the four steps

  Widget _step1() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _label('Becomes', required: true),
        _pill(const [('Outlet', true), ('Distributor', false)], _outlet, (v) => setState(() => _kind = v ? 'outlet' : 'distributor')),
        _label('GST', required: true),
        _pill(const [('GSTIN', true), ('No GST', false)], _hasGst, (v) => setState(() => _hasGst = v)),
        if (_hasGst) ...[
          _field('gstin', 'GSTIN', required: true, maxLength: 15, onChanged: (_) => _checkGst(), helper: _gstHelper()),
          _field('gst_name', 'Name as per GST', required: true),
        ],
        _field('billing_address', 'Billing address', required: true, lines: 3),
        _same(),
      ]);

  /// What the GSTIN says about itself.
  String? _gstHelper() {
    final info = _gstInfo;
    if (info == null) return _v('gstin').length == 15 ? 'Checking…' : '15 characters, e.g. 32ABCDE1234F1Z5';
    if (info['valid'] != true) return '${info['reason'] ?? 'Not a valid GSTIN'}';
    final state = asText(info['state']);
    final warning = asText(info['warning']);
    return [if (state != null) 'State: $state', if (warning != null) warning].join(' · ');
  }

  Widget _step2() {
    final cities = ((_pinInfo['cities'] as List?) ?? []).map((e) => '$e').toList();
    final areas = ((_pinInfo['areas'] as List?) ?? []).map((e) => '$e').toList();
    final place = [asText(_pinInfo['state']), asText(_pinInfo['district'])].whereType<String>().join(' · ');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _same(),
      _field('zip', 'PIN code', required: true, type: TextInputType.number, maxLength: 6, onChanged: (v) {
        if (v.length == 6) _lookupPin();
      }),
      _readOnly('State · District (auto from PIN)', place.isEmpty ? 'Enter the PIN code' : place),
      if (cities.isNotEmpty)
        _drop('City', [for (final c in cities) (c, c)], _city, (v) => setState(() => _city = v))
      else
        _field('city_text', 'City', required: true),
      if (areas.isNotEmpty)
        _drop('Area', [for (final a in areas) (a, a)], _area, (v) => setState(() => _area = v))
      else
        _field('area_text', 'Area', required: true),
      _field('street_name', 'Street name', required: true),
      _field('door', 'Door / TC No.', required: true),
    ]);
  }

  Widget _step3() {
    final region = asText((widget.client['region'] as Map?)?['name']) ?? Services.auth.profile?.team ?? '—';
    final onboardedText = fmtDate(_onboardedOn);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (_outlet) ...[
        _drop('Outlet category', [for (final o in _list('outlet_categories')) ('${o['code']}', '${o['name']}')], _category,
            (v) => setState(() => _category = v)),
        if (_categoryNeedsNote) _field('outlet_category_note', 'Describe the category', required: true),
      ],
      _drop('MRP', [for (final o in _list('mrp')) ('${o['code']}', '${o['name']}')], _mrp, (v) => setState(() => _mrp = v)),
      _readOnly('Region', region, tag: 'auto'),
      if (_outlet)
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              alignment: Alignment.centerLeft,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            icon: const Icon(Icons.local_shipping_rounded),
            label: Text(_distributor == null ? 'Distributor *' : '${_distributor!['name']}',
                maxLines: 1, overflow: TextOverflow.ellipsis),
            onPressed: () async {
              final d = await pickFromList(context,
                  title: 'Distributor',
                  load: () async {
                    final res = await Services.api.get('/api/v1/distributors');
                    final list = res is Map ? ((res['distributors'] as List?) ?? []) : (res as List);
                    return list.cast<Map<String, dynamic>>();
                  },
                  subtitle: distributorSubtitle);
              if (d != null) setState(() => _distributor = d);
            },
          ),
        ),
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            alignment: Alignment.centerLeft,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          icon: const Icon(Icons.event_rounded),
          label: Text('Onboarded date *   $onboardedText'),
          onPressed: () async {
            final today = DateUtils.dateOnly(DateTime.now());
            final picked = await showDatePicker(
              context: context,
              initialDate: _onboardedOn,
              firstDate: today.subtract(const Duration(days: 365)),
              lastDate: today,
            );
            if (picked != null) setState(() => _onboardedOn = picked);
          },
        ),
      ),
      _readOnly('Geo location', 'From New Lead creation', tag: 'auto'),
      const SizedBox(height: 4),
      _label('Commercials', required: true),
      _drop('Scheme', [for (final o in _list('schemes')) ('${o['code']}', schemeLabel(o['name']))], _scheme,
          (v) => setState(() => _scheme = v)),
      _field('credit_days', 'Credit days', required: true, type: TextInputType.number),
      _field('margin', 'Margin %', required: true, type: const TextInputType.numberWithOptions(decimal: true)),
      if (_outlet) ...[
        _label('Chiller from Kumbayah', required: true),
        _yesNo(_chiller, (v) => setState(() => _chiller = v)),
        if (_chiller == true) ...[
          const SizedBox(height: 14),
          _field('chiller_serial', 'Chiller serial number', required: true),
          _drop('Chiller model', [for (final o in _list('chiller_models')) ('${o['code']}', '${o['name']}')], _chillerModel,
              (v) => setState(() => _chillerModel = v)),
        ],
      ],
    ]);
  }

  Widget _step4() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _field('poc_name', _outlet ? 'POC name' : 'Sales POC name', required: true),
        _field('poc_phone', _outlet ? 'POC contact no.' : 'Sales POC contact no.', required: true, type: TextInputType.phone, maxLength: 10),
        _field('poc_email', _outlet ? 'POC email (optional)' : 'Sales POC email (optional)', type: TextInputType.emailAddress),
        if (!_outlet) ...[
          _field('accounts_poc_name', 'Accounts POC name', required: true),
          _field('accounts_poc_phone', 'Accounts POC contact no.', required: true, type: TextInputType.phone, maxLength: 10),
          _field('accounts_poc_email', 'Accounts email', required: true, type: TextInputType.emailAddress),
        ],
        _label('Swiggy', required: true),
        _yesNo(_swiggy, (v) => setState(() => _swiggy = v)),
        if (_swiggy == true) ...[const SizedBox(height: 14), _field('swiggy_id', 'Swiggy ID (optional)')],
        const SizedBox(height: 14),
        _label('Zomato', required: true),
        _yesNo(_zomato, (v) => setState(() => _zomato = v)),
        if (_zomato == true) ...[const SizedBox(height: 14), _field('zomato_id', 'Zomato ID (optional)')],
      ]);

  @override
  Widget build(BuildContext context) {
    final steps = [_step1(), _step2(), _step3(), _step4()];
    final titles = [..._titles]..[2] = _outlet ? 'Outlet details' : 'Distributor details';
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          leading: BackButton(onPressed: _leave),
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Complete Onboarding', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 19)),
            Text('Step ${_step + 1} of 4 – ${titles[_step]}',
                style: const TextStyle(fontSize: 11.5, color: AppColors.muted, fontWeight: FontWeight.w500)),
          ]),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(children: [
              if (_step > 0) ...[
                SizedBox(
                  width: 56,
                  height: 56,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(padding: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                    onPressed: _busy ? null : () => setState(() => _step--),
                    child: const Icon(Icons.arrow_back_rounded),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: GradientButton(
                  label: _step < 3 ? 'Next' : 'Complete Onboarding',
                  busy: _busy,
                  onPressed: _busy ? null : _next,
                ),
              ),
            ]),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            Row(children: [
              for (var i = 0; i < 4; i++)
                Expanded(
                  child: Container(
                    height: 5,
                    margin: EdgeInsets.only(right: i < 3 ? 6 : 0),
                    decoration: BoxDecoration(
                      color: i <= _step ? AppColors.primary : AppColors.border,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
            ]),
            const SizedBox(height: 18),
            steps[_step],
          ],
        ),
      ),
    );
  }
}
