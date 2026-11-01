import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

const _minLength = 6;

String? _checkNew(String? v) {
  if (v == null || v.isEmpty) return 'Enter a new password';
  if (v.length < _minLength) return 'At least $_minLength characters';
  return null;
}

InputDecoration _field(String label, IconData icon, {Widget? suffix}) =>
    InputDecoration(labelText: label, prefixIcon: Icon(icon), suffixIcon: suffix);

/// Forgot password: the app login, a code emailed to the employee, then the new password.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.login});

  final String? login;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _login = TextEditingController(text: widget.login ?? '');
  final _otp = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _sent = false;
  bool _busy = false;
  bool _hide = true;
  String? _error;

  @override
  void dispose() {
    _login.dispose();
    _otp.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (_login.text.trim().isEmpty) {
      setState(() => _error = 'Enter your app login');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Services.api.post('/api/v1/auth/forgot-password', {'login': _login.text.trim()});
      if (!mounted) return;
      setState(() => _sent = true);
      showSnack(context, 'If that login has an email on file, a code has been sent.');
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Services.api.post('/api/v1/auth/reset-password', {
        'login': _login.text.trim(),
        'otp': _otp.text.trim(),
        'new_password': _password.text,
      });
      if (!mounted) return;
      showSnack(context, 'Password changed. Log in with your new password.');
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Forgot password', style: TextStyle(fontWeight: FontWeight.w900))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Form(
          key: _formKey,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
              _sent
                  ? 'Enter the 6-digit code sent to your work email, then choose a new password.'
                  : 'Enter your app login. We will email a code to the work email on your employee record.',
              style: const TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _login,
              enabled: !_sent,
              decoration: _field('App login', Icons.person_rounded),
              keyboardType: TextInputType.emailAddress,
            ),
            if (_sent) ...[
              const SizedBox(height: 14),
              TextFormField(
                controller: _otp,
                decoration: _field('6-digit code', Icons.pin_rounded),
                keyboardType: TextInputType.number,
                maxLength: 6,
                validator: (v) => (v == null || v.trim().length != 6) ? 'Enter the 6-digit code' : null,
              ),
              TextFormField(
                controller: _password,
                obscureText: _hide,
                decoration: _field('New password', Icons.lock_rounded,
                    suffix: IconButton(
                      icon: Icon(_hide ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                      onPressed: () => setState(() => _hide = !_hide),
                    )),
                validator: _checkNew,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _confirm,
                obscureText: _hide,
                decoration: _field('Confirm new password', Icons.lock_outline_rounded),
                validator: (v) => v != _password.text ? 'Passwords do not match' : null,
                onFieldSubmitted: (_) => _reset(),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(_error!, style: const TextStyle(color: AppColors.danger)),
            ],
            const SizedBox(height: 22),
            GradientButton(
              label: _sent ? 'Change password' : 'Send code',
              icon: _sent ? Icons.check_rounded : Icons.mark_email_read_rounded,
              busy: _busy,
              onPressed: _sent ? _reset : _sendCode,
            ),
            if (_sent)
              TextButton(
                onPressed: _busy ? null : _sendCode,
                child: const Text('Send the code again'),
              ),
          ]),
        ),
      ),
    );
  }
}

/// Change password while logged in. Other phones signed in as this person are signed out.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _hide = true;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Services.api.post('/api/v1/auth/change-password', {
        'current_password': _current.text,
        'new_password': _password.text,
      });
      if (!mounted) return;
      showSnack(context, 'Password changed.');
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final toggle = IconButton(
      icon: Icon(_hide ? Icons.visibility_rounded : Icons.visibility_off_rounded),
      onPressed: () => setState(() => _hide = !_hide),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Change password', style: TextStyle(fontWeight: FontWeight.w900))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Form(
          key: _formKey,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Other phones signed in as you will be asked to log in again.',
                style: TextStyle(color: AppColors.muted)),
            const SizedBox(height: 20),
            TextFormField(
              controller: _current,
              obscureText: _hide,
              decoration: _field('Current password', Icons.lock_rounded, suffix: toggle),
              validator: (v) => (v == null || v.isEmpty) ? 'Enter your current password' : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _password,
              obscureText: _hide,
              decoration: _field('New password', Icons.lock_reset_rounded),
              validator: _checkNew,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _confirm,
              obscureText: _hide,
              decoration: _field('Confirm new password', Icons.lock_outline_rounded),
              validator: (v) => v != _password.text ? 'Passwords do not match' : null,
              onFieldSubmitted: (_) => _save(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(_error!, style: const TextStyle(color: AppColors.danger)),
            ],
            const SizedBox(height: 22),
            GradientButton(label: 'Change password', icon: Icons.check_rounded, busy: _busy, onPressed: _save),
          ]),
        ),
      ),
    );
  }
}
