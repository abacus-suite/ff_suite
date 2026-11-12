import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Tick the areas a beat covers, on a page of its own (as the District / Territory is chosen), with a search and
/// Select all / Clear all. Null when the person goes back without Done.
Future<Set<int>?> pickBeatAreas(BuildContext context, List<Map<String, dynamic>> areas, Set<int> selected) {
  return Navigator.of(context).push<Set<int>>(MaterialPageRoute(
    builder: (_) => _AreaPickerScreen(areas: areas, selected: selected),
  ));
}

class _AreaPickerScreen extends StatefulWidget {
  const _AreaPickerScreen({required this.areas, required this.selected});

  final List<Map<String, dynamic>> areas;
  final Set<int> selected;

  @override
  State<_AreaPickerScreen> createState() => _AreaPickerScreenState();
}

class _AreaPickerScreenState extends State<_AreaPickerScreen> {
  late final Set<int> _picked = {...widget.selected};
  String _query = '';

  List<Map<String, dynamic>> get _shown => [
        for (final a in widget.areas)
          if (_query.isEmpty || '${a['name']}'.toLowerCase().contains(_query.toLowerCase())) a,
      ];

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Areas of this beat', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
        actions: [
          TextButton(
              onPressed: () => setState(() => _picked.addAll([for (final a in shown) a['id'] as int])),
              child: const Text('Select all')),
          TextButton(
              onPressed: () => setState(() => _picked.removeAll([for (final a in shown) a['id'] as int])),
              child: const Text('Clear all')),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
          child: FilledButton(
            onPressed: () => Navigator.pop(context, _picked),
            child: Text('Done (${_picked.length} selected)'),
          ),
        ),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            onChanged: (v) => setState(() => _query = v.trim()),
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Search area…', isDense: true),
          ),
        ),
        Expanded(
          child: widget.areas.isEmpty
              ? const Center(child: Text('This District / Territory has no areas set up yet.'))
              : ListView.builder(
                  itemCount: shown.length,
                  itemBuilder: (_, i) {
                    final a = shown[i];
                    final id = a['id'] as int;
                    return CheckboxListTile(
                      value: _picked.contains(id),
                      title: Text('${a['name']}'),
                      onChanged: (on) => setState(() => on == true ? _picked.add(id) : _picked.remove(id)),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

/// The areas picked, as chips, with a button to change them.
class BeatAreaField extends StatelessWidget {
  const BeatAreaField({super.key, required this.names, required this.onChange, this.enabled = true});

  final List<String> names;
  final VoidCallback onChange;
  final bool enabled;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: enabled ? onChange : null,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(children: [
            Expanded(
              child: names.isEmpty
                  ? Text(enabled ? 'Choose the areas' : 'Choose a District / Territory first',
                      style: const TextStyle(fontSize: 14, color: Color(0xFF94A3B8)))
                  : Wrap(spacing: 6, runSpacing: 6, children: [
                      for (final n in names)
                        Chip(
                          label: Text(n, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                          visualDensity: VisualDensity.compact,
                          backgroundColor: AppColors.primary.withValues(alpha: 0.08),
                          side: BorderSide.none,
                        ),
                    ]),
            ),
            const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF64748B)),
          ]),
        ),
      );
}
