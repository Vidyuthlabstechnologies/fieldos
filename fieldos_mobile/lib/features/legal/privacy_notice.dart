/// The short privacy notice (India's DPDP Act, 2023 and its 2025 rules):
/// each kind of personal data FieldOS handles and why, in plain words,
/// then how to withdraw consent, use your rights and complain. It can be
/// read in English or any language FieldOS speaks (section 5(3) of the
/// Act), whatever language the screens are in.
///
/// Also the record of the one consent FieldOS asks for on top of the
/// sign-in: Ask FieldOS sends questions to AI companies, one of them
/// outside India, so it asks first (App Store guideline 5.1.2(i) asks the
/// same) and the person can take it back in Your privacy.
library;

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/l10n/language.dart';

/// One item of the notice, as English keys looked up with [trIn].
class NoticeItem {
  const NoticeItem(this.heading, this.body);
  final String heading;
  final String body;
}

const privacyNoticeItems = [
  NoticeItem(
    'Your account',
    'Your name, email address and the company you join, so that you can sign in and work with your team.',
  ),
  NoticeItem(
    'Site records',
    'Projects, reports, photos, attendance, wages and other records your company keeps. They stay on this phone, '
        'and in our cloud in Mumbai, India when Team & sync is on, so that your team can see them.',
  ),
  NoticeItem(
    'Location and selfies',
    'Your location, and a selfie, only when you check in or out, punch a worker in, set a site location or take a '
        'site photo, to show the work was done at the site. Never in the background.',
  ),
  NoticeItem(
    'The AI assistant',
    'Only when you use it: what you ask, and the site details needed to answer, go to Anthropic in the USA (or Sarvam '
        'AI in India as a backup) to work out the reply. They do not use it to train their models.',
  ),
  NoticeItem(
    'Paying for FieldOS',
    'Google Play or the App Store take the payment. RevenueCat in the USA gets the purchase record so the app can '
        'check your plan. We never see card or UPI details.',
  ),
  NoticeItem(
    'Bug and crash reports',
    'Only what you send us, and crash details if that setting is on, so that we can fix problems.',
  ),
  NoticeItem(
    'Your choices',
    'You can stop the AI assistant, turn off crash details, export your records or delete your cloud account at any '
        'time. Stopping does not change what was done before.',
  ),
  NoticeItem(
    'Your rights',
    'Ask us for a summary of your data, to correct or erase it, or to name someone to act for you. Write to '
        'info@mldynamic.com.',
  ),
  NoticeItem(
    'Complaints',
    'Write to our Grievance Officer at info@mldynamic.com. We reply within 30 days. You can also complain to the '
        'Data Protection Board of India.',
  ),
];

/// Every English key of the notice, for the translation test.
Iterable<String> get privacyNoticeKeys => privacyNoticeItems.expand((i) => [i.heading, i.body]);

/// [item] in [language].
NoticeItem noticeIn(AppLanguage language, NoticeItem item) =>
    NoticeItem(trIn(language, item.heading), trIn(language, item.body));

String aiConsentKey(String userId) => 'ai_consent:$userId';

/// Whether [userId] has agreed to Ask FieldOS sending questions to the AI
/// companies. The stored value is when they agreed, or '0' once withdrawn.
Future<bool> aiConsentGiven(AppDatabase db, String userId) async {
  final v = await db.settingsDao.get(aiConsentKey(userId));
  return v != null && v.isNotEmpty && v != '0';
}

Future<void> setAiConsent(AppDatabase db, String userId, bool given) =>
    db.settingsDao.set(aiConsentKey(userId), given ? DateTime.now().toUtc().toIso8601String() : '0');
