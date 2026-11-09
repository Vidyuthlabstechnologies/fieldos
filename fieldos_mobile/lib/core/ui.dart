/// Shared building blocks so every screen handles "nothing here yet",
/// "something went wrong" and "done" the same way, in plain words.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:supabase/supabase.dart' as sb;

import 'package:fieldos_mobile/auth/auth_service.dart';
import 'package:fieldos_mobile/core/brand.dart';
import 'package:fieldos_mobile/services/bug_report_service.dart';
import 'package:fieldos_mobile/l10n/language.dart';

/// A message a site engineer can act on, never a stack trace or a database
/// row. Anything unexpected is kept for the next bug report.
String friendlyError(Object error, [StackTrace? stack]) {
  if (error is AuthException) return error.message;
  if (error is SocketException || error is HttpException || error is HandshakeException) return offlineMessage;
  if (error is TimeoutException) return 'That took too long. Check your connection and try again.';
  final known = switch (error) {
    sb.AuthException e => _cloudAuthMessage(e),
    sb.PostgrestException e => _cloudServerMessage(e),
    _ => null,
  };
  if (known != null) return known;
  final text = error.toString();
  if (text.contains('SocketException') ||
      text.contains('ClientException') ||
      text.contains('Failed host lookup') ||
      text.contains('Connection refused')) {
    return offlineMessage;
  }
  RecentErrors.record(error, stack);
  return 'Something went wrong. Please try again, or send a bug report from the menu.';
}

const offlineMessage = 'No internet connection. Your work is saved on this phone; try again when you are online.';
const _cloudDownMessage =
    'The FieldOS cloud is not answering right now. Your work is saved on this phone; try again in a few minutes.';
const _signInAgainMessage = 'Your cloud sign-in has ended. Sign in again from Team & sync.';

/// Supabase Auth's errors, by their stable codes. A message the server
/// wrote for people is passed on when it is short; anything else is null.
String? _cloudAuthMessage(sb.AuthException e) {
  // No answer at all (offline), or the server itself failed (5xx), whose
  // body may be a whole HTML page.
  if (e is sb.AuthRetryableFetchException) return e.statusCode == null ? offlineMessage : _cloudDownMessage;
  if (e is sb.AuthUnknownException) return _cloudDownMessage;
  if (e is sb.AuthSessionMissingException) return 'Sign in from Team & sync first.';
  switch (e.code) {
    case 'invalid_credentials':
      return 'That email and password do not match. Check them and try again.';
    case 'email_not_confirmed':
      return 'Confirm your email first: open the link we sent you, then sign in here.';
    case 'user_already_exists' || 'email_exists':
      return 'That email already has a FieldOS cloud account. Sign in with its password.';
    case 'otp_expired':
      return 'That code is not right, or it is too old. Check it, or send a new code.';
    case 'same_password':
      return 'That is already your password. Choose a different one, or sign in with it.';
    case 'over_email_send_rate_limit' || 'over_request_rate_limit' || 'over_sms_send_rate_limit':
      return 'Too many tries in a short time. Wait a few minutes, then try again.';
    case 'signup_disabled':
      return 'New cloud accounts are switched off for now. Write to us at the support address and we will help.';
    case 'email_address_invalid' || 'email_address_not_authorized':
      return 'That email address cannot be used. Check it, or try another.';
    case 'session_expired' || 'session_not_found' || 'refresh_token_not_found' || 'refresh_token_already_used':
    case 'bad_jwt' || 'user_not_found':
      return _signInAgainMessage;
  }
  return _shortSentence(e.message);
}

/// Our own RPCs' messages (supabase/migrations), then PostgREST's codes.
/// Raw SQL text never reaches the screen.
String? _cloudServerMessage(sb.PostgrestException e) {
  switch (e.message.trim().toLowerCase()) {
    case 'invalid join code':
      return 'That join code is not right. Check it with the person who shared it: it is 10 letters and numbers.';
    case 'too many join attempts':
      return 'Too many wrong join codes. Wait an hour, then try again with the code from your company owner.';
    case 'this company is already registered to another account':
      return 'This company is already on the cloud under another account. Ask its owner for a join code.';
    case 'not authenticated' || 'sign in first':
      return 'Sign in from Team & sync first.';
    case 'only the company owner can change roles':
      return 'Only the company owner can change roles.';
    case 'owners cannot change their own role':
      return 'You are the owner, so your own role stays the same.';
    case 'only the company owner can reset the join code':
      return 'Only the company owner can make a new join code.';
    case 'only the company owner can remove people':
      return 'Only the company owner can remove people from the team.';
    case 'the owner cannot be removed':
      return 'The company owner cannot be removed from the team.';
  }
  switch (e.code) {
    case 'PGRST301' || 'PGRST302' || 'PGRST303' || '28000':
      return _signInAgainMessage;
    case '42501':
      return 'Your role in this company does not allow that. Ask the owner.';
  }
  return null;
}

/// [m] as a sentence, when it is short enough to be meant for people.
String? _shortSentence(String m) {
  final t = m.trim();
  if (t.isEmpty || t.length > 140 || t.contains('\n') || t.contains('{') || t.contains('<')) return null;
  final s = '${t[0].toUpperCase()}${t.substring(1)}';
  return s.endsWith('.') || s.endsWith('!') || s.endsWith('?') ? s : '$s.';
}

