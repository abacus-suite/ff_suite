import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../clients/clients_screen.dart';
import '../visits/visit_gate.dart';
import '../../widgets/busy.dart';
import 'onboard_screen.dart';
import 'task_flow_screen.dart';
import 'task_widgets.dart';

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
    return await withBusy(context, 'Loading tasks…',
        () async => await Services.api.get('/api/v1/field-tasks/config') as Map<String, dynamic>);
  } catch (e) {
    if (context.mounted) showProblem(context, 'The tasks could not be loaded: $e');
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
  final code = await _pickTask(context, config,
      withAdhoc: false, withNewLead: false, subtitle: '${client['name']}', client: client);
  if (code == null || !context.mounted) return;
  await _begin(context, config, code, client: client);
}

/// Takes somebody who is checked in straight back to where they were.
///
/// A visit that was opened for a task is not left by closing the app or going
/// to another screen: it ends when the task is submitted. So whenever the app
/// starts, or comes back to the front, it asks the server whether a visit is
/// still open and, if it is, puts the task back in front of the person.
Future<void> resumeOpenTask(BuildContext context) async {
  if (taskScreenOpen) return;
  try {
    final visit = await Services.api.get('/api/v1/visits/current') as Map<String, dynamic>?;
    final code = '${visit?['task'] ?? ''}';
    if (visit == null || code.isEmpty || taskScreenOpen || !context.mounted) return;
    if (taskMinimised(visit['id'])) return;
    final client = await Services.api.get('/api/v1/clients/${(visit['client'] as Map)['id']}')
        as Map<String, dynamic>;
    if (!context.mounted || taskScreenOpen) return;
    await resumeTask(context, client, visit);
  } catch (_) {
    // Offline, or nothing open: there is nowhere to take them.
  }
}

/// Picks up a task whose visit is already open, after the app was left.
Future<void> resumeTask(BuildContext context, Map<String, dynamic> client, Map<String, dynamic> visit) async {
  final config = await _config(context);
  final code = '${visit['task'] ?? ''}';
  if (config == null || !context.mounted || code.isEmpty) return;
  await _run(context, config, code, client, visit);
}

/// Whether the office offers this task for this kind of contact (mapped on the task type).
bool _offeredFor(Map<String, dynamic> task, Map<String, dynamic> client) {
  final allowed = ((task['category_ids'] as List?) ?? const []).map((e) => '$e').toSet();
  if (allowed.isEmpty) return true;
  final id = (client['category'] as Map?)?['id'];
  return id != null && allowed.contains('$id');
}

Future<String?> _pickTask(BuildContext context, Map<String, dynamic> config,
    {required bool withAdhoc, required bool withNewLead, String? subtitle, Map<String, dynamic>? client}) {
  final tasks = ((config['tasks'] as List?) ?? [])
      .cast<Map<String, dynamic>>()
      .where((t) => (withAdhoc || t['code'] != 'adhoc') && (withNewLead || t['code'] != 'new_lead'))
      .where((t) => client == null || _offeredFor(t, client))
      .toList();
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: double.infinity),
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (sheet) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('What are you doing?', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 21)),
            const SizedBox(height: 2),
            Text(subtitle ?? 'Pick a task. It opens its steps one at a time.',
                style: const TextStyle(fontSize: 13, color: AppColors.muted)),
            const SizedBox(height: 16),
            for (final task in tasks)
              _TaskTile(
                width: double.infinity,
                task: task,
                onTap: () => Navigator.pop(sheet, '${task['code']}'),
              ),
          ],
        ),
      ),
    ),
  );
}

/// One task, as a full-width row: its own colour and icon, its name, what it covers, how long it is.
class _TaskTile extends StatelessWidget {
  const _TaskTile({required this.width, required this.task, required this.onTap});

