import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'package:fieldos_mobile/auth/apple_auth.dart';
import 'package:fieldos_mobile/auth/google_auth.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/services/bug_report_service.dart';
import 'package:fieldos_mobile/sync/cloud_sync_providers.dart';
import 'package:fieldos_mobile/sync/cloud_sync_service.dart';

/// "Sign in with Apple" (iPhone) and "Continue with Google" for the cloud
/// account only, shown above the email form on Team & sync and the portal
/// screens. New cloud accounts are made this way: email sign-up is off on
/// the server (security review 2026-11-21, pre-account takeover), so the
/// email form only signs in to accounts that already exist.
///
/// Shows nothing when neither is available in this build.
class CloudSignInButtons extends ConsumerStatefulWidget {
  const CloudSignInButtons({super.key, required this.onSignedIn, required this.onError, this.enabled = true});

  /// Called after the cloud session is open.
  final Future<void> Function() onSignedIn;

  /// A sentence to show the person when sign-in did not go through.
  final void Function(String message) onError;
  final bool enabled;

  @override
  ConsumerState<CloudSignInButtons> createState() => _CloudSignInButtonsState();
}

class _CloudSignInButtonsState extends ConsumerState<CloudSignInButtons> {
  bool _busy = false;

  Future<void> _run(Future<CloudSyncResult?> Function() signIn, String didNotGoThrough) async {
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      final result = await signIn();
      if (result == null) return; // the person closed the picker
      if (result.outcome == CloudSyncOutcome.failed) {
        widget.onError(friendlyError(result.cause ?? StateError('cloud sign-in failed'), result.stack));
        return;
      }
      await widget.onSignedIn();
    } on GoogleSignInException catch (e, st) {
      RecentErrors.record(e, st);
      widget.onError(didNotGoThrough);
    } on SignInWithAppleException catch (e, st) {
      RecentErrors.record(e, st);
      widget.onError(didNotGoThrough);
    } catch (e, st) {
      widget.onError(friendlyError(e, st));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _google() => _run(() async {
    final picked = await ref.read(googlePickerProvider).pick();
    if (picked == null) return null;
    return ref.read(cloudSyncServiceProvider).enableSyncWithGoogle(idToken: picked.idToken);
  }, tr('Google sign-in did not go through. Please try again.'));

  Future<void> _apple() => _run(() async {
    final picked = await ref.read(applePickerProvider).pick();
    if (picked == null) return null;
    final signedIn = await ref
        .read(cloudSyncServiceProvider)
        .enableSyncWithApple(idToken: picked.idToken, rawNonce: picked.rawNonce);
    return signedIn.result;
  }, tr('Apple sign-in did not go through. Please try again.'));

  @override
  Widget build(BuildContext context) {
    final apple = ref.watch(applePickerProvider).available;
    final google = ref.watch(googlePickerProvider).available;
    if (!apple && !google) return const SizedBox.shrink();
    final off = _busy || !widget.enabled;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (apple) ...[
          SizedBox(
            height: 48,
            child: SignInWithAppleButton(
              key: const Key('cloud-apple'),
              onPressed: off ? () {} : _apple,
              text: tr('Sign in with Apple'),
              borderRadius: const BorderRadius.all(Radius.circular(12)),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (google) ...[
          OutlinedButton.icon(
            key: const Key('cloud-google'),
            onPressed: off ? null : _google,
            icon: const Icon(Icons.account_circle_outlined),
            label: Text(tr('Continue with Google')),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
          const SizedBox(height: 12),
        ],
        Row(
          children: [
            const Expanded(child: Divider()),
            // Long in some languages: it wraps rather than pushing the lines off.
            Flexible(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  tr('or, with an account you already have'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
            const Expanded(child: Divider()),
          ],
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}
