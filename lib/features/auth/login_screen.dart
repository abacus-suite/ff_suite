import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/security_guard.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/powered_by.dart';
import '../../widgets/common.dart';
import '../shell/app_shell.dart';
import 'password_screens.dart';

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
  List<String>? _dbs;
  String? _db;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _error = widget.message;
    Services.storage.baseUrl().then((url) {
      _server.text = url;
      _loadDbs();
    });
  }

  /// Ask the server which databases it has: the one used last (else the first) is chosen,
  /// and the person can change it. A server that does not list them leaves it to the server.
  Future<void> _loadDbs() async {
    final url = _server.text.trim();
    if (!url.startsWith('http')) return;
    setState(() => _checking = true);
    final list = await Services.api.listDatabases(url);
    final saved = await Services.storage.db();
    if (!mounted || url != _server.text.trim()) return;
    setState(() {
      _checking = false;
      _dbs = list;
      _db = list == null ? null : (list.contains(saved) ? saved : list.first);
    });
    // Remembered now, so Forgot password talks to the same server and database.
    await Services.storage.saveBaseUrl(url);
    await Services.storage.saveDb(_db);
  }

  Widget _dbField() => DropdownButtonFormField<String>(
        initialValue: _db,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Database', prefixIcon: Icon(Icons.storage_rounded)),
        items: [for (final name in _dbs!) DropdownMenuItem(value: name, child: Text(name))],
        onChanged: (value) {
          setState(() => _db = value);
          Services.storage.saveDb(value);
        },
      );

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
      try {
        await Services.auth.login(_server.text, _login.text, _password.text, db: _db);
      } on ApiException catch (e) {
        if (e.code != 'already_logged_in') rethrow;
        // Signed in on another phone: ask, then sign that one out and continue here.
        final yes = await showDialog<bool>(
          context: context,
          builder: (d) => AlertDialog(
            icon: const Icon(Icons.phonelink_erase_rounded, size: 36),
            title: const Text('Already signed in'),
            content: Text('${e.message}\n\nIf you continue, you are signed out on the other device.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('No')),
              FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Yes, continue here')),
            ],
          ),
        );
        if (yes != true) return;
        await Services.auth.login(_server.text, _login.text, _password.text, db: _db, force: true);
      }
      Services.notifications.start();
      await Services.outbox.start();
      await SecurityGuard.instance.start();
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
                  AppLogo(height: 78),
                  SizedBox(height: 10),
                  Text('Field force, simplified', style: TextStyle(color: AppColors.muted, fontSize: 15)),
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
                    const Text('Log in with the app login given by your admin.', style: TextStyle(color: AppColors.muted)),
                    const SizedBox(height: 20),
                    if (_dbs != null && _dbs!.length > 1) ...[
                      _dbField(),
                      const SizedBox(height: 14),
                    ],
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
                        decoration: InputDecoration(
                          labelText: 'Server URL',
                          prefixIcon: const Icon(Icons.dns_rounded),
                          suffixIcon: _checking
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                              : IconButton(
                                  tooltip: 'Check server and load databases',
                                  icon: const Icon(Icons.refresh_rounded),
                                  onPressed: _loadDbs),
                        ),
                        keyboardType: TextInputType.url,
                        validator: (v) => (v == null || !v.startsWith('http')) ? 'Enter a valid URL' : null,
                        onFieldSubmitted: (_) => _loadDbs(),
                      ),
                      if (_dbs != null && _dbs!.length == 1) ...[
                        const SizedBox(height: 14),
                        _dbField(),
                      ],
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Text(_error!, style: const TextStyle(color: AppColors.danger)),
                    ],
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => ForgotPasswordScreen(login: _login.text.trim()))),
                        child: const Text('Forgot password?'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    GradientButton(label: 'Log in', icon: Icons.login_rounded, busy: _busy, onPressed: _submit),
                    TextButton(
                      onPressed: () => setState(() => _showServer = !_showServer),
                      child: Text(_showServer ? 'Hide server settings' : 'Server settings'),
                    ),
                    const SizedBox(height: 12),
                    const Center(child: PoweredBy()),
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
