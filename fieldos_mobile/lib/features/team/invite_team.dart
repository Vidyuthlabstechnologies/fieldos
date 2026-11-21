/// Inviting the team: the message an owner sends (on WhatsApp, usually)
/// with the company's join code, in the owner's language, with the steps
/// a new phone actually takes and the store link for this country's app.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import 'package:fieldos_mobile/core/market.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';

/// The invite text for [companyName] and its join [code].
String joinCodeMessage({required String? companyName, required String code}) {
  final name = (companyName ?? '').trim();
  // One label per line: a key with a line break in it can't be checked by
  // test/l10n_coverage_test.dart.
  return [
    trf('Join {company} on FieldOS, our site app.', {'company': name.isEmpty ? tr('our company') : name}),
    trf('1. Install it: {link}', {'link': playStoreLink}),
    tr('2. Sign in with Google.'),
    trf('3. Tap "Join with a code" and enter {code}', {'code': code}),
  ].join('\n');
}

String inviteSharedKey(String companyId) => 'invite_shared:$companyId';

/// Whether this phone has sent the company's join code to anyone yet.
Future<bool> inviteShared(AppDatabase db, String companyId) async =>
    (await db.settingsDao.get(inviteSharedKey(companyId))) == '1';

/// Opens the phone's share sheet with the invite, and remembers it was
/// sent (the "Invite your team" step on Home is then done).
Future<void> shareJoinCode(WidgetRef ref,
    {required String companyId, required String? companyName, required String code}) async {
  final db = ref.read(appDatabaseProvider);
  await SharePlus.instance.share(ShareParams(text: joinCodeMessage(companyName: companyName, code: code)));
  await db.settingsDao.set(inviteSharedKey(companyId), '1');
}
