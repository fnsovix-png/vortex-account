import 'package:flutter/material.dart';

import 'account.dart';
import 'theme.dart';
import 'ui.dart';

class AuthScreen extends StatefulWidget {
  final Account account;

  const AuthScreen({super.key, required this.account});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _username = TextEditingController();
  bool _creating = false;
  bool _busy = false;
  bool _hidden = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _username.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_creating) {
        await widget.account.register(_email.text.trim(), _password.text, _username.text.trim());
      } else {
        await widget.account.signIn(_email.text.trim(), _password.text);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e is String ? e : 'Check your internet connection and try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Wordmark(size: 30),
                  const SizedBox(height: 28),
                  Text(_creating ? 'Create your account' : 'Welcome back', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                  const SizedBox(height: 4),
                  Text(_creating ? 'It works in Vortex Music too.' : 'Use the same login as Vortex Music.', style: const TextStyle(color: Palette.muted)),
                  const SizedBox(height: 22),
                  if (_creating) ...[
                    TextField(controller: _username, maxLength: 30, autofillHints: const [AutofillHints.newUsername], decoration: const InputDecoration(labelText: 'Username', counterText: '')),
                    const SizedBox(height: 12),
                  ],
                  TextField(controller: _email, keyboardType: TextInputType.emailAddress, autofillHints: const [AutofillHints.email], textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: 'Email')),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    obscureText: _hidden,
                    autofillHints: const [AutofillHints.password],
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      suffixIcon: IconButton(tooltip: _hidden ? 'Show password' : 'Hide password', icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined), onPressed: () => setState(() => _hidden = !_hidden)),
                    ),
                  ),
                  if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: Palette.danger))),
                  const SizedBox(height: 18),
                  FilledButton(onPressed: _busy ? null : _submit, child: Text(_busy ? 'One moment' : (_creating ? 'Create account' : 'Sign in'))),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => setState(() {
                      _creating = !_creating;
                      _error = null;
                    }),
                    style: TextButton.styleFrom(foregroundColor: Palette.lavender),
                    child: Text(_creating ? 'I already have an account' : 'New here? Create an account'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
