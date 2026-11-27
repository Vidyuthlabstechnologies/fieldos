/// Forgot PIN. Resetting the PIN is a way past the wrong-PIN waits, so it
/// asks for the cloud account first: its password, a sign-in code emailed
/// to it, or (for Google and Apple accounts) that sign-in again. Until one
/// of them works the wrong-PIN count and wait stay exactly as they were;
/// only then are they cleared and a new PIN chosen.
///
/// A phone with no usable cloud session (signed out of Team & sync, the
/// session expired, or never signed in) gets two choices:
///
///  - Sign in to keep the data. Only to the cloud account this phone's
///    data was linked to and synced with ([linkedCloudAccount]), checked by
///    its user id after the sign-in. Someone holding the phone who signs in
///    to their OWN account gets "That is a different account" and nothing
///    else: the sign-in runs on a separate client
///    ([CloudSyncService.signInAgainAs]) and their session never reaches
///    this phone. A phone whose data was never linked has no account that
///    could prove it is the owner's (anyone can make one, and linking the
///    data to it would hand it over), so it is not offered there.
///  - Erase this phone and start over ([PhoneEraser]), after typing the
///    confirmation word. That reveals nothing; it destroys what is not in
///    the cloud, which the warning says plainly.
///
/// The app has no phone-number sign-in, so there is no SMS code here.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase/supabase.dart' show OAuthProvider, OtpType;

import 'package:fieldos_mobile/auth/apple_auth.dart';
import 'package:fieldos_mobile/auth/google_auth.dart';
import 'package:fieldos_mobile/data/erase_phone.dart';
import 'package:fieldos_mobile/features/security/app_lock.dart';
import 'package:fieldos_mobile/features/tasks/team_roster.dart' show linkedCloudAccount;
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart' show appDatabaseProvider;
import 'package:fieldos_mobile/sync/cloud_sync_providers.dart';
import 'package:fieldos_mobile/sync/cloud_sync_service.dart';

export 'package:fieldos_mobile/sync/cloud_sync_service.dart' show ReauthOutcome;

enum ReauthMethod { password, emailCode, google, apple }

class ReauthAccount {
  const ReauthAccount({required this.email, required this.methods, this.signedIn = true});
  final String email;

  /// Ways this account can sign in again on this phone, in the order shown.
  final List<ReauthMethod> methods;

  /// False: the phone has no usable session, and this is the account its
  /// data was linked to. Signing in to it, and to no other, lets a new PIN
  /// be set.
  final bool signedIn;
}

/// Signing in to the cloud account again. The PIN reset only talks to
/// this, so tests swap in a fake.
abstract class AccountReauth {
  /// The cloud account to sign in to: the one this phone is signed in to,
  /// or, with no usable session, the one its data was linked to
  /// ([ReauthAccount.signedIn] false). Null when there is neither.
  Future<ReauthAccount?> account();
  Future<ReauthOutcome> password(String password);
  Future<ReauthOutcome> sendEmailCode();
  Future<ReauthOutcome> emailCode(String code);
  Future<ReauthOutcome> google();
  Future<ReauthOutcome> apple();
}

typedef LinkedAccount = ({String userId, String email});

class CloudAccountReauth implements AccountReauth {
  CloudAccountReauth({
    required this.cloud,
    required this.googlePicker,
    required this.applePicker,
    Future<LinkedAccount?> Function()? linked,
  }) : _linkedAccount = linked;

  /// Null in a build with no cloud.
  final CloudSyncService? cloud;
  final GoogleAccountPicker googlePicker;
  final AppleAccountPicker applePicker;
  final Future<LinkedAccount?> Function()? _linkedAccount;

  /// Set by [account] when the phone has no usable session: every sign-in
  /// below then has to land on this account.
  LinkedAccount? _linked;

