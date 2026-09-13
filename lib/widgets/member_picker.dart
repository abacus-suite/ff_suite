import 'package:flutter/material.dart';

import '../core/services.dart';
import '../core/theme.dart';

/// The people this employee may look at (their Data Access), fetched once.
class TeamScope {
  static Map<String, dynamic>? _data;

  static Future<Map<String, dynamic>> load() async {
    if (_data != null) return _data!;
    try {
      _data = await Services.api.get('/api/v1/team/members') as Map<String, dynamic>;
    } catch (_) {
      _data = {'can_team': false, 'members': <dynamic>[]};
    }
    return _data!;
  }

  static void reset() => _data = null;
}

/// "Only me ▾" chip that switches a screen between me, my team and one person.
/// Hidden for people without a team. [value] is 'me', 'team' or an employee id.
class MemberPicker extends StatefulWidget {
  const MemberPicker({super.key, required this.value, required this.onChanged, this.dense = false});

  final String value;
  final ValueChanged<String> onChanged;
  final bool dense;

  @override
  State<MemberPicker> createState() => _MemberPickerState();
}

class _MemberPickerState extends State<MemberPicker> {
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    TeamScope.load().then((data) {
      if (mounted) setState(() => _data = data);
    });
  }

  List<Map<String, dynamic>> get _members => ((_data?['members'] as List?) ?? []).cast<Map<String, dynamic>>();

  String get _label => switch (widget.value) {
        'me' => 'Only me',
        'team' => 'Me + team',
        _ => '${_members.where((m) => '${m['id']}' == widget.value).firstOrNull?['name'] ?? 'Employee'}',
      };

  Future<void> _choose() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (context, controller) => ListView(
          controller: controller,
          children: [
            _option(sheet, 'me', Icons.person_rounded, 'Only me'),
            _option(sheet, 'team', Icons.groups_rounded, 'Me and my whole team'),
            const Divider(),
            for (final m in _members)
              _option(sheet, '${m['id']}', Icons.person_outline_rounded, '${m['name']}',
                  subtitle: (m['team'] as Map?)?['name'] as String?),
          ],
        ),
      ),
    );
    if (choice != null && choice != widget.value) widget.onChanged(choice);
  }

  Widget _option(BuildContext sheet, String value, IconData icon, String title, {String? subtitle}) {
    final selected = value == widget.value;
    return ListTile(
      leading: Icon(icon, color: selected ? AixoloColors.primary : AixoloColors.muted),
      title: Text(title, style: TextStyle(fontWeight: selected ? FontWeight.w800 : FontWeight.w500)),
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing: selected ? const Icon(Icons.check_rounded, color: AixoloColors.primary) : null,
      onTap: () => Navigator.pop(sheet, value),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_data?['can_team'] != true) return const SizedBox.shrink();
    return ActionChip(
      visualDensity: widget.dense ? VisualDensity.compact : null,
      avatar: const Icon(Icons.people_alt_rounded, size: 16, color: AixoloColors.primary),
      label: Text(_label, overflow: TextOverflow.ellipsis),
      onPressed: _choose,
    );
  }
}
