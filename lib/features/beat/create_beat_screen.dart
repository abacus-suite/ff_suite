import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

/// Draw a route in the field.
///
/// The office draws most routes, but the field is the side that finds out a
/// patch of town has been missed or that one route has grown too big for a
/// day. The city it covers is the one thing it must have: a route without one
/// cannot be found again by anybody who did not draw it.
class CreateBeatScreen extends StatefulWidget {
  const CreateBeatScreen({super.key});

  @override
  State<CreateBeatScreen> createState() => _CreateBeatScreenState();
}

class _CreateBeatScreenState extends State<CreateBeatScreen> {
  final _name = TextEditingController();
  final _code = TextEditingController();
  Map<String, dynamic>? _city;
  Map<String, dynamic>? _type;
  List<Map<String, dynamic>> _types = [];
  bool _busy = false;

  String get _routeLabel => Services.auth.profile!.routeLabel;

  @override
  void initState() {
    super.initState();
    _loadTypes();
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _loadTypes() async {
    try {
      final list = await Services.api.get('/api/v1/route-types') as List;
      if (mounted) setState(() => _types = list.cast<Map<String, dynamic>>());
    } catch (_) {
      // Optional: a route can be drawn without one.
    }
  }

  Future<void> _pickCity() async {
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => const _CityPicker(),
    );
    if (picked != null && mounted) setState(() => _city = picked);
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      showProblem(context, 'Give the $_routeLabel a name.');
      return;
    }
    if (_city == null) {
      showProblem(context, 'Choose the city this $_routeLabel covers.');
      return;
    }
    setState(() => _busy = true);
    try {
      final beat = await Services.api.post('/api/v1/beats', {
        'name': name,
        'code': _code.text.trim(),
        'district_id': _city!['id'],
        if (_type != null) 'route_type_id': _type!['id'],
      }) as Map<String, dynamic>;
      if (!mounted) return;
      Navigator.of(context).pop(beat);
    } catch (e) {
      if (mounted) showProblem(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = _routeLabel;
    final title = '${label[0].toUpperCase()}${label.substring(1)}';
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text('New $title')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
          child: GradientButton(
            label: 'Create $title',
            icon: Icons.route_rounded,
            busy: _busy,
            onPressed: _busy ? null : _save,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 20),
        children: [
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('What is it called?',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 9),
                TextField(
                  controller: _name,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: _box('e.g. Cherthala - Muhamma'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _code,
                  textCapitalization: TextCapitalization.characters,
                  decoration: _box('Short code (optional), e.g. CHM-01'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('Which city does it cover?',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    const SizedBox(width: 6),
                    Text('required',
                        style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.danger)),
                  ],
                ),
                const SizedBox(height: 4),
                const Text('Chosen from the cities the office keeps, so two people never spell one two ways.',
                    style: TextStyle(fontSize: 11.5, color: AppColors.muted)),
                const SizedBox(height: 9),
                Material(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: _pickCity,
                    child: Padding(
                      padding: const EdgeInsets.all(13),
                      child: Row(
                        children: [
                          Icon(Icons.location_city_rounded,
                              size: 19, color: _city == null ? AppColors.muted : AppColors.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _city == null
                                  ? 'Choose a city'
                                  : '${_city!['name']}'
                                      '${(_city!['state'] as Map?)?['name'] != null ? ', ${(_city!['state'] as Map)['name']}' : ''}',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: _city == null ? AppColors.muted : AppColors.text),
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_types.isNotEmpty) ...[
            const SizedBox(height: 12),
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('What kind of route?',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  const SizedBox(height: 9),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final type in _types)
                        ChoiceChip(
                          label: Text('${type['name']}'),
                          selected: _type?['id'] == type['id'],
                          onSelected: (on) => setState(() => _type = on ? type : null),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'You are put on it, and you can add customers to it straight after. '
              'If the office has asked to see new routes first, it waits for them before '
              'anybody else can plan from it.',
              style: TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: child,
      );

  InputDecoration _box(String hint) => InputDecoration(
        hintText: hint,
        isDense: true,
        filled: true,
        fillColor: AppColors.background,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      );
}

/// The cities the office keeps, searchable.
class _CityPicker extends StatefulWidget {
  const _CityPicker();

  @override
  State<_CityPicker> createState() => _CityPickerState();
}

class _CityPickerState extends State<_CityPicker> {
  List<Map<String, dynamic>> _cities = [];
  String _query = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await Services.api.get('/api/v1/districts') as List;
      if (mounted) setState(() => _cities = list.cast<Map<String, dynamic>>());
    } catch (e) {
      if (mounted) showProblem(context, e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final shown = q.isEmpty
        ? _cities
        : _cities
            .where((c) => '${c['name']} ${(c['state'] as Map?)?['name'] ?? ''}'.toLowerCase().contains(q))
            .toList();
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.8,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                autofocus: true,
                onChanged: (value) => setState(() => _query = value),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded),
                  hintText: 'Search city or state',
                  isDense: true,
                ),
              ),
            ),
            if (_loading) const LinearProgressIndicator(),
            Expanded(
              child: shown.isEmpty && !_loading
                  ? const EmptyView(icon: Icons.location_off_rounded, text: 'No city matches')
                  : ListView.builder(
                      itemCount: shown.length,
                      itemBuilder: (_, i) {
                        final city = shown[i];
                        return ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: Color(0xFFE8EFFF),
                            child: Icon(Icons.location_city_rounded, color: AppColors.primary),
                          ),
                          title: Text('${city['name']}',
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text('${(city['state'] as Map?)?['name'] ?? ''}'),
                          onTap: () => Navigator.pop(context, city),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