  @override
  Future<ReauthAccount?> account() async {
    _linked = null;
    final c = cloud;
    if (c == null) return null;
    if (!c.isSignedIn) {
      try {
        await c.restoreSession();
      } catch (_) {}
    }
    final email = c.email;
    if (c.isSignedIn && email != null && email.isNotEmpty) {
      final providers = c.signInProviders;
      return ReauthAccount(email: email, methods: [
        if (providers.contains('email')) ReauthMethod.password,
        if (providers.contains('google') && googlePicker.available) ReauthMethod.google,
        if (providers.contains('apple') && applePicker.available) ReauthMethod.apple,
        // Every account has its email, whichever way it signs in.
        ReauthMethod.emailCode,
      ]);
    }
    final linked = await _linkedAccount?.call();
    if (linked == null) return null;
    _linked = linked;
    // How it signs in went with the session; offer every way there is.
    return ReauthAccount(signedIn: false, email: linked.email, methods: [
      ReauthMethod.password,
      if (googlePicker.available) ReauthMethod.google,
      if (applePicker.available) ReauthMethod.apple,
      ReauthMethod.emailCode,
    ]);
  }

  @override
  Future<ReauthOutcome> password(String password) async {
    final c = cloud;
    if (c == null) return ReauthOutcome.noSession;
    final l = _linked;
    if (l == null) return c.reauthWithPassword(password);
    return c.signInAgainAs(userId: l.userId, signIn: (auth) => auth.signInWithPassword(email: l.email, password: password));
  }

  @override
  Future<ReauthOutcome> sendEmailCode() async {
    final c = cloud;
    if (c == null) return ReauthOutcome.noSession;
    final l = _linked;
    return l == null ? c.sendReauthCode() : c.sendSignInCode(l.email);
  }

  @override
  Future<ReauthOutcome> emailCode(String code) async {
    final c = cloud;
    if (c == null) return ReauthOutcome.noSession;
    final l = _linked;
    if (l == null) return c.reauthWithCode(code);
    return c.signInAgainAs(
      userId: l.userId,
      signIn: (auth) => auth.verifyOTP(email: l.email, token: code.trim(), type: OtpType.email),
    );
  }

  @override
  Future<ReauthOutcome> google() async {
    final c = cloud;
    if (c == null) return ReauthOutcome.noSession;
    try {
      final picked = await googlePicker.pick();
      if (picked == null) return ReauthOutcome.cancelled;
      return _idToken(c, OAuthProvider.google, picked.idToken, null);
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
      return _idToken(c, OAuthProvider.apple, picked.idToken, picked.rawNonce);
    } catch (_) {
      return ReauthOutcome.failed;
    }
  }

  Future<ReauthOutcome> _idToken(CloudSyncService c, OAuthProvider provider, String idToken, String? rawNonce) {
    final l = _linked;
    if (l == null) return c.reauthWithIdToken(provider: provider, idToken: idToken, rawNonce: rawNonce);
    // Refused before sending: Supabase would make an account for a new
    // Google or Apple user.
    if (idTokenEmail(idToken)?.toLowerCase() != l.email.toLowerCase()) {
      return Future.value(ReauthOutcome.wrongAccount);
    }
    return c.signInAgainAs(
      userId: l.userId,
      signIn: (auth) => auth.signInWithIdToken(provider: provider, idToken: idToken, nonce: rawNonce),
    );
  }
}

final accountReauthProvider = Provider<AccountReauth>((ref) {
  final available = ref.watch(cloudSyncAvailableProvider);
  final db = ref.watch(appDatabaseProvider);
  return CloudAccountReauth(
    cloud: available ? ref.watch(cloudSyncServiceProvider) : null,
    googlePicker: ref.watch(googlePickerProvider),
    applePicker: ref.watch(applePickerProvider),
    linked: () => linkedCloudAccount(db),
  );
});

final phoneEraserProvider =
    Provider<PhoneEraser>((ref) => PhoneEraser(ref.watch(appDatabaseProvider), secrets: ref.watch(secretStoreProvider)));

/// The word typed to confirm erasing, in the person's language.
String eraseConfirmWord() => tr('ERASE');

/// Whether [typed] is the confirmation word: the one on the screen, or
/// ERASE, which every keyboard can type (an Indic or Arabic keyboard may
/// put the same word together from other characters). Capitals, spaces
/// around it and invisible joiners do not count; anything else does.
bool eraseWordMatches(String typed) {
  final t = _foldWord(typed);
  return t.isNotEmpty && (t == _foldWord(eraseConfirmWord()) || t == 'erase');
}

