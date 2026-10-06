import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/dashboard.dart';

/// The three wide cards under the day's summary: what was sold, what moved,
/// and how far the person travelled.

/// The header every one of these cards wears: an icon tile, a title with a
/// line under it, and whatever the card puts on the right.
class CardHead extends StatelessWidget {
  const CardHead({super.key, required this.icon, required this.title, required this.subtitle, required this.tint, this.trailing});

  final IconData icon;
  final String title;
  final String subtitle;
  final Color tint;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: tint.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: tint, size: 22),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: AppColors.text)),
              const SizedBox(height: 1),
              Text(subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ],
    );
  }
}

/// A small "Today / This week / This month" chooser, as a soft pill.
class PeriodPill extends StatelessWidget {
  const PeriodPill({super.key, required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  static const _labels = {'today': 'Today', 'week': 'This week', 'month': 'This month'};

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.only(left: 10, right: 2),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isDense: true,
          borderRadius: BorderRadius.circular(14),
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: AppColors.muted),
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.text),
          items: [
            for (final entry in _labels.entries)
              DropdownMenuItem(value: entry.key, child: Text(entry.value)),
          ],
          onChanged: (picked) => picked == null ? null : onChanged(picked),
        ),
      ),
    );
  }
}

/// A figure in its own soft box: an icon tile, the number and what it means.
class FigureBox extends StatelessWidget {
  const FigureBox({super.key, required this.icon, required this.value, required this.label, required this.tint});

  final IconData icon;
  final String value;
  final String label;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: tint.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(11)),
            child: Icon(icon, size: 18, color: tint),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value,
                      maxLines: 1,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.text)),
                ),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// What was sold in the chosen period, with the shape of the day under it.
class SalesCard extends StatelessWidget {
  const SalesCard({
    super.key,
    required this.amount,
    required this.currency,
    required this.change,
    required this.compareWith,
    required this.count,
    required this.points,
    this.second,
    required this.labels,
    required this.period,
    required this.onPeriod,
    required this.subtitle,
    this.onOpen,
  });

  final num amount;
  final String? currency;
  final double? change;
  final String compareWith;
  final int count;
  final List<double> points;

