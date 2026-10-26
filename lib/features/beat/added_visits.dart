import 'dart:convert';

import '../../core/format.dart';
import '../../core/services.dart';

/// Outlets added to today's beat with "Add a Visit", kept on the phone for the day.
/// They show in Today's Beat Plan as "Added" until visited; the visit itself then
/// comes back from the server like any other.
class AddedVisits {
  AddedVisits._();

  static String get _key => 'added_visits_${Services.auth.profile?.employeeId ?? 0}';

  /// Today's added outlets; anything from an earlier day is dropped.
  static Future<List<Map<String, dynamic>>> today() async {
    try {
      final raw = await Services.storage.read(_key);
      if (raw == null) return [];
      final saved = jsonDecode(raw) as Map<String, dynamic>;
      if (saved['date'] != fmtDate(DateTime.now())) return [];
      return ((saved['outlets'] as List?) ?? []).cast<Map>().map((m) => m.cast<String, dynamic>()).toList();
    } catch (_) {
      return [];
    }
  }

  /// Adds outlets to today, each once, keeping only what the list needs.
  static Future<void> add(List<Map<String, dynamic>> outlets) async {
    final have = await today();
    final ids = {for (final o in have) o['id']};
    for (final o in outlets) {
      if (!ids.add(o['id'])) continue;
      have.add({
        for (final k in const ['id', 'name', 'lat', 'lng', 'address', 'district', 'category_type', 'distance_m'])
          if (o[k] != null) k: o[k],
      });
    }
    await Services.storage.write(_key, jsonEncode({'date': fmtDate(DateTime.now()), 'outlets': have}));
  }
}
