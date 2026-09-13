import 'package:flutter/material.dart';

import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../shell/app_shell.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.message});

  final String? message;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _server = TextEditingController();
  final _login = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _showServer = false;
  bool _hidePassword = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _error = widget.message;
    Services.storage.baseUrl().then((url) => _server.text = url);
  }

  @override
  void dispose() {
    _server.dispose();
    _login.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Services.auth.login(_server.text, _login.text, _password.text);
      Services.notifications.start();
      await Services.outbox.start();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const AppShell()));
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const WaveHeader(
              height: 240,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AixoloLogo(height: 78),
                  SizedBox(height: 10),
                  Text('Field force, simplified', style: TextStyle(color: AixoloColors.muted, fontSize: 15)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Welcome back', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    const Text('Log in with the app login given by your admin.', style: TextStyle(color: AixoloColors.muted)),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _login,
                      decoration: const InputDecoration(labelText: 'App login', prefixIcon: Icon(Icons.person_rounded)),
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.username],
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your login' : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _password,
                      obscureText: _hidePassword,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_rounded),
                        suffixIcon: IconButton(
                          icon: Icon(_hidePassword ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                          onPressed: () => setState(() => _hidePassword = !_hidePassword),
                        ),
                      ),
                      autofillHints: const [AutofillHints.password],
                      validator: (v) => (v == null || v.isEmpty) ? 'Enter your password' : null,
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    if (_showServer) ...[
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _server,
                        decoration: const InputDecoration(labelText: 'Server URL', prefixIcon: Icon(Icons.dns_rounded)),
                        keyboardType: TextInputType.url,
                        validator: (v) => (v == null || !v.startsWith('http')) ? 'Enter a valid URL' : null,
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Text(_error!, style: const TextStyle(color: AixoloColors.danger)),
                    ],
                    const SizedBox(height: 24),
                    GradientButton(label: 'Log in', icon: Icons.login_rounded, busy: _busy, onPressed: _submit),
                    TextButton(
                      onPressed: () => setState(() => _showServer = !_showServer),
                      child: Text(_showServer ? 'Hide server settings' : 'Server settings'),
                    ),
                    const SizedBox(height: 12),
                    const Center(child: Text('by Aixomind', style: TextStyle(color: AixoloColors.muted, fontSize: 12))),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
