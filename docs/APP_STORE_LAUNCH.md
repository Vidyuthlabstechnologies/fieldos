# FieldOS on the Apple App Store (iPhone)

The iPhone app is the same Flutter app as Android (`fieldos_mobile/`), with
bundle id **com.mldynamic.fieldos**. This page is the developer reference:
what is in the code, how a build is made without GitHub Actions, and the
order of the owner's steps in Apple's websites.

## What the code already does for the App Store

| Apple rule | Where |
|---|---|
| Sign in with Apple next to Continue with Google (Guideline 4.8) | `lib/auth/apple_auth.dart`, the black Apple button on the login screen (iPhone only). Supabase checks Apple's ID token; the local account is keyed by the email Apple gives (it may be a private relay address). |
| Google sign-in on iPhone | Needs `GOOGLE_IOS_CLIENT_ID` at build time and its reversed form as a URL scheme (`ios/Flutter/Google.xcconfig`, written by `tool/ios/build_ipa.sh`). Without it the Google button is hidden on iPhone. |
| Subscriptions through Apple only, no unlock codes (3.1.1) | RevenueCat with `REVENUECAT_IOS_KEY`; the "Enter access code" menu is Android only. |
| Restore, price, length, trial and cancel wording, Terms and Privacy links on the paywall (3.1.2) | `lib/features/subscription/paywall_screen.dart` |
| In-app account deletion (5.1.1(v)) | Team & sync > Delete account |
| Privacy manifest | `ios/Runner/PrivacyInfo.xcprivacy` (no tracking; data types match "App Privacy" below) |
| Permission texts | `ios/Runner/Info.plist`: camera, photos, location while in use, microphone, speech recognition |
| Export compliance | `ITSAppUsesNonExemptEncryption = false` in Info.plist (only the HTTPS built into iOS) |
| iPhone only | `TARGETED_DEVICE_FAMILY = 1`, so no iPad screenshots or iPad review |
| Entitlements | `ios/Runner/Runner.entitlements`: Sign in with Apple |

## Building without GitHub Actions

GitHub Actions is switched off for this repo's builds (cost). The iPhone
build needs a Mac, so there are two ways, both using
`fieldos_mobile/tool/ios/build_ipa.sh`:

1. **Codemagic** (`codemagic.yaml` at the repo root). Free plan: 500 Mac
   minutes a month, about 15-20 per build. Builds start only when someone
   presses "Start new build". It signs with an App Store Connect API key,
   bumps the build number past the last TestFlight build, and uploads to
   TestFlight.
2. **Your own Mac** with Xcode: set the environment variables below, run
   `fieldos_mobile/tool/ios/build_ipa.sh`, then open
   `fieldos_mobile/build/ios/archive/Runner.xcarchive` in Xcode
   (Organizer > Distribute App > App Store Connect). Signing: Xcode >
   Runner target > Signing & Capabilities > Team = ML Dynamic Solutions,
   "Automatically manage signing".

Build variables (same values as the Android release):

| Variable | Required | Value |
|---|---|---|
| `SUPABASE_URL`, `SUPABASE_ANON_KEY` | yes | production Supabase |
| `REVENUECAT_IOS_KEY` | yes | RevenueCat > Project > API keys > the App Store app's public key (`appl_...`). The script refuses to build without it, because such a build has no paywall. |
| `GOOGLE_WEB_CLIENT_ID` | for Google | the existing Web OAuth client |
| `GOOGLE_IOS_CLIENT_ID` | for Google on iPhone | Google Cloud > Credentials > Create OAuth client > iOS, bundle id com.mldynamic.fieldos |
| `APP_STORE_APPLE_ID` | Codemagic only | App Store Connect > App Information > Apple ID (a number) |

## Server side (once)

- **Supabase** (Authentication > Sign In / Providers):
  - Apple: enable, Client IDs = `com.mldynamic.fieldos`. No secret key is
    needed for the native iPhone sign-in.
  - Google: add the iOS client id to "Client IDs" after the web client id,
    comma separated, so Google tokens from iPhone are accepted.
- **RevenueCat**: add an App Store app (bundle id com.mldynamic.fieldos),
  upload the In-App Purchase key (.p8) from App Store Connect, import the two
  subscriptions, attach both to the `fieldos_pro` entitlement and to the
  current offering's monthly and annual packages (the same packages Android
  uses).

## App Store Connect: what to enter

- Subscription group "FieldOS Pro" with two auto-renewable subscriptions:
  `fieldos_pro_monthly` (1 month, ₹999) and `fieldos_pro_yearly` (1 year,
  ₹10,999 or the nearest Apple price point), each with a 3-day free trial
  introductory offer for new subscribers. The first subscriptions must be
  submitted together with the first app version.
- Category Business (secondary Productivity). Age rating 4+. Price Free
  (with in-app purchases).
- Privacy policy https://fieldos-mldynamic.netlify.app/privacy-policy.html;
  Terms of Use https://fieldos-mldynamic.netlify.app/terms-of-use.html (also
  as a line at the end of the description: Apple asks for a working Terms
  link for subscriptions).
- App Privacy (matches `PrivacyInfo.xcprivacy`): no tracking. Collected and
  linked to the person, for App Functionality: Name, Email Address, Phone
  Number, Precise Location, Photos or Videos, Other User Content, Customer
  Support, Purchase History, User ID. Collected, not linked: Audio Data,
  Crash Data.
- Screenshots: 6.9-inch display slot, 1290x2796 PNGs (8 per language).
- App Review notes: how to make an account (any username on the phone),
  that buying in the sandbox unlocks everything, and that Sign in with Apple
  and Team & sync need internet. Apple's reviewers test the subscription
  with their own sandbox account; there is no access code on iPhone.
