/// The UAE app: Arabic and Urdu screens run right to left, number fields
/// read the digits Arabic and Urdu keyboards type, and layouts use start
/// and end instead of left and right so they mirror.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/core/digits_input.dart';
import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/market.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/l10n/language.dart';

void main() {
  tearDown(() => debugSetMarket(Market.india));

  test('the UAE offers English, Arabic, Hindi, Urdu and Malayalam', () {
    debugSetMarket(Market.uae);
    expect(AppLanguage.offered, [AppLanguage.en, AppLanguage.ar, AppLanguage.hi, AppLanguage.ur, AppLanguage.ml]);
    expect(AppLanguage.ar.locale, const Locale('ar', 'AE'));
    expect(AppLanguage.ur.locale, const Locale('ur', 'PK'));
    expect(AppLanguage.ml.locale, const Locale('ml', 'IN'));
    expect(AppLanguage.hi.locale, const Locale('hi', 'IN'));
    expect(speechCodeFor(AppLanguage.ar), 'ar-AE');
    expect([for (final l in AppLanguage.values) if (l.rightToLeft) l], [AppLanguage.ar, AppLanguage.ur]);
    for (final l in AppLanguage.offered) {
      expect(kMaterialSupportedLanguages, contains(l.code), reason: '${l.code} needs Material texts');
    }
  });

  test('amounts and money icons follow the dirham', () {
    debugSetMarket(Market.uae);
    expect(trIn(AppLanguage.en, 'Amount (₹)'), 'Amount (AED)');
    expect(trIn(AppLanguage.ar, 'Add ₹5,000 spent on cement'), contains('AED\u00A0500'));
    expect(trIn(AppLanguage.ar, 'Cancel'), isNot('Cancel'));
    expect(trIn(AppLanguage.ur, 'Cancel'), isNot('Cancel'));
    expect(trIn(AppLanguage.ml, 'Cancel'), isNot('Cancel'));
    expect(currencyIcon, isNot(Icons.currency_rupee_rounded));
    debugSetMarket(Market.india);
    expect(currencyIcon, Icons.currency_rupee_rounded);
    expect(trIn(AppLanguage.en, 'Amount (₹)'), 'Amount (₹)');
  });

  test('Arabic-Indic and Urdu digits read as numbers', () {
    expect(westernDigits('١٢٣٤٥٦٧٨٩٠'), '1234567890');
    expect(westernDigits('۱۲۳۴۵۶۷۸۹۰'), '1234567890');
    expect(westernDigits('١٬٢٣٤٫٥'), '1234.5');
    expect(westernDigits('\u2066123\u2069'), '123');
    expect(westernDigits('Site 7'), 'Site 7');
    expect(parseTypedNumber('١٬٢٣٤٫٥'), 1234.5);
    expect(parseTypedNumber('۴۵۰'), 450);
    debugSetMarket(Market.uae);
    expect(parseTypedNumber('AED 1,250'), 1250);
    expect(parseTypedNumber(money(1250)), 1250);
    expect(parseTypedNumber('١٢٥٠ د.إ'), 1250);
  });

  test('the digits formatter converts as typed and keeps the cursor', () {
    const f = WesternDigitsFormatter();
    final out = f.formatEditUpdate(
      TextEditingValue.empty,
      const TextEditingValue(text: '١٢٫٥', selection: TextSelection.collapsed(offset: 4)),
    );
    expect(out.text, '12.5');
    expect(out.selection.extentOffset, 4);
    final filtered = FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')).formatEditUpdate(TextEditingValue.empty, out);
    expect(filtered.text, '12.5');
  });

  testWidgets('an Arabic app lays out right to left', (tester) async {
    debugSetMarket(Market.uae);
    late TextDirection dir;
    await tester.pumpWidget(MaterialApp(
      locale: AppLanguage.ar.locale,
      supportedLocales: [for (final l in AppLanguage.offered) l.locale],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Builder(builder: (context) {
        dir = Directionality.of(context);
        return const Scaffold(
          body: Padding(
            padding: EdgeInsetsDirectional.only(start: 40),
            child: Align(alignment: AlignmentDirectional.centerStart, child: Text('x', key: Key('x'))),
          ),
        );
      }),
    ));
    expect(dir, TextDirection.rtl);
    final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    expect(tester.getTopRight(find.byKey(const Key('x'))).dx, closeTo(width - 40, 0.5));
  });

  test('screens use start and end, never left and right', () {
    final bad = <String>[];
    final rules = [
      RegExp(r'EdgeInsets\.only\([^)]*\b(left|right)\s*:'),
      RegExp(r'(?<![\w.])Alignment\.(center|top|bottom)(Left|Right)\b'),
      RegExp(r'(?<!pw\.)TextAlign\.(left|right)\b'),
      RegExp(r'(?<![\w.])Positioned\(\s*(left|right)\s*:'),
    ];
    final ltrb = RegExp(r'(?<!pw\.)EdgeInsets\.fromLTRB\(([^,]+),[^,]+,([^,]+),');
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final src = f.readAsStringSync();
      for (final r in rules) {
        for (final m in r.allMatches(src)) {
          bad.add('${f.path}: ${m[0]}');
        }
      }
      for (final m in ltrb.allMatches(src)) {
        if (m[1]!.trim() != m[2]!.trim()) bad.add('${f.path}: ${m[0]}');
      }
    }
    expect(bad, isEmpty, reason: bad.join('\n'));
  });
}
