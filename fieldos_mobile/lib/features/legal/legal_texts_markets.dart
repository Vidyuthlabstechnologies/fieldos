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

/// The policy this build shows: every market has its own draft
/// (test/market_legal_test.dart checks each one's law and wording).
LegalDocument get marketPrivacyPolicy => switch (currentMarket) {
  Market.india => privacyPolicy,
  Market.us => usPrivacyPolicy,
  Market.malaysia => myPrivacyPolicy,
  Market.uae => aePrivacyPolicy,
  Market.uk => ukPrivacyPolicy,
};

LegalDocument get marketTermsOfUse => switch (currentMarket) {
  Market.india => termsOfUse,
  Market.us => usTermsOfUse,
  Market.malaysia => myTermsOfUse,
  Market.uae => aeTermsOfUse,
  Market.uk => ukTermsOfUse,
};

/// Whether this market has its own legal texts yet.
bool get marketLegalReady => const {Market.india, Market.us, Market.malaysia, Market.uae, Market.uk}.contains(currentMarket);

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
      'When staff clock in or out, the app takes a photo with the front camera '
          'and saves it with the time, the job and the GPS position. A check-in photo is kept '
          'only until the day is verified, then deleted (see How long we keep data); until then only the owner '
          'and project managers of that company can see it, and only to confirm who was on the job. FieldOS does not use face recognition, does not make a face '
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
          'described below.\n\n• Check-in photos are kept only until the day is verified: at once '
          'when the person is on the job, or when an owner or project manager decides on a check-in made away '
          'from it. They are then deleted from the phone and, within a day, from our cloud, and only the result '
          'is kept.\n\n• Bug, crash and message reports are kept only as long as needed to fix or '
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
  add: const [
    LegalSection(
      'Do Not Track',
      'FieldOS does not track you across other apps or websites, so it works the same whether or not your '
          'browser or phone sends a Do Not Track or Global Privacy Control signal. There is nothing to opt out of.',
    ),
  ],
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
      'When staff check in or out, the app takes a photo with the front camera '
          'and saves it with the time, the site and the GPS position. A supervisor can also take a photo '
          'when punching workers in. A check-in selfie is kept '
          'only until the day is verified, then deleted (see How long we keep data); until then only the owner '
          'and project managers of that company can see it, and only to confirm attendance. Photos a supervisor '
          'takes when punching workers in stay with the company\'s attendance records. FieldOS '
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
          '1955, so export them before you delete an account.\n\n• Attendance selfies are kept only until the day is '
          'verified: at once when the person is at the site, or when an owner or project manager decides on a '
          'check-in made away from it. They are then deleted from the phone and, within a day, from our cloud, '
          'and only the result is kept.'
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
          'Withdrawing consent does not affect what was done before: turn off the AI assistant, crash details or '
          'the photo and location for your attendance, or delete your cloud account.',
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

