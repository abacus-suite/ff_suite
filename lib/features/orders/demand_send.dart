import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/busy.dart';
import 'distributor_submit.dart';

/// Opens WhatsApp with [text], to [phone] when it is known.
Future<bool> openWhatsApp(String? phone, String text) {
  final number = (phone ?? '').replaceAll(RegExp(r'\D'), '');
  final uri = Uri.parse('https://wa.me/${number.isEmpty ? '' : number}?text=${Uri.encodeComponent(text)}');
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Whether a demand can still be sent on: nothing ordered yet, or free goods not yet asked for.
bool demandSendable(Map<String, dynamic> d) => d['state'] == 'submitted' || d['state'] == 'draft';

/// Who the demands go to.
///
/// Each outlet's demand already carries the distributor it is linked to. When
/// they all agree that one is offered; when they are linked to several the
/// person must name the final one, because one order goes to one distributor;
/// and when none is linked the person picks. Demands with no distributor are
/// given the chosen one when the order is made.
Future<Map<String, dynamic>?> chooseFinalDistributor(BuildContext context, List<Map<String, dynamic>> demands) async {
  final linked = <int, Map<String, dynamic>>{};
  final counts = <int, int>{};
  var unlinked = 0;
  for (final d in demands) {
    final dist = (d['distributor'] as Map?)?.cast<String, dynamic>();
    if (dist == null) {
      unlinked++;
      continue;
    }
    final id = dist['id'] as int;
    linked[id] = dist;
    counts[id] = (counts[id] ?? 0) + 1;
  }
  if (linked.isEmpty) return pickDistributor(context, demandCount: demands.length);
  final picked = await showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) => _FinalDistributorSheet(
        linked: linked.values.toList(), counts: counts, unlinked: unlinked, total: demands.length),
  );
  if (picked == null) return null;
  if (picked['other'] == true) {
    if (!context.mounted) return null;
    return pickDistributor(context, demandCount: demands.length);
  }
  return picked;
}

class _FinalDistributorSheet extends StatelessWidget {
  const _FinalDistributorSheet(
      {required this.linked, required this.counts, required this.unlinked, required this.total});

  final List<Map<String, dynamic>> linked;
  final Map<int, int> counts;
  final int unlinked;
  final int total;

  @override
  Widget build(BuildContext context) {
    final several = linked.length > 1;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(several ? 'Choose the final distributor' : 'Send to ${linked.first['name']}?',
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
            const SizedBox(height: 6),
            Text(
              several
                  ? 'These $total demands are linked to ${linked.length} different distributors, but one order goes '
                      'to one distributor. Pick who it goes to; all the demands become theirs.'
                  : '${total - unlinked} of $total ${total == 1 ? 'demand is' : 'demands are'} linked to '
                      '${linked.first['name']}.',
              style: const TextStyle(fontSize: 13, color: AppColors.muted, height: 1.35),
            ),
            if (unlinked > 0)
              Container(
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                child: Text(
                    '$unlinked ${unlinked == 1 ? 'demand has' : 'demands have'} no distributor yet. '
                    '${unlinked == 1 ? 'It is' : 'They are'} added to the one you choose.',
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              ),
            const SizedBox(height: 14),
            for (final d in linked)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.border),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                    child: const Icon(Icons.local_shipping_rounded, color: AppColors.primary),
                  ),
                  title: Text('${d['name']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text('${counts[d['id']]} linked ${counts[d['id']] == 1 ? 'demand' : 'demands'}'),
                  trailing: FilledButton(
                    onPressed: () => Navigator.pop(context, d),
                    child: Text(several ? 'Choose' : 'Send'),
                  ),
                ),
              ),
            Center(
              child: TextButton.icon(
                onPressed: () => Navigator.pop(context, {'other': true}),
                icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                label: const Text('Another distributor'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sends the demands on: one order, as a draft, to the final distributor, with
/// the link to accept it, and a message asking for any free goods. Returns
/// whether anything was sent.
Future<bool> sendDemands(BuildContext context, List<Map<String, dynamic>> demands) async {
  if (demands.isEmpty) return false;
  final distributor = await chooseFinalDistributor(context, demands);
  if (distributor == null || !context.mounted) return false;
  try {
    // One draft order for the distributor. Free goods are on it as lines at 100% off, so the
    // summary and the link the distributor opens show them too.
    final result = await withBusy(context, 'Sending to ${distributor['name']}…', () async =>
        await Services.api.post('/api/v1/demands/submit', {
          'demand_ids': demands.map((o) => o['id']).toList(),
          'distributor_id': distributor['id'],
        }) as Map<String, dynamic>);
    if (!context.mounted) return true;
    await showSubmittedSheet(context, result);
    return true;
  } catch (e) {
    if (context.mounted) await showProblem(context, e.toString());
    return false;
  }
}
