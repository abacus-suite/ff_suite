import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/format.dart';
import '../../core/geo.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../clients/client_detail_screen.dart';

/// Nearby outlets: my own outlets close to where I am, nearest first, that are not on today's plan.
/// "+ Visit" opens the outlet to check in there, which adds the visit to today.
class NearbyOutletsCard extends StatefulWidget {
  const NearbyOutletsCard({super.key, this.plannedIds = const {}, this.onVisited});

  /// Today's planned outlets: they are already in Next Visit, so they are left out here.
  final Set<Object?> plannedIds;

  /// Called when the person comes back from an outlet, so the home screen can refresh.
  final VoidCallback? onVisited;

  @override
  State<NearbyOutletsCard> createState() => _NearbyOutletsCardState();
}

class _NearbyOutletsCardState extends State<NearbyOutletsCard> {
  List<Map<String, dynamic>> _outlets = [];
  Position? _here;

  /// How many to show, and how far to look.
  static const _shown = 3;
  static const _radiusKm = 5;

  @override
  void initState() {
    super.initState();
    Services.refresh.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    Services.refresh.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    try {
      final pos = await currentPosition(recentOk: true).timeout(const Duration(seconds: 12));
      final data = await Services.api.get('/api/v1/clients',
          query: {'lat': pos.latitude, 'lng': pos.longitude, 'radius_km': _radiusKm}) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _here = pos;
        _outlets = ((data['clients'] as List?) ?? []).cast<Map<String, dynamic>>();
      });
    } catch (_) {
      // No fix or no answer: the card simply stays away until the next refresh.
    }
  }

  /// Outlets only: distributors and leads are not visited from here.
  static bool _isOutlet(Map<String, dynamic> c) =>
      !const ['distributor', 'lead'].contains('${c['category_type'] ?? ''}'.toLowerCase());

  Future<void> _visit(Map<String, dynamic> c) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ClientDetailScreen(clientId: c['id'] as int)));
    widget.onVisited?.call();
  }

  @override
  Widget build(BuildContext context) {
    final rows = nearestFirst(
      _outlets.where((c) => _isOutlet(c) && !widget.plannedIds.contains(c['id'])).toList(),
      _here,
    ).where((c) => metresTo(_here, c) != null).take(_shown).toList();
    if (rows.isEmpty) return const SizedBox.shrink();
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [
              Icon(Icons.near_me_rounded, size: 20, color: AppColors.primary),
              SizedBox(width: 8),
              Expanded(
                child: Text('Nearby outlets', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              ),
              Text('Nearest first', style: TextStyle(fontSize: 11.5, color: AppColors.muted)),
            ]),
            const SizedBox(height: 6),
            for (final (i, c) in rows.indexed) ...[
              if (i > 0) const Divider(height: 1),
              _row(c),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(Map<String, dynamic> c) {
    final area = asText((c['district'] as Map?)?['name']) ?? asText(c['address']);
    final detail = [if (area != null) area, lastVisitLabel(c)].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${c['name']}',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
            Text(detail,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
          ]),
        ),
        const SizedBox(width: 8),
        Text(fmtDistance(metresTo(_here, c)),
            style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.primary, fontSize: 13)),
        const SizedBox(width: 8),
        SizedBox(
          height: 32,
          child: OutlinedButton.icon(
            onPressed: () => _visit(c),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            ),
            icon: const Icon(Icons.add_rounded, size: 16),
            label: const Text('Visit', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
          ),
        ),
      ]),
    );
  }
}
