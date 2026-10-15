import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/draft_store.dart';
import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/busy.dart';
import 'task_widgets.dart';

final _gstin = RegExp(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$');
final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
final _phone = RegExp(r'^[0-9]{10}$');

/// A lead that said yes becomes an outlet or a distributor, here, with every
/// detail the office needs before it can be onboarded. Returns the updated
/// contact, or null when left without finishing.
class OnboardScreen extends StatefulWidget {
  const OnboardScreen({super.key, required this.client});

  final Map<String, dynamic> client;

  @override
  State<OnboardScreen> createState() => _OnboardScreenState();
}

class _OnboardScreenState extends State<OnboardScreen> {
  String _kind = 'outlet';
  Map<String, dynamic> _options = {};
  final _c = <String, TextEditingController>{};
  bool? _swiggy;
  bool? _chiller;
  String? _mrp;
  String? _category;
  String? _scheme;
  String? _chillerModel;
  Map<String, dynamic>? _distributor;
  bool _busy = false;
  bool _saved = false;

  String get _draftKey => 'onboard-${widget.client['id']}';

  /// Anything typed or chosen beyond what the contact already had.
  bool get _filled =>
      _c.entries.any((e) => e.value.text.trim().isNotEmpty && e.value.text.trim() != _starting[e.key]) ||
      _swiggy != null || _chiller != null || _mrp != null || _category != null || _scheme != null ||
      _chillerModel != null || _distributor != null;

  final Map<String, String> _starting = {};

  Map<String, dynamic> _toDraft() => {
        'kind': _kind,
        'text': {for (final e in _c.entries) e.key: e.value.text},
        'swiggy': _swiggy, 'chiller': _chiller, 'mrp': _mrp, 'category': _category, 'scheme': _scheme,
        'chiller_model': _chillerModel, 'distributor': _distributor,
      };

  Future<void> _restore() async {
    final d = await DraftStore.read(_draftKey);
    if (d == null || !mounted) return;
    setState(() {
      _kind = '${d['kind'] ?? _kind}';
      for (final e in ((d['text'] as Map?) ?? {}).entries) {
        _t('${e.key}').text = '${e.value}';
      }
      _swiggy = d['swiggy'] as bool?;
      _chiller = d['chiller'] as bool?;
      _mrp = d['mrp'] as String?;
      _category = d['category'] as String?;
      _scheme = d['scheme'] as String?;
      _chillerModel = d['chiller_model'] as String?;
      _distributor = (d['distributor'] as Map?)?.cast<String, dynamic>();
    });
    showSnack(context, 'The details you filled earlier are back.');
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
    // No (or tapping outside): stay on the form with everything still in it.
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
    _t('street', '${c['street'] ?? ''}');
    _t('city', '${c['city'] ?? ''}');
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

  bool get _categoryNeedsNote =>
      _list('outlet_categories').any((o) => o['code'] == _category && o['needs_note'] == true);

  /// Everything still missing, all at once, so it can be put right in one go.
  List<String> _check() {
    final outlet = _kind == 'outlet';
    final bad = <String>[];
    if (!_gstin.hasMatch(_v('gstin').toUpperCase())) bad.add('GSTIN: enter a valid 15-character GSTIN');
    if (_v('gst_name').isEmpty) bad.add('Name as per GST');
    if (_v('street').isEmpty) bad.add('Delivery address: street');
    if (_v('city').isEmpty) bad.add('Delivery address: city');
    if (_v('zip').length != 6) bad.add('Delivery address: 6-digit pincode');
    if (_v('billing_address').isEmpty) bad.add('Billing address');
    if (outlet) {
      if (_category == null) bad.add('Outlet category');
      if (_categoryNeedsNote && _v('outlet_category_note').isEmpty) bad.add('Outlet category: describe it');
    }
    final who = outlet ? 'POC' : 'Sales POC';
    if (_v('poc_name').isEmpty) bad.add('$who name');
    if (!_phone.hasMatch(_v('poc_phone'))) bad.add('$who contact number: 10 digits');
    if (!_email.hasMatch(_v('poc_email'))) bad.add('$who email: enter a valid email');
    if (!outlet) {
      if (_v('accounts_poc_name').isEmpty) bad.add('Accounts POC name');
      if (!_phone.hasMatch(_v('accounts_poc_phone'))) bad.add('Accounts POC contact number: 10 digits');
      if (!_email.hasMatch(_v('accounts_poc_email'))) bad.add('Accounts email: enter a valid email');
    }
    if (_mrp == null) bad.add('MRP');
    if (outlet && _distributor == null) bad.add('Distributor');
    if (_swiggy == null) {
      bad.add('Swiggy / Zomato outlet: yes or no');
    } else if (_swiggy == true && _v('swiggy_zomato_id').isEmpty) {
      bad.add('Swiggy ID / Zomato ID');
    }
    if (outlet) {
      if (_chiller == null) {
        bad.add('Chiller from Kumbayah: yes or no');
      } else if (_chiller == true) {
        if (_v('chiller_serial').isEmpty) bad.add('Chiller serial number');
        if (_chillerModel == null) bad.add('Chiller model');
      }
    }
    if (_scheme == null) bad.add('Scheme');
    if (int.tryParse(_v('credit_days')) == null) bad.add('Credit days');
    if (double.tryParse(_v('margin')) == null) bad.add('Margin');
    return bad;
  }

  Future<void> _save() async {
    final problems = _check();
    if (problems.isNotEmpty) {
      await showProblem(context, problems, title: 'Still needed to onboard');
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await withBusy(context, 'Saving…', () async => await Services.api.post(
            '/api/v1/clients/${widget.client['id']}/onboard',
            {
              'kind': _kind,
              'gstin': _v('gstin').toUpperCase(),
              'gst_name': _v('gst_name'),
              'street': _v('street'),
              'city': _v('city'),
              'zip': _v('zip'),
              'billing_address': _v('billing_address'),
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
              'swiggy_zomato': _swiggy == true,
              'swiggy_zomato_id': _v('swiggy_zomato_id'),
              'has_chiller': _chiller == true,
              'chiller_serial': _v('chiller_serial'),
              'chiller_model': _chillerModel,
              'credit_days': _v('credit_days'),
              'margin': _v('margin'),
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

  Widget _field(String key, String hint, {String? title, TextInputType? type, int? maxLength}) {
    final controller = _t(key);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        keyboardType: type,
        maxLength: maxLength,
        textCapitalization: key == 'gstin' ? TextCapitalization.characters : TextCapitalization.sentences,
        decoration: InputDecoration(
          labelText: title ?? hint,
          counterText: '',
          isDense: true,
          filled: true,
          fillColor: AppColors.background,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final outlet = _kind == 'outlet';
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
      appBar: AppBar(title: Text('Onboard ${widget.client['name']}'), leading: BackButton(onPressed: _leave)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          StepCard(
            title: 'Becomes *',
            note: 'The lead moves to this category once saved.',
            child: Choice(
              options: const [
                {'code': 'outlet', 'name': 'Outlet'},
                {'code': 'distributor', 'name': 'Distributor'},
              ],
              value: _kind,
              onChanged: (v) => setState(() => _kind = v),
            ),
          ),
          StepCard(
            title: 'GST *',
            note: 'GSTIN is compulsory to onboard.',
            child: Column(children: [
              _field('gstin', 'GSTIN (e.g. 32ABCDE1234F1Z5)', maxLength: 15),
              _field('gst_name', 'Name as per GST'),
            ]),
          ),
          StepCard(
            title: 'Addresses *',
            child: Column(children: [
              _field('street', 'Delivery address — street'),
              _field('city', 'City'),
              _field('zip', 'Pincode', type: TextInputType.number, maxLength: 6),
              _field('billing_address', 'Billing address'),
            ]),
          ),
          StepCard(
            title: outlet ? 'Point of contact *' : 'Sales contact *',
            child: Column(children: [
              _field('poc_name', 'Name'),
              _field('poc_phone', 'Contact number (10 digits)', type: TextInputType.phone, maxLength: 10),
              _field('poc_email', 'Email', type: TextInputType.emailAddress),
            ]),
          ),
          if (!outlet)
            StepCard(
              title: 'Accounts contact *',
              child: Column(children: [
                _field('accounts_poc_name', 'Name'),
                _field('accounts_poc_phone', 'Contact number (10 digits)', type: TextInputType.phone, maxLength: 10),
                _field('accounts_poc_email', 'Email', type: TextInputType.emailAddress),
              ]),
            ),
          if (outlet)
            StepCard(
              title: 'Outlet category *',
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Choice(
                    options: _list('outlet_categories'),
                    value: _category,
                    onChanged: (v) => setState(() => _category = v)),
                if (_categoryNeedsNote) ...[const SizedBox(height: 10), _field('outlet_category_note', 'Describe')],
              ]),
            ),
          StepCard(
            title: 'MRP *',
            child: Choice(options: _list('mrp'), value: _mrp, onChanged: (v) => setState(() => _mrp = v)),
          ),
          if (outlet)
            StepCard(
              title: 'Distributor *',
              child: OutlinedButton.icon(
                icon: const Icon(Icons.local_shipping_rounded),
                label: Text(_distributor == null ? 'Choose the distributor' : '${_distributor!['name']}'),
                onPressed: () async {
                  final d = await pickFromList(context,
                      title: 'Distributor',
                      load: () async =>
                          (await Services.api.get('/api/v1/distributors') as List).cast<Map<String, dynamic>>(),
                      subtitle: (r) => '${r['city'] ?? ''}');
                  if (d != null) setState(() => _distributor = d);
                },
              ),
            ),
          StepCard(
            title: 'Swiggy / Zomato outlet *',
            child: Column(children: [
              YesNo(value: _swiggy, onChanged: (v) => setState(() => _swiggy = v)),
              if (_swiggy == true) ...[const SizedBox(height: 10), _field('swiggy_zomato_id', 'Swiggy ID / Zomato ID')],
            ]),
          ),
          if (outlet)
            StepCard(
              title: 'Chiller from Kumbayah *',
              child: Column(children: [
                YesNo(value: _chiller, onChanged: (v) => setState(() => _chiller = v)),
                if (_chiller == true) ...[
                  const SizedBox(height: 10),
                  _field('chiller_serial', 'Chiller serial number'),
                  Choice(
                      options: _list('chiller_models'),
                      value: _chillerModel,
                      onChanged: (v) => setState(() => _chillerModel = v)),
                ],
              ]),
            ),
          StepCard(
            title: 'Commercials *',
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Scheme', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Choice(options: _list('schemes'), value: _scheme, onChanged: (v) => setState(() => _scheme = v)),
              const SizedBox(height: 12),
              _field('credit_days', 'Credit days', type: TextInputType.number),
              _field('margin', 'Margin', type: const TextInputType.numberWithOptions(decimal: true)),
            ]),
          ),
          FilledButton(
            onPressed: _busy ? null : _save,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: const Text('Save and start the visit'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    ),
    );
  }
}
