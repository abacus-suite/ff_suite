import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/dashboard.dart';

/// The pieces of the new home screen: the check-in hero, the small sales and
/// product cards that sit side by side, the travel strip and the next visits.

/// The first thing on the screen: whether the day has started, and the one
/// button that starts or ends it, with today's target beside it.
class CheckInHero extends StatelessWidget {
  const CheckInHero({
    super.key,
    required this.punchedIn,
    required this.since,
    required this.worked,
    required this.target,
    required this.busy,
    required this.onPunch,
    this.routeLabel = 'Today',
  });

  final bool punchedIn;
  final String since;
  final String worked;

  /// How many visits are planned for today; 0 hides the badge.
  final int target;
  final bool busy;
  final VoidCallback onPunch;
  final String routeLabel;

  @override
  Widget build(BuildContext context) {
    final green = punchedIn;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: green
              ? const [Color(0xFFE6F7EE), Color(0xFFDDF3FF)]
              : const [Color(0xFFDCEBFF), Color(0xFFE9F7FF)],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _pill(
                  green ? 'ON DUTY · SINCE $since' : 'NOT CHECKED IN TODAY',
                  green ? AppColors.success : AppColors.muted,
                ),
              ),
              if (target > 0) _targetBadge(),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            green ? 'Your Field Day\nis Running' : 'Ready to Start\nYour Field Day?',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, height: 1.15, color: AppColors.text),
          ),
          const SizedBox(height: 6),
          Text(
            green
                ? 'Worked $worked so far. Keep going and close the day when you finish.'
                : 'Track visits, meet customers and create more opportunities.',
            style: const TextStyle(fontSize: 12.5, color: AppColors.muted, height: 1.35),
          ),
          const SizedBox(height: 14),
          _button(green),
        ],
      ),
    );
  }

  Widget _pill(String text, Color colour) => Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(color: const Color(0xCCFFFFFF), borderRadius: BorderRadius.circular(20)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: colour, shape: BoxShape.circle)),
              const SizedBox(width: 7),
              Flexible(
                child: Text(text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.4, color: AppColors.text)),
              ),
            ],
          ),
        ),
      );

  Widget _targetBadge() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 10, offset: Offset(0, 4))],
        ),
        child: Column(
          children: [
            const Text("Today's Target", style: TextStyle(fontSize: 10, color: AppColors.muted)),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.adjust_rounded, size: 16, color: AppColors.danger),
                const SizedBox(width: 5),
                Text('$target',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.text)),
              ],
            ),
            const Text('Visits', style: TextStyle(fontSize: 9.5, color: AppColors.muted)),
          ],
        ),
      );

  Widget _button(bool green) => SizedBox(
        height: 54,
        child: FilledButton(
          onPressed: busy ? null : onPunch,
          style: FilledButton.styleFrom(
            backgroundColor: green ? AppColors.danger : AppColors.primary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            padding: const EdgeInsets.symmetric(horizontal: 16),
          ),
          child: busy
              ? const SizedBox(
                  width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Row(
                  children: [
                    Icon(green ? Icons.stop_circle_rounded : Icons.play_circle_fill_rounded, size: 26),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(green ? 'Check Out' : 'Check In',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                          Text(green ? 'End your day' : 'Start your day now',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_rounded, size: 20),
                  ],
                ),
        ),
      );
}

/// A small card with a title, an optional action, and any body.
class MiniCard extends StatelessWidget {
  const MiniCard({super.key, required this.icon, required this.title, required this.child, this.action, this.onTap});

  final IconData icon;
  final String title;
  final Widget child;
  final Widget? action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                  ),
                  if (action != null) action!,
                ],
              ),
              const SizedBox(height: 10),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

/// The day's sales in one glance: the total, how it compares, and small bars.
class SalesGlance extends StatelessWidget {
  const SalesGlance({super.key, required this.amount, required this.currency, required this.change, required this.bars,
    required this.compareWith});

  final num amount;
  final String? currency;
  final double? change;
  final List<double> bars;
  final String compareWith;

  @override
  Widget build(BuildContext context) {
    final up = (change ?? 0) >= 0;
    final peak = bars.isEmpty ? 0.0 : bars.reduce((a, b) => a > b ? a : b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(fmtMoney(amount, currency),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.text)),
        const SizedBox(height: 4),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: (up ? AppColors.success : AppColors.danger).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                      size: 11, color: up ? AppColors.success : AppColors.danger),
                  Text('${(change ?? 0).abs().toStringAsFixed(0)}%',
                      style: TextStyle(
                          fontSize: 10.5, fontWeight: FontWeight.w800, color: up ? AppColors.success : AppColors.danger)),
                ],
              ),
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text('vs $compareWith',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10.5, color: AppColors.muted)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 46,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final value in bars)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1.5),
                    child: Container(
                      height: peak == 0 ? 4 : (6 + 40 * (value / peak)),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: value == peak && peak > 0 ? 0.85 : 0.28),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// What moved most, as a short bar list.
class TopProducts extends StatelessWidget {
  const TopProducts({super.key, required this.rows});

  final List<Map<String, dynamic>> rows;

  static const _colours = [AppColors.primary, AppColors.success, AppColors.warning, AppColors.purple, AppColors.sky];

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Text('Nothing sold yet', style: TextStyle(color: AppColors.muted, fontSize: 12)),
      );
    }
    final peak = rows
        .map((r) => ((r['qty'] as num?) ?? 0).toDouble())
        .fold<double>(0, (a, b) => a > b ? a : b);
    return Column(
      children: [
        for (final (i, row) in rows.take(4).indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${row['name']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: peak == 0 ? 0 : ((row['qty'] as num?) ?? 0) / peak,
                          minHeight: 6,
                          backgroundColor: AppColors.border,
                          color: _colours[i % _colours.length],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(fmtQty((row['qty'] as num?) ?? 0),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
      ],
    );
  }
}

/// Distance covered today, with the day's path beside it.
class TravelStrip extends StatelessWidget {
  const TravelStrip({super.key, required this.km, required this.change, required this.points, this.onOpen});

  final num km;
  final double? change;
  final List<LatLng> points;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final up = (change ?? 0) >= 0;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: SizedBox(
          height: 108,
          child: Row(
            children: [
              Expanded(
                flex: 5,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.route_rounded, size: 18, color: AppColors.primary),
                          SizedBox(width: 6),
                          Text('Total Travelled', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text('${km.toStringAsFixed(1)} km',
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppColors.text)),
                      const SizedBox(height: 4),
                      if (change != null)
                        Row(
                          children: [
                            Icon(up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                                size: 12, color: up ? AppColors.success : AppColors.danger),
                            Text('${change!.abs().toStringAsFixed(0)}% ',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: up ? AppColors.success : AppColors.danger)),
                            const Text('vs yesterday', style: TextStyle(fontSize: 11, color: AppColors.muted)),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
              Expanded(
                flex: 4,
                child: SizedBox.expand(child: RouteMiniMap(points: points, height: 108)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
