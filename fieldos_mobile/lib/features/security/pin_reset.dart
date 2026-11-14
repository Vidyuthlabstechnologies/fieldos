/// Forgot PIN. Resetting the PIN is a way past the wrong-PIN waits, so it
/// asks for the cloud account first: its password, a code emailed to it,
/// or (for Google and Apple accounts) that sign-in again. Until one of
/// them works the wrong-PIN count and wait stay exactly as they were; only
/// then are they cleared and a new PIN chosen.
///
/// A phone with no cloud account it can reach (never signed in to Team &
/// sync, or offline) cannot reset the PIN at all. Signing out locally used
/// to be the way out, and it skipped the waits; now the only way out is
/// the right PIN, or the forced sign-out after [PinLockout.signOutAt].
///
/// The app has no phone-number sign-in, so there is no SMS code here.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase/supabase.dart' show OAuthProvider;

import 'package:fieldos_mobile/auth/apple_auth.dart';
import 'package:fieldos_mobile/auth/google_auth.dart';
import 'package:fieldos_mobile/features/security/app_lock.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/sync/cloud_sync_providers.dart';
import 'package:fieldos_mobile/sync/cloud_sync_service.dart';

export 'package:fieldos_mobile/sync/cloud_sync_service.dart' show ReauthOutcome;

enum ReauthMethod { password, emailCode, google, apple }

class ReauthAccount {
  const ReauthAccount({required this.email, required this.methods});
  final String email;

  /// Ways this account can sign in again on this phone, in the order shown.
  final List<ReauthMethod> methods;
}

/// Signing in to the cloud account again. The PIN reset only talks to
/// this, so tests swap in a fake.
abstract class AccountReauth {
  /// The cloud account this phone is signed in to, or null when there is
  /// none it can use now.
  Future<ReauthAccount?> account();
  Future<ReauthOutcome> password(String password);
  Future<ReauthOutcome> sendEmailCode();
  Future<ReauthOutcome> emailCode(String code);
  Future<ReauthOutcome> google();
  Future<ReauthOutcome> apple();
}

class CloudAccountReauth implements AccountReauth {
  CloudAccountReauth({required this.cloud, required this.googlePicker, required this.applePicker});

  /// Null in a build with no cloud.
  final CloudSyncService? cloud;
  final GoogleAccountPicker googlePicker;
  final AppleAccountPicker applePicker;

  @override
  Future<ReauthAccount?> account() async {
    final c = cloud;
    if (c == null) return null;
    if (!c.isSignedIn) {
      try {
        await c.restoreSession();
      } catch (_) {}
    }
    final email = c.email;
    if (!c.isSignedIn || email == null || email.isEmpty) return null;
    final providers = c.signInProviders;
    return ReauthAccount(email: email, methods: [
      if (providers.contains('email')) ReauthMethod.password,
      if (providers.contains('google') && googlePicker.available) ReauthMethod.google,
      if (providers.contains('apple') && applePicker.available) ReauthMethod.apple,
      // Every account has its email, whichever way it signs in.
      ReauthMethod.emailCode,
    ]);
  }

  @override
  Future<ReauthOutcome> password(String password) async => cloud?.reauthWithPassword(password) ?? ReauthOutcome.noSession;

  @override
  Future<ReauthOutcome> sendEmailCode() async => cloud?.sendReauthCode() ?? ReauthOutcome.noSession;

  @override
  Future<ReauthOutcome> emailCode(String code) async => cloud?.reauthWithCode(code) ?? ReauthOutcome.noSession;

  @override
  Future<ReauthOutcome> google() async {
    final c = cloud;
    if (c == null) return ReauthOutcome.noSession;
    try {
      final picked = await googlePicker.pick();
      if (picked == null) return ReauthOutcome.cancelled;
      return c.reauthWithIdToken(provider: OAuthProvider.google, idToken: picked.idToken);
    } catch (_) {
      return ReauthOutcome.failed;
    }
  }

  @override
  Future<ReauthOutcome> apple() async {
    final c = cloud;
    if (c == null) return ReauthOutcome.noSession;
    try {
      final picked = await applePicker.pick();
      if (picked == null) return ReauthOutcome.cancelled;
      return c.reauthWithIdToken(provider: OAuthProvider.apple, idToken: picked.idToken, rawNonce: picked.rawNonce);
    } catch (_) {
      return ReauthOutcome.failed;
    }
  }
}

final accountReauthProvider = Provider<AccountReauth>((ref) => CloudAccountReauth(
      cloud: ref.watch(cloudSyncAvailableProvider) ? ref.watch(cloudSyncServiceProvider) : null,
      googlePicker: ref.watch(googlePickerProvider),
      applePicker: ref.watch(applePickerProvider),
    ));

