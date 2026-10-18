import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../features/notifications/notifications_screen.dart';
import 'services.dart';

/// The app's own inbox: what the office has told this employee.
///
/// Odoo records a notification the moment something needs them - a claim
/// waiting for their approval, a decision on their own request.
/// Firebase Cloud Messaging delivers push notifications in background or foreground,
/// and the unread count is synchronized with Odoo.
class NotificationsService {
  NotificationsService();

  static const _pollEvery = Duration(seconds: 60);

  /// The badge on the bell. Widgets listen to this rather than polling.
  final ValueNotifier<int> unread = ValueNotifier<int>(0);
  Timer? _timer;

  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'field_force_notifications',
    'Field Force Notifications',
    description: 'Notifications for tasks, approvals, and announcements',
    importance: Importance.high,
  );
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      // Create high-importance channel on Android for heads-up notifications
      await _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_channel);

      const initSettings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      );
      await _localNotifications.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: (response) {
          _openNotificationsScreen();
        },
      );

      // Handle foreground messages
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        refresh();
        final notification = message.notification;
        if (notification != null) {
          _localNotifications.show(
            id: notification.hashCode,
            title: notification.title ?? 'Field Force',
            body: notification.body ?? '',
            notificationDetails: NotificationDetails(
              android: AndroidNotificationDetails(
                _channel.id,
                _channel.name,
                channelDescription: _channel.description,
                icon: '@mipmap/ic_launcher',
                importance: Importance.high,
                priority: Priority.high,
              ),
            ),
            payload: jsonEncode(message.data),
          );
        }
      });

      // Handle message tap when app was in background
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        refresh();
        _openNotificationsScreen();
      });

      // Handle message tap when app was terminated
      messaging.getInitialMessage().then((message) {
        if (message != null) {
          refresh();
          _openNotificationsScreen();
        }
      });

      // Handle token refreshes
      messaging.onTokenRefresh.listen((token) {
        _registerToken(token);
      });
    } catch (_) {
      // Firebase messaging unavailable on this device (e.g. without Play Services)
    }
  }

  void _openNotificationsScreen() {
    Services.navigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
    );
  }

  Future<void> _registerToken(String token) async {
    if (Services.auth.profile == null) return;
    try {
      await Services.api.post('/api/v1/device/register', {
        'device_uid': await Services.storage.deviceUid(),
        'fcm_token': token,
      });
    } catch (_) {}
  }

  void start() {
    stop();
    refresh();
    _syncFcmToken();
    _timer = Timer.periodic(_pollEvery, (_) => refresh());
  }

  Future<void> _syncFcmToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) {
        await _registerToken(token);
      }
    } catch (_) {}
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Ask how many are unread. Silent on failure: a missing module or a lost
  /// connection must not interrupt the person's work.
  Future<void> refresh() async {
    if (Services.auth.profile == null) return;
    try {
      final data = await Services.api.get('/api/v1/notifications?unread=1&limit=1') as Map<String, dynamic>;
      unread.value = (data['unread'] as num?)?.toInt() ?? 0;
    } catch (_) {
      // leave the badge as it was
    }
  }

  Future<List<Map<String, dynamic>>> list({bool unreadOnly = false}) async {
    final data = await Services.api
        .get('/api/v1/notifications${unreadOnly ? '?unread=1' : ''}') as Map<String, dynamic>;
    unread.value = (data['unread'] as num?)?.toInt() ?? 0;
    return ((data['notifications'] as List?) ?? []).cast<Map<String, dynamic>>();
  }

  /// Mark everything read, or just the ids given.
  Future<void> markRead({List<int>? ids}) async {
    try {
      await Services.api.post('/api/v1/notifications/read', {if (ids != null) 'ids': ids});
      unread.value = ids == null ? 0 : (unread.value - ids.length).clamp(0, 9999);
    } catch (_) {
      // the next refresh will put the count right
    }
  }
}
