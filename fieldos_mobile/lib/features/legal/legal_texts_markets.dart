/// The privacy policy and terms for each market's app. The Indian texts
/// (legal_texts.dart) are the base; a market replaces the sections whose
/// law differs and keeps the rest (who sees what, chat, bug reports...),
/// so a fix to a shared section reaches every app.
///
/// These are drafts written from the research in the project files
/// (`international/<market>/02-compliance.md`). They need a lawyer in that
/// country to review them before the market's app is published, and must
/// never be described as lawyer-reviewed until then.
library;

import 'package:fieldos_mobile/core/market.dart';
import 'package:fieldos_mobile/features/legal/legal_texts.dart';

/// The policy this build shows. Markets whose own text is not written yet
/// get null, and [marketLegalReady] is false for them: their store build
/// must not ship (test/market_legal_test.dart checks the US one exists).
LegalDocument get marketPrivacyPolicy => switch (currentMarket) {
  Market.india => privacyPolicy,
  Market.us => usPrivacyPolicy,
  Market.malaysia => myPrivacyPolicy,
  _ => privacyPolicy,
};

LegalDocument get marketTermsOfUse => switch (currentMarket) {
  Market.india => termsOfUse,
  Market.us => usTermsOfUse,
  Market.malaysia => myTermsOfUse,
  _ => termsOfUse,
};

/// Whether this market has its own legal texts yet.
bool get marketLegalReady => const {Market.india, Market.us, Market.malaysia}.contains(currentMarket);

/// [base] with sections replaced by heading ([replace]; a null value drops
/// the section) and [add] appended before the contact section.
LegalDocument adaptLegal(
  LegalDocument base, {
  String? title,
  String? intro,
  Map<String, LegalSection?> replace = const {},
  List<LegalSection> add = const [],
}) {
  final out = <LegalSection>[];
  for (final s in base.sections) {
    if (replace.containsKey(s.heading)) {
      final r = replace[s.heading];
      if (r != null) out.add(r);
    } else {
      out.add(s);
    }
  }
  final contactAt = out.indexWhere((s) => s.heading.endsWith('Contact') || s.heading.endsWith('Contact us'));
  out.insertAll(contactAt < 0 ? out.length : contactAt, add);
  return LegalDocument(title: title ?? base.title, updated: base.updated, intro: intro ?? base.intro, sections: out);
}

const _contact =
    'info@mldynamic.com, ML Dynamic Solutions Private Limited, 606, 6th Floor, Gowra Fountainhead, '
    'Patrika Nagar, Madhapur, Hi-Tech City, Hyderabad, Telangana 500081, India.';

