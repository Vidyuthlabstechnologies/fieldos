# Play Store launch pack — FieldOS (Android)

Everything needed to publish `fieldos_mobile/` on Google Play. Items marked
**(you)** need the owner's own accounts and cannot be done by an agent
(see `docs/AGENT_HANDOFF.md`, "Never create third-party accounts").

## 1. Before the first upload

| # | Step | Who |
|---|---|---|
| 1 | Create the production Supabase project and run `supabase db push` (`docs/SUPABASE_PRODUCTION_RUNBOOK.md`). In **Authentication → Providers → Email**, keep "Confirm email" on; the app handles the confirmation step. | **(you)** |
| 2 | Add repo secrets `SUPABASE_URL` and `SUPABASE_ANON_KEY` (Settings → Secrets and variables → Actions). The release workflow bakes them into the build; without them the app ships offline-only and hides Team & sync. | **(you)** |
| 3 | Add the four signing secrets (`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`, `ANDROID_STORE_PASSWORD`). Back up the keystore and passwords offline: losing them after the first upload means a new app listing. | **(you)** |
| 4 | Decide the application id **before** the first upload; it can never change afterwards. Today it is `com.predictera.fieldos_mobile` (`android/app/build.gradle.kts`). `com.predictera.fieldos` reads cleaner on the store page. | **(you)** decide |
| 5 | Publish the privacy policy (section 4) at a public URL, e.g. GitHub Pages or the Predictera website. Play requires the URL. | **(you)** |
| 6 | Create the Play Console developer account (one-time USD 25, organisation account for Predictera Pvt Ltd; needs a D-U-N-S number). | **(you)** |
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

**Graphics to prepare:** 512×512 icon (the current launcher icon is the
Flutter default and must be replaced), 1024×500 feature graphic, and 4–8
phone screenshots (suggested: voice DPR, DPR PDF, project tabs, team chat,
site map, BOQ).

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

> **FieldOS privacy policy** — Predictera Pvt Ltd. Last updated: (date of publishing).
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
> We do not sell data, show ads, or use analytics or tracking SDKs.
>
> **Deleting data:** a company owner can ask for the company's cloud data to
> be deleted, and any user can ask for their account to be deleted, by
> emailing (support email). Data on the phone is removed by uninstalling the
> app.
>
> Contact: (support email), Predictera Pvt Ltd, (address).

## 5. Data safety form answers

| Question | Answer |
|---|---|
| Does the app collect or share user data? | Collects: yes. Shares: no (Supabase and Sarvam are service providers processing on our behalf). |
| Encrypted in transit? | Yes (HTTPS). |
| Can users request deletion? | Yes, by email (see policy). |
| Personal info → Email address, Name | Collected, required for Team & sync, purpose: App functionality, Account management. |
| Location → Precise location | Collected, optional, purpose: App functionality (attendance geofence). |
| Audio → Voice recordings | Collected, optional, processed ephemerally for transcription, purpose: App functionality. |
| Photos | Collected, optional, purpose: App functionality (site evidence). |
| Files and docs | Collected, optional, purpose: App functionality (project documents). |
| Messages → Other in-app messages | Collected (team chat), purpose: App functionality. |
| App activity, device IDs, financial info, contacts | Not collected. |

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

## 7. Known limits to state honestly in support replies

- Alerts arrive when the app syncs (on open, on return to the app, and
  every 5 minutes while open), not instantly while the app is closed. True
  push would need Firebase Cloud Messaging plus a server.
- Two people editing the same record while both offline: the last one to
  sync wins. An unsynced edit on a phone is never overwritten by a pull.
- PDF reports print Latin script only; a DPR written in an Indic script is
  carried in full in the share message instead.
- Android only. The desktop (Windows) app does not sync with the phones.