enum PinResetStep {
  checking,

  /// No cloud account to check against: the PIN cannot be reset.
  unavailable,
  choose,
  password,
  emailCode,

  /// Signed in again: the count is cleared and a new PIN may be set.
  newPin,
  done,
}

/// The Forgot PIN steps, with no widgets. Only [newPin] is reachable
/// without a successful sign-in, and only [setPin] there changes the PIN.
class PinReset extends ChangeNotifier {
  PinReset({required this.lock, required this.reauth});
  final AppLock lock;
  final AccountReauth reauth;

  PinResetStep _step = PinResetStep.checking;
  PinResetStep get step => _step;

  ReauthAccount? _account;
  ReauthAccount? get account => _account;

  /// Why the last try did not work; cleared by the next one.
  ReauthOutcome? _error;
  ReauthOutcome? get error => _error;

  bool _busy = false;
  bool get busy => _busy;

  bool _codeSent = false;
  bool get codeSent => _codeSent;

  bool _disposed = false;

  void _go(PinResetStep s) {
    _step = s;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> start() async {
    _go(PinResetStep.checking);
    final a = await reauth.account();
    _account = a;
    _go(a == null || a.methods.isEmpty ? PinResetStep.unavailable : PinResetStep.choose);
  }

  /// From the list of ways in. Google and Apple run straight away.
  Future<void> choose(ReauthMethod m) async {
    if (_busy || _step != PinResetStep.choose) return;
    _error = null;
    switch (m) {
      case ReauthMethod.password:
        _go(PinResetStep.password);
      case ReauthMethod.emailCode:
        _codeSent = false;
        _go(PinResetStep.emailCode);
        await sendCode();
      case ReauthMethod.google:
        await _try(reauth.google);
      case ReauthMethod.apple:
        await _try(reauth.apple);
    }
  }

  /// Back to the list of ways in. Never past it: the reset needs a sign-in.
  void back() {
    if (_busy || _step == PinResetStep.newPin || _step == PinResetStep.done) return;
    if (_step == PinResetStep.password || _step == PinResetStep.emailCode) {
      _error = null;
      _go(PinResetStep.choose);
    }
  }

  Future<void> submitPassword(String password) async {
    if (_step != PinResetStep.password || password.isEmpty) return;
    await _try(() => reauth.password(password));
  }

  Future<void> sendCode() async {
    if (_busy || _step != PinResetStep.emailCode) return;
    _busy = true;
    _error = null;
    _notify();
    final r = await reauth.sendEmailCode();
    _busy = false;
    if (r == ReauthOutcome.ok) {
      _codeSent = true;
    } else {
      _error = r;
    }
    _notify();
  }

  Future<void> submitCode(String code) async {
    if (_step != PinResetStep.emailCode || code.trim().isEmpty) return;
    await _try(() => reauth.emailCode(code));
  }

  Future<void> _try(Future<ReauthOutcome> Function() signIn) async {
    if (_busy) return;
    _busy = true;
    _error = null;
    _notify();
    final r = await signIn();
    if (r == ReauthOutcome.ok) {
      // The one place the count is cleared without the right PIN.
      await lock.clearLockout();
      _busy = false;
      _go(PinResetStep.newPin);
      return;
    }
    _busy = false;
    if (r != ReauthOutcome.cancelled) _error = r;
    _notify();
  }

  Future<void> setPin(String pin) async {
    if (_step != PinResetStep.newPin) throw StateError('Sign in again before choosing a new PIN.');
    await lock.setPin(pin);
    _go(PinResetStep.done);
  }
}

/// What a failed try says.
String reauthErrorText(ReauthOutcome e, {required PinResetStep step, required String email}) => switch (e) {
      ReauthOutcome.wrong => step == PinResetStep.password
          ? tr('That password is not right.')
          : tr('That code is wrong or has expired.'),
      ReauthOutcome.wrongAccount => trf('That is a different account. Use {email}.', {'email': email}),
      _ => tr('That did not go through. Check the internet and try again.'),
    };

/// The Forgot PIN screen over the locked app. [onDone] once a new PIN is
/// set; [onCancel] goes back to the PIN pad with its wait as it was.
class ForgotPinScreen extends StatefulWidget {
  const ForgotPinScreen({super.key, required this.reset, required this.onDone, required this.onCancel});
  final PinReset reset;
  final VoidCallback onDone;
  final VoidCallback onCancel;

  @override
  State<ForgotPinScreen> createState() => _ForgotPinScreenState();
}

class _ForgotPinScreenState extends State<ForgotPinScreen> {
  final _password = TextEditingController();
  final _code = TextEditingController();

