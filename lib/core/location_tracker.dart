import 'dart:io';
import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';

import 'api_client.dart';
import 'models.dart';
import 'offline_queue.dart';

/// Background GPS tracking while the employee is punched in.
///
/// Uses geolocator's Android foreground service (persistent notification),
/// stores every fix in the offline queue and uploads in batches.
class LocationTracker {
  LocationTracker(this._api, this._queue);

  final ApiClient _api;
  final OfflineQueue _queue;
  final Battery _battery = Battery();
  final Uuid _uuid = const Uuid();

  final ValueNotifier<bool> active = ValueNotifier(false);
  final ValueNotifier<int> pending = ValueNotifier(0);

  StreamSubscription<Position>? _positions;
  StreamSubscription<ServiceStatus>? _gpsStatus;
  Timer? _flushTimer;
  Timer? _heartbeat;
  DateTime? _lastFix;
  bool _flushing = false;

  Future<void> start(Profile profile) async {
    if (active.value || !profile.trackingEnabled) return;
    // iPhone: Apple's own background mode, with the blue location bar so the person knows.
    final LocationSettings settings = Platform.isIOS
        ? AppleSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: profile.distanceFilter,
            activityType: ActivityType.otherNavigation,
            pauseLocationUpdatesAutomatically: false,
            allowBackgroundLocationUpdates: true,
            showBackgroundLocationIndicator: true,
          )
        : AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: profile.distanceFilter,
      intervalDuration: Duration(seconds: profile.pingInterval),
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: 'Field Force',
        notificationText: 'Location is shared with your manager while you are punched in.',
        enableWakeLock: true,
        setOngoing: true,
      ),
    );
    _positions = Geolocator.getPositionStream(locationSettings: settings)
        .listen((pos) => _record(pos), onError: (Object _) {});
    _gpsStatus = Geolocator.getServiceStatusStream()
        .listen((s) => _event(s == ServiceStatus.enabled ? 'gps_on' : 'gps_off'));
    _flushTimer = Timer.periodic(const Duration(minutes: 2), (_) => flush());
    // With a distance filter no fix arrives while standing still: send a heartbeat.
    _heartbeat = Timer.periodic(const Duration(minutes: 10), (_) => _heartbeatFix());
    active.value = true;
    await _refreshPending();
  }

  Future<void> stop({bool flushFirst = true}) async {
    await _positions?.cancel();
    await _gpsStatus?.cancel();
    _flushTimer?.cancel();
    _heartbeat?.cancel();
    _positions = null;
    _gpsStatus = null;
    active.value = false;
    if (flushFirst) await flush();
  }

  Future<void> flush() async {
    if (_flushing) return;
    _flushing = true;
    try {
      await _flushKind('ping', '/api/v1/tracking/pings', 'pings');
      await _flushKind('event', '/api/v1/tracking/compliance', 'events');
    } catch (_) {
      // Offline or server error: items stay queued and are retried later.
    } finally {
      _flushing = false;
      await _refreshPending();
    }
  }

  Future<void> _flushKind(String kind, String path, String key) async {
    while (true) {
      final batch = await _queue.take(kind, 200);
      if (batch.isEmpty) return;
      await _api.post(path, {key: batch.map((e) => e.payload).toList()});
      await _queue.remove(batch.map((e) => e.uuid).toList());
    }
  }

  Future<void> _heartbeatFix() async {
    final last = _lastFix;
    if (last != null && DateTime.now().difference(last) < const Duration(minutes: 9)) return;
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 30),
        ),
      );
      await _record(pos);
    } catch (_) {}
  }

  Future<void> _record(Position pos) async {
    _lastFix = DateTime.now();
    int? level;
    var charging = false;
    try {
      level = await _battery.batteryLevel;
      charging = await _battery.batteryState == BatteryState.charging;
    } catch (_) {}
    await _queue.add('ping', {
      'uuid': _uuid.v4(),
      'ts': pos.timestamp.toUtc().toIso8601String(),
      'lat': pos.latitude,
      'lng': pos.longitude,
      'accuracy': pos.accuracy,
      'speed': pos.speed,
      'battery': level,
      'charging': charging,
      'mock': pos.isMocked,
      'source': 'background',
    });
    await _refreshPending();
    if (pending.value >= 20) unawaited(flush());
  }

  Future<void> _event(String type) async {
    await _queue.add('event', {
      'uuid': _uuid.v4(),
      'ts': DateTime.now().toUtc().toIso8601String(),
      'type': type,
    });
    unawaited(flush());
  }

  Future<void> _refreshPending() async {
    pending.value = await _queue.count();
  }
}
