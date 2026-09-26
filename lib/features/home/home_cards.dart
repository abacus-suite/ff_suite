import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/dashboard.dart';

/// The pieces of the new home screen: the check-in hero, the small sales and
/// product cards that sit side by side, the travel strip and the next visits.

/// The first thing on the screen: whether the day has started, and the one
/// button that starts or ends it, with today's target beside it.
class CheckInHero extends StatefulWidget {
  const CheckInHero({
    super.key,
    required this.punchedIn,
    required this.since,
    required this.worked,
    required this.target,
    required this.busy,
    required this.onPunch,
    this.onDutySince,
    this.workedHours = 0,
    this.km = 0,
    this.visits = 0,
    this.travelMinutes = 0,
    this.onOpenDay,
    this.routeLabel = 'Today',
  });

  final bool punchedIn;
  final String since;
  final String worked;

  /// How many visits are planned for today; 0 hides the badge.
  final int target;
  final bool busy;
  final VoidCallback? onPunch;
  final String routeLabel;

  /// When the punch that is still open began; null when the day is not running.
  final DateTime? onDutySince;

  /// Hours already finished today, before the open punch.
  final double workedHours;

  /// The day so far: distance, customers seen and time on the road.
  final num km;
  final int visits;
  final int travelMinutes;

  /// Opens the day's journey when the figures are tapped.
  final VoidCallback? onOpenDay;

  @override
  State<CheckInHero> createState() => _CheckInHeroState();
}

class _CheckInHeroState extends State<CheckInHero> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // While the person is on duty the card counts with them, every second.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.punchedIn && widget.onDutySince != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Duration get _onDuty {
    final since = widget.onDutySince;
    final running = since == null ? Duration.zero : DateTime.now().difference(since);
    return Duration(minutes: (widget.workedHours * 60).round()) +
        (running.isNegative ? Duration.zero : running);
  }

  /// "7h 22m", or the seconds too while the day is short.
  String get _soFar {
    final total = _onDuty;
    if (total.inHours > 0) return '${total.inHours}h ${total.inMinutes % 60}m';
    if (total.inMinutes > 0) return '${total.inMinutes}m ${total.inSeconds % 60}s';
    return '${total.inSeconds}s';
  }

  String get _travelTime {
    final minutes = widget.travelMinutes;
    if (minutes <= 0) return '—';
    return minutes >= 60 ? '${minutes ~/ 60}h ${minutes % 60}m' : '${minutes}m';
  }

  String get _speed {
    if (widget.travelMinutes <= 0 || widget.km <= 0) return '—';
    return '${(widget.km / (widget.travelMinutes / 60)).toStringAsFixed(1)} km/h';
  }

  @override
  Widget build(BuildContext context) {
    final green = widget.punchedIn;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: green
              ? const [Color(0xFFE8F8EF), Color(0xFFE2F1FF)]
              : const [Color(0xFFDCEBFF), Color(0xFFE9F7FF)],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _statusPill(green)),
              if (widget.target > 0) _targetBadge(),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            green ? 'Your Field Day is Running' : 'Ready to Start\nYour Field Day?',
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900, height: 1.2, color: AppColors.text),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(green ? Icons.schedule_rounded : Icons.play_circle_outline_rounded,
                  size: 16, color: AppColors.muted),
              const SizedBox(width: 6),
              Expanded(
                child: green
                    ? Text.rich(
                        TextSpan(
                          children: [
                            const TextSpan(text: 'On duty for '),
                            TextSpan(
                                text: _soFar,
                                style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.text)),
                            const TextSpan(text: ' so far.'),
                          ],
                        ),
                        style: const TextStyle(fontSize: 13, color: AppColors.muted),
                      )
                    : const Text('Track visits, meet customers and create more opportunities.',
                        style: TextStyle(fontSize: 12.5, color: AppColors.muted, height: 1.35)),
              ),
            ],
          ),
          if (green) ...[
            const SizedBox(height: 12),
            _figures(),
          ],
          const SizedBox(height: 12),
          green ? _footRow() : _button(green),
        ],
      ),
    );
  }

  Widget _statusPill(bool green) => Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(color: const Color(0xCCFFFFFF), borderRadius: BorderRadius.circular(20)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                      color: green ? AppColors.success : AppColors.muted, shape: BoxShape.circle)),
              const SizedBox(width: 7),
              Text(green ? 'Checked In' : 'Not checked in today',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.text)),
              if (green) ...[
                Container(
                  width: 1,
                  height: 14,
                  margin: const EdgeInsets.symmetric(horizontal: 9),
                  color: AppColors.border,
                ),
                Text(widget.since,
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.success)),
              ],
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
                Text('${widget.target}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.text)),
              ],
            ),
            const Text('Visits', style: TextStyle(fontSize: 9.5, color: AppColors.muted)),
          ],
        ),
      );

  /// The day so far, in the card itself: distance, visits, time and speed.
  Widget _figures() {
    final cells = <(IconData, String, String, Color)>[
      (Icons.place_rounded, '${widget.km.toStringAsFixed(1)} km', 'Total Travelled', AppColors.success),
      (Icons.directions_car_rounded, '${widget.visits}', 'Visits', AppColors.primary),
      (Icons.timer_rounded, _travelTime, 'Travel Time', AppColors.success),
      (Icons.speed_rounded, _speed, 'Avg. Speed', AppColors.danger),
    ];
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: widget.onOpenDay,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        decoration: BoxDecoration(color: const Color(0xCCFFFFFF), borderRadius: BorderRadius.circular(18)),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, cell) in cells.indexed) ...[
                if (i > 0) Container(width: 1, color: AppColors.border),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                              color: cell.$4.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(11)),
                          child: Icon(cell.$1, size: 17, color: cell.$4),
                        ),
                        const SizedBox(height: 6),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(cell.$2,
                              maxLines: 1,
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                        ),
                        Text(cell.$3,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 10.5, color: AppColors.muted)),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// When the day is running: when it started, and the way to close it.
  Widget _footRow() {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(color: const Color(0xCCFFFFFF), borderRadius: BorderRadius.circular(22)),
            child: Row(
              children: [
                const Icon(Icons.schedule_rounded, size: 16, color: AppColors.muted),
                const SizedBox(width: 7),
                const Text('Check-in', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                const Spacer(),
                Text(widget.since,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppColors.text)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          height: 46,
          child: FilledButton.icon(
            onPressed: widget.busy ? null : widget.onPunch,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            icon: widget.busy
                ? const SizedBox(
                    width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.stop_circle_rounded, size: 20),
            label: const Text('Check Out', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ),
      ],
    );
  }

  Widget _button(bool green) => SizedBox(
        height: 54,
        child: FilledButton(
          onPressed: widget.busy ? null : widget.onPunch,
          style: FilledButton.styleFrom(
            backgroundColor: green ? AppColors.danger : AppColors.primary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            padding: const EdgeInsets.symmetric(horizontal: 16),
          ),
          child: widget.busy
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
  const MiniCard(
      {super.key,
      required this.icon,
      required this.title,
      required this.child,
      this.action,
      this.onTap,
      this.tint = AppColors.primary});

  final IconData icon;
  final String title;
  final Widget child;
  final Widget? action;
  final VoidCallback? onTap;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [tint.withValues(alpha: 0.12), tint.withValues(alpha: 0.03)],
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(9),
                      boxShadow: [
                        BoxShadow(color: tint.withValues(alpha: 0.2), blurRadius: 7, offset: const Offset(0, 3))
                      ],
                    ),
                    child: Icon(icon, size: 16, color: tint),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                  ),
                  if (action != null) action!,
                ],
              ),
            ),
            Padding(padding: const EdgeInsets.fromLTRB(12, 10, 12, 12), child: child),
          ],
        ),
      ),
    );
  }
}

