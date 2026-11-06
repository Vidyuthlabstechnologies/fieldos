/// The privacy policy and terms of use the app carries, so they can be read
/// offline and before any account exists. Keep both in step with
/// docs/store/privacy-policy.html and docs/store/terms-of-use.html (the
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
  updated: '6 November 2026',
  intro: 'FieldOS is made by ML Dynamic Solutions Private Limited. FieldOS stores the projects, reports, photos, '
      'attendance and other site records you create on your phone. If you sign in to Team & sync, those records, '
      'your email address and the name you entered are also stored in our cloud database (Supabase, region: Mumbai, '
      "India) so that the members of your company can see them. Only members of your company can read your "
      "company's data.",
  sections: [
    LegalSection(
      'Location',
      'Your location is read only when you punch a worker in or out, set a site location, or take a site photo with '
          'the in-app camera (the date, time and position are printed on the photo). It is saved with that record. It '
          'is never tracked in the background.',
    ),
    LegalSection(
      'Voice reports',
      "Voice reports use your phone's own speech recognition: Google's on Android and Apple's on iPhone. When the "
          "language's offline speech pack is on the phone, your speech is turned into text on the phone. Otherwise "
          "the phone's speech service may send it to Google or Apple to be recognised, under their privacy policies. "
          'FieldOS does not record or keep your voice.\n\n'
          "Only if your phone can't recognise the language you chose, and your company owner has added a Sarvam key, "
          'FieldOS records your report and sends the recording to Sarvam AI (sarvam.ai) to be turned into text. '
          'FieldOS does not keep the recording afterwards.\n\n'
          'Translating a report to English happens on the phone, using Google ML Kit. The language pack is downloaded '
          'from Google once, and the text of your report is never sent. ML Kit does send Google diagnostic details so '
          'that Google can maintain it: the phone model and system version, the app version, an identifier for this '
          'installation, the languages chosen, and how long translation took.',
    ),
    LegalSection(
      'Maps',
      "Map tiles are loaded from OpenStreetMap. Their servers can see your device's IP address, as with any web "
          'request.',
    ),
    LegalSection(
      'Payments',
      'The FieldOS subscription is bought through Google Play or the Apple App Store, which handle your card or UPI '
          'details. FieldOS never sees them. RevenueCat (revenuecat.com) receives the purchase record from the store so '
          'that the app can check your subscription.',
    ),
    LegalSection(
      'Bug reports',
      'If you use "Report a bug", we receive what you type, the email address you give (optional), the app version, '
          "your phone's operating system version and the app's last few error messages. No project data, photos or "
          'contacts are included. Reports are stored in our cloud database and copied to our private issue tracker on '
          'GitHub so that we can fix the problem.\n\n'
          'Apart from what this policy describes, nothing about how you use FieldOS leaves your phone. We do not sell '
          'data or show ads.',
    ),
    LegalSection(
      'Deleting data',
      'In the app, open Team & sync and tap "Delete my cloud account". A company where you are the only member is '
          'deleted with all its records. In a company with other members, the records you added stay with that '
          'company, your name is removed from its team chat, and ownership passes to another member. You can also ask '
          'for deletion by emailing info@mldynamic.com. Uninstalling the app removes the data on the phone.',
    ),
    LegalSection(
      'Contact',
      'info@mldynamic.com, ML Dynamic Solutions Private Limited, 606, 6th Floor, Gowra Fountainhead, Patrika Nagar, '
          'Madhapur, Hi-Tech City, Hyderabad, Telangana 500081, India.',
    ),
  ],
);

const termsOfUse = LegalDocument(
  title: 'Terms of use',
  updated: '6 November 2026',
  intro: 'These terms are between you and ML Dynamic Solutions Private Limited ("we"), who make FieldOS. By creating '
      'an account or using the app you agree to them.',
  sections: [
    LegalSection(
      'Your account',
      'Your FieldOS account and its records are kept on your phone. Keep your password safe: we cannot see it or '
          'reset it, and records that are only on the phone cannot be recovered without it. Turning on Team & sync '
          'keeps a copy in the cloud for your company.',
    ),
    LegalSection(
      'Subscription and free trial',
      'FieldOS needs a FieldOS Pro subscription, bought through Google Play or the App Store, billed monthly. New '
          'subscribers get a 3-day free trial; the first payment is taken when the trial ends unless you cancel before '
          'then. The subscription renews every month at the price shown in the store until you cancel. Cancel at least '
          '24 hours before the end of the current period to avoid the next charge, in your Google Play or App Store '
          'subscriptions. Payments and refunds are handled by the store under its policies.',
    ),
    LegalSection(
      'Your data',
      'You own the records you create. We use the copy in our cloud only to run FieldOS for you and your company, as '
          'described in the privacy policy.',
    ),
    LegalSection(
      'Check the numbers',
      'FieldOS helps with estimates, quantities, wages, payments and reports, and it reads spoken reports '
          'automatically. Check figures and reports before relying on them for construction, payment or legal '
          'decisions; you are responsible for those decisions.',
    ),
    LegalSection(
      'Fair use',
      'Do not use FieldOS to break the law, to store content you have no right to, to get into other companies\' '
          'data, or to interfere with the service. We may suspend accounts that do.',
    ),
    LegalSection(
      'Availability and liability',
      'The offline features work on your phone. Cloud features may sometimes be unavailable. As far as the law allows, '
          'FieldOS is provided as it is, and our total liability to you is limited to what you paid for FieldOS in the '
          '12 months before the claim.',
    ),
    LegalSection(
      'Changes and law',
      'We may update these terms; the date above shows the latest version. Indian law applies, and the courts at '
          'Hyderabad, Telangana have jurisdiction.',
    ),
    LegalSection('Contact', 'info@mldynamic.com'),
  ],
);
