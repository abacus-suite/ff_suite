import 'dart:async';

import 'package:flutter/material.dart';

import '../core/services.dart';
import '../core/theme.dart';

/// A thin bar across the top of the app while something is being fetched.
///
/// Sits above every screen, because a screen that pushed another over itself
/// would otherwise hide whatever it was waiting on. It only appears once a
/// request has been going for a moment, so quick ones do not make it flicker.
class SlowRequestBar extends StatefulWidget {
  const SlowRequestBar({super.key});

  @override
  State<SlowRequestBar> createState() => _SlowRequestBarState();
}

class _SlowRequestBarState extends State<SlowRequestBar> {
  bool _show = false;
  Timer? _delay;

  @override
  void initState() {
    super.initState();
    Services.api.pending.addListener(_changed);
  }

  @override
  void dispose() {
    _delay?.cancel();
    Services.api.pending.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (Services.api.pending.value > 0) {
      _delay ??= Timer(const Duration(milliseconds: 500), () {
        if (mounted && Services.api.pending.value > 0) setState(() => _show = true);
      });
    } else {
      _delay?.cancel();
      _delay = null;
      if (_show && mounted) setState(() => _show = false);
    }
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: AnimatedOpacity(
          opacity: _show ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: const LinearProgressIndicator(
            minHeight: 3.5,
            backgroundColor: Colors.transparent,
            color: AppColors.primary,
          ),
        ),
      );
}

/// Runs [work] and, if it takes more than a moment, shows what is happening.
///
/// For things the person is waiting on and must not tap twice: checking in,
/// opening a list the server has to build. Fast work shows nothing at all.
Future<T> withBusy<T>(BuildContext context, String label, Future<T> Function() work) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  var shown = false;
  final timer = Timer(const Duration(milliseconds: 350), () {
    shown = true;
    showDialog<void>(
      context: navigator.context,
      barrierDismissible: false,
      builder: (dialog) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
              const SizedBox(width: 18),
              Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
            ],
          ),
        ),
      ),
    );
  });
  try {
    return await work();
  } finally {
    timer.cancel();
    if (shown && navigator.mounted) navigator.pop();
  }
}