final usPrivacyPolicy = adaptLegal(
  privacyPolicy,
  intro:
      'FieldOS is made by ML Dynamic Solutions Private Limited, a company based in India. This policy is for '
      'the FieldOS app for the United States. FieldOS stores the projects, daily logs, photos, time records and '
      'other job records you create on your phone. If you sign in to Team & sync, those records, your email '
      'address and the name you entered are also stored in our cloud database (Supabase), so that the people '
      'your company works with can see what is meant for them.',
  replace: {
    'Location': const LegalSection(
      'Location',
      'Your precise location is read only when you clock yourself in or out, clock a worker in or out, set a '
          'job location, or take a job photo with the in-app camera (the date, time and position are printed on '
          'the photo). It is saved with that record, so the company can see the work was done at the job. It is '
          'never tracked in the background, and the app asks for location only while you are using it. Before '
          'the first clock-in the app tells you this and asks you to agree.',
    ),
    'Attendance photos and selfies': const LegalSection(
      'Photo check-in',
      'If your company turns on photo check-in, the app takes a photo with the front camera when staff clock in '
          'or out, and saves it with the time, the job and the GPS position. The photos are part of the '
          'company\'s time records: the owner and project managers of that company can see them, and they are '
          'used only to confirm who was on the job. FieldOS does not use face recognition, does not make a face '
          'template or any other biometric identifier from the photo, and does not compare faces. The app tells '
          'you this and asks you to agree before the first photo check-in.',
    ),
    'Salaries, workers and leads': const LegalSection(
      'Pay, workers and leads',
      'Companies use FieldOS to keep their own records about other people: workers\' names, hours and pay '
          'rates, advances, and leads (the name, phone number and enquiry of a possible customer). The company '
          'decides what it records and why, and is the business responsible for those records; FieldOS stores '
          'and processes them only on the company\'s behalf, as its service provider. FieldOS is a record-keeping '
          'tool, not a payroll service: the employer is responsible for paying wages and overtime under the law.',
    ),
    'Voice reports': const LegalSection(
      'Voice reports',
      'Voice reports use your phone\'s own speech recognition: Google\'s on Android and Apple\'s on iPhone. '
          'When the language\'s offline speech pack is on the phone, your speech is turned into text on the '
          'phone. Otherwise the phone\'s speech service may send it to Google or Apple to be recognized, under '
          'their privacy policies. FieldOS does not record or keep your voice.\n\nTranslating a log between '
          'Spanish and English happens on the phone, using Google ML Kit. The language pack is downloaded from '
          'Google once, and the text is never sent. ML Kit sends Google diagnostic details so that Google can '
          'maintain it: the phone model and system version, the app version, an identifier for this '
          'installation, the languages chosen, and how long translation took.',
    ),
    'AI assistant': const LegalSection(
      'AI assistant',
      'When you use Ask FieldOS, what you type or say, and the job details the assistant needs to answer (such '
          'as project names, workers, tasks and amounts on this phone), go through FieldOS\'s server to Anthropic '
          '(anthropic.com), whose Claude model works out the reply. Photos and locations are never sent to it. '
          'Anthropic\'s commercial terms do not let it use this to train its models. If Anthropic is unavailable, '
          'the same goes instead to Sarvam AI (sarvam.ai) in India for the reply. FieldOS keeps only a count of '
          'how much each account uses the assistant, not the conversation. Nothing is saved to your records until '
          'you tap Save on the card the assistant shows, and the assistant never decides anyone\'s pay or time. '
          'The app asks for your permission before the first question, and you can take it back at any time in '
          'Settings, Your privacy.',
    ),
    'Payments': const LegalSection(
      'Payments',
      'The FieldOS subscription is bought through Google Play or the Apple App Store, which handle your card '
          'details and any sales tax. FieldOS never sees them. RevenueCat (revenuecat.com) receives the purchase '
          'record from the store, linked to your FieldOS account id, so that the app and the assistant can check '
          'your subscription.',
    ),
    'Where your data is processed': const LegalSection(
      'Where your data is processed',
      'Your cloud records are stored by Supabase. Today our cloud database is in India; we will update this '
          'policy before that changes. Services we use: Supabase for the database, Anthropic (USA) for the AI '
          'assistant, with Sarvam AI (India) as its backup, RevenueCat (USA) for checking subscriptions, GitHub (USA) for our private copy of bug and '
          'message reports, and Google and Apple for sign-in, speech and the stores. Each gets only what this '
          'policy describes for it, under a contract that limits it to providing its service.',
    ),
    'Keeping data safe': const LegalSection(
      'Keeping data safe',
      'We protect data with encryption in transit, access limited by role, and checks that keep each company\'s '
          'records apart. If a breach of personal data affects you, we will tell you and your company what '
          'happened, what it means for you and what we are doing about it, within the time state breach laws '
          'require.',
    ),
    'Children': const LegalSection(
      'Children',
      'FieldOS is for people aged 18 and over, for business use. We do not knowingly collect personal data of '
          'children under 13, or of anyone under 18. If you think a child has given us data, write to us and we '
          'will delete it.',
    ),
    'How long we keep data': const LegalSection(
      'How long we keep data',
      '• Company records stay as long as the company uses FieldOS, and are deleted with the account as '
          'described below.\n\n• Check-in photos are deleted after the period the company sets (90 days unless '
          'it chooses otherwise).\n\n• Bug, crash and message reports are kept only as long as needed to fix or '
          'review them, and never more than 12 months.\n\n• Deleted data can remain in our hosting provider\'s '
          'automatic backups for up to 30 days before they are overwritten.',
    ),
    'Your rights': const LegalSection(
      'Your privacy rights',
      'Depending on the state you live in (for example California, Virginia, Colorado, Connecticut, Texas and '
          'others), you can ask us to tell you what personal data we hold about you, to give you a copy, to '
          'correct it, or to delete it, and to limit the use of sensitive data such as precise location. We will '
          'not treat you differently for asking. Email info@mldynamic.com from the address on your account, or '
          'use Settings, Your privacy; an authorized agent can ask for you. We answer within 45 days. If your '
          'data is in a company\'s records (for example as a worker or a lead), we pass your request to that '
          'company, which decides about its own records, and tell you we have done so. If we turn down a request, '
          'you can appeal by replying to our answer.\n\nWe do not sell personal data or share it for '
          'cross-context behavioral advertising, and we do not show ads. We use sensitive data (precise '
          'location, check-in photos) only to provide the service you asked for.',
    ),
    'Grievance officer': null,
    'Contact': const LegalSection(
      'Contact',
      'Questions or requests about privacy: info@mldynamic.com with "Privacy" in the subject. $_contact',
    ),
  },
);

