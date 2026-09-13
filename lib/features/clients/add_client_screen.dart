import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/format.dart';
import '../../core/geo.dart';
import '../../core/services.dart';
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

  void _pickRoute(int? id) {
    setState(() => _routeId = id);
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
      if (mounted) showSnack(context, e.toString());
    }
  }

  Future<void> _locate() async {
    setState(() => _locating = true);
    try {
      final pos = await currentPosition();
      if (mounted) setState(() => (_pos = pos, _locError = null));
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
          'district_id': district,
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
      if (mounted) showSnack(context, e.toString());
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
                  backgroundColor: (pos != null ? AixoloColors.success : AixoloColors.warning).withValues(alpha: 0.14),
                  child: Icon(Icons.my_location_rounded, color: pos != null ? AixoloColors.success : AixoloColors.warning),
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
            if (_routes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: DropdownButtonFormField<int?>(
                  initialValue: _routeId,
                  decoration: InputDecoration(labelText: routeLabel, helperText: 'Fills the city and shares it with the $routeLabel team'),
                  items: [
                    DropdownMenuItem<int?>(value: null, child: Text('No $routeLabel')),
                    for (final r in _routes)
                      DropdownMenuItem<int?>(
                        value: r['id'] as int,
                        child: Text(r['city'] == null ? '${r['name']}' : '${r['name']} · ${r['city']}',
                            overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  isExpanded: true,
                  onChanged: _pickRoute,
                ),
              ),
            _field(_phone, 'Phone', type: TextInputType.phone),
            _field(_email, 'Email', type: TextInputType.emailAddress),
            _field(_street, 'Street / area'),
            _field(_city, 'City'),
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
