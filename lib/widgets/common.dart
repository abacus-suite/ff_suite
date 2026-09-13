import 'package:flutter/material.dart';

import '../core/theme.dart';

class AixoloLogo extends StatelessWidget {
  const AixoloLogo({super.key, this.height = 44});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Image.asset('assets/images/aixolo_logo.png', height: height, fit: BoxFit.contain);
  }
}

/// Soft blue gradient header with a wave at the bottom (as in the brand mock-up).
class WaveHeader extends StatelessWidget {
  const WaveHeader({super.key, required this.child, this.height = 180});

  final Widget child;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: _WaveClipper(),
      child: Container(
        height: height + MediaQuery.of(context).padding.top,
        decoration: const BoxDecoration(gradient: AixoloColors.headerGradient),
        padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 12, 20, 36),
        child: child,
      ),
    );
  }
}

class _WaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final w = size.width, h = size.height;
    return Path()
      ..lineTo(0, h - 26)
      ..quadraticBezierTo(w * 0.25, h, w * 0.52, h - 18)
      ..quadraticBezierTo(w * 0.8, h - 36, w, h - 6)
      ..lineTo(w, 0)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.icon, required this.label, required this.value, required this.color, this.onTap});

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(18)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: color.withValues(alpha: 0.18),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 8),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: AixoloColors.text)),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: AixoloColors.muted)),
          ],
        ),
      ),
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, required this.child, this.action});

  final String title;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
                if (action != null) action!,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

const _statusStyles = <String, (String, Color)>{
  'planned': ('Planned', AixoloColors.primary),
  'pending': ('Pending', AixoloColors.primary),
  'visited': ('Visited', AixoloColors.success),
  'done': ('Visited', AixoloColors.success),
  'ongoing': ('At client', AixoloColors.sky),
  'missed': ('Missed', AixoloColors.danger),
  'cancelled': ('Cancelled', AixoloColors.warning),
  'skipped': ('Not planned', AixoloColors.muted),
  'approved': ('Approved', AixoloColors.success),
  'submitted': ('To approve', AixoloColors.primary),
  'rejected': ('Rejected', AixoloColors.danger),
  'filled': ('Filled', AixoloColors.success),
  'collected': ('With you', AixoloColors.warning),
  'received': ('Received', AixoloColors.success),
  'quoted': ('Sent to distributor', AixoloColors.primary),
  'partial': ('Partly sent', AixoloColors.warning),
  'supplied': ('Supplied', AixoloColors.success),
  'required': ('Required', AixoloColors.danger),
};

class StatusBadge extends StatelessWidget {
  const StatusBadge(this.status, {super.key, this.label});

  final String status;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final style = _statusStyles[status] ?? (status, AixoloColors.muted);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: style.$2.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(label ?? style.$1, style: TextStyle(color: style.$2, fontWeight: FontWeight.w700, fontSize: 11)),
    );
  }
}

class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
    this.gradient = AixoloColors.brandGradient,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;
  final Gradient gradient;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    return Opacity(
      opacity: enabled ? 1 : 0.6,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: AixoloColors.primary.withValues(alpha: 0.25), blurRadius: 12, offset: const Offset(0, 5))],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: enabled ? onPressed : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (busy)
                    const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  else if (icon != null)
                    Icon(icon, color: Colors.white, size: 20),
                  if (busy || icon != null) const SizedBox(width: 8),
                  Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class EmptyView extends StatelessWidget {
  const EmptyView({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
      child: Column(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: AixoloColors.primary.withValues(alpha: 0.08),
            child: Icon(icon, color: AixoloColors.primary, size: 30),
          ),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(color: AixoloColors.muted)),
        ],
      ),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Icon(Icons.cloud_off_rounded, color: AixoloColors.muted, size: 40),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          TextButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}

String lastVisitLabel(Map<String, dynamic> client) {
  final days = client['days_since_visit'] as int?;
  if (days == null) return 'Never visited';
  final when = days <= 0 ? 'Today' : days == 1 ? 'Yesterday' : '$days days ago';
  final by = (client['last_visit_by'] as Map?)?['name'];
  return by != null ? '$when · $by' : when;
}
