import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/auth/auth_service.dart';
import 'package:fieldos_mobile/core/brand.dart';
import 'package:fieldos_mobile/core/branded_page.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/features/legal/legal_screen.dart';
import 'package:fieldos_mobile/providers.dart';

/// Sign in or create an account. On a phone where nobody has an account
/// yet it opens on "Create account", since there is nothing to log in to.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _username = TextEditingController();
  final _name = TextEditingController();
  final _password = TextEditingController();
  final _usernameFocus = FocusNode();
  final _passwordFocus = FocusNode();
  bool _registering = false;
  bool _showPassword = false;
  bool _busy = false;
  String? _error;
  late final _termsTap = TapGestureRecognizer()..onTap = () => openTerms(context);
  late final _privacyTap = TapGestureRecognizer()..onTap = () => openPrivacyPolicy(context);

  @override
  void initState() {
    super.initState();
    ref.read(appDatabaseProvider).userDao.any().then((has) {
      if (mounted && !has) setState(() => _registering = true);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _username.dispose();
    _name.dispose();
    _password.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    _termsTap.dispose();
    _privacyTap.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = ref.read(sessionProvider.notifier);
      if (_registering) {
        await session.register(username: _username.text, name: _name.text, password: _password.text);
      } else {
        await session.login(_username.text, _password.text);
      }
      TextInput.finishAutofillContext();
      // The app shell moves on by itself once the session is set.
    } catch (e, st) {
      // AuthException messages are written for the screen. Anything else is
      // unexpected, and its raw text could hold internals (a Drift error
      // includes the whole row, password hash and all), so it never shows.
      setState(() => _error = e is AuthException ? e.message : friendlyError(e, st));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _switchMode() => setState(() {
        _registering = !_registering;
        _error = null;
      });

  void _forgotPassword() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Forgot your password?'),
        content: const Text(
          'FieldOS accounts live on this phone, so there is no reset email. If you turned on Team & sync, your '
          "company's records are safe in the cloud: create a new account on this phone, then sign in to Team & sync "
          'with your email to get them back. If you are stuck, write to us and we will help.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              emailSupport(subject: 'FieldOS: forgot password');
            },
            child: const Text('Email support'),
          ),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final linkStyle = TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w600);
    final compact = BrandedSheetPage.isCompact(context);
    return BrandedSheetPage(
      header: [
        SizedBox(height: compact ? 16 : 36),
        BrandMark(size: compact ? 64 : 88, onDark: true),
        const SizedBox(height: 6),
        Wordmark(fontSize: compact ? 28 : 34, onDark: true),
        const SizedBox(height: 8),
        Text(
          'Daily reports, labour, materials and money for your sites. In your language, even offline.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.8)),
        ),
      ],
      sheet: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_registering ? 'Create your account' : 'Welcome back', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(
              _registering
                  ? 'Takes a minute. Works offline; your records stay on this phone unless you turn on Team & sync.'
                  : 'Log in to carry on where you left off.',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            if (_registering) ...[
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.name],
                onSubmitted: (_) => _usernameFocus.requestFocus(),
                decoration: const InputDecoration(labelText: 'Your name', prefixIcon: Icon(Icons.badge_outlined)),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _username,
              focusNode: _usernameFocus,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.next,
              autofillHints: [_registering ? AutofillHints.newUsername : AutofillHints.username],
              onSubmitted: (_) => _passwordFocus.requestFocus(),
              decoration: InputDecoration(
                labelText: 'Username',
                prefixIcon: const Icon(Icons.person_outline),
                helperText: _registering ? 'For example ravi, or your phone number' : null,
                helperMaxLines: 2,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              focusNode: _passwordFocus,
              obscureText: !_showPassword,
              textInputAction: TextInputAction.done,
              autofillHints: [_registering ? AutofillHints.newPassword : AutofillHints.password],
              onSubmitted: (_) => _busy ? null : _submit(),
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline),
                helperText: _registering ? 'At least ${AuthService.minPasswordLength} characters' : null,
                suffixIcon: IconButton(
                  tooltip: _showPassword ? 'Hide password' : 'Show password',
                  icon: Icon(_showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                  onPressed: () => setState(() => _showPassword = !_showPassword),
                ),
              ),
            ),
            if (!_registering)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: _forgotPassword, child: const Text('Forgot password?')),
              ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              FormMessage(_error!),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(_registering ? 'Create account' : 'Log in'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy ? null : _switchMode,
              child: Text(_registering ? 'Already have an account? Log in' : 'New to FieldOS? Create an account'),
            ),
            const SizedBox(height: 16),
            Text.rich(
              TextSpan(
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                children: [
                  const TextSpan(text: 'By continuing you agree to the '),
                  TextSpan(
                    text: 'Terms of use',
                    style: linkStyle,
                    recognizer: _termsTap,
                  ),
                  const TextSpan(text: ' and the '),
                  TextSpan(
                    text: 'Privacy policy',
                    style: linkStyle,
                    recognizer: _privacyTap,
                  ),
                  const TextSpan(text: '.'),
                ],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
