# Play Store launch pack — FieldOS (Android)

Everything needed to publish `fieldos_mobile/` on Google Play. Items marked
**(you)** need the owner's own accounts and cannot be done by an agent
(see `docs/AGENT_HANDOFF.md`, "Never create third-party accounts").

## 1. Before the first upload

| # | Step | Who |
|---|---|---|
| 1 | Create the production Supabase project (free plan is fine), then add repo secrets `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_ACCESS_TOKEN` and `SUPABASE_DB_PASSWORD`, and run the **supabase-deploy** workflow from the Actions tab; it applies every migration. In **Authentication → Sign In / Providers → Email**, turn "Confirm email" off for launch: Supabase's built-in mailer sends only a few emails an hour, and company data is already gated by the join code. Turn it back on once custom SMTP is set up. | **(you)** |
| 1b | **Setting secrets:** on a personal GitHub repo only the repository owner's account can add or see Actions secrets; a collaborator with write access gets a 403, so these steps cannot be delegated. `tools/set_launch_secrets.sh` sets all of them from one local file (`launch-secrets.env`, gitignored; copy `launch-secrets.env.example`). Then anyone can run the **launch-readiness** workflow from the Actions tab: it shows which secrets are set, whether each is the right kind of key (anon and not service_role, RevenueCat public and not secret, keystore opens with the alias and passwords), and what the Supabase project has deployed. It never prints a value. | **(you)** set, anyone checks |
| 2 | The release workflow bakes `SUPABASE_URL` and `SUPABASE_ANON_KEY` into the build; without them the app ships offline-only and hides Team & sync. | automatic |
| 3 | Create the upload keystore on your own computer (Android Studio → Build → Generate Signed App Bundle → Create new, or `keytool`), and add the four signing secrets (`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`, `ANDROID_STORE_PASSWORD`). Keep the keystore and passwords offline. With Play App Signing (the default for new apps) this is only the upload key, and Play support can reset it if lost. | **(you)** |
| 4 | The application id is `com.mldynamic.fieldos` (chosen by the owner, `android/app/build.gradle.kts`). It can never change after the first upload. The Kotlin `namespace` stays `com.predictera.fieldos_mobile`; that is internal and never shown. | done |
| 5 | Publish the privacy policy (section 4) at a public URL, e.g. a published Google Doc or the company website. Play requires the URL. | **(you)** |
| 6 | Play Console developer account for ML Dynamic Solutions Private Limited. | done |
| 7 | Tag a release: `git tag v1.1.0 && git push origin v1.1.0`. The workflow builds the signed `.aab` and drafts a GitHub Release with it. | either |
| 8 | Upload the `.aab` to an **internal testing** track first, install on 2+ real phones, run the smoke test in section 6, then promote to closed testing and production. New personal accounts must run a closed test with 12+ testers for 14 days before production; organisation accounts are exempt. | **(you)** |

## 2. Store listing

**App name** (30 chars max): `FieldOS: Site Diary & DPR`

**Short description** (80 chars max):
`Offline site diary for builders: voice DPR in Telugu & Hindi, BOQ, team chat.`

**Full description** (4,000 chars max):

```
FieldOS is the site management app for Indian contractors and builders. It
works fully offline on site and syncs with your team when there is signal.

SPEAK YOUR DAILY PROGRESS REPORT
Hold the mic and describe the day's work in Telugu, Hindi, English or other
Indian languages. FieldOS writes the DPR, counts manpower, and flags issues
for you to confirm. Attach site photos straight from the camera.

SHARE REPORTS ON WHATSAPP
Turn any DPR into a clean PDF with photos and issues, and send it to your
client or office group in one tap.

WORKS WITHOUT SIGNAL
Everything is saved on the phone first. Basements, highways, rural sites:
your team keeps working, and FieldOS syncs when the network comes back.

YOUR WHOLE TEAM, IN SYNC
Each person signs in with their own email. The owner shares a join code;
site engineers join in seconds and see the company's projects. Every
project has its own team chat, and you get alerts for new issues, approval
requests and messages.

BOQ AND ESTIMATION THAT MATCH YOUR EXCEL
Cost heads, measurement and steel entries, with the same maths your
estimators use. Track actuals against the BOQ.

GPS ATTENDANCE
Punch workers in and out with the phone's GPS, checked against each site's
geofence. See every site on the map.

EVERYTHING ELSE A SITE NEEDS
Tasks, issues, procurement (requisitions, purchase orders, goods receipts),
vendors, equipment and machinery logs, inspections and quality checklists,
subcontractors and work orders, multi-level approvals, documents.

Built in India for Indian construction: rupees, Indian languages, and
phones that spend half the day without a network.
```

