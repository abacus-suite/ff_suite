import 'package:flutter/material.dart';

import '../core/services.dart';

/// The logged-in person's photo, or their initial on the brand gradient.
class MyAvatar extends StatelessWidget {
  const MyAvatar({super.key, this.size = 44, this.border = false});

  final double size;
  final bool border;

  @override
  Widget build(BuildContext context) {
    final profile = Services.auth.profile!;
    final initial = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: border ? Colors.white.withValues(alpha: 0.22) : null,
        border: border ? Border.all(color: Colors.white, width: 2.2) : null,
        gradient: border
            ? null
            : const LinearGradient(
                colors: [Color(0xFF4C7BF4), Color(0xFF7C5CFC)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
      ),
      child: Text(profile.name.isNotEmpty ? profile.name[0].toUpperCase() : '?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: size * 0.44)),
    );
    final version = profile.photoVersion;
    Widget child = initial;
    if (version != null) {
      child = FutureBuilder<List<Object>>(
        future: Future.wait([Services.api.url('/api/v1/me/photo?size=${size > 80 ? 512 : 128}&v=$version'),
          Services.api.authHeaders()]),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return initial;
          return ClipOval(
            child: Image.network(
              snapshot.data![0] as String,
              headers: snapshot.data![1] as Map<String, String>,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => initial,
            ),
          );
        },
      );
    }
    if (!border || version == null) return child;
    return Container(
      padding: const EdgeInsets.all(2.5),
      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
      child: child,
    );
  }
}