  final double width;
  final Map<String, dynamic> task;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final code = '${task['code']}';
    final tint = _tints[code] ?? AppColors.primary;
    final steps = ((task['steps'] as num?) ?? 1).toInt();
    final hint = '${task['hint'] ?? ''}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: tint.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: tint.withValues(alpha: 0.25)),
            ),
            child: Row(children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(16)),
                child: Icon(_icons[code] ?? Icons.task_alt_rounded, color: Colors.white, size: 25),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${task['name']}',
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, height: 1.15)),
                  if (hint != 'null' && hint.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(hint,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: AppColors.muted, height: 1.25)),
                    ),
                ]),
              ),
              const SizedBox(width: 8),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(color: tint.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
                  child: Text(steps > 1 ? '$steps steps' : '1 step',
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: tint)),
                ),
                const SizedBox(height: 6),
                Icon(Icons.chevron_right_rounded, color: tint),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Which contact it is for, then checking in there, then the screens.
/// Where the samples are being collected: from the company, or at a distributor or outlet.
Future<String?> _pickSampleSource(BuildContext context, {required bool companyAllowed}) {
  Widget option(BuildContext sheet, String code, IconData icon, Color tint, String title, String note) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
          color: tint.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => Navigator.pop(sheet, code),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(15)),
                  child: Icon(icon, color: Colors.white),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15.5)),
                    const SizedBox(height: 2),
                    Text(note, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                  ]),
                ),
                Icon(Icons.chevron_right_rounded, color: tint),
              ]),
            ),
          ),
        ),
      );
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: double.infinity),
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (sheet) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Collect samples from', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 21)),
          const SizedBox(height: 14),
          if (companyAllowed)
            option(sheet, 'company', Icons.business_rounded, AppColors.sky, 'Company',
                'From the company stock. No customer, no check-in'),
          option(sheet, 'distributor', Icons.local_shipping_rounded, AppColors.purple, 'Distributor',
              'Choose the distributor and check in there'),
          option(sheet, 'outlet', Icons.storefront_rounded, AppColors.teal, 'Outlet',
              'Choose the outlet and check in there'),
        ]),
      ),
    ),
  );
}

Future<void> _begin(BuildContext context, Map<String, dynamic> config, String code,
    {Map<String, dynamic>? client}) async {
  // These two make a contact or do not need one.
  if (code == 'adhoc' || code == 'new_lead') {
    await _run(context, config, code, null, null);
    return;
  }
  // Sample collection starts by asking where from. The company has no customer: straight on
  // to the steps. A distributor is chosen from the distributors alone, and an outlet from the
  // contacts, then checked in at, as for any visit.
  if (code == 'sample_collection' && client == null) {
    final from = await _pickSampleSource(context, companyAllowed: config['company_samples'] == true);
    if (from == null || !context.mounted) return;
    if (from == 'company') {
      await _run(context, config, code, null, null, preset: {'source': 'company'});
      return;
    }
    if (from == 'distributor') {
      final picked = await pickFromList(context,
          title: 'Distributor',
          load: () async => (await Services.api.get('/api/v1/distributors') as List).cast<Map<String, dynamic>>(),
          subtitle: (r) => '${r['city'] ?? ''}');
      if (picked == null || !context.mounted) return;
      try {
        final full = await Services.api.get('/api/v1/clients/${picked['id']}') as Map<String, dynamic>;
        if (!context.mounted) return;
        final visit = await ensureCheckedIn(context, full, task: code);
        if (visit == null || !context.mounted) return;
        await _run(context, config, code, full, visit, preset: {'source': 'distributor', 'distributor': full});
      } catch (e) {
        if (context.mounted) showProblem(context, e.toString());
      }
      return;
    }
  }
  var chosen = client;
  Map<String, dynamic>? visit;
  if (chosen != null) {
    // Already on the customer's own screen, which is where any question belongs.
    visit = await ensureCheckedIn(context, chosen, task: code);
  } else if (code == 'lead_follow_up') {
    chosen = await _pickLead(context, (sheet, lead) async {
      visit = await ensureCheckedIn(sheet, lead, task: code);
      return visit == null ? null : lead;
    });
  } else {
    // Checking in happens on the list they chose from, before it closes: an
    // offsite question asked afterwards would be asked over whatever page the
    // "+" was pressed on.
    chosen = await Navigator.of(context).push<Map<String, dynamic>>(MaterialPageRoute(
      builder: (_) => ClientsScreen(
        pickMode: true,
        onPick: (picker, contact) async {
          final task = ((config['tasks'] as List?) ?? []).cast<Map<String, dynamic>>().firstWhere(
              (t) => t['code'] == code, orElse: () => <String, dynamic>{});
          if (task.isNotEmpty && !_offeredFor(task, contact)) {
            showSnack(picker, '${task['name']} is not done for ${(contact['category'] as Map?)?['name'] ?? 'this'} contacts');
            return null;
          }
          visit = await ensureCheckedIn(picker, contact, task: code);
          return visit == null ? null : contact;
        },
      ),
    ));
  }
  if (chosen == null || visit == null || !context.mounted) return;
  await _run(context, config, code, chosen, visit);
}