String _foldWord(String s) {
  const same = {
    // Romanian s and t with cedilla, from older keyboards.
    'ş': 'ș', 'ţ': 'ț',
    // Devanagari candrabindu typed for anusvara.
    'ँ': 'ं',
    // Arabic yeh, alef maksura and kaf from an Arabic keyboard, for Urdu.
    'ي': 'ی', 'ى': 'ی', 'ك': 'ک',
  };
  final out = StringBuffer();
  for (final ch in s.toLowerCase().runes.map(String.fromCharCode)) {
    if (RegExp('[­ـً-ْ​-‏⁠﻿]').hasMatch(ch)) continue;
    out.write(same[ch] ?? ch);
  }
  return out.toString().trim().replaceAll(RegExp(r'\s+'), ' ');
}

enum PinResetStep {
  checking,

  /// No usable cloud session: sign in to keep the data (when the data was
  /// linked to an account), or erase the phone.
  noSession,
  choose,
  password,
  emailCode,

  /// The warning and the confirmation word.
  erase,

  /// Signed in again: the count is cleared and a new PIN may be set.
  newPin,
  done,

  /// Everything on the phone is gone: back to first launch.
  erased,
}

/// The Forgot PIN steps, with no widgets. Only [newPin] is reachable
/// without a successful sign-in, and only [setPin] there changes the PIN.
/// Only [confirmErase], with the confirmation word, runs [erase].
class PinReset extends ChangeNotifier {
  PinReset({required this.lock, required this.reauth, required this.erase});
  final AppLock lock;
  final AccountReauth reauth;

  /// Wipes the phone ([PhoneEraser] and signing out).
  final Future<void> Function() erase;

  PinResetStep _step = PinResetStep.checking;
  PinResetStep get step => _step;

  ReauthAccount? _account;
  ReauthAccount? get account => _account;

  /// With no session: whether signing in can keep the data.
  bool get canSignIn => _account?.methods.isNotEmpty ?? false;

  /// Why the last try did not work; cleared by the next one.
  ReauthOutcome? _error;
  ReauthOutcome? get error => _error;