final usTermsOfUse = adaptLegal(
  termsOfUse,
  intro:
      'These terms of use ("terms") are an agreement between you and ML Dynamic Solutions Private Limited '
      '("we", "us"), which makes the FieldOS app for the United States and its cloud service ("FieldOS"). By '
      'creating an account, starting a free trial or using FieldOS, you agree to these terms and to the privacy '
      'policy. If you use FieldOS for a company, you confirm that you may accept these terms for it, and "you" '
      'includes that company. If you do not agree, do not use FieldOS. PLEASE READ SECTION 17: IT REQUIRES '
      'DISPUTES TO BE RESOLVED BY INDIVIDUAL ARBITRATION AND WAIVES CLASS ACTIONS.',
  replace: {
    '1. Who can use FieldOS': const LegalSection(
      '1. Who can use FieldOS',
      'You must be at least 18 years old and able to enter a binding contract. FieldOS is made for contractors, '
          'builders and their crews, for business use, not for personal, family or household use.',
    ),
    '3. Subscription, free trial and payment': const LegalSection(
      '3. Subscription, free trial and payment',
      'FieldOS needs a FieldOS Pro subscription, bought through Google Play or the Apple App Store, monthly or '
          'yearly at the price the store shows before you pay, plus any sales tax the store charges.\n\nNew '
          'subscribers get one 3-day free trial, where the store offers it to them. Unless you cancel before the '
          'trial ends, the first payment is taken when it ends. THE SUBSCRIPTION THEN RENEWS AUTOMATICALLY for the '
          'same period at the price then current, until you cancel. Cancel at least 24 hours before the end of a '
          'period, in your Google Play or App Store subscriptions (the app\'s paywall links there), to avoid the '
          'next charge. Uninstalling the app does not cancel a subscription.\n\nThe store takes the payment, and '
          'refunds are handled by the store under its own policies. If we change the price, the store tells you '
          'before the new price applies, and you can cancel before then. If a payment fails or a subscription '
          'ends, FieldOS cannot be used until you subscribe again. Your records are not deleted, and are there '
          'again when you resubscribe.',
    ),
    '5. Team chat and other shared content': const LegalSection(
      '5. Team chat and other shared content',
      'Project chat, photos, comments and other content you share are seen by the other members of your '
          'company. We do not allow objectionable content or abusive users. Do not post or share anything '
          'that:\n\n• threatens, harasses, bullies or abuses anyone, or attacks people for their race, ethnicity, '
          'national origin, religion, sex, sexual orientation, gender identity, disability or any other part of '
          'who they are;\n• is sexual, obscene, violent or hateful, or involves a child in any harmful way;\n• is '
          'spam, a scam or fraud, or asks for money under false pretenses;\n• is false or misleading in a way '
          'meant to harm someone, or impersonates another person;\n• shares someone\'s private information '
          'without their permission;\n• infringes anyone\'s copyright, trademark or other rights; or\n• breaks '
          'any law.',
    ),
    '8. Check the numbers': const LegalSection(
      '8. Check the numbers',
      'FieldOS works out hours, overtime, pay applications, taxes and estimates from what you enter, using '
          'common rules (for example time and a half past 40 hours in a work week). It is a record-keeping tool, '
          'not a payroll, tax, legal or accounting service, and it does not know every state, local or contract '
          'rule that applies to you (for example daily overtime in California, prevailing wage or union rates). '
          'Check the figures before you pay anyone, bill anyone or file anything. You, as the employer or '
          'contractor, are responsible for paying wages and taxes correctly.',
    ),
    '14. Limits on our liability': const LegalSection(
      '14. Limits on our liability',
      'TO THE FULLEST EXTENT THE LAW ALLOWS, WE ARE NOT LIABLE FOR INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL '
          'OR PUNITIVE DAMAGES, OR FOR LOSS OF PROFIT, BUSINESS, CONTRACTS OR DATA, ARISING FROM YOUR USE OF '
          'FIELDOS. OUR TOTAL LIABILITY TO YOU FOR ALL CLAIMS ABOUT FIELDOS IS LIMITED TO THE AMOUNT YOU PAID FOR '
          'FIELDOS IN THE 12 MONTHS BEFORE THE EVENT THAT LED TO THE CLAIM.\n\nSome states do not allow some of '
          'these limits, so they may not all apply to you. Nothing in these terms limits liability that cannot be '
          'limited by law, including liability for fraud.',
    ),
    '17. Law and disputes': const LegalSection(
      '17. Law and disputes',
      'These terms are governed by the laws of the State of Delaware, USA, without regard to its conflict of '
          'law rules, and the Federal Arbitration Act governs section 17.\n\nIf you have a complaint, write to us '
          'first at info@mldynamic.com; we will try to settle it within 30 days. If it is not settled, you and we '
          'agree to resolve it by binding individual arbitration administered by the American Arbitration '
          'Association under its Commercial Arbitration Rules, rather than in court, except that either of us may '
          'bring an individual claim in small-claims court. YOU AND WE EACH WAIVE THE RIGHT TO A JURY TRIAL AND TO '
          'TAKE PART IN A CLASS OR REPRESENTATIVE ACTION. You can opt out of arbitration by emailing us within 30 '
          'days of first accepting these terms.',
    ),
    '18. Grievance officer': null,
    '20. Contact us': const LegalSection('20. Contact us', _contact),
  },
);

