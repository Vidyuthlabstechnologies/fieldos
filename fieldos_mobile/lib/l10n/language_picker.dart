/// Choosing the app's language: a sheet from Settings, and a row of three
/// buttons on the sign-in screen so a new user can switch before reading
/// anything else.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/l10n/language.dart';

/// Rebuilds every widget so labels already on screen switch language in
/// place, keeping the screen and anything typed.
void rebuildAllWidgets() {
  void mark(Element e) {
    e.markNeedsBuild();
    e.visitChildren(mark);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(mark);
}

Future<void> chooseLanguage(WidgetRef ref, AppLanguage l) async {
  await ref.read(languageProvider.notifier).choose(l);
  rebuildAllWidgets();
}

/// Turns the screens' own language on or off ("Show screens in Telugu").
Future<void> setScreensInLanguage(WidgetRef ref, bool on) async {
  await ref.read(screensInLanguageProvider.notifier).set(on);
  rebuildAllWidgets();
}

Future<void> showLanguagePicker(BuildContext context, WidgetRef ref) async {
  final current = ref.read(languageProvider);
  final picked = await showModalBottomSheet<AppLanguage>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    // Six languages: scroll on short phones and in landscape.
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.8),
        child: ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(tr('Your language'), style: Theme.of(ctx).textTheme.titleLarge),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(tr('Mitra talks with you in it, mixed with English, and voice input listens for it.'),
                style: Theme.of(ctx).textTheme.bodySmall),
          ),
          for (final l in AppLanguage.values)
            ListTile(
              title: Text(l.nativeName),
              subtitle: l == AppLanguage.en ? null : Text(l.englishName),
              trailing: l == current ? const Icon(Icons.check) : null,
              onTap: () => Navigator.of(ctx).pop(l),
            ),
          const SizedBox(height: 8),
        ],
      ),
      ),
    ),
  );
  if (picked != null && picked != current) await chooseLanguage(ref, picked);
}

/// Every language in its own script, the current one highlighted.
class LanguageChooserRow extends ConsumerWidget {
  const LanguageChooserRow({super.key, this.color});
  final Color? color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(languageProvider);
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 4,
      children: [
        for (final l in AppLanguage.values)
          TextButton(
            onPressed: l == current ? null : () => chooseLanguage(ref, l),
            style: TextButton.styleFrom(
              foregroundColor: color,
              disabledForegroundColor: color,
              textStyle: TextStyle(fontWeight: l == current ? FontWeight.w800 : FontWeight.w400),
            ),
            child: Text(l.nativeName),
          ),
      ],
    );
  }
}