  PinReset get _r => widget.reset;

  @override
  void initState() {
    super.initState();
    _r.addListener(_changed);
  }

  @override
  void dispose() {
    _r.removeListener(_changed);
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    if (_r.step == PinResetStep.done) {
      widget.onDone();
      return;
    }
    setState(() {});
  }

  static const _bg = Color(0xFF14213D);
  static const _errorColor = Color(0xFFFFB4AB);

  Widget _text(String s, {TextStyle? style}) => Text(
        s,
        textAlign: TextAlign.center,
        style: (style ?? const TextStyle()).copyWith(color: Colors.white),
      );

  Widget _field(TextEditingController c, String label, {bool obscure = false, TextInputType? type, required VoidCallback onDone}) =>
      TextField(
        controller: c,
        obscureText: obscure,
        keyboardType: type,
        autofocus: true,
        enabled: !_r.busy,
        onSubmitted: (_) => onDone(),
        decoration: InputDecoration(labelText: label, filled: true, fillColor: Colors.white),
      );

  Widget _button(String label, VoidCallback? onPressed) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton(onPressed: _r.busy ? null : onPressed, child: Text(label)),
        ),
      );

  Widget _link(String label, VoidCallback? onPressed) => TextButton(
        onPressed: _r.busy ? null : onPressed,
        style: TextButton.styleFrom(foregroundColor: Colors.white70),
        child: Text(label, textAlign: TextAlign.center),
      );

  List<Widget> _body(ThemeData theme) {
    final email = _r.account?.email ?? '';
    final title = theme.textTheme.titleLarge;
    switch (_r.step) {
      case PinResetStep.checking:
      case PinResetStep.done:
        return [const CircularProgressIndicator(color: Colors.white)];
      case PinResetStep.unavailable:
        return [
          const Icon(Icons.cloud_off, color: Colors.white, size: 40),
          const SizedBox(height: 16),
          _text(
            tr('The PIN cannot be reset on this phone now. That needs the internet and this phone signed in to your FieldOS cloud account. Until then, the PIN lock stays as it is.'),
            style: theme.textTheme.titleMedium,
          ),
          _button(tr('Back'), widget.onCancel),
        ];
      case PinResetStep.choose:
        return [
          const Icon(Icons.verified_user_outlined, color: Colors.white, size: 40),
          const SizedBox(height: 12),
          _text(tr('Confirm it is you'), style: title),
          const SizedBox(height: 8),
          _text(trf('To choose a new PIN, sign in again to {email}.', {'email': email}),
              style: const TextStyle(color: Colors.white70)),
          for (final m in _r.account!.methods)
            _button(
              switch (m) {
                ReauthMethod.password => tr('Use my password'),
                ReauthMethod.emailCode => tr('Email me a code'),
                ReauthMethod.google => tr('Continue with Google'),
                ReauthMethod.apple => tr('Sign in with Apple'),
              },
              () => _r.choose(m),
            ),
          _link(tr('Cancel'), widget.onCancel),
        ];
      case PinResetStep.password:
        return [
          _text(tr('Confirm it is you'), style: title),
          const SizedBox(height: 8),
          _text(email, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 16),
          _field(_password, tr('Password'), obscure: true, onDone: () => _r.submitPassword(_password.text)),
          _button(tr('Next'), () => _r.submitPassword(_password.text)),
          _link(tr('Back'), _r.back),
        ];
      case PinResetStep.emailCode:
        return [
          _text(tr('Confirm it is you'), style: title),
          const SizedBox(height: 8),
          if (_r.codeSent)
            _text(
              trf('We emailed a code to {email}. The email calls it a password reset code; your password stays the same.', {'email': email}),
              style: const TextStyle(color: Colors.white70),
            ),
          const SizedBox(height: 16),
          _field(_code, tr('Code from the email'), type: TextInputType.number, onDone: () => _r.submitCode(_code.text)),
          _button(tr('Next'), () => _r.submitCode(_code.text)),
          _link(tr('Send a new code'), _r.sendCode),
          _link(tr('Back'), _r.back),
        ];
      case PinResetStep.newPin:
        return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_r.step == PinResetStep.newPin) {
      return NewPinPad(onChosen: _r.setPin, onCancel: widget.onCancel);
    }
    final theme = Theme.of(context);
    final error = _r.error;
    return Material(
      color: _bg,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ..._body(theme),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        reauthErrorText(error, step: _r.step, email: _r.account?.email ?? ''),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: _errorColor),
                      ),
                    ),
                  if (_r.busy && _r.step != PinResetStep.checking)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: LinearProgressIndicator(),
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
