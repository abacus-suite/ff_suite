import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'avatar.dart';

/// The pieces the home screen is built from.
///
/// They are kept together because they share one visual language - soft
/// gradient grounds, 20px corners, a coloured icon chip - and because the home
/// screen is the one place in the app where the design does more than list
/// records.

/// The greeting row: logo, who you are, the bell, the avatar.
class HomeHeader extends StatelessWidget {
  const HomeHeader({
    super.key,
    required this.name,
    required this.bell,
    this.onAvatar,
  });

  final String name;
  final Widget bell;
  final VoidCallback? onAvatar;

  /// Morning, afternoon or evening, as the person would say it.
  static String greeting([DateTime? now]) {
    final hour = (now ?? DateTime.now()).hour;
    if (hour < 12) return 'Good Morning,';
    if (hour < 17) return 'Good Afternoon,';
    return 'Good Evening,';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/images/aixolo_logo.png',
                height: 30, fit: BoxFit.contain),
            const SizedBox(height: 2),
            const Text('FIELD SALES, SIMPLIFIED',
                style: TextStyle(
                    fontSize: 7.5,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w700,
                    color: AixoloColors.muted)),
          ],
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(greeting(),
                  style:
                      const TextStyle(fontSize: 12, color: AixoloColors.muted)),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800)),
                  ),
                  const Text(' 👋', style: TextStyle(fontSize: 14)),
                ],
              ),
              const Text("Let's make today count!",
                  style: TextStyle(fontSize: 11, color: AixoloColors.muted)),
            ],
          ),
        ),
        const SizedBox(width: 4),
        bell,
        GestureDetector(
          onTap: onAvatar,
          child: const MyAvatar(size: 44),
        ),
      ],
    );
  }
}

/// The banner across the top: a line about the work, and a way in.
class HeroBanner extends StatelessWidget {
  const HeroBanner(
      {super.key, required this.onExplore, required this.routeLabel});

  final VoidCallback onExplore;
  final String routeLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 168,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          colors: [Color(0xFFDCEBFF), Color(0xFFEAF3FF), Color(0xFFE8F7F1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          // The scenery behind the words, drawn rather than shipped as an image.
          Positioned.fill(child: CustomPaint(painter: _BannerScenery())),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('ON THE MOVE',
                    style: TextStyle(
                        fontSize: 9.5,
                        letterSpacing: 1.6,
                        fontWeight: FontWeight.w800,
                        color: AixoloColors.muted)),
                const SizedBox(height: 6),
                const Text('Stronger Sales',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                        color: AixoloColors.text)),
                const Text('Brighter Tomorrow',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                        color: AixoloColors.sky)),
                const SizedBox(height: 6),
                const Text('More Visits · More Opportunities · More Growth',
                    style:
                        TextStyle(fontSize: 10.5, color: AixoloColors.muted)),
                const Spacer(),
                InkWell(
                  onTap: onExplore,
                  borderRadius: BorderRadius.circular(30),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(30),
                      gradient: AixoloColors.brandGradient,
                      boxShadow: [
                        BoxShadow(
                            color: AixoloColors.primary.withValues(alpha: 0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 5)),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Explore $routeLabel',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 13)),
                        const SizedBox(width: 6),
                        const Icon(Icons.arrow_forward_rounded,
                            color: Colors.white, size: 16),
                      ],
                    ),
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

/// Hills, a sun and a dotted route: enough of a scene without an asset.
class _BannerScenery extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final hill = Paint()
      ..color = const Color(0xFFBFE3D0).withValues(alpha: 0.55);
    final path = Path()
      ..moveTo(size.width * 0.45, size.height)
      ..quadraticBezierTo(size.width * 0.62, size.height * 0.52,
          size.width * 0.8, size.height * 0.78)
      ..quadraticBezierTo(
          size.width * 0.9, size.height * 0.92, size.width, size.height * 0.8)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, hill);

    canvas.drawCircle(Offset(size.width * 0.86, size.height * 0.22), 20,
        Paint()..color = const Color(0xFFFFD79B).withValues(alpha: 0.8));

    // The dotted road the pin sits on.
    final road = Paint()
      ..color = AixoloColors.primary.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (double t = 0; t < 1; t += 0.06) {
      final start = _roadPoint(size, t);
      final end = _roadPoint(size, math.min(t + 0.03, 1));
      canvas.drawLine(start, end, road);
    }
    canvas.drawCircle(
        _roadPoint(size, 1), 5, Paint()..color = const Color(0xFFE5484D));
  }

  Offset _roadPoint(Size size, double t) {
    final x = size.width * (0.6 + 0.32 * t);
    final y = size.height * (0.92 - 0.55 * t * t);
    return Offset(x, y);
  }

  @override
  bool shouldRepaint(_BannerScenery oldDelegate) => false;
}

