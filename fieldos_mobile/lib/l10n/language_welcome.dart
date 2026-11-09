/// The first thing a new install shows: "Which language do you speak?",
/// with one big tile per language in its own script. Nothing is picked for
/// the person; the phone's own language is only listed first.
///
/// The choice sets how Mitra talks and listens (mixed with English, as
/// people speak). Screens stay in English unless the person later turns on
/// "Show screens in ..." in Settings.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/features/mascot/mitra.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/services/read_aloud.dart';

class LanguageWelcomeScreen extends ConsumerWidget {
  const LanguageWelcomeScreen({super.key});

  /// The phone's language first, then the rest in the usual order.
  static List<AppLanguage> order([List<Locale>? locales]) {
    final phone = languageFromDevice(locales);
    return [phone, for (final l in AppLanguage.values) if (l != phone) l];
  }

  Future<void> _pick(WidgetRef ref, AppLanguage l) async {
    await ref.read(languageProvider.notifier).choose(l);
    // Mitra answers in the language just picked, as a check it's right.
    await ReadAloud.guide('greet');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final langs = order();
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
          children: [
            const Center(child: Mitra(mood: MitraMood.wave, size: 120)),
            const SizedBox(height: 12),
            Text('Which language do you speak?',
                textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 6),
            Text(
              'మీ భాష ఏది? · आपकी भाषा? · உங்கள் மொழி? · ನಿಮ್ಮ ಭಾಷೆ? · तुमची भाषा?',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Text(
              'Mitra will talk with you in it, mixed with English. You can change it any time in Settings.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.6,
              children: [for (final l in langs) _LanguageTile(language: l, onTap: () => _pick(ref, l))],
            ),
          ],
        ),
      ),
    );
  }
}

class _LanguageTile extends StatelessWidget {
  const _LanguageTile({required this.language, required this.onTap});
  final AppLanguage language;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      button: true,
      label: '${language.nativeName}, ${language.englishName}',
      excludeSemantics: true,
      child: Material(
        color: scheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(language.nativeName, style: theme.textTheme.headlineSmall),
              if (language != AppLanguage.en)
                Text(language.englishName,
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            ]),
          ),
        ),
      ),
    );
  }
}
