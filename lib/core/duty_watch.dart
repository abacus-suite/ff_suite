import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'format.dart';
import 'geo.dart';
import 'services.dart';
import 'theme.dart';

/// Keeps an eye on a day that is still running after the shift has ended.
///
/// People forget to check out. Once the shift is over and the day is still open
/// this asks, every so often, whether they are still working. No answer within
/// the time the office allows and the day is closed by itself, so nobody is left
/// "working" all night and tomorrow starts clean. During the shift it stays quiet.
class DutyWatch {
  DutyWatch._();

  static final DutyWatch instance = DutyWatch._();

  Timer? _timer;
  bool _asking = false;
  DateTime? _lastAsked;
  int _askEvery = 0;
  int _waitFor = 5;
  DateTime? _shiftEnd;
  int _failures = 0;

  /// Called by the app when it learns the person is on duty (or not).
  ///
  /// [shiftEnd] is the local time the shift ends today. With none there is no
  /// moment to ask after, so nothing is asked.
  void update({required bool onDuty, required int askEvery, required int waitFor, DateTime? shiftEnd}) {
    _askEvery = askEvery;
    _waitFor = waitFor;
    _shiftEnd = shiftEnd;
    if (!onDuty || askEvery <= 0 || shiftEnd == null) {
      stop();
      return;
    }
    if (_timer != null) return;
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => check());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _lastAsked = null;
  }

  /// Is it time to ask? Only once the shift is over, and then every [askEvery] minutes.
  void check() {
    final end = _shiftEnd;
    if (end == null || _asking || _askEvery <= 0) return;
    final now = DateTime.now();
    if (now.isBefore(end)) return;
    final last = _lastAsked;
    if (last != null && now.difference(last) < Duration(minutes: _askEvery)) return;
    _ask(_waitFor);
  }

  /// "Are you still working?" with a sound, a buzz, and a countdown.
  Future<void> _ask(int waitFor) async {
    final navigator = Services.navigatorKey.currentState;
    if (_asking || navigator == null || !navigator.mounted) return;
    _asking = true;
    _lastAsked = DateTime.now();
    HapticFeedback.heavyImpact();
    SystemSound.play(SystemSoundType.alert);

    // An absolute deadline: a phone that was locked while the question was up still runs out of time.
    final deadline = DateTime.now().add(Duration(minutes: waitFor > 0 ? waitFor : 5));
    var timedOut = false;
    Timer? countdown;
    final answered = await showDialog<bool>(
      context: navigator.context,
      barrierDismissible: false,
      builder: (dialog) => StatefulBuilder(
        builder: (_, setState) {
          countdown ??= Timer.periodic(const Duration(seconds: 1), (timer) {
            final left = deadline.difference(DateTime.now());
            if (left.inSeconds <= 0) {
              timer.cancel();
              timedOut = true;
              Navigator.of(dialog).pop(false);
            } else {
              setState(() {});
              if (left.inSeconds % 30 == 0) HapticFeedback.mediumImpact();
            }
          });
          final left = deadline.difference(DateTime.now());
          final secs = left.inSeconds < 0 ? 0 : left.inSeconds;
          final clock = '${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}';
          return AlertDialog(
            icon: const Icon(Icons.timer_rounded, color: AppColors.warning, size: 44),
            title: const Text('Are you still working?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Your shift has ended and your day is still open. Tap "Still working" to carry on, or close it now.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text('Closing by itself in $clock',
                    style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.danger)),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialog).pop(false),
                child: const Text('Close my day'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialog).pop(true),
                child: const Text('Still working'),
              ),
            ],
          );
        },
      ),
    );
    countdown?.cancel();
    _asking = false;
    if (answered == true) return;

    // No answer, or they chose to close: the day ends here.
    await closeDay(reason: timedOut ? 'no_reply' : 'user_closed');
  }

  /// Checks out where the person is now, and says why it happened.
  ///
  /// Offline the check-out is queued and goes when the network returns. When the
  /// office refuses it, that is said, because a day that stays open by itself is worse
  /// than a message.
  Future<void> closeDay({required String reason}) async {
    try {
      await Services.tracker.flush();
      final here = await lastKnownPosition();
      await Services.outbox.submit('/api/v1/attendance/punch-out', {
        'auto': true,
        'close_reason': reason,
        if (here != null) 'lat': here.latitude,
        if (here != null) 'lng': here.longitude,
        'device_time': DateTime.now().toUtc().toIso8601String(),
      }, label: 'Automatic check-out');
      await Services.tracker.stop();
      Services.refresh.value++;
      _failures = 0;
      stop();
    } catch (e) {
      _failures++;
      // Try again at the next question; after a few refusals, tell the person.
      if (_failures >= 3) {
        final context = Services.navigatorKey.currentContext;
        if (context != null && context.mounted) {
          await showProblem(context, 'Your day could not be closed automatically: $e\nPlease check out from Home.',
              title: 'Could not check you out');
        }
        _failures = 0;
        stop();
      } else {
        _lastAsked = DateTime.now().subtract(Duration(minutes: _askEvery > 1 ? _askEvery - 1 : 0));
      }
    }
  }
}
