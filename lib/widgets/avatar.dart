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
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [Color(0xFF4C7BF4), Color(0xFF7C5CFC)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Text(profile.name.isNotEmpty ? profile.name[0].toUpperCase() : '?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: size * 0.4)),
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
    if (!border) return child;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
      child: child,
    );
  }
}
