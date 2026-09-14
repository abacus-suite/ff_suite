import 'package:flutter/material.dart';

import 'core/services.dart';
import 'core/theme.dart';
import 'features/auth/login_screen.dart';
import 'features/intro/intro_screen.dart';
import 'features/shell/app_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
      home: IntroScreen(next: Services.auth.profile == null ? const LoginScreen() : const AppShell()),
    );
  }
}
