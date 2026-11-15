import 'package:flutter/material.dart';

import 'branding.dart';
import 'fx.dart';
import 'player_controller.dart';
import 'screens.dart';
import 'theme.dart';

class AuthScreen extends StatefulWidget {
  final PlayerController c;

  const AuthScreen({super.key, required this.c});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _username = TextEditingController();
  bool _creating = false;
  bool _busy = false;
  bool _hidePassword = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _username.dispose();
    super.dispose();
  }

  String? _signUpProblem() {
    if (!RegExp(r'^[A-Za-z0-9_.]{2,30}$').hasMatch(_username.text.trim())) {
      return 'Usernames are 2 to 30 letters, numbers, dots or underscores.';
    }
    if (!_email.text.contains('@')) return 'Enter a valid email address.';
    if (_password.text.length < 8) return 'Your password needs at least 8 characters.';
    return null;
  }

  Future<void> _submit() async {
    if (_busy) return;
    final problem = _creating ? _signUpProblem() : null;
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_creating) {
        await widget.c.register(_email.text.trim(), _password.text, _username.text.trim());
      } else {
        await widget.c.signIn(_email.text.trim(), _password.text);
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Glass(
              radius: 28,
              opacity: 0.1,
              padding: const EdgeInsets.all(28),
              child: AutofillGroup(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onLongPress: () => showServerDialog(context, widget.c),
                      child: const VortexWordmark(height: 28),
                    ),
                    const SizedBox(height: 20),
                    Text(_creating ? 'Create your account' : 'Welcome back', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -1)),
                    const SizedBox(height: 16),
                    if (_creating) ...[
                      TextField(
                        controller: _username,
                        maxLength: 30,
                        autofillHints: const [AutofillHints.newUsername],
                        decoration: const InputDecoration(labelText: 'Username', helperText: 'Friends find you with this', counterText: ''),
                      ),
                      const SizedBox(height: 10),
                    ],
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(labelText: 'Email'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _password,
                      obscureText: _hidePassword,
                      autofillHints: [_creating ? AutofillHints.newPassword : AutofillHints.password],
                      onSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        helperText: _creating ? 'At least 8 characters' : null,
                        suffixIcon: IconButton(
                          tooltip: _hidePassword ? 'Show password' : 'Hide password',
                          icon: Icon(_hidePassword ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                          onPressed: () => setState(() => _hidePassword = !_hidePassword),
                        ),
                      ),
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(_error!, style: const TextStyle(color: Color(0xFFFF9C9C), fontWeight: FontWeight.w600)),
                      ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _busy ? null : _submit,
                        style: FilledButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 14)),
                        child: Text(_busy ? 'One sec...' : (_creating ? 'Create account' : 'Sign in'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Center(
                      child: TextButton(
                        onPressed: () => setState(() {
                          _creating = !_creating;
                          _error = null;
                        }),
                        child: Text(_creating ? 'I already have an account' : 'New here? Create an account', style: const TextStyle(color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