/// UAE: Federal Decree-Law 45 of 2021 on personal data protection (PDPL),
/// transfers abroad under Articles 22 and 23, no face recognition, the
/// midday break and WPS left to the employer. The terms keep Indian law
/// (the store-sold app, as in India) with a carve-out for mandatory UAE
/// rights; enterprise contracts sold by invoice may agree DIAC arbitration.
/// The Arabic version of both is still to be made before launch.
final aePrivacyPolicy = adaptLegal(
  privacyPolicy,
  intro: 'FieldOS is made by ML Dynamic Solutions Private Limited, a company based in India. This policy is for the '
      'FieldOS app for the United Arab Emirates, and is given under Federal Decree-Law No. 45 of 2021 on the '
      'Protection of Personal Data (PDPL). FieldOS stores the projects, reports, photos, attendance and other site '
      'records you create on your phone. If you sign in to Team & sync, those records, your email address and the '
      'name you entered are also stored in our cloud database (Supabase, region: Mumbai, India), so that the people '
      'your company works with can see what is meant for them.',
  replace: {
    'Attendance photos and selfies': const LegalSection(
      'Attendance photos and selfies',
      'When staff check in or out, the app takes a photo with the front camera and saves it with the time, the '
          'site and the GPS position. A supervisor can also take a photo when punching workers in. A check-in '
          'selfie is kept only until the day is verified, then deleted (see How long we keep data); until then only '
          'the owner and project managers of that company can see it, and only to confirm attendance. Photos a '
          'supervisor takes when punching workers in stay with the company\'s attendance records. FieldOS does not use face '
          'recognition, and makes no face template or other biometric data from the photo. The app tells each person '
          'this and asks them to agree before their first check-in. They can turn it off at any time in Settings, '
          'Your privacy, and a supervisor then marks their attendance instead.',
    ),
    'Salaries, workers and leads': const LegalSection(
      'Salaries, workers and leads',
      'Companies use FieldOS to keep their own records about other people: workers\' names, attendance and wages, '
          'staff salaries and advances, work permit, Emirates ID and passport details, and leads (the name, phone '
          'number and enquiry of a possible customer). The company decides what it records and why, and is the '
          'controller of those records; FieldOS processes them only on the company\'s behalf. Only owners and '
          'project managers can see salaries and leads, and ID and passport numbers are shown masked in lists. A '
          'worker supplied by a labour supply company is also that company\'s employee.',
    ),
    'Payments': const LegalSection(
      'Payments',
      'The FieldOS subscription is bought through Google Play or the Apple App Store, which handle your card or '
          'other payment details and any VAT. FieldOS never sees them. RevenueCat (revenuecat.com, USA) receives the '
          'purchase record from the store, linked to your FieldOS account id, so that the app and the assistant can '
          'check your subscription.',
    ),
    'Where your data is processed': const LegalSection(
      'Where your data is processed',
      'Your cloud records are stored by Supabase in Mumbai, India, outside the UAE. A few other services we use are '
          'run from other countries: Anthropic (USA) for the AI assistant, with Sarvam AI (India) as its backup, '
          'RevenueCat (USA) for checking subscriptions, GitHub (USA) for our private copy of bug and message reports, '
          'and Google and Apple for sign-in, speech and the stores. We send personal data to these places under '
          'Articles 22 and 23 of the PDPL: each service gets only what this policy describes for it, under a contract '
          'that limits it to providing its service and requires it to protect the data to the PDPL\'s standard. '
          'If your company is in a free zone with its own data '
          'law (DIFC or ADGM), tell us before you use FieldOS. We will update this policy before the place where '
          'your records are stored changes.',
    ),
    'Keeping data safe': const LegalSection(
      'Keeping data safe',
      'We protect data with encryption in transit, access limited by role, and checks that keep each company\'s '
          'records apart. If a breach of personal data could harm your privacy, we will tell your company within 72 '
          'hours, and tell you and the UAE data protection authority without delay what happened, what it means for '
          'you and what we are doing about it.',
    ),
    'Children': const LegalSection(
      'Children',
      'FieldOS is for people aged 18 and over, for business use, and we do not knowingly collect personal data of '
          'children. Do not record anyone under 18 as a worker on a building site: UAE law does not allow juveniles '
          'to do dangerous work such as construction.',
    ),
    'How long we keep data': const LegalSection(
      'How long we keep data',
      '• Company records stay as long as the company uses FieldOS, and are deleted with the account as described '
          'below. Employers must keep wage records for the period UAE labour law sets, so export them before you '
          'delete an account.\n\n• Attendance selfies are kept only until the day is '
          'verified: at once when the person is at the site, or when an owner or project manager decides on a '
          'check-in made away from it. They are then deleted from the phone and, within a day, from our cloud, '
          'and only the result is kept.\n\n• Bug, crash and message reports are kept '
          'only as long as needed to fix or review them, and never more than 12 months.\n\n• Deleted data can remain '
          'in our hosting provider\'s automatic backups for up to 30 days before they are overwritten.',
    ),
    'Your rights': const LegalSection(
      'Your rights',
      'Under the PDPL you can ask us for the personal data we hold about you and a copy of it, ask us to correct or '
          'erase it, ask us to restrict or stop processing it, object to it, and ask us to send it to another '
          'organisation in a machine-readable form. FieldOS makes no decision about you by automated means alone. '
          'Email info@mldynamic.com from the address on your account, or use Settings, Your privacy. We reply within '
          '30 days. If your data is in a company\'s records (for example as a worker or a lead), we pass your request '
          'to that company, which decides about its own records, and tell you we have done so. You can withdraw '
          'your consent at any time: turn off the AI assistant, crash details, or the photo and location for your '
          'attendance in Settings, Your privacy, or delete your cloud account. '
          'Withdrawing does not affect what was done before.',
    ),
    'Grievance officer': const LegalSection(
      'Privacy contact and complaints',
      'For any question or complaint about your personal data, write to our privacy contact at info@mldynamic.com '
          'with "Privacy" in the subject. If you are not satisfied with our answer, you can complain to the UAE data '
          'protection authority.',
    ),
    'Contact': const LegalSection(
      'Contact',
      'Questions or requests about privacy: info@mldynamic.com with "Privacy" in the subject. $_contact',
    ),
  },
);