/// Malaysia: the Personal Data Protection Act 2010 as amended in 2024
/// (cross-border transfers under section 129, breach notice within 72
/// hours, data portability, a Data Protection Officer), Malaysian law and
/// AIAC arbitration in the terms.
final myPrivacyPolicy = adaptLegal(
  privacyPolicy,
  intro:
      'FieldOS is made by ML Dynamic Solutions Private Limited, a company based in India. This privacy notice '
      'is for the FieldOS app for Malaysia, and is given under the Personal Data Protection Act 2010 (PDPA). It '
      'is available in English and Bahasa Melayu (and Chinese) in the app, under Settings, Your privacy. FieldOS '
      'stores the projects, reports, photos, attendance and other site records you create on your phone. If you '
      'sign in to Team & sync, those records, your email address and the name you entered are also stored in our '
      'cloud database (Supabase, region: Mumbai, India), so that the people your company works with can see what '
      'is meant for them.',
  replace: {
    'Attendance photos and selfies': const LegalSection(
      'Attendance photos and selfies',
      'If your company turns on selfie attendance, the app takes a photo with the front camera when staff check in '
          'or out, and saves it with the time, the site and the GPS position. A supervisor can also take a photo '
          'when punching workers in. The photos are part of the company\'s attendance records: only the owner and '
          'project managers of that company can see them, and they are used only to confirm attendance. FieldOS '
          'does not use face recognition, and makes no face template or other biometric data from the photo. The '
          'app tells you this and asks you to agree before the first selfie; if you do not agree, your supervisor '
          'can mark your attendance instead, and your pay is never held back for it.',
    ),
    'Salaries, workers and leads': const LegalSection(
      'Salaries, workers and leads',
      'Companies use FieldOS to keep their own records about other people: workers\' names, attendance and '
          'wages, staff salaries and advances, work permit and passport details of foreign workers, and leads '
          '(the name, phone number and enquiry of a possible customer). The company decides what it records and '
          'why, and is the data controller for those records; it must give its workers notice and get their '
          'consent where the PDPA requires it. FieldOS processes these records only on the company\'s behalf, as '
          'its data processor. Only owners and project managers can see salaries and leads, and permit and '
          'passport numbers are shown masked in lists.',
    ),
    'Payments': const LegalSection(
      'Payments',
      'The FieldOS subscription is bought through Google Play or the Apple App Store, which handle your card or '
          'other payment details and any tax. FieldOS never sees them. RevenueCat (revenuecat.com, USA) receives '
          'the purchase record from the store, linked to your FieldOS account id, so that the app and the '
          'assistant can check your subscription.',
    ),
    'Where your data is processed': const LegalSection(
      'Where your data is processed',
      'Your cloud records are stored by Supabase in Mumbai, India, outside Malaysia. A few other services we use '
          'are run from other countries: Anthropic (USA) for the AI assistant, with Sarvam AI (India) as its '
          'backup, RevenueCat (USA) for checking subscriptions, GitHub (USA) for our private copy of bug and '
          'message reports, and Google and Apple for sign-in, speech and the stores. We send personal data to '
          'these places under section 129 of the PDPA: each service gets only what this policy describes for '
          'it, under a contract that limits it to providing its service and requires it to keep the data safe, '
          'and we keep an assessment of each transfer. We will update this notice before the place where your '
          'records are stored changes.',
    ),
    'Keeping data safe': const LegalSection(
      'Keeping data safe',
      'We protect data with encryption in transit, access limited by role, and checks that keep each company\'s '
          'records apart. If a breach of personal data happens, we will notify the Personal Data Protection '
          'Commissioner within 72 hours, tell your company without undue delay, and, where the breach is likely '
          'to cause you significant harm, tell you within 7 days what happened, what it means for you and what '
          'we are doing about it. We keep a record of breaches.',
    ),
    'Children': const LegalSection(
      'Children',
      'FieldOS is for people aged 18 and over, for business use, and we do not knowingly collect personal data of '
          'children. Do not record children or young persons as workers on a building site: Malaysian law does '
          'not allow them to do hazardous work such as building and construction.',
    ),
    'How long we keep data': const LegalSection(
      'How long we keep data',
      '• Company records stay as long as the company uses FieldOS, and are deleted with the account as described '
          'below. Employers must keep wage and attendance records for at least 6 years under the Employment Act '
          '1955, so export them before you delete an account.\n\n• Attendance selfies are deleted after the '
          'period the company sets (90 days unless it chooses otherwise); the attendance record itself stays.'
          '\n\n• Bug, crash and message reports are kept only as long as needed to fix or review them, and never '
          'more than 12 months.\n\n• Deleted data can remain in our hosting provider\'s automatic backups for up '
          'to 30 days before they are overwritten.',
    ),
    'Your rights': const LegalSection(
      'Your rights',
      'Under the PDPA you can ask us for access to the personal data we hold about you and a copy of it, ask us to '
          'correct it, ask us to send it to another organisation in a machine-readable form, withdraw your '
          'consent, and ask us to stop processing that causes you damage or distress, or for direct marketing. '
          'Email info@mldynamic.com from the address on your account, or use Settings, Your privacy. We reply '
          'within 21 days. If your data is in a company\'s records (for example as a worker or a lead), we pass '
          'your request to that company, which decides about its own records, and tell you we have done so. '
          'Withdrawing consent does not affect what was done before: turn off the AI assistant or crash details, '
          'or delete your cloud account.',
    ),
    'Grievance officer': const LegalSection(
      'Privacy contact and complaints',
      'For any question or complaint about your personal data, write to our privacy contact at '
          'info@mldynamic.com with "Privacy" in the subject. We will publish the contact of our Data Protection '
          'Officer for Malaysia here once one is appointed. If you are not satisfied with our answer, you can '
          'complain to the Personal Data Protection Commissioner of Malaysia (pdp.gov.my).',
    ),
    'Contact': const LegalSection(
      'Contact',
      'Questions or requests about privacy: info@mldynamic.com with "Privacy" in the subject. $_contact',
    ),
  },
  add: const [
    LegalSection(
      'Language',
      'This notice is given in English and Bahasa Melayu. If the two differ, the English text applies.',
    ),
  ],
);

