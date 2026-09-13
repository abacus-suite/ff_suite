import 'package:flutter/material.dart';

import 'core/services.dart';
import 'core/theme.dart';
import 'features/auth/login_screen.dart';
import 'features/intro/intro_screen.dart';
import 'features/shell/app_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Services.init();
  runApp(const AixoloApp());
}

class AixoloApp extends StatelessWidget {
  const AixoloApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aixolo',
      debugShowCheckedModeBanner: false,
      navigatorKey: Services.navigatorKey,
      theme: aixoloTheme(),
      home: IntroScreen(next: Services.auth.profile == null ? const LoginScreen() : const AppShell()),
    );
  }
}
