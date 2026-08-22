import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/providers.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _username = TextEditingController();
  final _name = TextEditingController();
  final _password = TextEditingController();
  bool _registering = false;
  String? _error;
  bool _busy = false;

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      if (_registering) {
        await ref.read(sessionProvider.notifier).register(
              username: _username.text.trim(),
              name: _name.text.trim(),
              password: _password.text,
            );
      } else {
        await ref.read(sessionProvider.notifier).login(
              _username.text.trim(),
              _password.text,
            );
      }
      // The app shell re-routes based on session state.
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.construction, size: 56, color: Color(0xFF1B5E20)),
                const SizedBox(height: 12),
                Text(
                  _registering ? 'Create your account' : 'FieldOS Mobile',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                if (_registering)
                  TextField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'Full name', border: OutlineInputBorder()),
                  ),
                if (_registering) const SizedBox(height: 12),
                TextField(
                  controller: _username,
                  decoration: const InputDecoration(labelText: 'Username', border: OutlineInputBorder()),
                  autocorrect: false,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
                  obscureText: true,
                ),
                const SizedBox(height: 16),
                if (_error != null)
                  Text(_error!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(_registering ? 'Create account' : 'Log in'),
                ),
                TextButton(
                  onPressed: _busy ? null : () => setState(() => _registering = !_registering),
                  child: Text(_registering ? 'Have an account? Log in' : 'New here? Create an account'),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Works fully offline. Your data stays on this device.',
                  style: TextStyle(color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
