import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/format.dart';
import '../../core/geo.dart';
import '../../core/services.dart';
import '../beat/create_beat_screen.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

class AddClientScreen extends StatefulWidget {
  const AddClientScreen({super.key});

  @override
  State<AddClientScreen> createState() => _AddClientScreenState();
}

class _AddClientScreenState extends State<AddClientScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _street = TextEditingController();
  final _city = TextEditingController();
  final _zip = TextEditingController();
  final _note = TextEditingController();
  List<Map<String, dynamic>> _categories = [];
  int? _categoryId;
  int? _routeId;
  List<Map<String, dynamic>> _routes = [];
  Position? _pos;

  // Territory and Area: suggested from where the person stands, and theirs to change.
  List<Map<String, dynamic>> _territories = [];
  int? _territoryId;
  int? _areaId;
  int? _districtId;
  bool _territoryTouched = false;
  bool _areaTouched = false;
  bool _cityAuto = false;
  bool _suggested = false;
  String? _locError;
  bool _locating = false;
  bool _busy = false;

  String get _clientLabel => Services.auth.profile!.label('client', 'Client');

  @override
  void initState() {
    super.initState();
    _locate();
    _loadCategories();
    _loadRoutes();
    _loadTerritories();
  }

  /// The territories this person works in, each with its areas.
  Future<void> _loadTerritories() async {
    try {
      final data = await Services.api.get('/api/v1/clients/filters') as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        // Their own territories only: primary first, then secondary (not the ones reached through a team or a beat).
        _territories = [
          for (final t in ((data['territories'] as List?) ?? []).cast<Map<String, dynamic>>())
            if (t['kind'] == null || t['kind'] == 'primary' || t['kind'] == 'secondary') t,
        ]..sort((a, b) {
            final kind = (a['kind'] == 'secondary' ? 1 : 0).compareTo(b['kind'] == 'secondary' ? 1 : 0);
            return kind != 0 ? kind : territoryLabel(a).toLowerCase().compareTo(territoryLabel(b).toLowerCase());
          });
      });
      _applySuggestion();
    } catch (_) {
      // Without them the territory and area simply stay empty.
    }
  }

  Map<String, dynamic>? _suggestion;

  /// Ask the server where this is: territory and area from the contacts around, the city from a lookup.
  Future<void> _suggest() async {
    final pos = _pos;
    if (pos == null) return;
    try {
      final data = await Services.api.post('/api/v1/geo/suggest', {'lat': pos.latitude, 'lng': pos.longitude})
          as Map<String, dynamic>;
      if (!mounted) return;
      _suggestion = data;
      _applySuggestion();
    } catch (_) {
      // An older server, or no network: the person fills the fields in.
    }
  }

  /// Fill what the person has not touched: territory and area when they are theirs to use, the city when empty.
  void _applySuggestion() {
    final data = _suggestion;
    if (data == null || !mounted) return;
    int? idOf(Object? ref) => ref is Map ? (ref['id'] as num?)?.toInt() : null;
    final territory = idOf(data['territory']);
    final area = idOf(data['area']);
    final district = idOf(data['district']);
    final city = asText(data['city']);
    var changed = false;
    setState(() {
      if (!_territoryTouched && territory != null && _territories.any((t) => t['id'] == territory)) {
        _territoryId = territory;
        changed = true;
      }
      final areas = _areasOf(_territoryId);
      if (!_areaTouched && area != null && areas.any((a) => a['id'] == area)) {
        _areaId = area;
        changed = true;
      }
      if (district != null) _districtId = district;
      if (city != null && (_city.text.trim().isEmpty || _cityAuto)) {
        _city.text = city;
        _cityAuto = true;
        changed = true;
      }
      if (changed) _suggested = true;
    });
  }

  List<Map<String, dynamic>> _areasOf(int? territoryId) {
    final t = _territories.where((t) => t['id'] == territoryId).firstOrNull;
    final list = ((t?['areas'] as List?) ?? const []).cast<Map<String, dynamic>>().toList()
      ..sort((a, b) => '${a['name']}'.toLowerCase().compareTo('${b['name']}'.toLowerCase()));
    return list;
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _street, _city, _zip, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Every route this person may use, with the city each one covers.
  Future<void> _loadRoutes() async {
    try {
      final list = (await Services.api.get('/api/v1/route-plan/routes') as List).cast<Map<String, dynamic>>();
      if (mounted) setState(() => _routes = list);
    } catch (_) {
      // No routes module or no access: the form works without one.
    }
  }

  /// Draws the route that is missing, from here, and uses it.
  ///
  /// A new shop is exactly when somebody finds out a route does not cover
  /// where they are standing, so the form asks rather than sending them away
  /// to make one and come back.
  Future<void> _newRoute() async {
    final beat = await Navigator.of(context)
        .push<Map<String, dynamic>>(MaterialPageRoute(builder: (_) => const CreateBeatScreen()));
    if (beat == null || !mounted) return;
    await _loadRoutes();
    if (!mounted) return;
    _pickRoute(beat['id'] as int?);
    showSnack(
        context,
        beat['approval_state'] == 'pending'
            ? '${beat['name']} created · waiting for the office'
            : '${beat['name']} created');
  }

  void _pickRoute(int? id) {
    setState(() => _routeId = id);
    // Only a city nobody has typed yet. A route covers a city but is named for
    // a stretch of it, so it must never overwrite an address somebody entered.
    if (_city.text.trim().isNotEmpty) return;
    final route = _routes.where((r) => r['id'] == id).firstOrNull;
    final city = route?['city'] as String?;
    if (city != null && city.isNotEmpty) _city.text = city;
  }

  Future<void> _loadCategories() async {
    try {
      final list = (await Services.api.get('/api/v1/contact-categories') as List).cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        _categories = list;
        if (list.length == 1) _categoryId = list.first['id'] as int;
      });
    } catch (e) {
      if (mounted) showProblem(context, e.toString());
    }
  }

  Future<void> _locate() async {
    setState(() => _locating = true);
    try {
      final pos = await currentPosition();
      if (mounted) setState(() => (_pos = pos, _locError = null));
      // Where is this? Territory, area and city come from the position.
      unawaited(_suggest());
    } catch (e) {
      if (mounted) setState(() => _locError = e.toString());
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final sent = await Services.outbox.submit('/api/v1/clients', {
        'uuid': const Uuid().v4(),
        'name': _name.text.trim(),
        'category_id': _categoryId,
        if (_routeId != null) 'route_id': _routeId,
        if (_routes.where((r) => r['id'] == _routeId).firstOrNull?['district'] case {'id': final int district})
          'district_id': district
        else if (_districtId != null)
          'district_id': _districtId,
        if (_territoryId != null) 'territory_id': _territoryId,
        if (_areaId != null) 'area_id': _areaId,
        'phone': _phone.text.trim(),
        'email': _email.text.trim(),
        'street': _street.text.trim(),
        'city': _city.text.trim(),
        'zip': _zip.text.trim(),
        'note': _note.text.trim(),
        'lat': _pos?.latitude,
        'lng': _pos?.longitude,
      }, label: 'New customer · ${_name.text.trim()}');
      final result = sent.map;
      if (!mounted) return;
      showSnack(context,
          sent.queued
              ? '$_clientLabel saved offline'
              : result['approval_state'] == 'pending'
                  ? '$_clientLabel sent to your manager for approval'
                  : '$_clientLabel added');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showProblem(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(TextEditingController c, String label, {TextInputType? type, bool required = false, int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: c,
        keyboardType: type,
        maxLines: maxLines,
        decoration: InputDecoration(labelText: required ? '$label *' : label),
        validator: required ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null : null,
      ),
    );
  }

  /// Territory and Area, with a note while they were filled in from the location.
  Widget _territoryAreaFields() {
    final areas = _areasOf(_territoryId);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        DropdownButtonFormField<int?>(
          initialValue: _territories.any((t) => t['id'] == _territoryId) ? _territoryId : null,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'City / Town'),
          items: [
            const DropdownMenuItem<int?>(value: null, child: Text('No city / town')),
            for (final t in _territories)
              DropdownMenuItem<int?>(
                  value: t['id'] as int,
                  child: Text('${territoryLabel(t)}${t['kind'] == 'secondary' ? ' (secondary)' : ''}',
                      overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => setState(() {
            _territoryTouched = true;
            if (v != _territoryId) {
              _areaId = null;
              _areaTouched = false;
            }
            _territoryId = v;
          }),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int?>(
          initialValue: areas.any((a) => a['id'] == _areaId) ? _areaId : null,
          isExpanded: true,
          decoration: InputDecoration(
              labelText: 'Area',
              helperText: _territoryId == null ? 'Choose a city / town first' : (areas.isEmpty ? 'No areas in this city / town yet' : null)),
          items: [
            const DropdownMenuItem<int?>(value: null, child: Text('No area')),
            for (final a in areas) DropdownMenuItem<int?>(value: a['id'] as int, child: Text('${a['name']}', overflow: TextOverflow.ellipsis)),
          ],
          onChanged: areas.isEmpty
              ? null
              : (v) => setState(() {
                    _areaTouched = true;
                    _areaId = v;
                  }),
        ),
        if (_suggested)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('Suggested from your location. Change it if it is not right.',
                style: TextStyle(fontSize: 12, color: AppColors.muted)),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pos = _pos;
    final routeLabel = Services.auth.profile!.routeLabel;
    return Scaffold(
      appBar: AppBar(title: Text('Add $_clientLabel')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: (pos != null ? AppColors.success : AppColors.warning).withValues(alpha: 0.14),
                  child: Icon(Icons.my_location_rounded, color: pos != null ? AppColors.success : AppColors.warning),
                ),
                title: Text(_locating
                    ? 'Getting location...'
                    : pos != null
                        ? '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)} (±${pos.accuracy.round()} m)'
                        : (_locError ?? 'No location')),
                subtitle: Text("Stand at the ${_clientLabel.toLowerCase()}'s place so the location is right"),
                trailing: IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _locating ? null : _locate),
              ),
            ),
            const SizedBox(height: 16),
            _field(_name, 'Name', required: true),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: DropdownButtonFormField<int>(
                initialValue: _categoryId,
                decoration: const InputDecoration(labelText: 'Category *'),
                items: [
                  for (final c in _categories)
                    DropdownMenuItem(value: c['id'] as int, child: Text('${c['name']}')),
                ],
                onChanged: (v) => setState(() => _categoryId = v),
                validator: (v) => v == null ? 'Choose a category' : null,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int?>(
                      initialValue: _routes.any((r) => r['id'] == _routeId) ? _routeId : null,
                      decoration: InputDecoration(
                          labelText: routeLabel,
                          helperText: 'Shares the contact with the $routeLabel team'),
                      items: [
                        DropdownMenuItem<int?>(value: null, child: Text('No $routeLabel')),
                        for (final r in _routes)
                          DropdownMenuItem<int?>(
                            value: r['id'] as int,
                            child: Text('${r['name']}',
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      isExpanded: true,
                      onChanged: _pickRoute,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: IconButton.filledTonal(
                      tooltip: 'New $routeLabel',
                      onPressed: _newRoute,
                      icon: const Icon(Icons.add_rounded),
                    ),
                  ),
                ],
              ),
            ),
            _territoryAreaFields(),
            _field(_phone, 'Phone', type: TextInputType.phone),
            _field(_email, 'Email', type: TextInputType.emailAddress),
            _field(_street, 'Street / area'),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextFormField(
                controller: _city,
                onChanged: (_) => _cityAuto = false,
                decoration: const InputDecoration(labelText: 'City'),
              ),
            ),
            _field(_zip, 'PIN code', type: TextInputType.number),
            _field(_note, 'Notes', maxLines: 3),
            const SizedBox(height: 8),
            GradientButton(label: 'Save $_clientLabel', icon: Icons.check_rounded, busy: _busy, onPressed: _submit),
          ],
        ),
      ),
    );
  }
}