final aeTermsOfUse = adaptLegal(
  termsOfUse,
  intro: 'These terms of use ("terms") are an agreement between you and ML Dynamic Solutions Private Limited, a '
      'company incorporated in India ("we", "us"), which makes the FieldOS app for the United Arab Emirates and its '
      'cloud service ("FieldOS"). By creating an account, starting a free trial or using FieldOS, you agree to these '
      'terms and to the privacy policy. If you use FieldOS for a company, you confirm that you may accept these terms '
      'for it, and "you" includes that company. If you do not agree, do not use FieldOS.',
  replace: {
    '1. Who can use FieldOS': const LegalSection(
      '1. Who can use FieldOS',
      'You must be at least 18 years old and able to enter a binding contract. FieldOS is made for contractors, '
          'builders and their site teams, for business use.',
    ),
    '3. Subscription, free trial and payment': const LegalSection(
      '3. Subscription, free trial and payment',
      'FieldOS needs a FieldOS Pro subscription, bought through Google Play or the Apple App Store, monthly or yearly '
          'at the price in AED the store shows before you pay, including VAT.\n\nNew subscribers get one 3-day free '
          'trial, where the store offers it to them. Unless you cancel before the trial ends, the first payment is '
          'taken when it ends. The subscription then renews automatically for the same period at the price then '
          'current, until you cancel. Cancel at least 24 hours before the end of a period, in your Google Play or App '
          'Store subscriptions, to avoid the next charge. Uninstalling the app does not cancel a subscription.\n\nThe '
          'store takes the payment, and refunds are handled by the store under its own policies. If we change the '
          'price, the store tells you before the new price applies, and you can cancel before then. If a payment '
          'fails or a subscription ends, FieldOS cannot be used until you subscribe again. Your records are not '
          'deleted, and are there again when you resubscribe.',
    ),
    '5. Team chat and other shared content': const LegalSection(
      '5. Team chat and other shared content',
      'Project chat, photos, comments and other content you share are seen by the other members of your company. We '
          'do not allow objectionable content or abusive users. Do not post or share anything that:\n\n• threatens, '
          'harasses, bullies or abuses anyone, or attacks people for their religion, nationality, race, gender, '
          'disability or any other part of who they are;\n• offends any religion, the UAE, its symbols or its leaders, '
          'or public morals;\n• is sexual, obscene, violent or hateful, or involves a child in any harmful way;\n• is '
          'spam, a scam or fraud, or asks for money under false pretences;\n• is false or misleading in a way meant to '
          'harm someone, or impersonates another person;\n• shares someone\'s private information or photos without '
          'their permission;\n• infringes anyone\'s copyright, trademark or other rights; or\n• breaks any UAE law, '
          'including the laws on cybercrime and media.',
    ),
    '8. Check the numbers': const LegalSection(
      '8. Check the numbers',
      'FieldOS helps with estimates, quantities, wages, overtime, interim payment applications, VAT, retention, '
          'attendance and reports, and its AI assistant answers questions and fills in records for you to confirm. '
          'These can contain mistakes, and FieldOS does not know every rule in your contract or every decision of the '
          'Ministry of Human Resources and Emiratisation. Check figures before you rely on them. FieldOS is a '
          'record-keeping aid, not engineering, legal, payroll, tax or accounting advice: it does not pay salaries '
          'through the Wage Protection System, file VAT returns or issue e-invoices through an accredited service '
          'provider, and its warnings about the midday break do not make a site compliant. Those duties remain yours '
          'as the employer or contractor.',
    ),
    '14. Limits on our liability': const LegalSection(
      '14. Limits on our liability',
      'As far as the law allows, we are not liable for indirect or consequential loss, or for loss of profit, '
          'business, contracts or data, arising from your use of FieldOS. Our total liability to you for all claims '
          'about FieldOS is limited to the amount you paid for FieldOS in the 12 months before the event that led to '
          'the claim.\n\nNothing in these terms limits liability that cannot be limited by law, including liability '
          'for fraud, or takes away any right you have under UAE law that cannot be excluded by contract.',
    ),
    '16. Changes to these terms': const LegalSection(
      '16. Changes to these terms',
      'We may update these terms, for example when the law or FieldOS changes. The date at the top shows the current '
          'version. We will tell you in the app at least 30 days before a change that matters to you takes effect. If '
          'you do not agree, you can cancel before then; if you keep using FieldOS after that, the new terms apply.',
    ),
    '17. Law and disputes': const LegalSection(
      '17. Law and disputes',
      'These terms are governed by the laws of India. If you have a complaint, please write to us first at '
          'info@mldynamic.com so we can try to settle it; most problems can be solved this way within 30 days. If it '
          'is not settled, the courts at Hyderabad, Telangana have jurisdiction, but nothing in this section takes '
          'away a right you have under UAE law to bring a claim in the UAE. A company plan agreed in writing may '
          'instead provide for arbitration under the rules of the Dubai International Arbitration Centre.',
    ),
    '18. Grievance officer': const LegalSection(
      '18. Your workers\' personal data',
      'Your company is the controller of the personal data it records about its workers, staff, subcontractors and '
          'leads, and we process it only on your behalf, to run FieldOS, as the privacy policy describes. You confirm '
          'that you have told those people what is recorded and why, in a language they understand, including for '
          'attendance selfies and location, and that you have a lawful basis for it. We will tell you within 72 hours '
          'of a breach that affects your company\'s data, help you answer requests from the people in your records, '
          'and delete your company\'s data when your account is deleted.',
    ),
    '20. Contact us': const LegalSection('20. Contact us', _contact),
  },
);

