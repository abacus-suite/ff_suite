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

/// How close two pins must be on screen to end up in the same bubble.
const _mergePixels = 78.0;

/// Groups points that sit close together on screen at this zoom.
///
/// Points are placed on the world pixel grid of the current zoom and then
/// gathered around the busiest ones, so a bubble never splits in two just
/// because a grid line ran between two shops, and two bubbles never land on
/// top of each other.
List<MapCluster> clusterPoints(
  List<Map<String, dynamic>> rows,
  double zoom, {
  String latKey = 'lat',
  String lngKey = 'lng',
}) {
  if (rows.isEmpty) return const [];
  final scale = 256 * math.pow(2, zoom).toDouble();
  final points = <(Offset, Map<String, dynamic>)>[];
  for (final row in rows) {
    final lat = (row[latKey] as num?)?.toDouble();
    final lng = (row[lngKey] as num?)?.toDouble();
    if (lat == null || lng == null) continue;
    final x = (lng + 180) / 360 * scale;
    final sin = math.sin(lat * math.pi / 180).clamp(-0.9999, 0.9999);
    final y = (0.5 - math.log((1 + sin) / (1 - sin)) / (4 * math.pi)) * scale;
    points.add((Offset(x, y), row));
  }
  if (points.isEmpty) return const [];

  // Buckets of a merge-width each, so every point only looks at its neighbours.
  final buckets = <String, List<int>>{};
  String keyOf(Offset p) => '${(p.dx / _mergePixels).floor()}:${(p.dy / _mergePixels).floor()}';
  for (var i = 0; i < points.length; i++) {
    buckets.putIfAbsent(keyOf(points[i].$1), () => []).add(i);
  }

  final taken = List<bool>.filled(points.length, false);
  final clusters = <MapCluster>[];
  for (var i = 0; i < points.length; i++) {
    if (taken[i]) continue;
    final here = points[i].$1;
    final cellX = (here.dx / _mergePixels).floor();
    final cellY = (here.dy / _mergePixels).floor();
    final members = <Map<String, dynamic>>[];
    var sumX = 0.0;
    var sumY = 0.0;
    var sumLat = 0.0;
    var sumLng = 0.0;
    for (var dx = -1; dx <= 1; dx++) {
      for (var dy = -1; dy <= 1; dy++) {
        for (final j in buckets['${cellX + dx}:${cellY + dy}'] ?? const <int>[]) {
          if (taken[j]) continue;
          if ((points[j].$1 - here).distance > _mergePixels) continue;
          taken[j] = true;
          members.add(points[j].$2);
          sumX += points[j].$1.dx;
          sumY += points[j].$1.dy;
          sumLat += (points[j].$2[latKey] as num).toDouble();
          sumLng += (points[j].$2[lngKey] as num).toDouble();
        }
      }
    }
    if (members.isEmpty) continue;
    // The bubble sits on the middle of what it holds, not on its first pin.
    clusters.add(MapCluster(LatLng(sumLat / members.length, sumLng / members.length), members));
    // Keep the centre in pixels out of the way of rounding: it is only used above.
    sumX;
    sumY;
  }
  return clusters;
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
