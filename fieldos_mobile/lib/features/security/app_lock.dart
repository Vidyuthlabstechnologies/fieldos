/// App lock: a 4-digit PIN asked when FieldOS opens and when it comes back
/// after a minute or more in the background, so a phone left on a site
/// table doesn't show the company's money and wages. The PIN is stored
/// only as a salted hash (the same hashing as passwords). Someone who
/// forgets it signs in to their cloud account again to choose a new one,
/// or, on a phone with no cloud session, erases the phone
/// (lib/features/security/pin_reset.dart); without that, the waits below
/// stand.
///
/// Wrong PINs: four digits are only 10,000 guesses, so after
/// [PinLockout.freeTries] wrong ones in a row the pad waits 30 seconds,
/// doubling with each further wrong one; at [PinLockout.signOutAt] the
/// lock is removed and the person is signed out (locally and of the cloud
/// account) and must log in with their password. Data on the phone stays.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/core/crypto.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/security/pin_reset.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/services/notification_service.dart' show appNavigatorKey;
import 'package:fieldos_mobile/sync/cloud_sync_bootstrap.dart';
import 'package:fieldos_mobile/sync/cloud_sync_providers.dart';

const appLockPinKey = 'app_lock_pin';

/// Wrong PINs in a row, and when the current wait started (ms since
/// epoch), kept next to the PIN so killing the app doesn't reset them.
const appLockFailsKey = 'app_lock_fails';
const appLockLockedAtKey = 'app_lock_locked_at';

/// Away this long, and the PIN is asked again.
const appLockAfter = Duration(minutes: 1);

bool isValidPin(String pin) => RegExp(r'^\d{4}$').hasMatch(pin);

/// The wrong-PIN rules, with no storage or clock of their own.
class PinLockout {
  const PinLockout({this.fails = 0, this.lockedAt});

  /// Wrong PINs in a row.
  final int fails;

  /// When the current wait started; null when there is none.
  final DateTime? lockedAt;

  static const none = PinLockout();

  /// Wrong PINs allowed before the first wait.
  static const freeTries = 5;

  /// Wrong PINs in a row that remove the lock and sign the person out.
  static const signOutAt = 10;

  static const firstWait = Duration(seconds: 30);

  /// The wait after [fails] wrong PINs: none below [freeTries], then 30 s,
  /// 60 s, 120 s...
  static Duration waitAfter(int fails) =>
      fails < freeTries ? Duration.zero : firstWait * (1 << (fails - freeTries).clamp(0, 20));

  bool get mustSignIn => fails >= signOutAt;

  /// Wrong PINs left before the forced sign-out.
  int get triesLeft => (signOutAt - fails).clamp(0, signOutAt);

  /// A start in the future means the clock was set back: the wait counts
  /// from [now] instead, so turning the clock back never shortens it.
  PinLockout settle(DateTime now) {
    final at = lockedAt;
    return at != null && at.isAfter(now) ? PinLockout(fails: fails, lockedAt: now) : this;
  }

  /// How long PIN entry stays refused.
  Duration remaining(DateTime now) {
    final at = settle(now).lockedAt;
    if (at == null) return Duration.zero;
    final left = at.add(waitAfter(fails)).difference(now);
    return left.isNegative ? Duration.zero : left;
  }

  bool isLocked(DateTime now) => remaining(now) > Duration.zero;

  /// After one more wrong PIN at [now].
  PinLockout wrong(DateTime now) {
    final n = fails + 1;
    return PinLockout(fails: n, lockedAt: waitAfter(n) > Duration.zero ? now : null);
  }

  @override
  bool operator ==(Object other) => other is PinLockout && other.fails == fails && other.lockedAt == lockedAt;

  @override
  int get hashCode => Object.hash(fails, lockedAt);

  @override
  String toString() => 'PinLockout($fails, $lockedAt)';
}

enum PinResult {
  right,
  wrong,

  /// Refused unchecked: a wait is running.
  locked,

  /// Too many wrong PINs: the caller signs the person out.
  signOut,
}

class PinAttempt {
  const PinAttempt(this.result, {this.wait = Duration.zero, this.triesLeft = PinLockout.signOutAt});
  final PinResult result;

