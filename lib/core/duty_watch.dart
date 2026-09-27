import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'geo.dart';
import 'services.dart';
import 'theme.dart';

/// Keeps an eye on a day that is still running.
///
/// People forget to check out. While somebody is on duty this asks, every so
/// often, whether they are still working. No answer within the time the office
/// allows and the day is closed by itself, at that moment, so nobody is left
/// "working" all night and tomorrow starts clean.
class DutyWatch {
  DutyWatch._();

  static final DutyWatch instance = DutyWatch._();

  Timer? _timer;
  bool _asking = false;

  /// Called by the app when it learns the person is on duty (or not).
  void update({required bool onDuty, required int askEvery, required int waitFor}) {
    _timer?.cancel();
    _timer = null;
    if (!onDuty || askEvery <= 0) return;
    _timer = Timer.periodic(Duration(minutes: askEvery), (_) => _ask(waitFor));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// "Are you still working?" with a sound, a buzz, and a countdown.
  Future<void> _ask(int waitFor) async {
    final navigator = Services.navigatorKey.currentState;
    if (_asking || navigator == null || !navigator.mounted) return;
    _asking = true;
    HapticFeedback.heavyImpact();
    SystemSound.play(SystemSoundType.alert);

    final minutes = waitFor > 0 ? waitFor : 5;
    var left = Duration(minutes: minutes);
    Timer? countdown;
    final answered = await showDialog<bool>(
      context: navigator.context,
      barrierDismissible: false,
      builder: (dialog) => StatefulBuilder(
        builder: (_, setState) {
          countdown ??= Timer.periodic(const Duration(seconds: 1), (timer) {
            left -= const Duration(seconds: 1);
            if (left.inSeconds <= 0) {
              timer.cancel();
              Navigator.of(dialog).pop(false);
            } else {
              setState(() {});
              if (left.inSeconds % 30 == 0) HapticFeedback.mediumImpact();
            }
          });
          final clock = '${left.inMinutes}:${(left.inSeconds % 60).toString().padLeft(2, '0')}';
          return AlertDialog(
            icon: const Icon(Icons.timer_rounded, color: AppColors.warning, size: 44),
            title: const Text('Are you still working?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Your day is still open. Tap "Still working" to carry on, or close it now.',
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
    await closeDay(reason: answered == null ? 'no_reply' : 'no_reply');
  }

  /// Checks out where the person is now, and says why it happened.
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
    } catch (_) {
      // Offline: the queued punch-out goes when the network returns.
    }
    stop();
  }
}
