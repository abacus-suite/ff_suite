import 'package:flutter/material.dart';

/// Shows [child] normally and nothing at all while the keyboard is up.
///
/// For the floating buttons of a screen that sits inside the app shell: the shell's Scaffold already lifts its body
/// above the keyboard, so inside it the usual `MediaQuery.viewInsets` reads 0 and a screen cannot tell that someone is
/// typing. This asks the window itself, and rebuilds when the keyboard comes or goes.
class HideWhenTyping extends StatefulWidget {
  const HideWhenTyping({super.key, required this.child});

  final Widget child;

  @override
  State<HideWhenTyping> createState() => _HideWhenTypingState();
}

class _HideWhenTypingState extends State<HideWhenTyping> with WidgetsBindingObserver {
  bool _typing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    if (!mounted) return;
    final typing = View.of(context).viewInsets.bottom > 0;
    if (typing != _typing) setState(() => _typing = typing);
  }

  @override
  Widget build(BuildContext context) => _typing ? const SizedBox.shrink() : widget.child;
}
