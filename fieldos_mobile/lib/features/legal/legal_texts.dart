/// The privacy policy and terms of use the app carries, so they can be read
/// offline and before any account exists. Keep both in step with
/// website/privacy-policy.html and website/terms-of-use.html (the
/// published copies).
library;

class LegalSection {
  const LegalSection(this.heading, this.body);
  final String heading;
  final String body;
}

class LegalDocument {
  const LegalDocument({required this.title, required this.updated, required this.intro, required this.sections});
  final String title;
  final String updated;
  final String intro;
  final List<LegalSection> sections;
}

const privacyPolicy = LegalDocument(
  title: 'Privacy policy',
  updated: '11 November 2026',
  intro:
      'FieldOS is made by ML Dynamic Solutions Private Limited. FieldOS stores the projects, reports, '
      'photos, attendance and other site records you create on your phone. If you sign in to Team & sync, '
      'those records, your email address and the name you entered are also stored in our cloud database '
      '(Supabase, region: Mumbai, India), so that the people your company works with can see what is meant '
      'for them.',
  sections: [
    LegalSection(
      'Who can see your company\'s data',
      '• Members of your company see the company\'s sites and records, limited by their role. For example, '
          'only owners and project managers see salaries, leads and the change history.\n\n• Subcontractors, '
          'suppliers and the client see only what the company shares with them, and only after they join with '
          'a code an owner or project manager gave them. A subcontractor sees their own work orders and '
          'claims. A supplier sees the price requests and orders sent to them. A site\'s client sees that '
          'site\'s progress, its photos and the bills sent to them. They never see the rest of the '
          'company.\n\n• The FieldOS team does not look at company data, except to fix a problem you report or '
          'when the law requires it.',
    ),
    LegalSection(
      'Location',
      'Your location is read only when you check yourself in or out, punch a worker in or out, set a site '
          'location, or take a site photo with the in-app camera (the date, time and position are printed on '
          'the photo). It is saved with that record, so the company can see the work was done at the site. It '
          'is never tracked in the background.',
    ),
    LegalSection(
      'Attendance photos and selfies',
      'When staff check in or out, the app takes a selfie with the front camera and saves it with the '
          'time, the site and the GPS position. A supervisor can also take a photo when punching workers in. '
          'The photos are part of the company\'s attendance records: the owner and project managers of that '
          'company can see them, and they are used only to confirm attendance. FieldOS does not use face '
          'recognition.',
    ),
    LegalSection(
      'Salaries, workers and leads',
      'Companies use FieldOS to keep their own records about other people: workers\' names, attendance and '
          'wages, staff salaries and advances, and leads (the name, phone number and enquiry of a possible '
          'customer). The company decides what it records and why. FieldOS stores and processes these records '
          'only on the company\'s behalf, and only owners and project managers can see salaries and leads.',
    ),
    LegalSection(
      'Change history',
      'When someone changes or deletes a money or progress record, FieldOS keeps who did it, when, and the '
          'old and new values, so the company can check its records. Owners, project managers and the accounts '
          'team can see this history.',
    ),
    LegalSection(
      'Voice reports',
      'Voice reports use your phone\'s own speech recognition: Google\'s on Android and Apple\'s on '
          'iPhone. When the language\'s offline speech pack is on the phone, your speech is turned into text '
          'on the phone. Otherwise the phone\'s speech service may send it to Google or Apple to be '
          'recognised, under their privacy policies. FieldOS does not record or keep your voice.\n\nOnly if '
          'your phone can\'t recognise the language you chose, and you are signed in to Team & sync, FieldOS '
          'records your report and sends the recording through its own server to Sarvam AI (sarvam.ai) to be '
          'turned into text. FieldOS does not keep the recording afterwards.\n\nTranslating a report to '
          'English happens on the phone, using Google ML Kit. The language pack is downloaded from Google '
          'once, and the text of your report is never sent. ML Kit does send Google diagnostic details so that '
          'Google can maintain it: the phone model and system version, the app version, an identifier for this '
          'installation, the languages chosen, and how long translation took.',
    ),
    LegalSection(
      'AI assistant',
      'When you use Ask FieldOS, what you type or say, and the site details the assistant needs to answer '
          '(such as project names, workers, tasks and amounts on this phone), go through FieldOS\'s server to '
          'Anthropic (anthropic.com), whose Claude model works out the reply. Anthropic\'s commercial terms do '
          'not let it use this to train its models. If Anthropic is unavailable, the same goes instead to '
          'Sarvam AI (sarvam.ai), which runs a DeepSeek model for the reply. FieldOS keeps only a count of how '
          'much each account uses the assistant each day and month, not the conversation. Nothing is saved to '
          'your records until you tap Save on the card the assistant shows.',
    ),
    LegalSection(
      'Maps',
      'Map tiles are loaded from OpenStreetMap. Their servers can see your device\'s IP address, as with '
          'any web request.',
    ),
    LegalSection(
      'Payments',
      'The FieldOS subscription is bought through Google Play or the Apple App Store, which handle your '
          'card or UPI details. FieldOS never sees them. RevenueCat (revenuecat.com) receives the purchase '
          'record from the store, linked to your FieldOS account id, so that the app and the assistant can '
          'check your subscription. Company plans are invoiced directly by ML Dynamic Solutions.',
    ),
    LegalSection(
      'Bug reports and crash details',
      'If you use "Report a bug", we receive what you type, the email address you give (optional), the app '
          'version, your phone\'s operating system version and the app\'s last few error messages. No project '
          'data, photos or contacts are included. Reports are stored in our cloud database and copied to our '
          'private issue tracker on GitHub so that we can fix the problem.\n\nIf the app crashes and "Send '
          'crash details" is on in Settings (you can turn it off at any time), the next time you are online '
          'the app sends the error, where in the app it happened, the app version and the phone\'s system '
          'version, the same way as a bug report. No project data is included.\n\nIf you use "Report this '
          'message" in project chat, we receive the reported message, the name it was sent under, the reason '
          'you picked, anything you add, and your account id. The sender is not told who reported it. Reports '
          'are stored in our cloud database and copied to our private issue tracker on GitHub so that we can '
          'review them within 24 hours. You can also block a teammate, which hides their chat messages on your '
          'phone.\n\nApart from what this policy describes, nothing about how you use FieldOS leaves your '
          'phone. We do not sell data or show ads.',
    ),
    LegalSection(
      'How long we keep data',
      '• Company records stay as long as the company uses FieldOS, and are deleted with the account as '
          'described below.\n\n• Bug, crash and message reports are kept only as long as needed to fix or '
          'review them, and never more than 12 months.\n\n• Deleted data can remain in our hosting provider\'s '
          'automatic backups for up to 30 days before they are overwritten.',
    ),
    LegalSection(
      'Deleting data',
      'In the app, open Team & sync and tap "Delete my cloud account". A company where you are the only '
          'member is deleted with all its records and files: site photos, selfies, documents and claim photos. '
          'In a company with other members, the records you added (including your attendance) stay with that '
          'company, because they are its work records. Your name is removed from its team chat, ownership '
          'passes to another member, and your portal access and assistant usage are deleted. You can also ask '
          'for deletion by emailing info@mldynamic.com. Uninstalling the app removes the data on the phone. '
          'See Delete your account.',
    ),
    LegalSection(
      'Your rights',
      'Under India\'s Digital Personal Data Protection Act, 2023, you can ask us for a summary of the '
          'personal data we hold about you, ask us to correct or complete it, ask us to erase it, and nominate '
          'someone to act for you. Email info@mldynamic.com from the address on your account. If your data is '
          'in a company\'s records (for example as a worker or a lead), we pass your request to that company, '
          'which decides about its own records, and we tell you that we have done so.',
    ),
    LegalSection(
      'Grievance officer',
      'For any complaint about your personal data, write to the Grievance Officer, ML Dynamic Solutions '
          'Private Limited, at info@mldynamic.com with "Privacy grievance" in the subject. We reply within 30 '
          'days. If you are not satisfied, you can complain to the Data Protection Board of India.',
    ),
    LegalSection(
      'Contact',
      'info@mldynamic.com, ML Dynamic Solutions Private Limited, 606, 6th Floor, Gowra Fountainhead, '
          'Patrika Nagar, Madhapur, Hi-Tech City, Hyderabad, Telangana 500081, India.',
    ),
  ],
);