  /// How long entry is refused from now.
  final Duration wait;
  final int triesLeft;
}

class AppLock {
  AppLock(this._db, {DateTime Function()? clock}) : _now = clock ?? DateTime.now;
  final AppDatabase _db;
  final DateTime Function() _now;

  /// The clock the waits are measured with.
  DateTime now() => _now();

  Future<bool> isOn() async => ((await _db.settingsDao.get(appLockPinKey)) ?? '').isNotEmpty;

  Future<void> setPin(String pin) async {
    if (!isValidPin(pin)) throw ArgumentError.value(pin, 'pin', 'four digits');
    await _db.settingsDao.set(appLockPinKey, await hashPassword(pin));
    await _save(PinLockout.none);
  }

  Future<void> turnOff() async {
    await _db.settingsDao.set(appLockPinKey, '');
    await _save(PinLockout.none);
  }

  /// Clears the wrong-PIN count and wait, keeping the PIN. Only for after
  /// the person has signed in to their account again (Forgot PIN): it is
  /// the one way past a wait other than waiting.
  Future<void> clearLockout() => _save(PinLockout.none);

  /// Whether [pin] is the PIN. Counts nothing; the PIN pad uses [attempt].
  Future<bool> check(String pin) async {
    final stored = await _db.settingsDao.get(appLockPinKey);
    if (stored == null || stored.isEmpty) return true;
    return verifyPassword(pin, stored);
  }

  /// The stored wrong-PIN state. A wait that started "in the future"
  /// (clock set back) is restarted from now and saved that way.
  Future<PinLockout> lockout() async {
    final fails = int.tryParse(await _db.settingsDao.get(appLockFailsKey) ?? '') ?? 0;
    final ms = int.tryParse(await _db.settingsDao.get(appLockLockedAtKey) ?? '');
    final stored = PinLockout(fails: fails, lockedAt: ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms));
    final settled = stored.settle(_now());
    if (settled != stored) await _save(settled);
    return settled;
  }

  Future<void> _save(PinLockout s) async {
    await _db.settingsDao.set(appLockFailsKey, '${s.fails}');
    await _db.settingsDao.set(appLockLockedAtKey, s.lockedAt == null ? '' : '${s.lockedAt!.millisecondsSinceEpoch}');
  }

  /// One PIN typed on the pad: checks it unless a wait is running, and
  /// counts it.
  Future<PinAttempt> attempt(String pin) async {
    final s = await lockout();
    if (s.mustSignIn) return const PinAttempt(PinResult.signOut, triesLeft: 0);
    final now = _now();
    if (s.isLocked(now)) return PinAttempt(PinResult.locked, wait: s.remaining(now), triesLeft: s.triesLeft);
    if (await check(pin)) {
      await _save(PinLockout.none);
      return const PinAttempt(PinResult.right);
    }
    final next = s.wrong(now);
    await _save(next);
    if (next.mustSignIn) return const PinAttempt(PinResult.signOut, triesLeft: 0);
    return PinAttempt(PinResult.wrong, wait: next.remaining(now), triesLeft: next.triesLeft);
  }
}

