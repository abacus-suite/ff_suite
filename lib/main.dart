import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/services.dart';
import 'core/theme.dart';
import 'widgets/busy.dart';
import 'widgets/gps_gate.dart';
import 'features/auth/login_screen.dart';
import 'features/intro/intro_screen.dart';
import 'features/shell/app_shell.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {}
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  } catch (_) {}
  // Modern edge-to-edge layout with transparent status bar and dark icons.
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await Services.init();
  runApp(const FieldForceApp());
}

/// Every list can be pulled down to refresh, even a short or empty one: without this, Android ignores the pull
/// when the content does not fill the screen, and the refresh only worked from its icon.
class _PullToRefreshBehavior extends MaterialScrollBehavior {
  const _PullToRefreshBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics());
}

class FieldForceApp extends StatelessWidget {
  const FieldForceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Field Force',
      debugShowCheckedModeBanner: false,
      navigatorKey: Services.navigatorKey,
      scrollBehavior: const _PullToRefreshBehavior(),
      theme: appTheme(),
      // Above every screen, so a page that pushed another over itself cannot hide
      // the sign that something is still being fetched.
      builder: (context, child) => GpsGate(
        child: Stack(
          children: [
            child ?? const SizedBox.shrink(),
            const Positioned(top: 0, left: 0, right: 0, child: SlowRequestBar()),
          ],
        ),
      ),
      home: IntroScreen(next: Services.auth.profile == null ? const LoginScreen() : const AppShell()),
    );
  }
}
