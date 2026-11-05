import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:fieldos_mobile/services/bug_report_service.dart';
import 'package:fieldos_mobile/sync/cloud_sync_providers.dart';

/// "Report a bug": a short description, an optional email for a reply, and
/// the app version, phone type and last few errors attached automatically.
class BugReportScreen extends ConsumerStatefulWidget {
  const BugReportScreen({super.key});

  @override
  ConsumerState<BugReportScreen> createState() => _BugReportScreenState();
}

class _BugReportScreenState extends ConsumerState<BugReportScreen> {
  final _message = TextEditingController();
  final _email = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _message.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<String> _version() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return '${info.version}+${info.buildNumber}';
    } catch (_) {
      return 'unknown';
    }
  }

  Future<void> _send() async {
    final text = _message.text.trim();
    if (text.length < 5) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Please describe what went wrong in a few words.')));
      return;
    }
    setState(() => _sending = true);
    final report = BugReport(
      message: text.length > 5000 ? text.substring(0, 5000) : text,
      contactEmail: _email.text.trim(),
      appVersion: await _version(),
      platform: '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      recentErrors: RecentErrors.dump(),
    );
    final outcome = await ref.read(bugReportServiceProvider).submit(report);
    if (!mounted) return;
    setState(() => _sending = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(outcome == BugReportOutcome.sent
          ? 'Thank you. Your report was sent to the FieldOS team.'
          : 'No internet right now. Your report is saved and will be sent automatically.'),
    ));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Report a bug')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Tell us what happened and what you expected. We read every report.'),
          const SizedBox(height: 16),
          TextField(
            key: const Key('bug-message'),
            controller: _message,
            maxLines: 6,
            maxLength: 5000,
            decoration: const InputDecoration(
              labelText: 'What went wrong?',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('bug-email'),
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Your email (optional, so we can reply)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'The app version, phone type and the last few error messages are attached to help us fix it. '
            'No project data, photos or contacts are sent.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('bug-send'),
            onPressed: _sending ? null : _send,
            icon: _sending
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send),
            label: const Text('Send report'),
          ),
        ],
      ),
    );
  }
}