  bool _eraseFailed = false;
  bool get eraseFailed => _eraseFailed;

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
    _go(a != null && a.signedIn && a.methods.isNotEmpty ? PinResetStep.choose : PinResetStep.noSession);
  }

  /// No session: on to the ways of signing in to the linked account.
  void signInToKeep() {
    if (_busy || _step != PinResetStep.noSession || !canSignIn) return;
    _error = null;
    _go(PinResetStep.choose);
  }

  /// No session: on to the erase warning. Nothing is erased yet.
  void startErase() {
    if (_busy || _step != PinResetStep.noSession) return;
    _eraseFailed = false;
    _go(PinResetStep.erase);
  }

  /// Erases the phone, only with the confirmation word typed.
  Future<bool> confirmErase(String typed) async {
    if (_busy || _step != PinResetStep.erase || !eraseWordMatches(typed)) return false;
    _busy = true;
    _eraseFailed = false;
    _notify();
    try {
      await erase();
    } catch (_) {
      _busy = false;
      _eraseFailed = true;
      _notify();
      return false;
    }
    _busy = false;
    _go(PinResetStep.erased);
    return true;
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

  /// One step back. Never past the sign-in: the reset needs one.
  void back() {
    if (_busy) return;
    switch (_step) {
      case PinResetStep.password:
      case PinResetStep.emailCode:
        _error = null;
        _go(PinResetStep.choose);
      case PinResetStep.choose when !(_account?.signedIn ?? true):
        _error = null;
        _go(PinResetStep.noSession);
      case PinResetStep.erase:
        _eraseFailed = false;
        _go(PinResetStep.noSession);
      default:
        break;
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
/// set or the phone is erased; [onCancel] goes back to the PIN pad with
/// its wait as it was.
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
  final _eraseWord = TextEditingController();

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
    _eraseWord.dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    if (_r.step == PinResetStep.done || _r.step == PinResetStep.erased) {
      widget.onDone();
      return;
    }
    if (_r.step != PinResetStep.erase) _eraseWord.clear();
    setState(() {});
  }

  static const _bg = Color(0xFF14213D);
  static const _errorColor = Color(0xFFFFB4AB);
  static const _danger = Color(0xFFB3261E);

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

  Widget _button(String label, VoidCallback? onPressed, {bool danger = false}) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: danger
                ? FilledButton.styleFrom(
                    backgroundColor: _danger,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.white12,
                    disabledForegroundColor: Colors.white38,
                  )
                : null,
            onPressed: _r.busy ? null : onPressed,
            child: Text(label, textAlign: TextAlign.center),
          ),
        ),
      );

  Widget _outlined(String label, VoidCallback? onPressed) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: _errorColor,
              side: const BorderSide(color: _errorColor),
            ),
            onPressed: _r.busy ? null : onPressed,
            child: Text(label, textAlign: TextAlign.center),
          ),
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
    const muted = TextStyle(color: Colors.white70);
    switch (_r.step) {
      case PinResetStep.checking:
      case PinResetStep.done:
      case PinResetStep.erased:
        return [const CircularProgressIndicator(color: Colors.white)];
      case PinResetStep.noSession:
        return [
          const Icon(Icons.cloud_off, color: Colors.white, size: 40),
          const SizedBox(height: 12),
          _text(tr('This phone is not signed in to the cloud'), style: title),
          const SizedBox(height: 8),
          _text(
            _r.canSignIn
                ? trf('The data on this phone goes with the cloud account {email}. Sign in to it to keep the data and choose a new PIN.',
                    {'email': email})
                : tr('The data on this phone was never linked to a cloud account, so signing in cannot show that it is yours. '
                    'Without the PIN, the only way in is to erase this phone and start over.'),
            style: muted,
          ),
          if (_r.canSignIn) _button(tr('Sign in to keep my data'), _r.signInToKeep),
          _outlined(tr('Erase this phone and start over'), _r.startErase),
          _link(tr('Back'), widget.onCancel),
        ];
      case PinResetStep.erase:
        final word = eraseConfirmWord();
        return [
          const Icon(Icons.warning_amber_rounded, color: _errorColor, size: 40),
          const SizedBox(height: 12),
          _text(tr('Erase this phone?'), style: title),
          const SizedBox(height: 8),
          _text(
            tr('Everything on this phone that is not backed up to the cloud is lost for good: sites, workers, '
                'attendance, bills, photos and the rest. This cannot be undone.'),
            style: const TextStyle(color: _errorColor),
          ),
          const SizedBox(height: 12),
          _text(trf('To confirm, type {word} below.', {'word': word})),
          if (_foldWord(word) != 'erase') _text(trf('You can also type {word}.', {'word': 'ERASE'}), style: muted),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('erase-word'),
            controller: _eraseWord,
            enabled: !_r.busy,
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [LengthLimitingTextInputFormatter(40)],
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: tr('Confirmation word'), filled: true, fillColor: Colors.white),
          ),
          _button(
            tr('Erase everything'),
            eraseWordMatches(_eraseWord.text) ? () => _r.confirmErase(_eraseWord.text) : null,
            danger: true,
          ),
          _link(tr('Cancel'), _r.back),
        ];
      case PinResetStep.choose:
        return [
          const Icon(Icons.verified_user_outlined, color: Colors.white, size: 40),
          const SizedBox(height: 12),
          _text(tr('Confirm it is you'), style: title),
          const SizedBox(height: 8),
          _text(trf('To choose a new PIN, sign in again to {email}.', {'email': email}), style: muted),
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
          if (_r.account!.signedIn) _link(tr('Cancel'), widget.onCancel) else _link(tr('Back'), _r.back),
        ];
      case PinResetStep.password:
        return [
          _text(tr('Confirm it is you'), style: title),
          const SizedBox(height: 8),
          _text(email, style: muted),
          const SizedBox(height: 16),
          _field(_password, tr('Password'), obscure: true, onDone: () => _r.submitPassword(_password.text)),
          _button(tr('Next'), () => _r.submitPassword(_password.text)),
          _link(tr('Back'), _r.back),
        ];
      case PinResetStep.emailCode:
        return [
          _text(tr('Confirm it is you'), style: title),
          const SizedBox(height: 8),
          if (_r.codeSent) _text(trf('We emailed a sign-in code to {email}.', {'email': email}), style: muted),
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
                  if (_r.eraseFailed)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        tr('The phone could not be erased. Close FieldOS, open it again and try once more.'),
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
