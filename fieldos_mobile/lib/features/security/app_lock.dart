/// App lock: a 4-digit PIN asked when FieldOS opens and when it comes back
/// after a minute or more in the background, so a phone left on a site
/// table doesn't show the company's money and wages. The PIN is stored
/// only as a salted hash (the same hashing as passwords). Someone who
/// forgets it logs in again with their password, which clears it.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/core/crypto.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';

const appLockPinKey = 'app_lock_pin';

/// Away this long, and the PIN is asked again.
const appLockAfter = Duration(minutes: 1);

bool isValidPin(String pin) => RegExp(r'^\d{4}$').hasMatch(pin);

class AppLock {
  AppLock(this._db);
  final AppDatabase _db;

  Future<bool> isOn() async => ((await _db.settingsDao.get(appLockPinKey)) ?? '').isNotEmpty;

  Future<void> setPin(String pin) async {
    if (!isValidPin(pin)) throw ArgumentError.value(pin, 'pin', 'four digits');
    await _db.settingsDao.set(appLockPinKey, await hashPassword(pin));
  }

  Future<void> turnOff() => _db.settingsDao.set(appLockPinKey, '');

  Future<bool> check(String pin) async {
    final stored = await _db.settingsDao.get(appLockPinKey);
    if (stored == null || stored.isEmpty) return true;
    return verifyPassword(pin, stored);
  }
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lockIfOn();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _lockIfOn() async {
    final on = await ref.read(appLockProvider).isOn();
    if (!mounted) return;
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
                        builder: (_) => PinPad(
                          title: tr('Enter your PIN'),
                          onSubmit: (pin) async {
                            final ok = await ref.read(appLockProvider).check(pin);
                            if (ok && mounted) setState(() => _locked = false);
                            return ok;
                          },
                          onForgot: _forgot,
                        ),
                      ),
                    ],
                  )
                : const ColoredBox(color: Color(0xFF14213D)),
          ),
      ],
    );
  }

  Future<void> _forgot() async {
    await ref.read(appLockProvider).turnOff();
    await ref.read(sessionProvider.notifier).logout();
    ref.invalidate(appLockOnProvider);
    if (mounted) setState(() => _locked = false);
  }
}

/// A full-screen four-digit PIN pad. [onSubmit] returns whether the PIN
/// was right; a wrong one shakes the dots clear.
class PinPad extends StatefulWidget {
  const PinPad({super.key, required this.title, required this.onSubmit, this.onForgot, this.onCancel});
  final String title;
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

  Future<void> _tap(String d) async {
    if (_busy || _pin.length >= 4) return;
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
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget key(String d) => SizedBox(
      width: 76,
      height: 76,
      child: TextButton(
        onPressed: () => _tap(d),
        style: TextButton.styleFrom(shape: const CircleBorder(), foregroundColor: Colors.white),
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
                SizedBox(
                  height: 20,
                  child: _wrong
                      ? Text(tr('Wrong PIN. Try again.'), style: const TextStyle(color: Color(0xFFFFB4AB)))
                      : null,
                ),
                const SizedBox(height: 12),
                Semantics(
                  label: '${_pin.length} of 4',
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
                        onPressed: _back,
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
                    child: Text(tr('Forgot PIN? Log in again with your password')),
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
Future<String?> askNewPin(BuildContext context) async {
  String? first;
  var mismatch = false;
  return Navigator.of(context).push<String>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => PinPad(
          key: ValueKey('${first == null}$mismatch'),
          title: first != null
              ? tr('Enter the same PIN again')
              : mismatch
              ? tr('The PINs did not match. Choose again.')
              : tr('Choose a 4-digit PIN'),
          onCancel: () => Navigator.of(ctx).pop(),
          onSubmit: (pin) async {
            if (first == null) {
              setState(() => first = pin);
              return true;
            }
            if (pin != first) {
              setState(() {
                first = null;
                mismatch = true;
              });
              return false;
            }
            Navigator.of(ctx).pop(pin);
            return true;
          },
        ),
      ),
    ),
  );
}
