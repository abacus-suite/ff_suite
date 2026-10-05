import 'package:flutter/material.dart';

import '../core/theme.dart';

/// A soft light that sweeps across whatever is inside while it waits for its data.
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child});

  final Widget child;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        child: widget.child,
        builder: (context, child) => ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (rect) {
            final x = -1.0 + 3.0 * _c.value;
            return LinearGradient(
              begin: Alignment(x - 1, -0.3),
              end: Alignment(x + 1, 0.3),
              colors: const [Color(0xFFE6EBF3), Color(0xFFF7F9FC), Color(0xFFE6EBF3)],
              stops: const [0.25, 0.5, 0.75],
            ).createShader(rect);
          },
          child: child,
        ),
      );
}

/// A grey rounded block: the shape of a line of text, a picture or a figure that is on its way.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.width, this.height = 14, this.radius = 8});

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(color: const Color(0xFFE6EBF3), borderRadius: BorderRadius.circular(radius)),
      );
}

/// One placeholder row in the shape of a list card.
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: const Row(children: [
          SkeletonBox(width: 44, height: 44, radius: 14),
          SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SkeletonBox(width: 150, height: 14),
              SizedBox(height: 9),
              SkeletonBox(height: 11),
              SizedBox(height: 7),
              SkeletonBox(width: 90, height: 11),
            ]),
          ),
          SizedBox(width: 12),
          SkeletonBox(width: 54, height: 18),
        ]),
      );
}

/// What a screen shows while it is loading: placeholder cards that shimmer, as many as fit.
class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.header = true});

  /// A search-bar sized block above the cards.
  final bool header;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) {
          final room = box.hasBoundedHeight ? box.maxHeight : 560.0;
          final rows = ((room - (header ? 70 : 0) - 24) / 84).floor().clamp(1, 8);
          return Shimmer(
            child: ClipRect(
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (header) ...[
                      Container(
                        height: 48,
                        decoration: BoxDecoration(color: const Color(0xFFE6EBF3), borderRadius: BorderRadius.circular(16)),
                      ),
                      const SizedBox(height: 16),
                    ],
                    for (var i = 0; i < rows; i++) const SkeletonCard(),
                  ],
                ),
              ),
            ),
          );
        },
      );
}

/// A coloured bar that fills in as something loads, for in-place refreshes.
class LoadingBar extends StatelessWidget {
  const LoadingBar({super.key});

  @override
  Widget build(BuildContext context) => const ClipRRect(
        child: LinearProgressIndicator(minHeight: 3, color: AppColors.primary, backgroundColor: Color(0xFFE6EBF3)),
      );
}
