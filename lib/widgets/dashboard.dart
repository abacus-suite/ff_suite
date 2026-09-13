import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/theme.dart';
import 'map.dart';

/// Blue banner with the brand tagline and a walking-rep illustration.
class BrandBanner extends StatelessWidget {
  const BrandBanner({super.key, required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 132,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFFDCEBFF), Color(0xFFEAF6FF), Color(0xFFE6FAF6)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: 4,
            bottom: 0,
            child: Opacity(
              opacity: 0.85,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Icon(Icons.directions_walk_rounded, size: 78, color: AixoloColors.primary),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 46),
                    child: Icon(Icons.location_on_rounded, size: 34, color: AixoloColors.sky.withValues(alpha: 0.9)),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 130, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(subtitle, style: const TextStyle(color: AixoloColors.muted, fontSize: 13)),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, height: 1.15, color: AixoloColors.text),
                ),
                const SizedBox(height: 8),
                Container(width: 34, height: 3, color: AixoloColors.teal),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Big tappable action card (Check In / Check Out).
class ActionCard extends StatelessWidget {
  const ActionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.busy = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.55 : 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: busy ? null : onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(18)),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: color,
                child: busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Icon(icon, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: color)),
                    Text(subtitle, style: const TextStyle(fontSize: 11, color: AixoloColors.muted), maxLines: 2),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Card header: icon + title + optional trailing (View All / period picker).
class CardHeader extends StatelessWidget {
  const CardHeader({super.key, required this.icon, required this.title, this.color = AixoloColors.primary, this.trailing});

  final IconData icon;
  final String title;
  final Color color;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// "Today" selector used on the dashboard cards.
class PeriodSelector extends StatelessWidget {
  const PeriodSelector({super.key, required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  static const labels = {'today': 'Today', 'week': 'This week', 'month': 'This month'};

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      initialValue: value,
      onSelected: onChanged,
      itemBuilder: (_) => [
        for (final entry in labels.entries) PopupMenuItem(value: entry.key, child: Text(entry.value)),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(border: Border.all(color: AixoloColors.border), borderRadius: BorderRadius.circular(20)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(labels[value] ?? 'Today', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            const Icon(Icons.expand_more_rounded, size: 16),
          ],
        ),
      ),
    );
  }
}

/// Ranked row with a coloured progress bar (top moved products).
class RankedBar extends StatelessWidget {
  const RankedBar({
    super.key,
    required this.rank,
    required this.label,
    required this.value,
    required this.share,
    required this.color,
  });

  final int rank;
  final String label;
  final String value;
  final double share;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: color.withValues(alpha: 0.14),
            child: Text('$rank', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                    ),
                    Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: share.clamp(0, 1).toDouble(),
                    minHeight: 6,
                    backgroundColor: AixoloColors.border,
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Small non-interactive map showing the travelled route.
class RouteMiniMap extends StatelessWidget {
  const RouteMiniMap({super.key, required this.points, this.height = 130});

  final List<LatLng> points;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return Container(
        height: height,
        decoration: BoxDecoration(color: AixoloColors.background, borderRadius: BorderRadius.circular(14)),
        child: const Center(child: Text('No movement yet', style: TextStyle(color: AixoloColors.muted, fontSize: 12))),
      );
    }
    return SizedBox(
      height: height,
      child: AixoloMap(
        borderRadius: BorderRadius.circular(14),
        fitPoints: points,
        center: points.first,
        interactive: false,
        controls: false,
        padding: const EdgeInsets.all(24),
        children: [
          PolylineLayer(polylines: travelPath(points)),
          MarkerLayer(markers: [
            Marker(point: points.first, child: const Icon(Icons.trip_origin_rounded, color: AixoloColors.success, size: 18)),
            Marker(
              point: points.last,
              width: MapPin.size.width,
              height: MapPin.size.height,
              alignment: Alignment.topCenter,
              child: const MapPin(color: AixoloColors.danger, icon: Icons.navigation_rounded),
            ),
          ]),
        ],
      ),
    );
  }
}