/// The day's money in one glance: the total, how it compares, the number of
/// orders behind it and a soft curve of how the day went.
class SalesGlance extends StatelessWidget {
  const SalesGlance(
      {super.key,
      required this.amount,
      required this.currency,
      required this.change,
      required this.bars,
      required this.compareWith,
      this.count,
      this.labels = const []});

  final num amount;
  final String? currency;
  final double? change;
  final List<double> bars;
  final String compareWith;

  /// How many orders made up the amount; null hides the line.
  final int? count;

  /// The label of each bar, used to name the best one.
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final up = (change ?? 0) >= 0;
    final tone = up ? AppColors.success : AppColors.danger;
    final peak = bars.isEmpty ? 0.0 : bars.reduce((a, b) => a > b ? a : b);
    final bestAt = peak > 0 ? bars.indexOf(peak) : -1;
    final average = (count ?? 0) > 0 ? amount / count! : 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(fmtMoney(amount, currency),
              maxLines: 1,
              style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900, height: 1.1, color: AppColors.text)),
        ),
        const SizedBox(height: 7),
        Wrap(
          spacing: 5,
          runSpacing: 5,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(color: tone.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(9)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(up ? Icons.trending_up_rounded : Icons.trending_down_rounded, size: 12, color: tone),
                  const SizedBox(width: 3),
                  Text('${(change ?? 0).abs().toStringAsFixed(0)}%',
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: tone)),
                ],
              ),
            ),
            Text('vs $compareWith',
                style: const TextStyle(fontSize: 10.5, color: AppColors.muted, height: 1.6)),
          ],
        ),
        const SizedBox(height: 10),
        if (count != null)
          Row(
            children: [
              Expanded(child: _figure(Icons.receipt_long_rounded, '$count', 'orders')),
              Container(width: 1, height: 26, color: AppColors.border),
              Expanded(child: _figure(Icons.sell_rounded, fmtMoney(average, currency), 'average')),
            ],
          ),
        const SizedBox(height: 10),
        SizedBox(
          height: 48,
          width: double.infinity,
          child: bars.every((v) => v == 0)
              ? _flatLine()
              : CustomPaint(painter: _SalesCurve(bars)),
        ),
        if (bestAt >= 0 && bestAt < labels.length) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.star_rounded, size: 13, color: AppColors.warning),
              const SizedBox(width: 4),
              Flexible(
                child: Text('Best ${labels[bestAt]} - ${fmtMoney(peak, currency)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: AppColors.muted, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _figure(IconData icon, String value, String label) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: AppColors.muted),
              const SizedBox(width: 4),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value,
                      maxLines: 1, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
          Text(label, style: const TextStyle(fontSize: 10, color: AppColors.muted)),
        ],
      );

  Widget _flatLine() => Center(
        child: Container(
          height: 4,
          decoration: BoxDecoration(
            color: AppColors.border,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      );
}

/// A soft curve with the area under it filled, drawn from the day's figures.
class _SalesCurve extends CustomPainter {
  _SalesCurve(this.values);

  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final peak = values.reduce((a, b) => a > b ? a : b);
    if (peak <= 0) return;
    final step = size.width / (values.length - 1);
    final points = [
      for (final (i, value) in values.indexed)
        Offset(i * step, size.height - (value / peak) * (size.height - 6) - 3)
    ];
    final line = ui.Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      // A gentle curve between points reads better than a jagged line.
      final previous = points[i - 1];
      final current = points[i];
      final midX = (previous.dx + current.dx) / 2;
      line.cubicTo(midX, previous.dy, midX, current.dy, current.dx, current.dy);
    }
    final area = ui.Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x331A56DB), Color(0x001A56DB)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..shader = const LinearGradient(colors: [AppColors.primary, AppColors.sky])
            .createShader(Offset.zero & size),
    );
    final last = points.last;
    canvas.drawCircle(last, 4.5, Paint()..color = Colors.white);
    canvas.drawCircle(last, 3, Paint()..color = AppColors.primary);
  }

  @override
  bool shouldRepaint(_SalesCurve old) => old.values != values;
}