/// Check in / check out, side by side.
class PunchTile extends StatelessWidget {
  const PunchTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.hint,
    required this.icon,
    required this.colour,
    required this.enabled,
    required this.onTap,
    this.busy = false,
  });

  final String title;
  final String subtitle;
  final String hint;
  final IconData icon;
  final Color colour;
  final bool enabled;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: InkWell(
        onTap: enabled && !busy ? onTap : null,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              colors: [
                colour.withValues(alpha: 0.16),
                colour.withValues(alpha: 0.05)
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: colour.withValues(alpha: 0.18)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration:
                        BoxDecoration(color: colour, shape: BoxShape.circle),
                    child: busy
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : Icon(icon, color: Colors.white, size: 22),
                  ),
                  const Spacer(),
                  Container(
                    width: 26,
                    height: 26,
                    decoration:
                        BoxDecoration(color: colour, shape: BoxShape.circle),
                    child: const Icon(Icons.chevron_right_rounded,
                        color: Colors.white, size: 18),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 16)),
              Text(subtitle,
                  style:
                      const TextStyle(fontSize: 12, color: AixoloColors.muted)),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.place_rounded, size: 11, color: colour),
                  const SizedBox(width: 3),
                  Flexible(
                    child: Text(hint,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 10.5, color: AixoloColors.muted)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One of the four counters under "Today Summary".
class SummaryTile extends StatelessWidget {
  const SummaryTile({
    super.key,
    required this.icon,
    required this.colour,
    required this.value,
    required this.label,
    required this.percent,
  });

  final IconData icon;
  final Color colour;
  final int value;
  final String label;
  final double percent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
                color: colour.withValues(alpha: 0.16), shape: BoxShape.circle),
            child: Icon(icon, color: colour, size: 18),
          ),
          const SizedBox(height: 8),
          Text('$value',
              style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w900, height: 1)),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: AixoloColors.muted)),
          const SizedBox(height: 8),
          Row(
            children: [
              Text('${(percent * 100).round()}%',
                  style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      color: colour)),
              const SizedBox(width: 4),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: percent.clamp(0, 1),
                    minHeight: 5,
                    backgroundColor: colour.withValues(alpha: 0.15),
                    valueColor: AlwaysStoppedAnimation<Color>(colour),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A headline number with the change against yesterday.
class StatBox extends StatelessWidget {
  const StatBox({
    super.key,
    required this.icon,
    required this.colour,
    required this.label,
    required this.value,
    this.change,
  });

  final IconData icon;
  final Color colour;
  final String label;
  final String value;
  final double? change;

  @override
  Widget build(BuildContext context) {
    final change = this.change;
    final up = (change ?? 0) >= 0;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: const Color(0xFFF7F9FD),
          borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
                color: colour.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(icon, color: colour, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 11, color: AixoloColors.muted)),
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w900)),
              ],
            ),
          ),
          if (change != null)
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  children: [
                    Icon(
                        up
                            ? Icons.trending_up_rounded
                            : Icons.trending_down_rounded,
                        size: 13,
                        color: up ? AixoloColors.success : AixoloColors.danger),
                    const SizedBox(width: 2),
                    Text('${up ? '+' : ''}${change.round()}%',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: up
                                ? AixoloColors.success
                                : AixoloColors.danger)),
                  ],
                ),
                const Text('vs. yesterday',
                    style: TextStyle(fontSize: 9, color: AixoloColors.muted)),
              ],
            ),
        ],
      ),
    );
  }
}

/// One of the pastel shortcuts.
class QuickAction extends StatelessWidget {
  const QuickAction({
    super.key,
    required this.icon,
    required this.label,
    required this.colour,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color colour;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: 76,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: colour.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          children: [
            Icon(icon, color: colour, size: 24),
            const SizedBox(height: 8),
            Text(label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 10.5, fontWeight: FontWeight.w700, height: 1.2)),
          ],
        ),
      ),
    );
  }
}

/// "Keep going" - how the day is running against the target.
class TargetBanner extends StatelessWidget {
  const TargetBanner({
    super.key,
    required this.done,
    required this.target,
    required this.title,
    required this.message,
  });