**Category:** Business. **Tags:** Construction, Project management, Productivity.

**Graphics:** the 512×512 icon and the 1024×500 feature graphic are in
`docs/store/` (drawn by `tools/make_icons.py`, which also writes the
Android and iOS launcher icons). Still needed: 4–8 phone screenshots
(suggested: voice DPR, DPR PDF, project tabs, team chat, site map, BOQ).

## 3. Permissions and why (for review notes)

| Permission | Used for | When asked |
|---|---|---|
| `INTERNET` | Team sync (Supabase), voice-to-DPR (Sarvam), map tiles | Never (normal permission) |
| `RECORD_AUDIO` | Voice DPR | When the user taps Voice DPR |
| `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION` | GPS punch-in/out and setting a site location; foreground only, one reading per action | First punch-in or site placement |
| `POST_NOTIFICATIONS` | Alerts for colleagues' new issues, approval requests and messages | After the user links a company to the cloud |
| Camera / photos | Through the system camera and photo picker; no camera permission is declared | — |

No background location, no SMS/call log, no contacts.

## 4. Privacy policy (publish this text)

> **FieldOS privacy policy** — ML Dynamic Solutions Private Limited. Last updated: (date of publishing).
>
> FieldOS stores the projects, reports, photos, attendance and other site
> records you create on your phone. If you sign in to Team & sync, those
> records, your email address, and the name you entered are also stored on
> our cloud database (Supabase, region: (your Supabase region)) so the
> members of your company can see them. Only members of your company can
> read your company's data.
>
> **Location:** read only when you punch a worker in or out or set a site
> location, and saved with that record. Never tracked in the background.
>
> **Voice:** when you use voice DPR, the recording is sent to Sarvam AI
> (sarvam.ai) to be transcribed, and is not kept by FieldOS afterwards.
>
> **Maps:** map tiles are loaded from OpenStreetMap; your device's IP
> address is visible to their servers as for any web request.
>
> **Payments:** the FieldOS subscription is bought through Google Play or
> the Apple App Store, which handle your card or UPI details; FieldOS
> never sees them. RevenueCat (revenuecat.com) receives the purchase
> record from the store so the app can check your subscription.
>
> **Bug reports:** if you use "Report a bug", we receive what you type,
> the email you give (optional), the app version, your phone's operating
> system version and the app's last few error messages. No project data,
> photos or contacts are included. Reports are stored in our cloud
> database and copied to our private issue tracker on GitHub so we can
> fix the problem.
>
> We do not sell data, show ads, or use analytics or tracking SDKs.
>
> **Deleting data:** in the app, open Team & sync and tap "Delete my cloud
> account". Companies where you are the only member are deleted with all
> their records. In companies with other members, the records you added
> stay with that company, your name is removed from its team chat, and
> ownership passes to another member. You can also ask for deletion by
> emailing (support email). Data on the phone is removed by uninstalling
> the app.
>
> Contact: (support email), ML Dynamic Solutions Private Limited, (address).

## 5. Data safety form answers

| Question | Answer |
|---|---|
| Does the app collect or share user data? | Collects: yes. Shares: no (Supabase and Sarvam are service providers processing on our behalf). |
| Encrypted in transit? | Yes (HTTPS). |
| Can users request deletion? | Yes: in the app (Team & sync → Delete my cloud account) and by email (see policy). For "Delete account URL", use the published privacy policy page; its "Deleting data" section explains both routes. |
| Personal info → Email address, Name | Collected, required for Team & sync, purpose: App functionality, Account management. |
| Location → Precise location | Collected, optional, purpose: App functionality (attendance geofence). |
| Audio → Voice recordings | Collected, optional, processed ephemerally for transcription, purpose: App functionality. |
| Photos | Collected, optional, purpose: App functionality (site evidence). |
| Files and docs | Collected, optional, purpose: App functionality (project documents). |
| Messages → Other in-app messages | Collected (team chat), purpose: App functionality. |
| Financial info → Purchase history | Collected (subscription, via Google Play and RevenueCat), purpose: App functionality. |
| App info and performance → Crash logs, Diagnostics | Collected only when the user sends a bug report, optional, purpose: App functionality (fixing bugs). |
| Personal info → Email address | Also collected, optional, when a user adds it to a bug report so we can reply. |
| App activity, device IDs, contacts | Not collected. |