/// "0:30", "2:00" for a wait on the PIN pad.
String formatPinWait(Duration d) {
  final s = (d.inMilliseconds / 1000).ceil();
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

final appLockProvider = Provider<AppLock>((ref) => AppLock(ref.watch(appDatabaseProvider)));

final appLockOnProvider = FutureProvider<bool>((ref) => ref.watch(appLockProvider).isOn());

/// Whether to lock on coming back, given when the app went to the
/// background.
bool shouldLockOnResume(DateTime? pausedAt, DateTime now) =>
    pausedAt != null && now.difference(pausedAt) >= appLockAfter;

/// Wraps the app: shows the PIN pad over it when locked, keeping the
/// screen underneath as it was.
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate> with WidgetsBindingObserver {
  bool _locked = false;
  bool _checkedAtLaunch = false;
  DateTime? _pausedAt;

  /// What the pad shows; the overlay entry below is built once, so it
  /// listens to this instead of the gate's setState.
  final _view = ValueNotifier<int>(0);
  Duration _wait = Duration.zero;
  int? _triesLeft;

  /// Bumped when a wait starts, so the pad starts a fresh countdown.
  int _waitSerial = 0;

  /// Signed out after too many wrong PINs: says so before showing the
  /// log-in screen.
  bool _forcedOut = false;

  /// Forgot PIN, while it is open.
  PinReset? _reset;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lockIfOn();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reset?.dispose();
    _view.dispose();
    super.dispose();
  }

  void _show({required Duration wait, int? triesLeft}) {
    _wait = wait;
    _triesLeft = triesLeft;
    if (wait > Duration.zero) _waitSerial++;
    _view.value++;
  }

  /// The tries-left line shows once the waits have started.
  static int? _warnTries(int triesLeft) =>
      triesLeft <= PinLockout.signOutAt - PinLockout.freeTries ? triesLeft : null;

  Future<void> _lockIfOn() async {
    final lock = ref.read(appLockProvider);
    final on = await lock.isOn();
    final state = on ? await lock.lockout() : PinLockout.none;
    if (!mounted) return;
    if (state.mustSignIn) {
      // Killed part-way through the sign-out: finish it.
      setState(() {
        _locked = true;
        _checkedAtLaunch = true;
      });
      await _forceSignOut();
      return;
    }
    _show(wait: state.remaining(lock.now()), triesLeft: _warnTries(state.triesLeft));
    setState(() {
      _locked = on;
      _checkedAtLaunch = true;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _pausedAt ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final lock = shouldLockOnResume(_pausedAt, DateTime.now());
      _pausedAt = null;
      if (lock) _lockIfOn();
    }
  }

  Future<bool> _submit(String pin) async {
    final r = await ref.read(appLockProvider).attempt(pin);
    if (!mounted) return false;
    switch (r.result) {
      case PinResult.right:
        _show(wait: Duration.zero);
        setState(() => _locked = false);
        return true;
      case PinResult.wrong:
      case PinResult.locked:
        _show(wait: r.wait, triesLeft: _warnTries(r.triesLeft));
        return false;
      case PinResult.signOut:
        await _forceSignOut();
        return false;
    }
  }

  /// Ten wrong PINs: the lock comes off and the person is signed out, of
  /// the cloud account too (as Team sync's Sign out does), so only the
  /// password gets back in. The data on the phone is not touched.
  Future<void> _forceSignOut() async {
    await _signOutEverywhere();
    // Last, so a phone killed before here finishes the sign-out on launch.
    await ref.read(appLockProvider).turnOff();
    ref.invalidate(appLockOnProvider);
    if (!mounted) return;
    _forcedOut = true;
    _show(wait: Duration.zero);
  }

  /// Stops sync, signs out of the cloud account and of the phone's own
  /// account. Shared by the forced sign-out and erasing the phone.
  Future<void> _signOutEverywhere() async {
    try {
      ref.read(cloudSyncBootstrapProvider).stop();
      if (ref.read(cloudSyncAvailableProvider)) await ref.read(cloudSyncServiceProvider).disableSync();
    } catch (_) {
      // Best effort: the local sign-out below is what stops the guessing.
    }
    await ref.read(sessionProvider.notifier).logout();
  }

  /// Forgot PIN with no cloud session, after the confirmation word: the
  /// sign-out above, then every record, setting (the PIN, the cloud
  /// session) and file on the phone, and back to first launch.
  ///
  /// Erase is only offered with no usable session, so disableSync has
  /// nothing it could send; the outbox goes with the database.
  Future<void> _erasePhone() async {
    await _signOutEverywhere();
    await ref.read(phoneEraserProvider).erase();
    try {
      // Reminders already planned would still name the erased sites.
      await ref.read(notificationServiceProvider).replaceScheduled(const []).timeout(const Duration(seconds: 5));
    } catch (_) {}
    ref.invalidate(appLockOnProvider);
    ref.invalidate(sessionProvider);
    ref.invalidate(languageChosenProvider);
    appNavigatorKey.currentState?.popUntil((r) => r.isFirst);
  }

  Widget _pad() {
    final reset = _reset;
    if (reset != null) {
      return ForgotPinScreen(
        key: ObjectKey(reset),
        reset: reset,
        onDone: () => _closeReset(unlock: true),
        onCancel: () => _closeReset(unlock: false),
      );
    }
    if (_forcedOut) {
      return _SignedOutNotice(
        onOk: () {
          _forcedOut = false;
          setState(() => _locked = false);
        },
      );
    }
    return PinPad(
      // A new wait starts a fresh countdown.
      key: ValueKey(_waitSerial),
      title: tr('Enter your PIN'),
      lockedFor: _wait,
      note: _triesLeft == null ? null : trf('Tries left before sign-out: {n}', {'n': _triesLeft!}),
      onSubmit: _submit,
      onForgot: _forgot,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Until the first check is done, show nothing of the app.
    final hide = _locked || !_checkedAtLaunch;
    return Stack(
      children: [
        widget.child,
        if (hide)
          Positioned.fill(
            // Above the app's navigator, so it brings its own overlay for
            // the buttons' tooltips.
            child: _checkedAtLaunch
                ? Overlay(
                    initialEntries: [
                      OverlayEntry(
                        builder: (_) => ValueListenableBuilder<int>(
                          valueListenable: _view,
                          builder: (_, _, _) => _pad(),
                        ),
                      ),
                    ],
                  )
                : const ColoredBox(color: Color(0xFF14213D)),
          ),
      ],
    );
  }

  /// Forgot PIN: nothing is cleared or signed out here. The count and the
  /// wait stay until [PinReset] has signed in to the account again.
  void _forgot() {
    if (_reset != null) return;
    _reset = PinReset(lock: ref.read(appLockProvider), reauth: ref.read(accountReauthProvider), erase: _erasePhone)
      ..start();
    _view.value++;
  }

  Future<void> _closeReset({required bool unlock}) async {
    final reset = _reset;
    _reset = null;
    // After the frame: the screen that called this is still building.
    WidgetsBinding.instance.addPostFrameCallback((_) => reset?.dispose());
    if (unlock) {
      // Signed in again: a phone that had no session was not syncing.
      if (reset?.step == PinResetStep.done) unawaited(ref.read(cloudSyncBootstrapProvider).ensureRunning().catchError((_) {}));
      _show(wait: Duration.zero);
      if (mounted) setState(() => _locked = false);
      return;
    }
    // Back to the pad with the wait as it stands now, not as it was.
    final lock = ref.read(appLockProvider);
    final state = await lock.lockout();
    if (!mounted) return;
    _show(wait: state.remaining(lock.now()), triesLeft: _warnTries(state.triesLeft));
    _waitSerial++;
    _view.value++;
  }
}

class _SignedOutNotice extends StatelessWidget {
  const _SignedOutNotice({required this.onOk});
  final VoidCallback onOk;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFF14213D),
    child: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_open, color: Colors.white, size: 40),
              const SizedBox(height: 16),
              Text(
                tr('Too many wrong PINs. The app lock is off. Log in again with your password.'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 24),
              FilledButton(onPressed: onOk, child: Text(tr('Log in'))),
            ],
          ),
        ),
      ),
    ),
  );
}