  /// A second line (distributor orders) when there is one; [points] are then the outlet demands.
  final List<double>? second;
  final List<String> labels;
  final String period;
  final ValueChanged<String> onPeriod;
  final String subtitle;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final up = (change ?? 0) >= 0;
    final tone = up ? AppColors.success : AppColors.danger;
    final average = count > 0 ? amount / count : 0;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CardHead(
              icon: Icons.bar_chart_rounded,
              title: switch (period) { 'week' => "Week's Sales", 'month' => "Month's Sales", _ => "Today's Sales" },
              subtitle: subtitle,
              tint: AppColors.primary,
              trailing: PeriodPill(value: period, onChanged: onPeriod),
            ),
            const SizedBox(height: 14),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(fmtMoney(amount, currency),
                  maxLines: 1,
                  style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, height: 1, color: AppColors.text)),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: tone.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(up ? Icons.trending_up_rounded : Icons.trending_down_rounded, size: 15, color: tone),
                      const SizedBox(width: 4),
                      Text('${up ? '+' : '-'}${(change ?? 0).abs().toStringAsFixed(0)}%',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: tone)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text('vs $compareWith',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: AppColors.muted)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FigureBox(
                      icon: Icons.shopping_bag_rounded,
                      value: '$count',
                      label: 'Orders',
                      tint: AppColors.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FigureBox(
                      icon: Icons.sell_rounded,
                      value: fmtMoney(average, currency),
                      label: 'Average Order',
                      tint: AppColors.purple),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(height: 118, child: SalesCurve(values: points, second: second, labels: labels, currency: currency)),
            if (second != null) ...[
              const SizedBox(height: 6),
              const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                SalesKey(color: AppColors.primary, label: 'Outlet demands'),
                SizedBox(width: 16),
                SalesKey(color: Color(0xFFF59E0B), label: 'Distributor orders'),
              ]),
            ],
            if (onOpen != null) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: const Text('Details'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The curve of the period with its dots, the hours along the bottom, and a
/// small flag on the best point.
class SalesCurve extends StatelessWidget {
  const SalesCurve({super.key, required this.values, required this.labels, this.currency, this.second});

  final List<double> values;
  final List<double>? second;
  final List<String> labels;
  final String? currency;

  @override
  Widget build(BuildContext context) {
    if (values.length < 2) {
      return const Center(child: Text('Nothing to chart yet', style: TextStyle(color: AppColors.muted, fontSize: 12)));
    }
    final peak = [...values, ...?second].reduce((a, b) => a > b ? a : b);
    final bestAt = second == null && peak > 0 ? values.indexOf(peak) : -1;
    // Every other label when they would collide.
    final step = labels.length > 7 ? (labels.length / 6).ceil() : 1;
    return LayoutBuilder(
      builder: (_, box) {
        final chartHeight = box.maxHeight - 20;
        return Column(
          children: [
            SizedBox(
              height: chartHeight,
              width: double.infinity,
              child: CustomPaint(
                painter: _CurvePainter(values, second),
                child: peak <= 0 || bestAt < 0
                    ? null
                    : LayoutBuilder(
                        builder: (_, inner) {
                          final x = inner.maxWidth / (values.length - 1) * bestAt;
                          return Stack(
                            children: [
                              Positioned(
                                left: (x - 44).clamp(0, (inner.maxWidth - 88).clamp(0, double.infinity)),
                                top: 0,
                                child: _flag(peak, bestAt),
                              ),
                            ],
                          );
                        },
                      ),
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 14,
              child: Row(
                children: [
                  for (final (i, label) in labels.indexed)
                    Expanded(
                      child: Text(
                        i % step == 0 ? label : '',
                        textAlign: i == 0
                            ? TextAlign.left
                            : (i == labels.length - 1 ? TextAlign.right : TextAlign.center),
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        style: const TextStyle(fontSize: 10, color: AppColors.muted),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _flag(double value, int at) => Container(
        width: 88,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(color: AppColors.text, borderRadius: BorderRadius.circular(10)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(fmtMoney(value, currency),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
            Text(at < labels.length ? labels[at] : '',
                maxLines: 1,
                style: const TextStyle(color: Colors.white70, fontSize: 10.5)),
          ],
        ),
      );
}

class _CurvePainter extends CustomPainter {
  _CurvePainter(this.values, [this.second]);

  final List<double> values;
  final List<double>? second;

  @override
  void paint(Canvas canvas, Size size) {
    final peak = [...values, ...?second].reduce((a, b) => a > b ? a : b);
    final step = size.width / (values.length - 1);
    final grid = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    for (var i = 0; i < values.length; i += (values.length / 6).ceil().clamp(1, 12)) {
      canvas.drawLine(Offset(i * step, 0), Offset(i * step, size.height), grid);
    }
    if (peak <= 0) {
      canvas.drawLine(Offset(0, size.height - 4), Offset(size.width, size.height - 4),
          Paint()
            ..color = AppColors.border
            ..strokeWidth = 3
            ..strokeCap = StrokeCap.round);
      return;
    }
    final points = [
      for (final (i, value) in values.indexed)
        Offset(i * step, size.height - (value / peak) * (size.height - 34) - 6)
    ];
    final line = ui.Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
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
          colors: [Color(0x381A56DB), Color(0x001A56DB)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round
        ..color = AppColors.primary,
    );
    for (final (i, point) in points.indexed) {
      if (values[i] <= 0) continue;
      canvas.drawCircle(point, 4.5, Paint()..color = Colors.white);
      canvas.drawCircle(point, 3, Paint()..color = AppColors.primary);
    }
    final other = second;
    if (other != null && other.length == values.length) {
      const tone = Color(0xFFF59E0B);
      final pts = [
        for (final (i, value) in other.indexed)
          Offset(i * step, size.height - (value / peak) * (size.height - 34) - 6)
      ];
      final path = ui.Path()..moveTo(pts.first.dx, pts.first.dy);
      for (var i = 1; i < pts.length; i++) {
        final from = pts[i - 1];
        final to = pts[i];
        final mid = (from.dx + to.dx) / 2;
        path.cubicTo(mid, from.dy, mid, to.dy, to.dx, to.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6
          ..strokeCap = StrokeCap.round
          ..color = tone,
      );
      for (final (i, point) in pts.indexed) {
        if (other[i] <= 0) continue;
        canvas.drawCircle(point, 4.5, Paint()..color = Colors.white);
        canvas.drawCircle(point, 3, Paint()..color = tone);
      }
    }
  }

  @override
  bool shouldRepaint(_CurvePainter old) => old.values != values || old.second != second;
}

class SalesKey extends StatelessWidget {
  const SalesKey({super.key, required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 14, height: 4, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 11.5, color: AppColors.muted, fontWeight: FontWeight.w600)),
      ]);
}

/// The best selling items of the period, with their picture when there is one.
class TopProductsCard extends StatefulWidget {
  const TopProductsCard({
    super.key,
    required this.rows,
    required this.period,
    required this.onPeriod,
    this.onViewAll,
  });

  final List<Map<String, dynamic>> rows;
  final String period;
  final ValueChanged<String> onPeriod;
  final VoidCallback? onViewAll;

  @override
  State<TopProductsCard> createState() => _TopProductsCardState();
}

class _TopProductsCardState extends State<TopProductsCard> {
  static const _ranks = [AppColors.warning, AppColors.primary, AppColors.success, AppColors.purple, AppColors.sky];

  @override
  Widget build(BuildContext context) {
    final rows = widget.rows;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CardHead(
              icon: Icons.inventory_2_rounded,
              title: 'Top Products',
              subtitle: 'Best performing items',
              tint: AppColors.purple,
              trailing: PeriodPill(value: widget.period, onChanged: widget.onPeriod),
            ),
            const SizedBox(height: 10),
            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 22),
                child: Center(
                  child: Column(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: AppColors.purple.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: const Icon(Icons.inventory_2_outlined, color: AppColors.purple),
                      ),
                      const SizedBox(height: 8),
                      const Text('Nothing sold yet',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      const Text('Products you sell appear here',
                          style: TextStyle(color: AppColors.muted, fontSize: 11.5)),
                    ],
                  ),
                ),
              )
            else
              _table(rows.take(5).toList()),
            if (widget.onViewAll != null) ...[
              const SizedBox(height: 4),
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: widget.onViewAll,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                        child: const Icon(Icons.grid_view_rounded, size: 16, color: AppColors.primary),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text('View All Products',
                            style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.primary, fontSize: 14)),
                      ),
                      const Icon(Icons.chevron_right_rounded, color: AppColors.primary),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// The best sellers as a table: rank, product, units and value.
  Widget _table(List<Map<String, dynamic>> rows) {
    const head = TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.muted, letterSpacing: 0.4);
    Widget cell(Widget child, {int flex = 1, Alignment align = Alignment.centerLeft}) =>
        Expanded(flex: flex, child: Align(alignment: align, child: child));
    return Container(
      decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        Container(
          color: AppColors.background,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(children: [
            cell(const Text('#', style: head), flex: 1),
            cell(const Text('PRODUCT', style: head), flex: 8),
            cell(const Text('UNITS', style: head), flex: 3, align: Alignment.centerRight),
            cell(const Text('VALUE', style: head), flex: 4, align: Alignment.centerRight),
          ]),
        ),
        for (final (i, row) in rows.indexed)
          Container(
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(children: [
              cell(Text('${i + 1}', style: TextStyle(fontWeight: FontWeight.w900, color: _ranks[i % _ranks.length])), flex: 1),
              cell(
                  Text('${row['name']}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  flex: 8),
              cell(Text(fmtQty((row['qty'] as num?) ?? 0), style: const TextStyle(fontWeight: FontWeight.w800)),
                  flex: 3, align: Alignment.centerRight),
              cell(Text(fmtMoney(row['amount'] as num?), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                  flex: 4, align: Alignment.centerRight),
            ]),
          ),
      ]),
    );
  }
}

/// How far the person went today, with the day's path beside it.
class TravelCard extends StatelessWidget {
  const TravelCard({
    super.key,
    required this.km,
    required this.points,
    required this.visits,
    required this.minutes,
    this.onOpen,
    this.onOpenMap,
  });

  final num km;
  final List<LatLng> points;
  final int visits;

  /// Minutes between the first and the last position of the day.
  final int minutes;
  final VoidCallback? onOpen;

  /// The corner button: straight to the map of the day.
  final VoidCallback? onOpenMap;

  String get _travelTime {
    if (minutes <= 0) return '-';
    final hours = minutes ~/ 60;
    return hours > 0 ? '${hours}h ${minutes % 60}m' : '$minutes min';
  }

  String get _speed {
    if (minutes <= 0 || km <= 0) return '-';
    return '${(km / (minutes / 60)).toStringAsFixed(1)} km/h';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 6,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 10, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CardHead(
                        icon: Icons.place_rounded,
                        title: 'Total Travelled',
                        subtitle: 'Distance covered today',
                        tint: AppColors.success,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(km.toStringAsFixed(1),
                              style:
                                  const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: AppColors.text)),
                          const SizedBox(width: 4),
                          const Text('km', style: TextStyle(fontSize: 15, color: AppColors.muted)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _small(Icons.directions_car_rounded, '$visits', 'Visits', AppColors.primary),
                          _divider(),
                          _small(Icons.timer_rounded, _travelTime, 'Travel Time', AppColors.success),
                          _divider(),
                          _small(Icons.speed_rounded, _speed, 'Avg. Speed', AppColors.danger),
                        ],
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
                    RouteMiniMap(points: points, height: double.infinity),
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: onOpenMap ?? onOpen,
                          child: const Padding(
                            padding: EdgeInsets.all(6),
                            child: Icon(Icons.fullscreen_rounded, size: 16, color: AppColors.text),
                          ),
                        ),
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

  Widget _divider() => Container(width: 1, height: 30, color: AppColors.border);

  Widget _small(IconData icon, String value, String label, Color tint) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(color: tint.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(9)),
                child: Icon(icon, size: 15, color: tint),
              ),
              const SizedBox(height: 5),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value,
                    maxLines: 1, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
              ),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10.5, color: AppColors.muted)),
            ],
          ),
        ),
      );
}
