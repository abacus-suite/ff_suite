import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/services.dart';
import 'core/theme.dart';
import 'widgets/busy.dart';
import 'features/auth/login_screen.dart';
import 'features/intro/intro_screen.dart';
import 'features/shell/app_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The phone's own back and home bar hides itself, so the app has the whole
  // screen; a swipe from the edge brings it back when it is needed.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  await Services.init();
  runApp(const FieldForceApp());
}

class FieldForceApp extends StatelessWidget {
  const FieldForceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Field Force',
      debugShowCheckedModeBanner: false,
      navigatorKey: Services.navigatorKey,
      theme: appTheme(),
      // Above every screen, so a page that pushed another over itself cannot hide
      // the sign that something is still being fetched.
      builder: (context, child) => Stack(
        children: [
          child ?? const SizedBox.shrink(),
          const Positioned(top: 0, left: 0, right: 0, child: SlowRequestBar()),
        ],
      ),
      home: IntroScreen(next: Services.auth.profile == null ? const LoginScreen() : const AppShell()),
    );
  }
}
