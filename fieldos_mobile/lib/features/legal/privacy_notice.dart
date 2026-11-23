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

import 'package:fieldos_mobile/core/market.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/legal/consent_record.dart';
import 'package:fieldos_mobile/l10n/language.dart';

/// One item of the notice, as English keys looked up with [trIn].
class NoticeItem {
  const NoticeItem(this.heading, this.body);
  final String heading;
  final String body;
}

/// The notice this build shows: the US app has its own (state privacy
/// laws, no Indian authority); other markets use India's until theirs is
/// written (see legal_texts_markets.dart).
List<NoticeItem> get privacyNoticeItems => switch (currentMarket) {
  Market.us => usPrivacyNoticeItems,
  Market.malaysia => myPrivacyNoticeItems,
  Market.uae => aePrivacyNoticeItems,
  Market.uk => ukPrivacyNoticeItems,
  _ => indiaPrivacyNoticeItems,
};

const indiaPrivacyNoticeItems = [
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

const usPrivacyNoticeItems = [
  NoticeItem(
    'Your account',
    'Your name, email address and the company you join, so that you can sign in and work with your team.',
  ),
  NoticeItem(
    'Job records',
    'Projects, logs, photos, time cards, pay and other records your company keeps. They stay on this phone, and in '
        'our cloud when Team & sync is on, so that your team can see them. Our cloud is in India today.',
  ),
  NoticeItem(
    'Location and photo check-in',
    'Your location, and a photo, only when you clock in or out, clock a worker in, set a job location or take a '
        'job photo, to show the work was done on the job. Never in the background. FieldOS does not use face '
        'recognition and keeps no face scan.',
  ),
  NoticeItem(
    'The AI assistant',
    'Only when you use it: what you ask, and the job details needed to answer, go to Anthropic in the USA (or Sarvam '
        'AI in India as a backup) to work out the reply. Photos and locations are never sent. They do not use it to '
        'train their models.',
  ),
  NoticeItem(
    'Paying for FieldOS',
    'Google Play or the App Store take the payment. RevenueCat in the USA gets the purchase record so the app can '
        'check your plan. We never see card details.',
  ),
  NoticeItem(
    'Bug and crash reports',
    'Only what you send us, and crash details if that setting is on, so that we can fix problems.',
  ),
  NoticeItem(
    'Your choices',
    'You can stop the AI assistant, turn off crash details, export your records or delete your cloud account at any '
        'time. We do not sell or share your personal information, and we do not use it for targeted ads.',
  ),
  NoticeItem(
    'Your privacy rights',
    'Ask us what we hold about you, to correct it, delete it or get a copy, or let someone act for you. Write to '
        'info@mldynamic.com. We reply within 45 days.',
  ),
  NoticeItem(
    'Appeals',
    'If we turn down a request, write to info@mldynamic.com with the word "Appeal" and we will look at it again. If '
        'you are still not satisfied, you can contact your state attorney general.',
  ),
];

/// Malaysia: the PDPA section 7 notice, which must be readable in
/// Bahasa Melayu as well as English.
const myPrivacyNoticeItems = [
  NoticeItem(
    'Your account',
    'Your name, email address and the company you join, so that you can sign in and work with your team.',
  ),
  NoticeItem(
    'Site records',
    'Projects, reports, photos, attendance, wages, work permits and other records your company keeps. They stay on '
        'this phone, and in our cloud in Mumbai, India when Team & sync is on, so that your team can see them. Your '
        'company decides what it records and is responsible for it.',
  ),
  NoticeItem(
    'Location and selfies',
    'Your location and a selfie when you check in or out, and your location when you punch a worker in, set a site '
        'location or take a site photo, to show the work was done at the site. The app asks you first. Never in the '
        'background. FieldOS does not use face recognition.',
  ),
  NoticeItem(
    'The AI assistant',
    'Only when you use it: what you ask, and the site details needed to answer, go to Anthropic in the USA (or Sarvam '
        'AI in India as a backup) to work out the reply. They do not use it to train their models.',
  ),
  NoticeItem(
    'Paying for FieldOS',
    'Google Play or the App Store take the payment. RevenueCat in the USA gets the purchase record so the app can '
        'check your plan. We never see card details.',
  ),
  NoticeItem(
    'Data sent outside Malaysia',
    'Our cloud is in India, and the services above are in India and the USA. Each gets only what it needs, under a '
        'contract that requires it to keep the data safe.',
  ),
  NoticeItem(
    'Your choices',
    'You can stop the AI assistant, turn off crash details, export your records or delete your cloud account at any '
        'time. Stopping does not change what was done before.',
  ),
  NoticeItem(
    'Your rights under the PDPA',
    'Ask us for access to your data or a copy, to correct it, or to send it to another organisation. Write to '
        'info@mldynamic.com. We reply within 21 days.',
  ),
  NoticeItem(
    'Complaints',
    'Write to info@mldynamic.com with "Privacy" in the subject. If you are not satisfied, you can complain to the '
        'Personal Data Protection Commissioner of Malaysia.',
  ),
];

/// UAE: the PDPL notice, read in English, Arabic, Hindi, Urdu or Malayalam.
const aePrivacyNoticeItems = [
  NoticeItem(
    'Your account',
    'Your name, email address and the company you join, so that you can sign in and work with your team.',
  ),
  NoticeItem(
    'Site records',
    'Projects, reports, photos, attendance, wages, work permits and other records your company keeps. They stay on '
        'this phone, and in our cloud in Mumbai, India when Team & sync is on, so that your team can see them. Your '
        'company decides what it records and is responsible for it.',
  ),
  NoticeItem(
    'Location and selfies',
    'Your location and a selfie when you check in or out, and your location when you punch a worker in, set a site '
        'location or take a site photo, to show the work was done at the site. The app asks you first. Never in the '
        'background. FieldOS does not use face recognition.',
  ),
  NoticeItem(
    'The AI assistant',
    'Only when you use it: what you ask, and the site details needed to answer, go to Anthropic in the USA (or Sarvam '
        'AI in India as a backup) to work out the reply. They do not use it to train their models.',
  ),
  NoticeItem(
    'Paying for FieldOS',
    'Google Play or the App Store take the payment. RevenueCat in the USA gets the purchase record so the app can '
        'check your plan. We never see card details.',
  ),
  NoticeItem(
    'Data sent outside the UAE',
    'Our cloud is in India, and the services above are in India and the USA. Each gets only what it needs, under a '
        'contract that requires it to protect the data.',
  ),
  NoticeItem(
    'Your choices',
    'You can stop the AI assistant, turn off crash details, export your records or delete your cloud account at any '
        'time. Stopping does not change what was done before.',
  ),
  NoticeItem(
    'Your rights under the PDPL',
    'Ask us for a copy of your data, to correct or erase it, to stop using it, or to send it to another organisation. '
        'Write to info@mldynamic.com. We reply within 30 days.',
  ),
  NoticeItem(
    'Complaints',
    'Write to info@mldynamic.com with "Privacy" in the subject. If you are not satisfied, you can complain to the UAE '
        'data protection authority.',
  ),
];

/// UK: the UK GDPR notice, read in English, Polish or Romanian.
const ukPrivacyNoticeItems = [
  NoticeItem(
    'Your account',
    'Your name, email address and the company you join, so that you can sign in and work with your team.',
  ),
  NoticeItem(
    'Site records',
    'Projects, site diaries, photos, attendance, pay, CSCS cards and other records your company keeps. They stay on '
        'this phone, and in our cloud in Mumbai, India when Team & sync is on, so that your team can see them. Your '
        'company is the controller of these records and decides what it keeps.',
  ),
  NoticeItem(
    'Location and selfies',
    'Your location and a selfie when you sign in or out on site, and your location when you set a site location or '
        'take a site photo, to show the work was done at the site. The app asks you first. Never in the background. '
        'FieldOS does not use face recognition.',
  ),
  NoticeItem(
    'The AI assistant',
    'Only when you use it: what you ask, and the site details needed to answer, go to Anthropic in the USA (or Sarvam '
        'AI in India as a backup) to work out the reply. They do not use it to train their models.',
  ),
  NoticeItem(
    'Paying for FieldOS',
    'Google Play or the App Store take the payment. RevenueCat in the USA gets the purchase record so the app can '
        'check your plan. We never see card details.',
  ),
  NoticeItem(
    'Data sent outside the UK',
    'Our cloud is in India, and the services above are in India and the USA. Each gets only what it needs, under the '
        'UK\'s approved transfer contracts.',
  ),
  NoticeItem(
    'Your choices',
    'You can stop the AI assistant, turn off crash details or the attendance photo, export your records or delete '
        'your cloud account at any time. Stopping does not change what was done before.',
  ),
  NoticeItem(
    'Your rights under the UK GDPR',
    'Ask us for a copy of your data, to correct or erase it, to restrict or object to its use, or to send it to '
        'another organisation. Write to info@mldynamic.com. We reply within one month.',
  ),
  NoticeItem(
    'Complaints',
    'Write to info@mldynamic.com with "Privacy" in the subject. If you are not satisfied, you can complain to the '
        'Information Commissioner\'s Office (ico.org.uk).',
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

/// Also queues the choice as proof of consent for the server (see
/// consent_record.dart).
Future<void> setAiConsent(AppDatabase db, String userId, bool given) async {
  final at = DateTime.now().toUtc();
  await db.settingsDao.set(aiConsentKey(userId), given ? at.toIso8601String() : '0');
  await queueConsentRecord(db, userId, ConsentPurpose.aiAssistant, given, at: at);
}