Future<Map<String, dynamic>?> _pickLead(
    BuildContext context, Future<Map<String, dynamic>?> Function(BuildContext, Map<String, dynamic>) onPick) async {
  List<Map<String, dynamic>> leads;
  try {
    leads = await withBusy(context, 'Finding your leads…', () async =>
        (await Services.api.get('/api/v1/field-tasks/leads-due') as List).cast<Map<String, dynamic>>());
  } catch (e) {
    if (context.mounted) showProblem(context, e.toString());
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
    builder: (sheet) => _LeadList(leads: leads, onPick: onPick),
  );
}

Future<void> _run(BuildContext context, Map<String, dynamic> config, String code,
    Map<String, dynamic>? client, Map<String, dynamic>? visit,
    {Map<String, dynamic>? preset}) async {
  final result = await Navigator.of(context).push<Map<String, dynamic>>(MaterialPageRoute(
    builder: (_) => TaskFlowScreen(code: code, config: config, client: client, visit: visit, preset: preset),
  ));
  if (result == null || !context.mounted) return;
  // Onboarded: change the lead into an outlet or distributor with everything
  // the office needs, then straight into a Client Visit.
  if (result['onboard'] == true && result['partner'] is Map) {
    await completeOnboarding(context, (result['partner'] as Map).cast<String, dynamic>(), config: config);
  }
}

/// The onboarding form for a lead that said yes, and the Client Visit that follows it.
Future<void> completeOnboarding(BuildContext context, Map<String, dynamic> client,
    {Map<String, dynamic>? config}) async {
  config ??= await _config(context);
  if (config == null || !context.mounted) return;
  try {
    final full = await Services.api.get('/api/v1/clients/${client['id']}') as Map<String, dynamic>;
    if (!context.mounted) return;
    final done = await Navigator.of(context)
        .push<Map<String, dynamic>>(MaterialPageRoute(builder: (_) => OnboardScreen(client: full)));
    if (done == null || !context.mounted) return;
    // The contact is an outlet or distributor now. The visit that follows is the
    // person's to start: check in, then choose the task.
    if (context.mounted) showSnack(context, '${done['name']} is onboarded. Check in to start a visit.');
  } catch (e) {
    if (context.mounted) showProblem(context, e.toString());
  }
}

class _LeadList extends StatefulWidget {
  const _LeadList({required this.leads, required this.onPick});

  final List<Map<String, dynamic>> leads;
  final Future<Map<String, dynamic>?> Function(BuildContext, Map<String, dynamic>) onPick;

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
                    onTap: () async {
                      final result = await widget.onPick(context, lead);
                      if (result != null && context.mounted) Navigator.pop(context, result);
                    },
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