**Content rating:** questionnaire answers are all "No" (utility app, no
user-generated content shared publicly; team chat is private to the
company). Expected rating: Everyone / 3+.

**Target audience:** 18+. **Ads:** No. **Government app:** No.

## 6. Two-phone smoke test (before promoting past internal testing)

1. Phone A: create account, create company, Team & sync → sign in with email
   A → "Put company on the cloud". Note the join code.
2. Phone B: create account, "Join with a code" → sign in with email B →
   enter the code. Projects from A appear after the first sync.
3. On A, create a project and set its site location from the Site map.
   On B, open Labour → Punch in; the geofence check uses A's location.
4. On B, post in the project's Chat tab with flight mode on; turn flight
   mode off; the message reaches A.
5. On B, raise a high-severity issue. Within one sync on A (open the app
   or wait 5 minutes), A gets a notification.
6. Kill and reopen both apps: neither asks for the cloud password again.
7. On A, share a DPR as PDF to WhatsApp and check photos and issues show.

## 7. Subscription: 3-day free trial, then paid

There is no free plan. Every person who uses the app subscribes for
themselves (owner, engineers, supervisors), starting with a 3-day free
trial. Past the login screen the app shows a paywall until the store says
the person has an active subscription or trial.

- The trial is an offer on the store subscription, so Google and Apple
  decide who is eligible (once per Google/Apple account) and charge
  automatically when it ends. Reinstalling the app can't reset it.
- Offline: a phone that was paid up keeps working for 3 days past its
  last known paid-up date, then needs the internet once to check.
- Restore on the paywall finds a subscription already on the phone's
  Google Play or Apple account (new phone, reinstall).
- A build without the RevenueCat keys has no paywall at all. The release
  workflow passes them from repo secrets, so set them before a store build.

To turn it on (owner):

1. **Play Console** → Monetize → Subscriptions → create `fieldos_pro`.
   Add a monthly base plan (and yearly if wanted) and set the price.
   On the base plan, add an **offer** → *Free trial*, 3 days, eligibility
   "New customer acquisition". This needs a payments profile on the Play
   Console account.
2. **App Store Connect** (when publishing on iPhone): a subscription with
   the same id, with an introductory offer: Free, 3 days.
3. **RevenueCat** (free up to USD 2,500 a month in revenue): create a
   project, add the Android app (`com.mldynamic.fieldos`, with a Play
   service account JSON) and the iOS app.
   - Create the entitlement `pro` and attach the store products.
   - Make the default offering contain them.
4. Add the repo secrets `REVENUECAT_ANDROID_KEY` and `REVENUECAT_IOS_KEY`:
   the public SDK keys, from RevenueCat → API keys (`goog_…` and `appl_…`;
   the launch-readiness workflow rejects a secret `sk_…` key).
5. Build a new release. Test with a Play licence tester account, which is
   never charged (test trials last minutes, not days).

Known limit: the check runs in the app. The cloud does not yet refuse
someone who never paid but uses a modified copy of the app.

## 7b. Bug reports

"Report a bug" is in the home menu and on the paywall. A report goes to
the `bug_reports` table (anyone can add one; nobody can read them back
through the app). Offline, it waits on the phone and is sent later.

The **bug-reports** workflow runs every 15 minutes and turns each new
report into a GitHub issue labelled `bug-report`, then marks it filed. It
uses the existing `SUPABASE_URL` and `SUPABASE_ACCESS_TOKEN` secrets and
does nothing until they're set. GitHub can pause scheduled workflows in a
repo with no activity for 60 days; re-enable it from the Actions tab.

## 8. Known limits to state honestly in support replies