void showSnack(BuildContext context, String message, {bool error = false, SnackBarAction? action}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Row(children: [
        Icon(error ? Icons.error_outline : Icons.check_circle_outline,
            color: error ? const Color(0xFFFFB4AB) : Brand.amber, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(tr(message))),
      ]),
      action: action,
      duration: Duration(seconds: error ? 6 : 3),
    ));
}

/// "Nothing here yet" with a picture, one sentence of why it matters, and
/// the button that fixes it.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.secondaryLabel,
    this.onSecondary,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// A quieter second choice under the main one.
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = Padding(
      padding: EdgeInsets.symmetric(horizontal: 32, vertical: compact ? 16 : 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: compact ? 56 : 76,
            height: compact ? 56 : 76,
            decoration: BoxDecoration(color: theme.colorScheme.secondaryContainer, shape: BoxShape.circle),
            child: Icon(icon, size: compact ? 28 : 38, color: theme.colorScheme.onSecondaryContainer),
          ),
          const SizedBox(height: 16),
          Text(title, textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(message!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 18),
            FilledButton.icon(onPressed: onAction, icon: const Icon(Icons.add), label: Text(actionLabel!)),
          ],
          if (secondaryLabel != null && onSecondary != null) ...[
            const SizedBox(height: 8),
            OutlinedButton(onPressed: onSecondary, child: Text(secondaryLabel!)),
          ],
        ],
      ),
    );
    // Scrollable so pull-to-refresh still works on an empty list.
    return LayoutBuilder(
      builder: (context, c) => ListView(
        // A compact one sits inside another list, which does the scrolling.
        physics: compact ? const NeverScrollableScrollPhysics() : const AlwaysScrollableScrollPhysics(),
        shrinkWrap: compact,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: compact || !c.hasBoundedHeight ? 0 : c.maxHeight * 0.8),
            child: Center(child: content),
          ),
        ],
      ),
    );
  }
}

/// A failed load, in plain words, with a way to try again.
class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.error, this.stack, this.onRetry});

  final Object error;
  final StackTrace? stack;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 44, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(friendlyError(error, stack),
                textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: Text(tr('Try again'))),
            ],
          ],
        ),
      ),
    );
  }
}

/// A small coloured label for statuses: "open", "paid", "late".
class StatusPill extends StatelessWidget {
  const StatusPill(this.label, {super.key, this.tone = PillTone.neutral});

  final String label;
  final PillTone tone;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final (bg, fg) = switch (tone) {
      PillTone.ok => (dark ? const Color(0xFF173D2B) : Brand.okSoft, dark ? const Color(0xFF8FD9B0) : Brand.ok),
      PillTone.warn => (dark ? const Color(0xFF4A3305) : Brand.warnSoft, dark ? Brand.amber : Brand.warn),
      PillTone.danger => (dark ? const Color(0xFF4A1A1A) : Brand.dangerSoft, dark ? const Color(0xFFFF9C9C) : Brand.danger),
      PillTone.neutral => (
          Theme.of(context).colorScheme.surfaceContainerHighest,
          Theme.of(context).colorScheme.onSurfaceVariant
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

enum PillTone { ok, warn, danger, neutral }

/// The text or icon colour for [tone], readable in light and dark mode.
Color toneColor(BuildContext context, PillTone tone) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return switch (tone) {
    PillTone.ok => dark ? const Color(0xFF8FD9B0) : Brand.ok,
    PillTone.warn => dark ? Brand.amber : Brand.warn,
    PillTone.danger => dark ? const Color(0xFFFF9C9C) : Brand.danger,
    PillTone.neutral => Theme.of(context).colorScheme.onSurfaceVariant,
  };
}

/// A section heading inside long screens (settings, reports).
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.padding = const EdgeInsets.fromLTRB(4, 20, 4, 8)});

  final String title;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding,
      child: Text(tr(title).toUpperCase(),
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w700,
          )),
    );
  }
}

/// The result of a form, under its fields: red with a warning sign for a
/// problem, green with a tick when something worked.
class FormMessage extends StatelessWidget {
  const FormMessage(this.message, {super.key, this.error = true});

  final String message;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final color = error ? theme.colorScheme.error : (dark ? const Color(0xFF8FD9B0) : Brand.ok);
    return Semantics(
      liveRegion: true,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(error ? Icons.error_outline : Icons.check_circle_outline, size: 20, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(message, style: theme.textTheme.bodyMedium?.copyWith(color: color))),
      ]),
    );
  }
}

/// Keeps every screen clear of the phone's own navigation: the 3-button
/// bar (back, home, recents) or the gesture bar. Android 15 draws apps
/// edge to edge, under that bar, so without this the bottom buttons
/// (Add task, Speak report, a chat's send box...) sat behind back/home.
/// The strip under the bar is painted in the page colour.
class SystemNavBarSafeArea extends StatelessWidget {
  const SystemNavBarSafeArea({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    return ColoredBox(
      color: dark ? const Color(0xFF0A1424) : Brand.paper,
      child: SafeArea(top: false, left: false, right: false, child: child),
    );
  }
}
