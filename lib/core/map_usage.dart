import 'dart:async';

import 'services.dart';

/// Counts the Google tiles this phone fetched and reports the total to Odoo.
///
/// Google bills per tile, so the office can only see what it is spending if the
/// app says how much it used. Counting is local and cheap; the number is sent
/// in one small request at most once a minute.
class MapUsage {
  static int _tiles = 0;
  static int _sessions = 0;
  static Timer? _timer;

  static void tile() {
    _tiles++;
    _schedule();
  }

  static void session() {
    _sessions++;
    _schedule();
  }

  static void _schedule() {
    _timer ??= Timer(const Duration(seconds: 60), flush);
  }

  /// Send what we counted. Failure is fine: the counts stay and go next time.
  static Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    final tiles = _tiles;
    final sessions = _sessions;
    if (tiles == 0 && sessions == 0) return;
    if (Services.auth.profile == null) return;
    _tiles = 0;
    _sessions = 0;
    try {
      final res = await Services.api.post('/api/v1/maps/usage', {'tiles': tiles, 'sessions': sessions});
      if (res is Map && res['google'] is bool) {
        Services.googleTiles.freeLimitReached = res['google'] == false;
      }
    } catch (_) {
      _tiles += tiles;
      _sessions += sessions;
    }
  }
}
