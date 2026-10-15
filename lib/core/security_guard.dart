import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../features/auth/login_screen.dart';
import 'services.dart';

/// App-wide rules the office sets in Field Force settings:
/// - log out an app left unused for too long;
/// - while on duty, say loudly when GPS gets switched off.
/// (The phone-clock check is done by the server on every punch and check-in.)
class SecurityGuard with WidgetsBindingObserver {
  SecurityGuard._();

  static final instance = SecurityGuard._();
  static const _lastSeenKey = 'last_seen_at';

  /// False while on duty with location services off.
  final ValueNotifier<bool> gpsOn = ValueNotifier(true);

  StreamSubscription<ServiceStatus>? _gps;
  bool _started = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    try {
      gpsOn.value = await Geolocator.isLocationServiceEnabled();
      _gps = Geolocator.getServiceStatusStream().listen((s) => gpsOn.value = s == ServiceStatus.enabled);
    } catch (_) {
      // Location plugin unavailable (tests, emulators): nothing to watch.
    }
    await _checkIdle();
    await _touch();
  }

  void stop() {
    WidgetsBinding.instance.removeObserver(this);
    _gps?.cancel();
    _gps = null;
    _started = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkIdle().then((_) => _touch());
    } else if (state == AppLifecycleState.paused) {
      _touch();
    }
  }

  Future<void> _touch() => Services.storage.write(_lastSeenKey, DateTime.now().toIso8601String());

  Future<void> _checkIdle() async {
    final profile = Services.auth.profile;
    if (profile == null || profile.idleLogoutHours <= 0) return;
    // Someone on duty is still working, however long since the app was opened.
    if (Services.tracker.active.value) return;
    final raw = await Services.storage.read(_lastSeenKey);
    final last = raw == null ? null : DateTime.tryParse(raw);
    if (last == null || DateTime.now().difference(last) < Duration(hours: profile.idleLogoutHours)) return;
    await Services.outbox.flush();
    if (Services.outbox.pending.value + Services.outbox.failed.value > 0) return; // never lose unsynced work
    stop();
    Services.outbox.stop();
    Services.notifications.stop();
    await Services.queue.clearCache();
    await Services.auth.logout();
    Services.navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(
          builder: (_) => LoginScreen(
              message: 'Logged out after ${profile.idleLogoutHours} hours without use. Please log in again.')),
      (_) => false,
    );
  }
}

/// Red strip while on duty with GPS switched off.
class GpsOffBanner extends StatelessWidget {
  const GpsOffBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([SecurityGuard.instance.gpsOn, Services.tracker.active]),
      builder: (context, _) {
        if (SecurityGuard.instance.gpsOn.value || !Services.tracker.active.value) return const SizedBox.shrink();
        return Material(
          color: const Color(0xFFDC2626),
          child: SafeArea(
            bottom: false,
            child: InkWell(
              onTap: Geolocator.openLocationSettings,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.location_off_rounded, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text('GPS is off while you are on duty · your manager is told. Tap to turn it on.',
                          style: TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
