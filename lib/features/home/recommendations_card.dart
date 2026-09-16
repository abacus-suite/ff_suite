import 'package:flutter/material.dart';

import '../../core/geo.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../clients/client_detail_screen.dart';

/// "Visit next": today's planned customers in the shortest order from here,
/// and customers close by that are due a visit. Shown only when the office
/// turned Visit Recommendations on and the person is punched in.
class RecommendationsCard extends StatefulWidget {
  const RecommendationsCard({super.key});

  @override
  State<RecommendationsCard> createState() => _RecommendationsCardState();
}

class _RecommendationsCardState extends State<RecommendationsCard> {
  Map<String, dynamic>? _data;
  bool _loading = false;
  String? _error;
  bool _showAll = false;

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
    if (!(Services.auth.profile?.visitRecommendations ?? false) || !mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final pos = await currentPosition(recentOk: true).timeout(const Duration(seconds: 12));
      final data = await Services.api.get('/api/v1/recommendations',
          query: {'lat': pos.latitude, 'lng': pos.longitude}) as Map<String, dynamic>;
      if (mounted) setState(() => _data = data);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _open(Map<String, dynamic> client) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ClientDetailScreen(clientId: client['id'] as int)));
  }

  String _km(num? value) => value == null ? '' : '${value.toStringAsFixed(value < 10 ? 1 : 0)} km';

  @override
  Widget build(BuildContext context) {
    if (!(Services.auth.profile?.visitRecommendations ?? false)) return const SizedBox.shrink();
    final data = _data;
    if (data != null && data['enabled'] == false) return const SizedBox.shrink();
    final planned = ((data?['planned'] as List?) ?? []).cast<Map<String, dynamic>>();
    final nearby = ((data?['nearby'] as List?) ?? []).cast<Map<String, dynamic>>();
    final shownPlanned = _showAll ? planned : planned.take(4).toList();
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.alt_route_rounded, color: AppColors.primary),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Visit next', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      Text('Shortest order from where you are', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: _loading ? null : _load,
                  icon: _loading
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.my_location_rounded),
                ),
              ],
            ),
            if (_error != null && data == null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(_error!, style: const TextStyle(color: AppColors.muted)),
              ),
            if (data != null && planned.isEmpty && nearby.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Text('Nothing to suggest right now.', style: TextStyle(color: AppColors.muted)),
              ),
            if (planned.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('PLANNED TODAY',
                      style: TextStyle(fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w800, color: AppColors.muted)),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text('${planned.length} left · ${_km(data?['planned_km'] as num?)}',
                        style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                  ),
                ],
              ),
              for (final c in shownPlanned)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: CircleAvatar(
                    radius: 15,
                    backgroundColor: c['sequence'] == 1 ? AppColors.primary : AppColors.primary.withValues(alpha: 0.12),
                    child: Text('${c['sequence']}',
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                            color: c['sequence'] == 1 ? Colors.white : AppColors.primary)),
                  ),
                  title: Text('${c['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text([if (c['address'] != null) c['address'], if (c['route'] != null) c['route']].join(' · '),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_km(c['leg_km'] as num?), style: const TextStyle(fontWeight: FontWeight.w700)),
                      if (c['lat'] != null)
                        IconButton(
                          tooltip: 'Directions',
                          icon: const Icon(Icons.directions_rounded, color: AppColors.primary),
                          onPressed: () => openDirections(c['lat'] as num, c['lng'] as num),
                        ),
                    ],
                  ),
                  onTap: () => _open(c),
                ),
              if (planned.length > 4)
                TextButton(
                  onPressed: () => setState(() => _showAll = !_showAll),
                  child: Text(_showAll ? 'Show less' : 'Show all ${planned.length}'),
                ),
            ],
            if (nearby.isNotEmpty) ...[
              const SizedBox(height: 6),
              const Text('YOU ARE NEAR · WORTH A VISIT',
                  style: TextStyle(fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w800, color: AppColors.muted)),
              for (final c in nearby.take(5))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: CircleAvatar(
                    radius: 15,
                    backgroundColor: AppColors.success.withValues(alpha: 0.12),
                    child: const Icon(Icons.storefront_rounded, size: 16, color: AppColors.success),
                  ),
                  title: Text('${c['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('${c['reason'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: Text(_km(c['distance_km'] as num?), style: const TextStyle(fontWeight: FontWeight.w700)),
                  onTap: () => _open(c),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
