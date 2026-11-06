/// Reading the privacy policy and terms: the published page when its
/// address is set at build time, otherwise the copy the app carries (which
/// also works offline).
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:fieldos_mobile/core/brand.dart';
import 'package:fieldos_mobile/features/legal/legal_texts.dart';

/// The published terms page, when there is one (--dart-define=TERMS_URL=...).
const termsUrl = String.fromEnvironment('TERMS_URL');

Future<void> openPrivacyPolicy(BuildContext context) => _open(context, Brand.privacyPolicyUrl, privacyPolicy);

Future<void> openTerms(BuildContext context) => _open(context, termsUrl, termsOfUse);

Future<void> _open(BuildContext context, String url, LegalDocument doc) async {
  if (url.isNotEmpty) {
    final uri = Uri.tryParse(url);
    if (uri != null && await launchUrl(uri, mode: LaunchMode.externalApplication).catchError((_) => false)) return;
  }
  if (!context.mounted) return;
  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => LegalScreen(document: doc)));
}

/// Opens an email to support, with [subject].
Future<bool> emailSupport({String subject = 'FieldOS'}) => launchUrl(
      Uri(scheme: 'mailto', path: Brand.supportEmail, queryParameters: {'subject': subject}),
    ).catchError((_) => false);

class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key, required this.document});
  final LegalDocument document;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(document.title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            Text(document.title, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text('${Brand.companyName} · Last updated ${document.updated}',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            Text(document.intro, style: theme.textTheme.bodyLarge?.copyWith(height: 1.45)),
            for (final s in document.sections) ...[
              const SizedBox(height: 20),
              Text(s.heading, style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(s.body, style: theme.textTheme.bodyLarge?.copyWith(height: 1.45)),
            ],
          ],
        ),
      ),
    );
  }
}