final ukPrivacyPolicy = adaptLegal(
  privacyPolicy,
  intro: 'FieldOS is made by ML Dynamic Solutions Private Limited, a company based in India ("we", "us"). This privacy '
      'notice is for the FieldOS app for the United Kingdom, and is given under the UK General Data Protection '
      'Regulation (UK GDPR) and the Data Protection Act 2018. We are the controller of your account data. FieldOS '
      'stores the projects, site diaries, photos, attendance and other site records you create on your phone. If you '
      'sign in to Team & sync, those records, your email address and the name you entered are also stored in our cloud '
      'database (Supabase, region: Mumbai, India), so that the people your company works with can see what is meant '
      'for them. Our representative in the UK under Article 27 of the UK GDPR will be named in this notice before the '
      'UK app is published.',
  replace: {
    'Attendance photos and selfies': const LegalSection(
      'Attendance photos and selfies',
      'When staff sign in or out on site, the app takes a photo with the front camera and saves it with the time, the '
          'site and the GPS position. A supervisor can also take a photo when signing operatives in. A sign-in selfie is '
          'kept only until the day is verified, then deleted (see How long we keep data); until then only the owner '
          'and project managers of that company can see it, and only to confirm attendance. Photos a supervisor takes '
          'when signing operatives in stay with the company\'s attendance records. FieldOS does not use face recognition, '
          'and makes no face template or other biometric data from the photo, so it is not special category data. The '
          'app tells each person this and asks them to agree before their first sign-in. They can turn it off at any '
          'time in Settings, Your privacy, and a supervisor then marks their attendance instead.',
    ),
    'Salaries, workers and leads': const LegalSection(
      'Pay, operatives and leads',
      'Companies use FieldOS to keep their own records about other people: operatives\' names, attendance, hours and '
          'pay, staff salaries and advances, CSCS card and right to work details, subcontractors\' CIS details, and '
          'leads (the name, phone number and enquiry of a possible customer). The company decides what it records and '
          'why, and is the controller of those records; FieldOS processes them only on the company\'s behalf, as its '
          'processor. Only owners and project managers can see pay and leads, and ID numbers are shown masked in lists.',
    ),
    'Voice reports': const LegalSection(
      'Voice reports',
      'Voice reports use your phone\'s own speech recognition: Google\'s on Android and Apple\'s on iPhone. When the '
          'language\'s offline speech pack is on the phone, your speech is turned into text on the phone. Otherwise the '
          'phone\'s speech service may send it to Google or Apple to be recognised, under their privacy policies. '
          'FieldOS does not record or keep your voice in the UK app.',
    ),
    'Payments': const LegalSection(
      'Payments',
      'The FieldOS subscription is bought through Google Play or the Apple App Store, which handle your card or other '
          'payment details and the VAT. FieldOS never sees them. RevenueCat (revenuecat.com, USA) receives the purchase '
          'record from the store, linked to your FieldOS account id, so that the app and the assistant can check your '
          'subscription.',
    ),
    'Where your data is processed': const LegalSection(
      'Where your data is processed',
      'Why we use your data (the lawful basis): to provide FieldOS to you and your company under our contract; for our '
          'legitimate interests in keeping FieldOS secure, fixing faults and answering reports; and with your consent '
          'for the AI assistant and crash details, which you can withdraw at any time. The photo and location for '
          'attendance are processed for your company, which decides its own lawful basis; the app tells you first and '
          'lets you use supervisor sign-in instead.\n\nYour cloud records are stored by Supabase in Mumbai, India, outside the UK. A few other '
          'services we use are run from other countries: Anthropic (USA) for the AI assistant, with Sarvam AI (India) '
          'as its backup, RevenueCat (USA) for checking subscriptions, GitHub (USA) for our private copy of bug and '
          'message reports, and Google and Apple for sign-in, speech and the stores. India has no UK adequacy decision, '
          'so we send personal data there, and to US services that are not certified under the UK Extension to the '
          'EU-US Data Privacy Framework, under the ICO\'s International Data Transfer Agreement or the UK Addendum to '
          'the EU standard contractual clauses, with a transfer risk assessment. Each service gets only what this '
          'notice describes for it. You can ask us for a copy of these safeguards. We will update this notice before '
          'the place where your records are stored changes.',
    ),
    'Keeping data safe': const LegalSection(
      'Keeping data safe',
      'We protect data with encryption in transit, access limited by role, and checks that keep each company\'s '
          'records apart. If a breach of personal data is likely to put people at risk, we will tell the Information '
          'Commissioner\'s Office (ICO) within 72 hours of finding it, tell your company, and tell you without undue '
          'delay if the risk to you is high.',
    ),
    'Children': const LegalSection(
      'Children',
      'FieldOS is for people aged 18 and over, for business use, and we do not knowingly collect personal data of '
          'children. Do not record a child of compulsory school age as an operative on a building site: UK law does not '
          'allow them to work there.',
    ),
    'How long we keep data': const LegalSection(
      'How long we keep data',
      '• Company records stay as long as the company uses FieldOS, and are deleted with the account as described '
          'below. Employers must keep payroll and CIS records for at least 3 years after the end of the tax year, and '
          'VAT records for 6 years, so export them before you delete an account.\n\n• Attendance selfies are kept '
          'only until the day is verified: at once when the person is on site, or when an owner or project manager '
          'decides on a sign-in made away from it. They are then deleted from the phone and, within a day, from '
          'our cloud, and only the result is kept.\n\n• Bug, crash '
          'and message reports are kept only as long as needed to fix or review them, and never more than 12 months.'
          '\n\n• Deleted data can remain in our hosting provider\'s automatic backups for up to 30 days before they are '
          'overwritten.',
    ),
    'Your rights': const LegalSection(
      'Your rights',
      'Under the UK GDPR you can ask us for the personal data we hold about you and a copy of it, ask us to correct or '
          'erase it, ask us to restrict processing, object to processing based on our legitimate interests, and ask us '
          'to send it to another organisation in a machine-readable form. FieldOS makes no decision about you by '
          'automated means alone. Email info@mldynamic.com from the address on your account, or use Settings, Your '
          'privacy. We reply within one month; if a request is complex we may take up to two more months, and will tell '
          'you why within the first month. If your data is in a company\'s records (for example as an operative or a '
          'lead), that company is the controller: we pass your request to it and tell you we have done so. You can '
          'withdraw your consent at any time: turn off the AI assistant or crash details in Settings, Your privacy, or '
          'delete your cloud account. Withdrawing does not affect what was done before. In the same place you can also '
          'choose supervisor sign-in instead of the attendance photo and location.',
    ),
    'Grievance officer': const LegalSection(
      'Privacy contact and complaints',
      'For any question or complaint about your personal data, write to our privacy contact at info@mldynamic.com with '
          '"Privacy" in the subject. We acknowledge a complaint within 30 days and tell you what we are doing about it. '
          'If you are not satisfied with our answer, you can complain to the Information Commissioner\'s Office '
          '(ico.org.uk, 0303 123 1113).',
    ),
    'Contact': const LegalSection(
      'Contact',
      'Questions or requests about privacy: info@mldynamic.com with "Privacy" in the subject. $_contact',
    ),
  },
);