  final int done;
  final int target;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final ratio = target == 0 ? 0.0 : (done / target).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AixoloColors.border.withValues(alpha: 0.7)),
        boxShadow: const [
          BoxShadow(
              color: Color(0x140F1B3D), blurRadius: 14, offset: Offset(0, 6))
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFF7C5CFC), Color(0xFF4C7BF4)]),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.emoji_events_rounded,
                color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 14)),
                Text(message,
                    maxLines: 2,
                    style: const TextStyle(
                        fontSize: 11.5,
                        color: AixoloColors.muted,
                        height: 1.3)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 46,
            height: 46,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: ratio,
                  strokeWidth: 5,
                  backgroundColor: const Color(0xFFE8EDF8),
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(AixoloColors.primary),
                ),
                Text('${(ratio * 100).round()}%',
                    style: const TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$done / $target',
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 14)),
              const Text('Daily Target',
                  style: TextStyle(fontSize: 10, color: AixoloColors.muted)),
            ],
          ),
        ],
      ),
    );
  }
}

/// A soft line chart with the peak called out, as on the sales card.
class SalesLineChart extends StatelessWidget {
  const SalesLineChart({
    super.key,
    required this.points,
    required this.labels,
    required this.format,
    this.height = 150,
  });

  final List<double> points;
  final List<String> labels;
  final String Function(double value) format;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return SizedBox(
        height: height,
        child: const Center(
          child: Text('No sales yet today',
              style: TextStyle(color: AixoloColors.muted, fontSize: 12)),
        ),
      );
    }
    return SizedBox(
      height: height,
      child: CustomPaint(
        painter:
            _SalesLinePainter(points: points, labels: labels, format: format),
        size: Size.infinite,
      ),
    );
  }
}

class _SalesLinePainter extends CustomPainter {
  _SalesLinePainter(
      {required this.points, required this.labels, required this.format});

  final List<double> points;
  final List<String> labels;
  final String Function(double value) format;

  @override
  void paint(Canvas canvas, Size size) {
    const leftPad = 44.0;
    const bottomPad = 22.0;
    const topPad = 26.0;
    final chart =
        Rect.fromLTRB(leftPad, topPad, size.width, size.height - bottomPad);
    final peak = points.reduce(math.max);
    final scale = peak <= 0 ? 1.0 : peak;

    // The four guide lines and their money labels.
    final grid = Paint()
      ..color = const Color(0xFFEEF2FA)
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = chart.bottom - chart.height * i / 3;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), grid);
      _text(canvas, format(scale * i / 3), Offset(0, y - 6), 9,
          AixoloColors.muted);
    }

    Offset at(int index) {
      final step = points.length == 1 ? 0.0 : chart.width / (points.length - 1);
      final x = chart.left + step * index;
      final y = chart.bottom - (points[index] / scale) * chart.height;
      return Offset(x, y);
    }

    // A smooth line, with the area beneath it washed in.
    final line = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < points.length; i++) {
      final previous = at(i - 1);
      final current = at(i);
      final middle = (previous.dx + current.dx) / 2;
      line.cubicTo(
          middle, previous.dy, middle, current.dy, current.dx, current.dy);
    }
    final area = Path.from(line)
      ..lineTo(at(points.length - 1).dx, chart.bottom)
      ..lineTo(chart.left, chart.bottom)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0x553B82F6), Color(0x083B82F6)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(chart),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = AixoloColors.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );

    // Every hour gets a dot; the best one gets a label.
    final dot = Paint()..color = AixoloColors.primary;
    final ring = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    var best = 0;
    for (var i = 0; i < points.length; i++) {
      if (points[i] > points[best]) best = i;
      canvas.drawCircle(at(i), 3.5, dot);
      canvas.drawCircle(at(i), 3.5, ring);
      if (i < labels.length) {
        _text(canvas, labels[i], Offset(at(i).dx - 14, chart.bottom + 6), 9,
            AixoloColors.muted);
      }
    }
    if (peak > 0) {
      final anchor = at(best);
      final bubble = RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(anchor.dx, anchor.dy - 22), width: 78, height: 30),
        const Radius.circular(8),
      );
      canvas.drawRRect(bubble, Paint()..color = AixoloColors.primary);
      _text(canvas, format(points[best]),
          Offset(bubble.left + 8, bubble.top + 4), 10, Colors.white,
          bold: true);
      if (best < labels.length) {
        _text(canvas, labels[best], Offset(bubble.left + 8, bubble.top + 16),
            8.5, Colors.white70);
      }
      canvas.drawCircle(anchor, 5, dot);
      canvas.drawCircle(anchor, 5, ring);
    }
  }

  void _text(Canvas canvas, String value, Offset at, double size, Color colour,
      {bool bold = false}) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
            fontSize: size,
            color: colour,
            fontWeight: bold ? FontWeight.w800 : FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, at);
  }

  @override
  bool shouldRepaint(_SalesLinePainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.labels != labels;
}
