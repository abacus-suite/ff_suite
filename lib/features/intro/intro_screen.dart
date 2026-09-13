import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// The opening animation: the icon pops in on a pulse, a route draws itself
/// to a pin, the name rises letter by letter, then the app fades in.
/// A tap skips it.
class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key, required this.next});

  final Widget next;

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));
  bool _left = false;

  static const _name = 'Aixolo';

  @override
  void initState() {
    super.initState();
    _c.forward().whenComplete(_go);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _go() {
    if (_left || !mounted) return;
    _left = true;
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 450),
      pageBuilder: (_, __, ___) => widget.next,
      transitionsBuilder: (_, animation, __, child) => FadeTransition(opacity: animation, child: child),
    ));
  }

  /// 0..1 progress of [begin]..[end] (fractions of the whole run), eased.
  double _part(double begin, double end, [Curve curve = Curves.easeOutCubic]) {
    final t = ((_c.value - begin) / (end - begin)).clamp(0.0, 1.0);
    return curve.transform(t);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _go,
      child: Scaffold(
        body: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final pop = _part(0.0, 0.32, Curves.elasticOut);
            final pulse = _part(0.12, 0.62);
            final route = _part(0.30, 0.62, Curves.easeInOut);
            final pin = _part(0.58, 0.72, Curves.easeOutBack);
            final tagline = _part(0.72, 0.88);
            final exit = _part(0.90, 1.0, Curves.easeIn);
            return Opacity(
              opacity: 1 - exit * 0.35,
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF0B3AA8), Color(0xFF1A56DB), Color(0xFF14B8C8)],
                  ),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Soft rings spreading from the icon.
                    for (var i = 0; i < 3; i++)
                      Builder(builder: (_) {
                        final t = ((pulse - i * 0.18) / (1 - i * 0.18)).clamp(0.0, 1.0);
                        return Positioned(
                          top: MediaQuery.of(context).size.height * 0.30 - 40 - 110 * t,
                          child: Container(
                            width: 120 + 220 * t,
                            height: 120 + 220 * t,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white.withValues(alpha: 0.25 * (1 - t)), width: 2),
                            ),
                          ),
                        );
                      }),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Spacer(flex: 3),
                        Transform.rotate(
                          angle: (1 - pop) * -0.5,
                          child: Transform.scale(
                            scale: 0.2 + 0.8 * pop,
                            child: Container(
                              width: 118,
                              height: 118,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(32),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.22),
                                    blurRadius: 30,
                                    offset: const Offset(0, 14),
                                  ),
                                ],
                              ),
                              child: Image.asset('assets/images/app_icon.png', fit: BoxFit.contain),
                            ),
                          ),
                        ),
                        const SizedBox(height: 26),
                        // A route drawing itself, ending in a dropped pin.
                        SizedBox(
                          width: 220,
                          height: 46,
                          child: CustomPaint(painter: _RoutePainter(route, pin)),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (var i = 0; i < _name.length; i++)
                              Builder(builder: (_) {
                                final t = _part(0.34 + i * 0.05, 0.56 + i * 0.05, Curves.easeOutBack);
                                return Opacity(
                                  opacity: t.clamp(0.0, 1.0),
                                  child: Transform.translate(
                                    offset: Offset(0, 28 * (1 - t)),
                                    child: Text(
                                      _name[i],
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 46,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 1.5,
                                        height: 1,
                                      ),
                                    ),
                                  ),
                                );
                              }),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Opacity(
                          opacity: tagline,
                          child: Transform.translate(
                            offset: Offset(0, 10 * (1 - tagline)),
                            child: Text(
                              'FIELD SALES, SIMPLIFIED',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.9),
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 3.2,
                              ),
                            ),
                          ),
                        ),
                        const Spacer(flex: 4),
                        Opacity(
                          opacity: tagline * 0.7,
                          child: const Padding(
                            padding: EdgeInsets.only(bottom: 34),
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _RoutePainter extends CustomPainter {
  _RoutePainter(this.progress, this.pin);

  final double progress;
  final double pin;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(6, size.height - 8)
      ..cubicTo(size.width * 0.28, size.height * 0.05, size.width * 0.52, size.height * 1.1, size.width - 26,
          size.height * 0.45);
    final metric = path.computeMetrics().first;
    final drawn = metric.extractPath(0, metric.length * progress);
    // Dashed look: draw the extracted path in short pieces.
    final dash = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (final m in drawn.computeMetrics()) {
      for (double d = 0; d < m.length; d += 12) {
        canvas.drawPath(m.extractPath(d, math.min(d + 6, m.length)), dash);
      }
    }
    canvas.drawCircle(Offset(6, size.height - 8), 5 * math.min(1, progress * 4), Paint()..color = Colors.white);
    if (pin > 0) {
      final tip = metric.getTangentForOffset(metric.length)!.position;
      canvas.save();
      canvas.translate(tip.dx, tip.dy - 18 * (1 - pin));
      canvas.scale(pin);
      final head = Paint()..color = const Color(0xFFFF4D4F);
      final pinPath = Path()
        ..moveTo(0, 0)
        ..cubicTo(-12, -14, -12, -30, 0, -30)
        ..cubicTo(12, -30, 12, -14, 0, 0);
      canvas.drawPath(pinPath, head);
      canvas.drawCircle(const Offset(0, -20), 4.5, Paint()..color = Colors.white);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _RoutePainter old) => old.progress != progress || old.pin != pin;
}

/// Keeps the theme import used for callers that want the brand colours.
const introBrand = AixoloColors.primary;
