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

/// A scheme as people read it: its amount with the company's currency symbol (₹30). When the option's name
/// says more than the number, the name follows.
String schemeText(Map<String, dynamic> option, String symbol) {
  final value = option['value'];
  final name = '${option['name']}'.trim();
  if (value is! num || value <= 0) return name;
  final amount = '$symbol${fmtQty(value)}';
  return RegExp(r'^\d+(\.\d+)?$').hasMatch(name) ? amount : '$amount · $name';
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

  // Step 2: what the PIN code says, and where it sits (each a dropdown, filled from the lead and editable).
  Map<String, dynamic> _pinInfo = {};
  List<Map<String, dynamic>> _regions = [];
  List<Map<String, dynamic>> _territories = [];
  List<Map<String, dynamic>> _districts = [];
  int? _regionId;
  int? _territoryId;
  int? _districtId;
  int? _areaId;

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

  /// The company's currency symbol, sent with the options.
  String _currency = '₹';

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
        'region': _regionId, 'territory': _territoryId, 'district': _districtId, 'area': _areaId,
        'date': fmtDate(_onboardedOn),
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
      _regionId = (d['region'] as num?)?.toInt();
      _territoryId = (d['territory'] as num?)?.toInt();
      _districtId = (d['district'] as num?)?.toInt();
      _areaId = (d['area'] as num?)?.toInt();
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
    _restore().then((_) => _loadPlaces());
    _startAutosave();
    Services.api.get('/api/v1/onboarding/options').then((d) {
      if (!mounted) return;
      setState(() {
        _options = d as Map<String, dynamic>;
        final symbol = asText(_options['currency_symbol']);
        if (symbol != null) _currency = symbol;
      });
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

  int? _idOf(Object? ref) => ref is Map ? (ref['id'] as num?)?.toInt() : null;

  /// The lists behind the four dropdowns, then what the lead already knows put into them.
  Future<void> _loadPlaces() async {
    List<Map<String, dynamic>> regions = [], territories = [], districts = [];
    try {
      final info = await Services.api.get('/api/v1/me/profile-details') as Map<String, dynamic>;
      regions = ((info['teams'] as List?) ?? []).cast<Map<String, dynamic>>();
    } catch (_) {}
    try {
      territories = [
        for (final t in (await Services.api.get('/api/v1/territories') as List).cast<Map<String, dynamic>>())
          if (t['kind'] == null || t['kind'] == 'primary' || t['kind'] == 'secondary') t,
      ];
    } catch (_) {}
    try {
      districts = (await Services.api.get('/api/v1/districts') as List).cast<Map<String, dynamic>>();
    } catch (_) {}
    int byName(Map<String, dynamic> a, Map<String, dynamic> b) => '${a['name']}'.toLowerCase().compareTo('${b['name']}'.toLowerCase());
    if (!mounted) return;
    final c = widget.client;
    setState(() {
      // A region on the lead's own profile is the person's even when the list could not be read.
      final mineId = Services.auth.profile?.teamId;
      if (mineId != null && !regions.any((r) => r['id'] == mineId)) {
        regions = [...regions, {'id': mineId, 'name': Services.auth.profile?.team ?? 'My region'}];
      }
      _regions = regions..sort(byName);
      _territories = territories..sort(byName);
      _districts = districts..sort(byName);
      // What the lead was created with; whatever is missing is left for the person to choose.
      final territory = _idOf(c['territory']);
      if (_territoryId == null && territory != null && _territories.any((t) => t['id'] == territory)) _territoryId = territory;
      _districtId ??= _idOf(c['district']) ?? _districtOfTerritory(_territoryId);
      _mrp ??= _territoryMrp(_territoryId);
      final area = _idOf(c['area_master']);
      if (_areaId == null && area != null && _areaOptions().any((a) => a['id'] == area)) _areaId = area;
      final region = _idOf(c['region']) ?? mineId;
      if (_regionId == null && region != null && _regions.any((r) => r['id'] == region)) _regionId = region;
      if (_regionId == null && _regions.length == 1) _regionId = _regions.first['id'] as int;
    });
  }

  int? _districtOfTerritory(int? territoryId) =>
      (_territories.where((t) => t['id'] == territoryId).firstOrNull?['district_id'] as num?)?.toInt();

  /// The MRP set on a territory (its code), so the MRP is chosen by itself when somebody is onboarded there.
  String? _territoryMrp(int? territoryId) {
    final mrp = _territories.where((t) => t['id'] == territoryId).firstOrNull?['mrp'];
    return mrp is Map ? asText(mrp['code']) : null;
  }

  /// The areas of the chosen territory, A to Z.
  List<Map<String, dynamic>> _areaOptions() {
    final t = _territories.where((t) => t['id'] == _territoryId).firstOrNull;
    return ((t?['areas'] as List?) ?? const []).cast<Map<String, dynamic>>().toList()
      ..sort((a, b) => '${a['name']}'.toLowerCase().compareTo('${b['name']}'.toLowerCase()));
  }

  /// Choosing a territory sets the city, and drops an area that is not in it.
  void _pickTerritory(int? id) {
    setState(() {
      _territoryId = id;
      final city = _districtOfTerritory(id);
      if (city != null) _districtId = city;
      final mrp = _territoryMrp(id);
      if (mrp != null) _mrp = mrp;
      if (!_areaOptions().any((a) => a['id'] == _areaId)) _areaId = null;
    });
  }

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
        if (_regions.isNotEmpty && _regionId == null) bad.add('Region');
        if (_territoryId == null) bad.add('Territory');
        // The city comes from the territory (or, failing that, the PIN code).
        if (_districtId == null && asText(_pinInfo['district']) == null) bad.add('City: choose a territory that has one, or enter a valid PIN code');
        if (_areaOptions().isNotEmpty && _areaId == null) bad.add('Area');
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
          if (_v('accounts_poc_email').isNotEmpty && !_email.hasMatch(_v('accounts_poc_email'))) {
            bad.add('Accounts email: not a valid email');
          }
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
      final city = asText(_districts.where((d) => d['id'] == _districtId).firstOrNull?['name']) ?? asText(_pinInfo['district']) ?? '';
      final area = '${_areaOptions().where((a) => a['id'] == _areaId).firstOrNull?['name'] ?? ''}';
      final result = await withBusy(context, 'Saving…', () async => await Services.api.post(
            '/api/v1/clients/${widget.client['id']}/onboard',
            {
              'kind': _kind,
              'has_gst': _hasGst,
              if (_hasGst) 'gstin': _v('gstin').toUpperCase(),
              'gst_name': _v('gst_name'),
              'billing_address': _v('billing_address'),
              'street': [_v('door'), _v('street_name')].where((e) => e.isNotEmpty).join(', '),
              'door_no': _v('door'),
              'street_name': _v('street_name'),
              'delivery_same': _sameAsBilling,
              'street2': area,
              'city': city,
              'zip': _v('zip'),
              if (_pinInfo['state'] != null) 'state': _pinInfo['state'],
              if (_regionId != null) 'region_id': _regionId,
              if (_territoryId != null) 'territory_id': _territoryId,
              if (_districtId != null) 'district_id': _districtId,
              if (_areaId != null) 'area_id': _areaId,
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

  /// A dropdown over {id, name} rows, the id as its value.
  Widget _dropId(String label, List<Map<String, dynamic>> rows, int? value, ValueChanged<int?> onChanged,
          {bool required = true, String? helper}) =>
      _drop(label, [for (final r in rows) ('${r['id']}', '${r['name']}')], value?.toString(),
          (v) => onChanged(v == null ? null : int.tryParse(v)),
          required: required, helper: helper);

  Widget _step2() {
    final place = [asText(_pinInfo['state']), asText(_pinInfo['district'])].whereType<String>().join(' · ');
    final areas = _areaOptions();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _same(),
      // Each one a dropdown, filled from the lead and editable: some leads arrive without a region or territory.
      _dropId('Region', _regions, _regionId, (v) => setState(() => _regionId = v),
          required: _regions.isNotEmpty, helper: _regions.isEmpty ? 'No region is set for you' : null),
      _dropId('Territory', [
        for (final t in _territories) {'id': t['id'], 'name': '${t['name']}${t['kind'] == 'secondary' ? ' (secondary)' : ''}'},
      ], _territoryId, _pickTerritory),
      _dropId('Area', areas, _areaId, (v) => setState(() => _areaId = v),
          required: areas.isNotEmpty,
          helper: _territoryId == null ? 'Choose a territory first' : (areas.isEmpty ? 'No areas in this territory yet' : null)),
      _field('zip', 'PIN code', required: true, type: TextInputType.number, maxLength: 6, onChanged: (v) {
        if (v.length == 6) _lookupPin();
      }),
      _readOnly('State · District (auto from PIN)', place.isEmpty ? 'Enter the PIN code' : place),
      _field('street_name', 'Street name', required: true),
      _field('door', 'Door / TC No.', required: true),
    ]);
  }

  Widget _step3() {
    final onboardedText = fmtDate(_onboardedOn);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (_outlet) ...[
        _drop('Outlet category', [for (final o in _list('outlet_categories')) ('${o['code']}', '${o['name']}')], _category,
            (v) => setState(() => _category = v)),
        if (_categoryNeedsNote) _field('outlet_category_note', 'Describe the category', required: true),
      ],
      _drop('MRP', [for (final o in _list('mrp')) ('${o['code']}', '${o['name']}')], _mrp, (v) => setState(() => _mrp = v),
          helper: _mrp != null && _mrp == _territoryMrp(_territoryId) ? 'From the territory' : null),
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
      _drop('Scheme', [for (final o in _list('schemes')) ('${o['code']}', schemeText(o, _currency))], _scheme,
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
          _field('accounts_poc_email', 'Accounts email (optional)', type: TextInputType.emailAddress),
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
