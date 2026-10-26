import 'package:flutter/material.dart';

/// "Powered by" and the company's own logo. On a dark screen the logo sits on a white chip so it stays readable.
class PoweredBy extends StatelessWidget {
  const PoweredBy({super.key, this.onDark = false, this.height = 26});

  final bool onDark;
  final double height;

  @override
  Widget build(BuildContext context) {
    final logo = Image.asset('assets/images/links4engg_logo.png', height: height, fit: BoxFit.contain);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(
        'POWERED BY',
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 2.6,
          color: onDark ? Colors.white.withValues(alpha: 0.75) : const Color(0xFF64748B),
        ),
      ),
      const SizedBox(height: 7),
      if (onDark)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
          child: logo,
        )
      else
        logo,
    ]);
  }
}
