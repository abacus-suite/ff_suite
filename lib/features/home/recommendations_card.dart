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
    final rest = planned.skip(1).toList();
    final shownRest = _showAll ? rest : rest.take(3).toList();
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(data, planned),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_error != null && data == null)
                  Text(_error!, style: const TextStyle(color: AppColors.muted)),
                if (data != null && planned.isEmpty && nearby.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Text('Nothing to suggest right now.', style: TextStyle(color: AppColors.muted)),
                  ),
                if (planned.isNotEmpty) ...[
                  _nextStop(planned.first),
                  if (rest.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text('THEN', style: _capsStyle),
                    const SizedBox(height: 2),
                    for (final c in shownRest) _stopRow(c),
                    if (rest.length > 3)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: () => setState(() => _showAll = !_showAll),
                          child: Text(_showAll ? 'Show less' : 'Show all ${planned.length}'),
                        ),
                      ),
                  ],
                ],
                if (nearby.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  const Text('NEAR YOU - WORTH A VISIT', style: _capsStyle),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 96,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: nearby.length > 6 ? 6 : nearby.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (_, i) => _nearbyCard(nearby[i]),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static const _capsStyle =
      TextStyle(fontSize: 10.5, letterSpacing: 1.1, fontWeight: FontWeight.w800, color: AppColors.muted);

  /// The title strip, with what is left of the day beside it.
  Widget _header(Map<String, dynamic>? data, List<Map<String, dynamic>> planned) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFEAF1FF), Color(0xFFF3F8FF)],
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              gradient: AppColors.brandGradient,
              boxShadow: const [BoxShadow(color: Color(0x331A56DB), blurRadius: 10, offset: Offset(0, 4))],
            ),
            child: const Icon(Icons.alt_route_rounded, color: Colors.white, size: 21),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Visit next', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                const SizedBox(height: 3),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (planned.isNotEmpty) _chip('${planned.length} left', Icons.flag_rounded, AppColors.primary),
                    if (data?['planned_km'] != null)
                      _chip(_km(data?['planned_km'] as num?), Icons.route_rounded, AppColors.purple),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Use my position again',
            onPressed: _loading ? null : _load,
            icon: _loading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.my_location_rounded),
          ),
        ],
      ),
    );
  }

  Widget _chip(String text, IconData icon, Color colour) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: colour),
            const SizedBox(width: 4),
            Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: colour)),
          ],
        ),
      );

  /// The one to go to now, given room of its own.
  Widget _nextStop(Map<String, dynamic> c) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _open(c),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.primary.withValues(alpha: 0.1), AppColors.sky.withValues(alpha: 0.04)],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(20)),
                  child: const Text('NEXT STOP',
                      style: TextStyle(
                          color: Colors.white, fontSize: 9.5, letterSpacing: 0.8, fontWeight: FontWeight.w900)),
                ),
                const Spacer(),
                Text(_km(c['leg_km'] as num?),
                    style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.primary)),
              ],
            ),
            const SizedBox(height: 8),
            Text('${c['name']}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15.5)),
            const SizedBox(height: 3),
            Row(
              children: [
                const Icon(Icons.location_on_outlined, size: 13, color: AppColors.muted),
                const SizedBox(width: 3),
                Expanded(
                  child: Text(
                    [if (c['address'] != null) c['address'], if (c['route'] != null) c['route']].join(' - '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _open(c),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    icon: const Icon(Icons.storefront_rounded, size: 18),
                    label: const Text('Open'),
                  ),
                ),
                if (c['lat'] != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => openDirections(c['lat'] as num, c['lng'] as num),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      icon: const Icon(Icons.directions_rounded, size: 18),
                      label: const Text('Directions'),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// The stops after the next one, as a short numbered trail.
  Widget _stopRow(Map<String, dynamic> c) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _open(c),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(9),
              ),
              alignment: Alignment.center,
              child: Text('${c['sequence']}',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppColors.primary)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${c['name']}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                  Text([if (c['address'] != null) c['address'], if (c['route'] != null) c['route']].join(' - '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Text(_km(c['leg_km'] as num?),
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: AppColors.text)),
            if (c['lat'] != null)
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Directions',
                icon: const Icon(Icons.directions_rounded, size: 19, color: AppColors.primary),
                onPressed: () => openDirections(c['lat'] as num, c['lng'] as num),
              ),
          ],
        ),
      ),
    );
  }

  /// Customers close by that nobody has seen for a while.
  Widget _nearbyCard(Map<String, dynamic> c) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _open(c),
      child: Container(
        width: 190,
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: AppColors.success.withValues(alpha: 0.07),
          border: Border.all(color: AppColors.success.withValues(alpha: 0.18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.storefront_rounded, size: 16, color: AppColors.success),
                const Spacer(),
                Text(_km(c['distance_km'] as num?),
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppColors.success)),
              ],
            ),
            const SizedBox(height: 6),
            Text('${c['name']}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
            const SizedBox(height: 2),
            Expanded(
              child: Text('${c['reason'] ?? ''}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: AppColors.muted)),
            ),
          ],
        ),
      ),
    );
  }
}
