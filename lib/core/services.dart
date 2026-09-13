import 'package:flutter/material.dart';

import '../features/auth/login_screen.dart';
import 'api_client.dart';
import 'auth_repository.dart';
import 'google_tiles.dart';
import 'location_tracker.dart';
import 'notifications.dart';
import 'offline_queue.dart';
import 'security_guard.dart';
import 'outbox.dart';
import 'storage.dart';

/// Simple app-wide service holder, initialised once in main().
class Services {
  static final navigatorKey = GlobalKey<NavigatorState>();

  /// Bumped when the user switches tabs so dashboards reload.
  static final refresh = ValueNotifier<int>(0);
  static late final AppStorage storage;
  static late final ApiClient api;
  static late final AuthRepository auth;
  static late final OfflineQueue queue;
  static late final Outbox outbox;
  static late final LocationTracker tracker;
  static late final GoogleTiles googleTiles;
  static late final NotificationsService notifications;

  static Future<void> init() async {
    storage = AppStorage();
    api = ApiClient(storage);
    queue = OfflineQueue();
    api.store = queue;
    outbox = Outbox(api, queue);
    api.beforeRead = () async {
      if (outbox.pending.value > 0) await outbox.flush();
    };
    auth = AuthRepository(api, storage);
    tracker = LocationTracker(api, queue);
    googleTiles = GoogleTiles(storage);
    notifications = NotificationsService();
    await auth.restore();
    api.onUnauthorized = _sessionExpired;
    if (auth.profile != null) {
      notifications.start();
      await outbox.start();
      await SecurityGuard.instance.start();
    }
  }

  static bool _handlingExpiry = false;

  static Future<void> _sessionExpired() async {
    if (_handlingExpiry || auth.profile == null) return;
    _handlingExpiry = true;
    try {
      await tracker.stop(flushFirst: false);
      notifications.stop();
      outbox.stop();
      SecurityGuard.instance.stop();
      await queue.clearCache();
      await auth.clearLocal();
      navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen(message: 'Session expired. Please log in again.')),
        (_) => false,
      );
    } finally {
      _handlingExpiry = false;
    }
  }
}