/// A full-screen four-digit PIN pad. [onSubmit] returns whether the PIN
/// was right; a wrong one shakes the dots clear.
class PinPad extends StatefulWidget {
  const PinPad({
    super.key,
    required this.title,
    required this.onSubmit,
    this.onForgot,
    this.onCancel,
    this.lockedFor = Duration.zero,
    this.note,
  });
  final String title;

  /// Too many wrong PINs: entry is refused for this long, counting down.
  final Duration lockedFor;

  /// A line under the title, e.g. how many tries are left.
  final String? note;
  final Future<bool> Function(String pin) onSubmit;
  final VoidCallback? onForgot;
  final VoidCallback? onCancel;

  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> {
  String _pin = '';
  bool _wrong = false;
  bool _busy = false;
  Duration _left = Duration.zero;
  Timer? _timer;

  bool get _waiting => _left > Duration.zero;

  @override
  void initState() {
    super.initState();
    _left = widget.lockedFor;
    if (_waiting) {
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) return;
        setState(() {
          _left -= const Duration(seconds: 1);
          if (!_waiting) {
            _left = Duration.zero;
            t.cancel();
          }
        });
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _tap(String d) async {
    if (_busy || _waiting || _pin.length >= 4) return;
    HapticFeedback.selectionClick();
    setState(() {
      _pin += d;
      _wrong = false;
    });
    if (_pin.length < 4) return;
    setState(() => _busy = true);
    final ok = await widget.onSubmit(_pin);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!ok) {
        _wrong = true;
        _pin = '';
      }
    });
  }

  void _back() {
    if (_pin.isEmpty || _waiting) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget key(String d) => SizedBox(
      width: 76,
      height: 76,
      child: TextButton(
        onPressed: _waiting ? null : () => _tap(d),
        style: TextButton.styleFrom(
          shape: const CircleBorder(),
          foregroundColor: Colors.white,
          disabledForegroundColor: Colors.white24,
        ),
        child: Text(d, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w500)),
      ),
    );
    return Material(
      color: const Color(0xFF14213D),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, color: Colors.white, size: 40),
                const SizedBox(height: 12),
                Text(widget.title, style: theme.textTheme.titleLarge?.copyWith(color: Colors.white)),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 20),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: _waiting
                        ? Text(
                            trf('Too many wrong PINs. Wait {time}.', {'time': formatPinWait(_left)}),
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Color(0xFFFFB4AB)),
                          )
                        : _wrong
                        ? Text(
                            tr('Wrong PIN. Try again.'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Color(0xFFFFB4AB)),
                          )
                        : null,
                  ),
                ),
                if (widget.note != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
                    child: Text(widget.note!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
                  ),
                const SizedBox(height: 12),
                Semantics(
                  label: trf('{n} of {total}', {'n': _pin.length, 'total': 4}),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < 4; i++)
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i < _pin.length ? Colors.white : Colors.transparent,
                            border: Border.all(color: Colors.white70, width: 2),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                for (final row in const [
                  ['1', '2', '3'],
                  ['4', '5', '6'],
                  ['7', '8', '9'],
                ])
                  Row(mainAxisSize: MainAxisSize.min, children: [for (final d in row) key(d)]),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 76,
                      height: 76,
                      child: widget.onCancel == null
                          ? null
                          : IconButton(
                              tooltip: tr('Cancel'),
                              onPressed: widget.onCancel,
                              icon: const Icon(Icons.close, color: Colors.white70),
                            ),
                    ),
                    key('0'),
                    SizedBox(
                      width: 76,
                      height: 76,
                      child: IconButton(
                        tooltip: tr('Delete'),
                        onPressed: _waiting ? null : _back,
                        icon: const Icon(Icons.backspace_outlined, color: Colors.white70),
                      ),
                    ),
                  ],
                ),
                if (widget.onForgot != null) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: widget.onForgot,
                    style: TextButton.styleFrom(foregroundColor: Colors.white70),
                    child: Text(tr('Forgot PIN?')),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Settings: asks for a new PIN twice. Returns the PIN, or null.
