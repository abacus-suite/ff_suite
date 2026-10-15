import 'dart:async';

import 'package:flutter/foundation.dart';

import 'services.dart';

/// The app's own inbox: what the office has told this employee.
///
/// Odoo records a notification the moment something needs them - a claim
/// waiting for their approval, a decision on their own request. Until push is
/// wired up, the app asks for the unread count while it is open, which is
/// enough for somebody who works inside the app all day.
class NotificationsService {
  NotificationsService();

  static const _pollEvery = Duration(seconds: 60);

  /// The badge on the bell. Widgets listen to this rather than polling.
  final ValueNotifier<int> unread = ValueNotifier<int>(0);
  Timer? _timer;

  void start() {
    stop();
    refresh();
    _timer = Timer.periodic(_pollEvery, (_) => refresh());
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
