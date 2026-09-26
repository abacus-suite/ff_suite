import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../core/theme.dart';

/// Pins that group themselves while the map is far out and come apart as it is
/// zoomed in, the way people expect a map of hundreds of customers to behave.
///
/// Points are placed on the world pixel grid of the current zoom and gathered
/// into square cells, so the grouping follows the zoom without asking the
/// server for anything.
class MapCluster {
  MapCluster(this.centre, this.items);

  final LatLng centre;
  final List<Map<String, dynamic>> items;

  bool get isSingle => items.length == 1;
}

/// Size of a cell on screen; bigger means fewer, fatter bubbles.
const _cellPixels = 92.0;

List<MapCluster> clusterPoints(
  List<Map<String, dynamic>> rows,
  double zoom, {
  String latKey = 'lat',
  String lngKey = 'lng',
}) {
  if (rows.isEmpty) return const [];
  final scale = 256 * math.pow(2, zoom).toDouble();
  final cells = <String, List<Map<String, dynamic>>>{};
  for (final row in rows) {
    final lat = (row[latKey] as num?)?.toDouble();
    final lng = (row[lngKey] as num?)?.toDouble();
    if (lat == null || lng == null) continue;
    final x = (lng + 180) / 360 * scale;
    final sin = math.sin(lat * math.pi / 180).clamp(-0.9999, 0.9999);
    final y = (0.5 - math.log((1 + sin) / (1 - sin)) / (4 * math.pi)) * scale;
    final key = '${(x / _cellPixels).floor()}:${(y / _cellPixels).floor()}';
    cells.putIfAbsent(key, () => []).add(row);
  }
  return [
    for (final group in cells.values)
      MapCluster(
        LatLng(
          group.map((r) => (r[latKey] as num).toDouble()).reduce((a, b) => a + b) / group.length,
          group.map((r) => (r[lngKey] as num).toDouble()).reduce((a, b) => a + b) / group.length,
        ),
        group,
      ),
  ];
}

/// The blue bubble with the number of contacts inside it.
class ClusterBubble extends StatelessWidget {
  const ClusterBubble({super.key, required this.count, this.onTap, this.colour = AppColors.primary});

  final int count;
  final VoidCallback? onTap;
  final Color colour;

  /// Bubbles grow with what they hold, so a big group reads as a big group.
  static double sizeFor(int count) =>
      count >= 100 ? 62 : (count >= 50 ? 56 : (count >= 20 ? 50 : (count >= 10 ? 45 : 40)));

  @override
  Widget build(BuildContext context) {
    final size = sizeFor(count);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colour,
          border: Border.all(color: colour.withValues(alpha: 0.28), width: 4),
          boxShadow: [BoxShadow(color: colour.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 3))],
        ),
        alignment: Alignment.center,
        child: Text(
          count > 100 ? '100+' : '$count',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: count > 100 ? 13 : 14,
          ),
        ),
      ),
    );
  }
}
