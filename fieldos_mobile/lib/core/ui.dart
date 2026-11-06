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

/// A message a site engineer can act on, never a stack trace or a database
/// row. Anything unexpected is kept for the next bug report.
String friendlyError(Object error, [StackTrace? stack]) {
  if (error is AuthException) return error.message;
  if (error is SocketException || error is HttpException) {
    return 'No internet connection. Your work is saved on this phone; try again when you are online.';
  }
  if (error is TimeoutException) return 'That took too long. Check your connection and try again.';
  if (error is sb.AuthException) return error.message;
  if (error is sb.PostgrestException) {
    // RPCs raise readable messages ("invalid join code"); raw SQL errors
    // are not, so only short, single-line messages go to the screen.
    final m = error.message.trim();
    if (m.isNotEmpty && m.length < 140 && !m.contains('\n')) return '${m[0].toUpperCase()}${m.substring(1)}.'.replaceAll('..', '.');
  }
  final text = error.toString();
  if (text.contains('SocketException') || text.contains('Failed host lookup') || text.contains('Connection refused')) {
    return 'No internet connection. Your work is saved on this phone; try again when you are online.';
  }
  RecentErrors.record(error, stack);
  return 'Something went wrong. Please try again, or send a bug report from the menu.';
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
        Expanded(child: Text(message)),
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
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
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
        ],
      ),
    );
    // Scrollable so pull-to-refresh still works on an empty list.
    return LayoutBuilder(
      builder: (context, c) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
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
              OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Try again')),
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
      child: Text(title.toUpperCase(),
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w700,
          )),
    );
  }
}