Future<String?> askNewPin(BuildContext context) => Navigator.of(context).push<String>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (ctx) => NewPinPad(onChosen: (pin) async => Navigator.of(ctx).pop(pin), onCancel: () => Navigator.of(ctx).pop()),
  ),
);

/// A new PIN, typed twice; starts over when the two differ.
class NewPinPad extends StatefulWidget {
  const NewPinPad({super.key, required this.onChosen, this.onCancel});
  final Future<void> Function(String pin) onChosen;
  final VoidCallback? onCancel;

  @override
  State<NewPinPad> createState() => _NewPinPadState();
}

class _NewPinPadState extends State<NewPinPad> {
  String? _first;
  bool _mismatch = false;

  @override
  Widget build(BuildContext context) => PinPad(
    key: ValueKey('${_first == null}$_mismatch'),
    title: _first != null
        ? tr('Enter the same PIN again')
        : _mismatch
        ? tr('The PINs did not match. Choose again.')
        : tr('Choose a 4-digit PIN'),
    onCancel: widget.onCancel,
    onSubmit: (pin) async {
      if (_first == null) {
        setState(() => _first = pin);
        return true;
      }
      if (pin != _first) {
        setState(() {
          _first = null;
          _mismatch = true;
        });
        return false;
      }
      await widget.onChosen(pin);
      return true;
    },
  );
}