const termsOfUse = LegalDocument(
  title: 'Terms of use',
  updated: '8 November 2026',
  intro:
      'These terms of use ("terms") are an agreement between you and ML Dynamic Solutions Private Limited, '
      'a company incorporated in India ("we", "us"), which makes the FieldOS app and its cloud service '
      '("FieldOS"). By creating an account, starting a free trial or using FieldOS, you agree to these '
      'terms and to the privacy policy. If you use FieldOS for a company, you confirm that you may accept '
      'these terms for it, and "you" includes that company. If you do not agree, do not use FieldOS.',
  sections: [
    LegalSection(
      '1. Who can use FieldOS',
      'You must be at least 18 years old and able to enter a binding contract under Indian law. FieldOS is '
          'made for builders, contractors and their site teams, for business use.',
    ),
    LegalSection(
      '2. Your account and your team',
      'Give true details when you sign up and keep them up to date. Keep your password and your phone '
          'secure; you are responsible for what is done with your account. Tell us at info@mldynamic.com '
          'straight away if you think someone else has used it.\n\nRecords you make without Team & sync stay '
          'only on your phone, and we cannot recover them if the phone is lost or reset. With Team & sync on, '
          'a copy is kept in our cloud for your company.\n\nThe person who creates a company in Team & sync is '
          'its owner. The owner decides who joins and what role they have, and is responsible for making sure '
          'members follow these terms. Members can see the company\'s records that their role allows.',
    ),
    LegalSection(
      '3. Subscription, free trial and payment',
      'FieldOS needs a FieldOS Pro subscription, bought through Google Play or the Apple App Store, '
          'monthly or yearly at the price the store shows before you pay, including any taxes the store '
          'charges.\n\nNew subscribers get one 3-day free trial, where the store offers it to them. Unless you '
          'cancel before the trial ends, the first payment is taken when it ends. The subscription then renews '
          'automatically for the same period at the price then current, until you cancel. Cancel at least 24 '
          'hours before the end of a period, in your Google Play or App Store subscriptions, to avoid the next '
          'charge. Uninstalling the app does not cancel a subscription.\n\nThe store takes the payment, and '
          'refunds are handled by the store under its own policies. If we change the price, the store tells '
          'you before the new price applies, and you can cancel before then. If a payment fails or a '
          'subscription ends, FieldOS cannot be used until you subscribe again. Your records are not deleted: '
          'they stay on your phone, and in the cloud for your company if Team & sync is on, and are there '
          'again when you resubscribe.',
    ),
    LegalSection(
      '4. Your content',
      'You own the projects, reports, photos, messages and other records you and your team put into '
          'FieldOS ("your content"). You give us permission to store, copy, process and show your content only '
          'to run FieldOS for you and your company, to keep it secure and to fix problems, as the privacy '
          'policy describes. We do not sell your content or use it for advertising.\n\nYou confirm that you '
          'have the right to put your content into FieldOS, including photos of people and the details of '
          'workers you record, and that you have told them where your law requires it. Keep your own copies of '
          'anything important; FieldOS can export reports and records.',
    ),
    LegalSection(
      '5. Team chat and other shared content',
      'Project chat, photos, comments and other content you share are seen by the other members of your '
          'company. We do not allow objectionable content or abusive users. Do not post or share anything '
          'that:\n\n• threatens, harasses, bullies or abuses anyone, or attacks people for their caste, '
          'religion, gender, sexuality, disability, region or any other part of who they are;\n• is sexual, '
          'obscene, violent or hateful, or involves a child in any harmful way;\n• is spam, a scam or fraud, '
          'or asks for money under false pretences;\n• is false or misleading in a way meant to harm someone, '
          'or impersonates another person;\n• shares someone\'s private information without their '
          'permission;\n• infringes anyone\'s copyright, trademark or other rights; or\n• breaks any law in '
          'force in India, including the content the Information Technology Act, 2000 and its rules prohibit.',
    ),
    LegalSection(
      '6. Reporting content and how we act',
      'Press and hold any message from someone else in project chat and tap "Report this message". You can '
          'also report any content or user by writing to info@mldynamic.com. The person you report is not told '
          'who reported them, and a message you report is hidden on your phone.\n\nWe review every report '
          'within 24 hours. If the content breaks these terms we remove it, and we may warn, suspend or '
          'permanently remove the user who posted it. We may also keep the content and pass it to the police '
          'or other authorities where the law requires it.',
    ),
    LegalSection(
      '7. Acceptable use',
      'Do not use FieldOS to break the law, and do not: try to get into another company\'s data or any '
          'account that is not yours; test, probe or get round FieldOS\'s security; copy, decompile or reverse '
          'engineer the app, except as far as the law allows; use bots or scripts to collect data from '
          'FieldOS; upload viruses or other harmful code; overload or interfere with the service; or resell or '
          'rent FieldOS to others.',
    ),
    LegalSection(
      '8. Check the numbers',
      'FieldOS helps with estimates, quantities, wages, payments, attendance and reports, and it turns '
          'spoken reports into text automatically, and its AI assistant answers questions and fills in records '
          'for you to confirm. These can contain mistakes. Check figures, reports and what the assistant '
          'proposes '
          'before you rely on them. FieldOS is not engineering, structural, legal, tax or accounting advice, '
          'and it does not make you compliant with labour, wage, tax or safety laws; those decisions and '
          'duties remain yours.',
    ),
    LegalSection(
      '9. Other companies\' services',
      'Some parts of FieldOS use services from other companies, including Google Play and the Apple App '
          'Store (payments), RevenueCat (checking subscriptions), Supabase (our cloud database), Google '
          '(sign-in, speech and translation), Apple (speech), OpenStreetMap (maps), Anthropic (the AI '
          'assistant) and Sarvam AI (speech, only for languages your phone can\'t recognise). Their own terms apply to their services, and we are '
          'not responsible for them.',
    ),
    LegalSection(
      '10. Changes to FieldOS',
      'We keep improving FieldOS, so features may change, and we may stop a feature where we have a good '
          'reason. Features that work offline keep working on your phone; cloud features need an internet '
          'connection and may sometimes be unavailable, for example during maintenance. We will tell you in '
          'the app before removing a feature that is a main part of what you pay for.',
    ),
    LegalSection(
      '11. Our rights in FieldOS',
      'FieldOS, its software, design, name and logo belong to us or the people we license them from. We '
          'give you a personal, non-exclusive, non-transferable right to use the app while you follow these '
          'terms. If you send us ideas or feedback, we may use them without owing you anything.',
    ),
    LegalSection(
      '12. Ending your use, suspension and termination',
      'You can stop using FieldOS at any time. Cancel your subscription in the store, and delete your '
          'cloud account in the app under Team & sync, "Delete my cloud account", or by writing to us. What '
          'happens to your company\'s records when you delete your account is explained in the privacy '
          'policy.\n\nWe may suspend or close your account, with notice where it is reasonable to give it, if '
          'you seriously or repeatedly break these terms, if the law requires it, or if your use puts other '
          'users or FieldOS at risk. If we close your account without a good reason under these terms, we will '
          'refund the unused part of your subscription through the store or directly. Sections 4, 8, 13, 14, '
          '15 and 17 continue after these terms end.',
    ),
    LegalSection(
      '13. No guarantees',
      'We work hard to keep FieldOS accurate, secure and available, but as far as the law allows, FieldOS '
          'is provided "as is" and "as available", without any promise that it will be free of errors or '
          'interruptions or that it suits a particular purpose.',
    ),
    LegalSection(
      '14. Limits on our liability',
      'As far as the law allows, we are not liable for indirect or consequential loss, or for loss of '
          'profit, business, contracts or data, arising from your use of FieldOS. Our total liability to you '
          'for all claims about FieldOS is limited to the amount you paid for FieldOS in the 12 months before '
          'the event that led to the claim.\n\nNothing in these terms limits liability that cannot be limited '
          'by law, including liability for fraud, and nothing takes away your rights under the Consumer '
          'Protection Act, 2019 where that Act applies to you.',
    ),
    LegalSection(
      '15. Your responsibility to us',
      'If someone makes a claim against us because of content you or your team put into FieldOS, or '
          'because you broke these terms or the law, you will cover our reasonable losses and costs from that '
          'claim. This does not apply to the extent the claim was caused by our own fault.',
    ),
    LegalSection(
      '16. Changes to these terms',
      'We may update these terms, for example when the law or FieldOS changes. The date at the top shows '
          'the current version. If a change matters to you, we will tell you in the app at least 15 days '
          'before it takes effect. If you keep using FieldOS after that, the new terms apply; if you do not '
          'agree, cancel and stop using FieldOS.',
    ),
    LegalSection(
      '17. Law and disputes',
      'These terms are governed by the laws of India. If you have a complaint, please write to us first so '
          'we can try to settle it; most problems can be solved this way within 30 days. If it is not settled, '
          'the courts at Hyderabad, Telangana have exclusive jurisdiction, except where consumer law lets you '
          'bring a claim where you live.',
    ),
    LegalSection(
      '18. Grievance officer',
      'Complaints about content in FieldOS, or about these terms, can be sent to our Grievance Officer at '
          'info@mldynamic.com, or by post to the address below, marked "Grievance Officer". We acknowledge a '
          'complaint within 24 hours and resolve it within 15 days of receiving it.',
    ),
    LegalSection(
      '19. General',
      'These terms and the privacy policy are the whole agreement between you and us about FieldOS. If a '
          'court finds any part of them unenforceable, the rest still applies. If we do not enforce a right '
          'straight away, we can still enforce it later. You may not transfer these terms to anyone else; we '
          'may transfer them to a company that takes over FieldOS, and your rights under them will not be '
          'reduced.',
    ),
    LegalSection(
      '20. Contact us',
      'info@mldynamic.com, ML Dynamic Solutions Private Limited, 606, 6th Floor, Gowra Fountainhead, '
          'Patrika Nagar, Madhapur, Hi-Tech City, Hyderabad, Telangana 500081, India.',
    ),
  ],
);