- Alerts arrive when the app syncs (on open, on return to the app, and
  every 5 minutes while open), not instantly while the app is closed. True
  push would need Firebase Cloud Messaging plus a server.
- Two people editing the same record while both offline: the last one to
  sync wins. An unsynced edit on a phone is never overwritten by a pull.
- PDF reports print Latin script only; a DPR written in an Indic script is
  carried in full in the share message instead.
- The iPhone build compiles in CI (`ios-build`), but publishing it needs an
  Apple Developer account (USD 99/year) and signing set up on a Mac or in
  CI; it has not been run on a real iPhone yet.
- Deleting an account leaves the document files of deleted companies in
  Storage until they are cleared from the Supabase dashboard.
- The desktop (Windows) app does not sync with the phones.

## 9. If something goes wrong

Start with the **launch-readiness** workflow (Actions tab → Run workflow);
its summary table says what is missing or wrong without showing any value.

| Symptom | Cause | Fix |
|---|---|---|
| `supabase-deploy` fails at "Check the secrets are set" | The secrets are not on the repo. Collaborators cannot add them. | The owner runs `tools/set_launch_secrets.sh`, or adds them in Settings → Secrets and variables → Actions. |
| `gh secret set` says 403 / "Resource not accessible" | Signed in to `gh` as a collaborator, not the owner. | `gh auth login` as the repository owner and run the script again. |
| `supabase link` fails with "Unauthorized" or "Access token not provided" | `SUPABASE_ACCESS_TOKEN` is wrong, expired, or from a Supabase account that cannot see this project. | Make a new token at supabase.com/dashboard/account/tokens while signed in as the project's owner; update the secret. |
| `supabase link` / `db push` fails with "password authentication failed" | `SUPABASE_DB_PASSWORD` is not the project's database password. | Supabase → Project Settings → Database → Reset database password, then update the secret. |
| `db push` says a table or policy "already exists" | Migrations were pasted into the SQL editor by hand before the workflow ran, so the project has the objects but no record of the migration. | In a checkout with the CLI: `supabase link`, then `supabase migration repair --status applied <version>` for each hand-applied file (the version is the leading timestamp), then run the workflow again. |
| launch-readiness shows ❌ on `SUPABASE_ANON_KEY` ("service_role") | The service key was pasted instead of the anon / publishable key. | Copy the **anon** (or `sb_publishable_…`) key from Project Settings → API. The service key in an APK lets anyone read every company's data. |
| launch-readiness shows "Migration … not deployed" | supabase-deploy has not run (or failed) since that migration was added. The check covers every table in `supabase/migrations/`, so a newly merged migration shows up here until it is deployed. | Run supabase-deploy; it skips what is already applied. |
| Sign-up works but the confirmation email never arrives | Built-in Supabase mailer: a few emails an hour, shared by every project. | Turn "Confirm email" off for launch (section 1, step 1); launch-readiness shows "Confirm email: required" while it is on. Or set up custom SMTP under Authentication → Emails. |
| `bug-reports` fails at "File new reports as issues" | `SUPABASE_ACCESS_TOKEN` cannot read this project's API keys (wrong account), or `SUPABASE_URL` is for another project. | Same token fix as above. "no new bug reports" in the log is success. |
| Release build hides Team & sync | It was built before `SUPABASE_URL` / `SUPABASE_ANON_KEY` were set. | Set them, then run the **release** workflow again (or push a new tag). |
| Release build has no paywall | Built before the RevenueCat secrets were set, or `REVENUECAT_ANDROID_KEY` is empty. | Set the key (section 7, step 4), rebuild, re-upload to internal testing. |
| Paywall says "Could not reach the store" or shows no prices | The build on the phone was not installed from Google Play (internal testing), the Google account is not a licence tester, or the products are not in RevenueCat's **default** offering. | Install from the internal-testing link, add the tester under Play Console → Setup → Licence testing, and check RevenueCat → Offerings. |
| Trial unlocks, but the app locks again straight after | The `pro` entitlement is not attached to the product that was bought. | RevenueCat → Entitlements → `pro` → attach every store product. |
| `launch-readiness` is red | Only ever because a secret that *is* set is the wrong kind of value (❌ rows). Missing secrets never fail it. | Fix the ❌ rows; the Note column says what was expected. |
