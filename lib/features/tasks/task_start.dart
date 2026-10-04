import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../clients/client_extras.dart';
import '../clients/clients_screen.dart';
import '../visits/visit_gate.dart';
import 'task_flow_screen.dart';

const _icons = <String, IconData>{
  'client_visit': Icons.storefront_rounded,
  'new_lead': Icons.person_add_alt_1_rounded,
  'lead_follow_up': Icons.event_repeat_rounded,
  'adhoc': Icons.bolt_rounded,
  'sample_collection': Icons.science_rounded,
  'marketing_supply': Icons.campaign_rounded,
};

const _tints = <String, Color>{
  'client_visit': AppColors.primary,
  'new_lead': AppColors.success,
  'lead_follow_up': AppColors.purple,
  'adhoc': AppColors.warning,
  'sample_collection': AppColors.teal,
  'marketing_supply': AppColors.sky,
};

Future<Map<String, dynamic>?> _config(BuildContext context) async {
  try {
    return await Services.api.get('/api/v1/field-tasks/config') as Map<String, dynamic>;
  } catch (e) {
    if (context.mounted) showSnack(context, 'The tasks could not be loaded: $e');
    return null;
  }
}

/// The "Task" option: pick one of the six, then the contact it is for.
Future<void> openTasks(BuildContext context) async {
  final config = await _config(context);
  if (config == null || !context.mounted) return;
  final code = await _pickTask(context, config, withAdhoc: true, withNewLead: true);
  if (code == null || !context.mounted) return;
  await _begin(context, config, code);
}

/// Checking in at a customer: what is this visit for? Adhoc is not a visit, and
/// a new lead has no customer yet, so neither is offered here.
Future<void> startTaskForClient(BuildContext context, Map<String, dynamic> client) async {
  final config = await _config(context);
  if (config == null || !context.mounted) return;
  final code = await _pickTask(context, config, withAdhoc: false, withNewLead: false, subtitle: '${client['name']}');
  if (code == null || !context.mounted) return;
  await _begin(context, config, code, client: client);
}

/// Picks up a task whose visit is already open, after the app was left.
Future<void> resumeTask(BuildContext context, Map<String, dynamic> client, Map<String, dynamic> visit) async {
  final config = await _config(context);
  final code = '${visit['task'] ?? ''}';
  if (config == null || !context.mounted || code.isEmpty) return;
  await _run(context, config, code, client, visit);
}

Future<String?> _pickTask(BuildContext context, Map<String, dynamic> config,
    {required bool withAdhoc, required bool withNewLead, String? subtitle}) {
  final tasks = ((config['tasks'] as List?) ?? [])
      .cast<Map<String, dynamic>>()
      .where((t) => (withAdhoc || t['code'] != 'adhoc') && (withNewLead || t['code'] != 'new_lead'))
      .toList();
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Select a task', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 19)),
            if (subtitle != null)
              Text(subtitle, style: const TextStyle(fontSize: 13, color: AppColors.muted)),
            const SizedBox(height: 12),
            for (final task in tasks)
              Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Material(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => Navigator.pop(sheet, '${task['code']}'),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: (_tints[task['code']] ?? AppColors.primary).withValues(alpha: 0.13),
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: Icon(_icons[task['code']] ?? Icons.task_alt_rounded,
                                color: _tints[task['code']] ?? AppColors.primary),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${task['name']}',
                                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                                Text(
                                    ((task['steps'] as num?) ?? 1) > 1
                                        ? '${task['steps']} steps'
                                        : '${task['hint'] ?? '1 step'}',
                                    style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

/// Which contact it is for, then checking in there, then the screens.
Future<void> _begin(BuildContext context, Map<String, dynamic> config, String code,
    {Map<String, dynamic>? client}) async {
  // These two make a contact or do not need one.
  if (code == 'adhoc' || code == 'new_lead') {
    await _run(context, config, code, null, null);
    return;
  }
  var chosen = client;
  if (code == 'lead_follow_up') {
    chosen ??= await _pickLead(context);
  } else {
    chosen ??= await Navigator.of(context).push<Map<String, dynamic>>(
        MaterialPageRoute(builder: (_) => const ClientsScreen(pickMode: true)));
  }
  if (chosen == null || !context.mounted) return;
  final visit = await ensureCheckedIn(context, chosen, task: code);
  if (visit == null || !context.mounted) return;
  await _run(context, config, code, chosen, visit);
}

Future<Map<String, dynamic>?> _pickLead(BuildContext context) async {
  List<Map<String, dynamic>> leads;
  try {
    leads = (await Services.api.get('/api/v1/field-tasks/leads-due') as List).cast<Map<String, dynamic>>();
  } catch (e) {
    if (context.mounted) showSnack(context, e.toString());
    return null;
  }
  if (!context.mounted) return null;
  if (leads.isEmpty) {
    showSnack(context, 'No leads are waiting for a follow-up.');
    return null;
  }
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) => _LeadList(leads: leads),
  );
}

Future<void> _run(BuildContext context, Map<String, dynamic> config, String code,
    Map<String, dynamic>? client, Map<String, dynamic>? visit) async {
  final result = await Navigator.of(context).push<Map<String, dynamic>>(MaterialPageRoute(
    builder: (_) => TaskFlowScreen(code: code, config: config, client: client, visit: visit),
  ));
  if (result == null || !context.mounted) return;
  // Onboarded: fill in the rest of the outlet, then straight into a Client Visit.
  if (result['onboard'] == true && result['partner'] is Map) {
    final partner = (result['partner'] as Map).cast<String, dynamic>();
    try {
      final full = await Services.api.get('/api/v1/clients/${partner['id']}') as Map<String, dynamic>;
      if (!context.mounted) return;
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => EditClientScreen(client: full)));
      if (!context.mounted) return;
      await _begin(context, config, 'client_visit', client: full);
    } catch (e) {
      if (context.mounted) showSnack(context, e.toString());
    }
  }
}

class _LeadList extends StatefulWidget {
  const _LeadList({required this.leads});

  final List<Map<String, dynamic>> leads;

  @override
  State<_LeadList> createState() => _LeadListState();
}

class _LeadListState extends State<_LeadList> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final shown = q.isEmpty
        ? widget.leads
        : widget.leads.where((l) => '${l['name']}'.toLowerCase().contains(q)).toList();
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.8,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Leads due for follow-up',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                  const SizedBox(height: 8),
                  TextField(
                    onChanged: (v) => setState(() => _query = v),
                    decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search_rounded), hintText: 'Search by name', isDense: true),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: shown.length,
                itemBuilder: (_, i) {
                  final lead = shown[i];
                  final status = '${lead['follow_up_status']}';
                  final tint = status == 'overdue'
                      ? AppColors.danger
                      : status == 'today'
                          ? AppColors.warning
                          : AppColors.sky;
                  return ListTile(
                    title: Text('${lead['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text([
                      if (asText(lead['city']) != null) '${lead['city']}',
                      'Follow-up ${lead['follow_up']}',
                    ].join(' · ')),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                          color: tint.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(20)),
                      child: Text(
                          status == 'overdue' ? 'Overdue' : status == 'today' ? 'Today' : 'Upcoming',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: tint)),
                    ),
                    onTap: () => Navigator.pop(context, lead),
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