final myTermsOfUse = adaptLegal(
  termsOfUse,
  intro:
      'These terms of use ("terms") are an agreement between you and ML Dynamic Solutions Private Limited, a '
      'company incorporated in India ("we", "us"), which makes the FieldOS app for Malaysia and its cloud service '
      '("FieldOS"). By creating an account, starting a free trial or using FieldOS, you agree to these terms and '
      'to the privacy notice. If you use FieldOS for a company, you confirm that you may accept these terms for '
      'it, and "you" includes that company. If you do not agree, do not use FieldOS.',
  replace: {
    '1. Who can use FieldOS': const LegalSection(
      '1. Who can use FieldOS',
      'You must be at least 18 years old and able to enter a binding contract. FieldOS is made for contractors, '
          'builders and their site teams, for business use, not as a consumer.',
    ),
    '3. Subscription, free trial and payment': const LegalSection(
      '3. Subscription, free trial and payment',
      'FieldOS needs a FieldOS Pro subscription, bought through Google Play or the Apple App Store, monthly or '
          'yearly at the price the store shows before you pay, including any tax the store charges.\n\nNew '
          'subscribers get one 3-day free trial, where the store offers it to them. Unless you cancel before the '
          'trial ends, the first payment is taken when it ends. The subscription then renews automatically for '
          'the same period at the price then current, until you cancel. Cancel at least 24 hours before the end '
          'of a period, in your Google Play or App Store subscriptions, to avoid the next charge. Uninstalling '
          'the app does not cancel a subscription.\n\nThe store takes the payment, and refunds are handled by the '
          'store under its own policies. If we change the price, the store tells you before the new price '
          'applies, and you can cancel before then. If a payment fails or a subscription ends, FieldOS cannot be '
          'used until you subscribe again. Your records are not deleted, and are there again when you '
          'resubscribe.',
    ),
    '5. Team chat and other shared content': const LegalSection(
      '5. Team chat and other shared content',
      'Project chat, photos, comments and other content you share are seen by the other members of your '
          'company. We do not allow objectionable content or abusive users. Do not post or share anything '
          'that:\n\n• threatens, harasses, bullies or abuses anyone, or attacks people for their race, religion, '
          'nationality, gender, disability or any other part of who they are;\n• is sexual, obscene, violent or '
          'hateful, or involves a child in any harmful way;\n• is spam, a scam or fraud, or asks for money under '
          'false pretences;\n• is false or misleading in a way meant to harm someone, or impersonates another '
          'person;\n• shares someone\'s private information without their permission;\n• infringes anyone\'s '
          'copyright, trademark or other rights; or\n• is unlawful in Malaysia, including content that the '
          'Communications and Multimedia Act 1998 or the Online Safety Act 2025 does not allow.',
    ),
    '8. Check the numbers': const LegalSection(
      '8. Check the numbers',
      'FieldOS helps with estimates, quantities, wages, overtime, rest day and public holiday pay, payment '
          'claims, retention, attendance and reports, and its AI assistant answers questions and fills in records '
          'for you to confirm. These can contain mistakes, and FieldOS does not know every rule in your contract '
          'or every state law (Sabah and Sarawak have their own Labour Ordinances). Check figures before you rely '
          'on them. FieldOS is a record-keeping aid, not engineering, legal, payroll, tax or accounting advice: it '
          'does not file EPF, SOCSO, EIS, PCB or SST returns for you, and the bills it makes are not e-Invoices '
          'validated by LHDN (MyInvois). Those duties remain yours as the employer or contractor.',
    ),
    '14. Limits on our liability': const LegalSection(
      '14. Limits on our liability',
      'As far as the law allows, we are not liable for indirect or consequential loss, or for loss of profit, '
          'business, contracts or data, arising from your use of FieldOS. Our total liability to you for all '
          'claims about FieldOS is limited to the amount you paid for FieldOS in the 12 months before the event '
          'that led to the claim.\n\nNothing in these terms limits liability that cannot be limited by law, '
          'including liability for fraud.',
    ),
    '17. Law and disputes': const LegalSection(
      '17. Law and disputes',
      'These terms are governed by the laws of Malaysia. If you have a complaint, please write to us first at '
          'info@mldynamic.com so we can try to settle it; most problems can be solved this way within 30 days. If '
          'it is not settled, it will be finally resolved by arbitration in Kuala Lumpur under the AIAC '
          'Arbitration Rules of the Asian International Arbitration Centre, by one arbitrator, in English.',
    ),
    '18. Grievance officer': const LegalSection(
      '18. Your workers\' personal data',
      'Your company is the data controller of the personal data it records about its workers, staff, '
          'subcontractors and leads, and we process it only on your behalf, to run FieldOS, as the privacy notice '
          'describes. You confirm that you have given those people the notice the PDPA requires, and got their '
          'consent where it is needed, including for attendance selfies and location. We will tell you without '
          'undue delay of a breach that affects your company\'s data, help you answer requests from the people '
          'in your records, and delete your company\'s data when your account is deleted.',
    ),
    '20. Contact us': const LegalSection('21. Contact us', _contact),
  },
  add: const [
    LegalSection(
      '20. Language',
      'These terms are written in English. A Bahasa Melayu or Chinese translation in the app is for your '
          'convenience; if it differs, the English text applies.',
    ),
  ],
);
