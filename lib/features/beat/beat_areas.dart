import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Tick the areas a beat covers, from the areas of its territory. Null when cancelled.
Future<Set<int>?> pickBeatAreas(BuildContext context, List<Map<String, dynamic>> areas, Set<int> selected) {
  final picked = Set<int>.from(selected);
  return showDialog<Set<int>>(
    context: context,
    builder: (dialog) => StatefulBuilder(
      builder: (context, setDialog) => AlertDialog(
        title: const Text('Areas of this beat'),
        contentPadding: const EdgeInsets.only(top: 8),
        content: SizedBox(
          width: double.maxFinite,
          child: areas.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(20), child: Text('This territory has no areas set up yet.'))
              : ListView(shrinkWrap: true, children: [
                  for (final a in areas)
                    CheckboxListTile(
                      value: picked.contains(a['id']),
                      title: Text('${a['name']}'),
                      onChanged: (on) =>
                          setDialog(() => on == true ? picked.add(a['id'] as int) : picked.remove(a['id'])),
                    ),
                ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialog, picked), child: const Text('Done')),
        ],
      ),
    ),
  );
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
