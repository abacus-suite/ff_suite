import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/api_client.dart';
import '../../core/geo.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../core/format.dart';

/// Demands, orders and payments are taken at a customer, so they start with a
/// check-in there. Returns the open visit, or null when the person backed out.
///
/// The server decides onsite or offsite: a customer without coordinates takes
/// them from this check-in; one too far away comes back as `offsite_confirm`,
/// and only an explicit "yes, offsite" checks in anyway.
Future<Map<String, dynamic>?> ensureCheckedIn(BuildContext context, Map<String, dynamic> client) async {
  final clientId = client['id'] as int;
  final name = '${client['name']}';
  try {
    final current = await Services.api.get('/api/v1/visits/current') as Map<String, dynamic>?;
    if (current != null) {
      final at = current['client'] as Map;
      if (at['id'] == clientId) return current;
      if (context.mounted) showSnack(context, 'Check out from ${at['name']} first.');
      return null;
    }
    if (Services.auth.profile!.feature('attendance')) {
      final status = await Services.api.get('/api/v1/attendance/status') as Map<String, dynamic>;
      if (status['punched_in'] != true) {
        if (context.mounted) {
          await showDialog<void>(
            context: context,
            builder: (dialog) => AlertDialog(
              icon: const Icon(Icons.fingerprint_rounded, color: AixoloColors.warning, size: 36),
              title: const Text('Start your day first'),
              content: const Text(
                  'Check in for attendance on the Home screen before visiting customers, taking demands or collecting payments.'),
              actions: [FilledButton(onPressed: () => Navigator.pop(dialog), child: const Text('OK'))],
            ),
          );
        }
        return null;
      }
    }
    if (!context.mounted) return null;
    final go = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        icon: const Icon(Icons.storefront_rounded, color: AixoloColors.primary, size: 36),
        title: Text('Check in at $name?'),
        content: const Text('Your location is matched with the customer before you start.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialog, true),
            icon: const Icon(Icons.place_rounded),
            label: const Text('Check in'),
          ),
        ],
      ),
    );
    if (go != true || !context.mounted) return null;

    final pos = await currentPosition();
    final payload = {
      'partner_id': clientId,
      'lat': pos.latitude,
      'lng': pos.longitude,
      'accuracy': pos.accuracy,
      'mock': pos.isMocked,
      'uuid': const Uuid().v4(),
    };
    try {
      return await _checkIn(context, payload);
    } on ApiException catch (e) {
      if (e.code != 'offsite_confirm' || !context.mounted) rethrow;
      final reason = TextEditingController();
      final offsite = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          icon: const Icon(Icons.wrong_location_rounded, color: AixoloColors.warning, size: 36),
          title: const Text('Offsite visit?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(e.message),
              const SizedBox(height: 12),
              TextField(
                controller: reason,
                decoration: const InputDecoration(labelText: 'Reason (optional)', hintText: 'e.g. met at the market'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Check in offsite')),
          ],
        ),
      );
      if (offsite != true || !context.mounted) return null;
      return await _checkIn(context, {...payload, 'offsite': true, 'offsite_reason': reason.text.trim()});
    }
  } catch (e) {
    if (context.mounted) showSnack(context, e.toString());
    return null;
  }
}

Future<Map<String, dynamic>> _checkIn(BuildContext context, Map<String, dynamic> payload) async {
  final visit = await Services.api.post('/api/v1/visits/check-in', payload) as Map<String, dynamic>;
  if (context.mounted) {
    showSnack(
      context,
      visit['location_captured'] == true
          ? 'Checked in · customer location saved'
          : visit['visit_type'] == 'offsite'
              ? 'Checked in as offsite visit'
              : 'Checked in',
    );
  }
  Services.refresh.value++;
  return visit;
}
