/// Settings › Your privacy: the short notice in the language the person
/// picks, and every right in one place: a copy of their records, asking
/// for a summary, a correction, erasure or a nominee, the grievance
/// officer, the AI assistant permission and deleting the cloud account.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/core/brand.dart';
import 'package:fieldos_mobile/core/market.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/features/export/export_action.dart';
import 'package:fieldos_mobile/features/legal/legal_screen.dart';
import 'package:fieldos_mobile/features/legal/privacy_notice.dart';
import 'package:fieldos_mobile/features/team/team_sync_screen.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';

class PrivacyRightsScreen extends ConsumerStatefulWidget {
  const PrivacyRightsScreen({super.key});

  @override
  ConsumerState<PrivacyRightsScreen> createState() => _PrivacyRightsScreenState();
}

class _PrivacyRightsScreenState extends ConsumerState<PrivacyRightsScreen> {
  late AppLanguage _noticeLanguage = spokenLanguage;
  bool? _aiAllowed;

  String get _userId => ref.read(sessionProvider).user?.id ?? '';

  @override
  void initState() {
    super.initState();
    aiConsentGiven(ref.read(appDatabaseProvider), _userId).then((v) {
      if (mounted) setState(() => _aiAllowed = v);
    });
  }

  Future<void> _email(String subject) async {
    final ok = await emailSupport(subject: subject);
    if (!ok && mounted) {
      showSnack(
        context,
        trf('Write to {email} with "{subject}" as the subject.', {'email': Brand.supportEmail, 'subject': subject}),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasCompany = ref.watch(sessionProvider).activeCompany != null;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Your privacy'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Text(tr('What FieldOS collects and why'), style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final l in AppLanguage.offered)
                  ChoiceChip(
                    key: Key('notice-lang-${l.code}'),
                    label: Text(l.nativeName),
                    selected: l == _noticeLanguage,
                    onSelected: (_) => setState(() => _noticeLanguage = l),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            for (final item in privacyNoticeItems.map((i) => noticeIn(_noticeLanguage, i)))
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.heading, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(item.body, style: theme.textTheme.bodyMedium?.copyWith(height: 1.4)),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => openPrivacyPolicy(context),
                child: Text(tr('Read the full privacy policy')),
              ),
            ),
            const SectionHeader('Your choices'),
            SwitchListTile(
              key: const Key('privacy-ai-consent'),
              contentPadding: EdgeInsets.zero,
              title: Text(tr('Let Ask FieldOS send questions to AI')),
              subtitle: Text(tr('Anthropic in the USA, with Sarvam AI in India as a backup')),
              value: _aiAllowed ?? false,
              onChanged: _aiAllowed == null
                  ? null
                  : (v) async {
                      await setAiConsent(ref.read(appDatabaseProvider), _userId, v);
                      if (mounted) setState(() => _aiAllowed = v);
                    },
            ),
            if (hasCompany)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.download_outlined),
                title: Text(tr('Export my data')),
                subtitle: Text(tr('Every record on this phone, in one file you keep. Free, always.')),
                onTap: () => exportCompanyToExcel(context, ref),
              ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.person_remove_outlined),
              title: Text(tr('Delete my cloud account')),
              subtitle: Text(tr('In Team & sync. This also withdraws your consent.')),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TeamSyncScreen())),
            ),
            const SectionHeader('Your rights'),
            for (final (icon, label, subject) in [
              (Icons.summarize_outlined, tr('Ask for a summary of my data'), 'Privacy request: summary of my data'),
              (Icons.edit_note, tr('Ask to correct or erase my data'), 'Privacy request: correct or erase my data'),
              (
                Icons.supervisor_account_outlined,
                tr('Name someone to act for me'),
                'Privacy request: nominate a person',
              ),
              if (isIndia)
                (Icons.report_gmailerrorred_outlined, tr('Complain to the Grievance Officer'), 'Privacy grievance')
              else
                (Icons.report_gmailerrorred_outlined, tr('Appeal a privacy decision'), 'Privacy appeal'),
            ])
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(icon),
                title: Text(label),
                subtitle: const Text(Brand.supportEmail),
                onTap: () => _email(subject),
              ),
            const SizedBox(height: 8),
            Text(
              switch (currentMarket) {
                Market.india => tr(
                    'Write from the email address on your account. We reply within 30 days. If you are not '
                    'satisfied, you can complain to the Data Protection Board of India.',
                  ),
                Market.malaysia => tr(
                    'Write from the email address on your account. We reply within 21 days. If you are not '
                    'satisfied, you can complain to the Personal Data Protection Commissioner of Malaysia.',
                  ),
                _ => tr(
                    'Write from the email address on your account. We reply within 45 days. If you are not '
                    'satisfied, you can appeal, and then contact the authority for privacy where you live.',
                  ),
              },
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