/// What moved most: the total on top, then each product with a bar behind it.
class TopProducts extends StatelessWidget {
  const TopProducts({super.key, required this.rows});

  final List<Map<String, dynamic>> rows;

  static const _colours = [AppColors.purple, AppColors.primary, AppColors.success, AppColors.warning, AppColors.sky];

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.purple.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.inventory_2_outlined, color: AppColors.purple, size: 20),
            ),
            const SizedBox(height: 8),
            const Text('Nothing sold yet',
                style: TextStyle(color: AppColors.text, fontSize: 12.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            const Text('Products you sell today appear here',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted, fontSize: 10.5)),
          ],
        ),
      );
    }
    final peak = rows.map((r) => ((r['qty'] as num?) ?? 0).toDouble()).fold<double>(0, (a, b) => a > b ? a : b);
    final total = rows.fold<double>(0, (sum, r) => sum + ((r['qty'] as num?) ?? 0).toDouble());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(fmtQty(total),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.text)),
            const SizedBox(width: 4),
            const Padding(
              padding: EdgeInsets.only(bottom: 2),
              child: Text('units', style: TextStyle(fontSize: 11, color: AppColors.muted)),
            ),
            const Spacer(),
            Text('${rows.length} items',
                style: const TextStyle(fontSize: 10.5, color: AppColors.muted, fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 10),
        for (final (i, row) in rows.take(4).indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: Row(
              children: [
                Container(
                  width: 18,
                  height: 18,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _colours[i % _colours.length].withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('${i + 1}',
                      style:
                          TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: _colours[i % _colours.length])),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text('${row['name']}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                          ),
                          const SizedBox(width: 6),
                          Text(fmtQty((row['qty'] as num?) ?? 0),
                              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: peak == 0 ? 0 : ((row['qty'] as num?) ?? 0) / peak,
                          minHeight: 5,
                          backgroundColor: AppColors.border,
                          color: _colours[i % _colours.length],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Distance covered today, with the day's path behind it.
class TravelStrip extends StatelessWidget {
  const TravelStrip({super.key, required this.km, required this.change, required this.points, this.onOpen});

  final num km;
  final double? change;
  final List<LatLng> points;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final up = (change ?? 0) >= 0;
    final tone = up ? AppColors.success : AppColors.danger;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: SizedBox(
          height: 116,
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
                      Row(
                        children: [
                          Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(9),
                              gradient: AppColors.brandGradient,
                            ),
                            child: const Icon(Icons.route_rounded, size: 15, color: Colors.white),
                          ),
                          const SizedBox(width: 7),
                          const Text('Total Travelled',
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(km.toStringAsFixed(1),
                              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: AppColors.text)),
                          const SizedBox(width: 3),
                          const Text('km', style: TextStyle(fontSize: 13, color: AppColors.muted)),
                        ],
                      ),
                      const SizedBox(height: 5),
                      if (change != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: tone.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(up ? Icons.trending_up_rounded : Icons.trending_down_rounded, size: 12, color: tone),
                              const SizedBox(width: 3),
                              Text('${change!.abs().toStringAsFixed(0)}% vs yesterday',
                                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: tone)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Expanded(
                flex: 4,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    RouteMiniMap(points: points, height: 116),
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                        child: const Icon(Icons.open_in_full_rounded, size: 13, color: AppColors.primary),
                      ),
                    ),
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
