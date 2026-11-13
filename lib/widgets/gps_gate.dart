import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../core/services.dart';
import '../core/theme.dart';

/// The app needs the phone's GPS: once somebody is signed in, nothing can be used while location is off or not
/// allowed. A full-screen notice with the buttons to turn it on covers every screen until it is.
class GpsGate extends StatefulWidget {
  const GpsGate({super.key, required this.child});

  final Widget child;

  @override
  State<GpsGate> createState() => _GpsGateState();
}

class _GpsGateState extends State<GpsGate> with WidgetsBindingObserver {
  bool _serviceOn = true;
  LocationPermission _permission = LocationPermission.always;
  Timer? _timer;

  bool get _ok =>
      _serviceOn && _permission != LocationPermission.denied && _permission != LocationPermission.deniedForever;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
    // Switching GPS off from the notification shade does not leave the app, so it is looked at every few seconds too.
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _check());
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    try {
      final on = await Geolocator.isLocationServiceEnabled();
      final permission = await Geolocator.checkPermission();
      if (mounted && (on != _serviceOn || permission != _permission)) {
        setState(() {
          _serviceOn = on;
          _permission = permission;
        });
      }
    } catch (_) {}
  }

  Future<void> _fix() async {
    if (!_serviceOn) {
      await Geolocator.openLocationSettings();
    } else if (_permission == LocationPermission.deniedForever) {
      await Geolocator.openAppSettings();
    } else {
      await Geolocator.requestPermission();
    }
    await _check();
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = Services.auth.profile != null;
    return Stack(children: [
      widget.child,
      if (signedIn && !_ok)
        Positioned.fill(
          child: Material(
            color: Colors.white,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.location_off_rounded, size: 72, color: AppColors.danger),
                  const SizedBox(height: 18),
                  const Text('Turn on your GPS',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22, color: AppColors.text)),
                  const SizedBox(height: 10),
                  Text(
                      _serviceOn
                          ? 'Allow this app to use your location. It cannot be used without it.'
                          : 'Location is switched off. This app cannot be used until the GPS is turned on.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.muted, fontSize: 14.5)),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                    onPressed: _fix,
                    icon: const Icon(Icons.gps_fixed_rounded),
                    label: Text(_serviceOn ? 'Allow location' : 'Turn on GPS'),
                  ),
                ]),
              ),
            ),
          ),
        ),
    ]);
  }
}