final ukTermsOfUse = adaptLegal(
  termsOfUse,
  intro: 'These terms of use ("terms") are an agreement between you and ML Dynamic Solutions Private Limited, a '
      'company incorporated in India ("we", "us"), which makes the FieldOS app for the United Kingdom and its cloud '
      'service ("FieldOS"). By creating an account, starting a free trial or using FieldOS, you agree to these terms. '
      'The privacy notice explains how we use personal data. FieldOS is made for businesses: if you use it for a '
      'company, you confirm that you may accept these terms for it, and "you" includes that company. If you do not '
      'agree, do not use FieldOS.',
  replace: {
    '1. Who can use FieldOS': const LegalSection(
      '1. Who can use FieldOS',
      'You must be at least 18 years old. FieldOS is made for contractors, builders and their site teams, for use in '
          'their trade or business.',
    ),
    '3. Subscription, free trial and payment': const LegalSection(
      '3. Subscription, free trial and payment',
      'FieldOS needs a FieldOS Pro subscription, bought through Google Play or the Apple App Store, monthly or yearly at '
          'the price in pounds the store shows before you pay, including VAT.\n\nNew subscribers get one 3-day free '
          'trial, where the store offers it to them. Unless you cancel before the trial ends, the first payment is taken '
          'when it ends. The subscription then renews automatically for the same period at the price then current, '
          'until you cancel. Cancel at least 24 hours before the end of a period, in your Google Play or App Store '
          'subscriptions, to avoid the next charge. Uninstalling the app does not cancel a subscription.\n\nThe store '
          'takes the payment, and refunds are handled by the store under its own policies. If we change the price, the '
          'store tells you before the new price applies, and you can cancel before then. If a payment fails or a '
          'subscription ends, FieldOS cannot be used until you subscribe again. Your records are not deleted, and are '
          'there again when you resubscribe.',
    ),
    '5. Team chat and other shared content': const LegalSection(
      '5. Team chat and other shared content',
      'Project chat, photos, comments and other content you share are seen by the other members of your company. We do '
          'not allow objectionable content or abusive users. Do not post or share anything that:\n\n• threatens, '
          'harasses, bullies or abuses anyone, or attacks people for their race, religion, sex, sexual orientation, '
          'disability, age or any other protected characteristic;\n• is sexual, obscene, violent or hateful, or involves '
          'a child in any harmful way;\n• is spam, a scam or fraud, or asks for money under false pretences;\n• is false '
          'or misleading in a way meant to harm someone, or impersonates another person;\n• shares someone\'s private '
          'information or photos without their permission;\n• infringes anyone\'s copyright, trade mark or other '
          'rights; or\n• breaks any UK law.',
    ),
    '8. Check the numbers': const LegalSection(
      '8. Check the numbers',
      'FieldOS helps with estimates, quantities, pay, hours, applications for payment, VAT, the domestic reverse charge, '
          'CIS deductions, retention, attendance and reports, and its AI assistant answers questions and fills in '
          'records for you to confirm. These can contain mistakes, and FieldOS does not know every term of your '
          'contract. Check figures before you rely on them. FieldOS is a record-keeping aid, not engineering, legal, '
          'payroll, tax or accounting advice: it does not verify subcontractors with HMRC, file CIS or VAT returns, '
          'run payroll or Real Time Information, or decide whether the reverse charge applies to a supply. Those duties '
          'remain yours as the contractor or employer.',
    ),
    '14. Limits on our liability': const LegalSection(
      '14. Limits on our liability',
      'As far as the law allows, we are not liable for indirect or consequential loss, or for loss of profit, business, '
          'contracts or data, arising from your use of FieldOS. Our total liability to you for all claims about FieldOS '
          'is limited to the amount you paid for FieldOS in the 12 months before the event that led to the claim.'
          '\n\nNothing in these terms limits or excludes liability for death or personal injury caused by negligence, '
          'for fraud or fraudulent misrepresentation, or any other liability that cannot be limited or excluded under '
          'the law of England and Wales.\n\nIf you are a consumer, nothing in these terms affects your statutory '
          'rights, including those under the Consumer Rights Act 2015.',
    ),
    '16. Changes to these terms': const LegalSection(
      '16. Changes to these terms',
      'We may update these terms, for example when the law or FieldOS changes. The date at the top shows the current '
          'version. We will tell you in the app at least 30 days before a change that matters to you takes effect. If '
          'you do not agree, you can cancel before then; if you keep using FieldOS after that, the new terms apply.',
    ),
    '17. Law and disputes': const LegalSection(
      '17. Law and disputes',
      'These terms are governed by the law of England and Wales. If you have a complaint, please write to us first at '
          'info@mldynamic.com so we can try to settle it; most problems can be solved this way within 30 days. If it is '
          'not settled, the courts of England and Wales have jurisdiction, except that if you or your business are in '
          'Scotland or Northern Ireland you may also bring a claim in the courts there.',
    ),
    '18. Grievance officer': const LegalSection(
      '18. Your operatives\' personal data',
      'Your company is the controller of the personal data it records about its operatives, staff, subcontractors and '
          'leads, and we process it only on your documented instructions, to run FieldOS, as the privacy notice '
          'describes. These terms are our data processing agreement under Article 28 of the UK GDPR: our staff who '
          'handle it are bound by confidentiality, we keep it secure, we use the sub-processors the privacy notice '
          'lists and tell you before we add one, we help you answer requests from the people in your records, we tell '
          'you without undue delay of a breach that affects your company\'s data, and we delete it when your account is '
          'deleted. You confirm that you have told those people what is recorded and why, including for attendance '
          'selfies and location, and that you have a lawful basis for it.',
    ),
    '20. Contact us': const LegalSection('20. Contact us', _contact),
  },
);
