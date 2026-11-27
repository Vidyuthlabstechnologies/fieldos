# Customer review of FieldOS 1.8.1 (26 Nov 2026)

Thirteen simulated customers and reviewers read the real code, screens, strings, SQL and docs and reported what would stop them using or paying for the app. Nobody ran the app on a phone, and nothing touched production.

How to read the tags:

- **[V]** verified by reading the code or SQL after the reviewer reported it.
- **[C]** a reviewer's claim, not yet checked. Treat as likely, verify before fixing.
- **[fixed]** fixed in a PR (linked).
- **[owner]** needs the owner or a login, not a code change.
- **[server]** needs a Supabase migration. Test it on a local stack and deploy it with the runbook in `docs/HANDOVER.md`. Never write one untested.

Reviewers: small-builder owner (Hyderabad), junior site engineer (Warangal, Telugu, 2 GB phone), accountant (Chennai), labour sub-contractor (Pune, Hindi), steel dealer (Nagpur), homeowner client (Bengaluru), storekeeper and night guard (Tamil, Kannada), quality and safety engineer (Pune), CFO and IT procurement (Mumbai), first-time trial user (Nashik), Indian-language reviewer, low-end performance engineer, fraud and security red team.

---

## Status of the findings (27-28 Nov 2026)

**Merged to `master`: everything below. Live on production: all the server work** (73 migrations, isolation-check passed after the RLS rewrite, the AI-assistant function). The final `master` passes the whole reference run (analyzer, every test against a fresh Supabase stack, the Android build). The release bundle 1.8.2+27 is built, signed and checked; **uploading it to Play is the owner's step** (no Play service account is set).

| Finding | Status | PR |
|---|---|---|
| #1 No backups | Daily encrypted copy running (first one taken and restored against production's own data); **the Pro plan upgrade is yours** | #251 |
| #2 Any member edits POs and requests | Fixed, live | #252 |
| #3 Approval rules dodged by back-dating | Fixed, live | #256 |
| #5 No history for wages, attendance marks, POs | Fixed, live | #253 |
| #9 AI consent not enforced | Withdrawal stops processing, live | #257 |
| #11 Attendance trust (time) | Late check-ins wait for a manager, live | #259 |
| #13 Cube acceptance not IS 456 | Fixed: three cubes per sample, groups of four (`docs/CUBE_ACCEPTANCE.md`) | #248, #266 |
| #6 Wage rates readable by every site member | **Closed, live** (27 Nov): only owners, project managers and accounts read rates, through `worker_wage_rates()`; production had no users on older builds, so the minimum build was raised to 26 first | #272 |
| #7 Login session as plain text in the phone's database | Moved to Android Keystore / iOS Keychain with a fallback so nobody is logged out (**check on a real phone**) | #269 |
| #24 Client sees one net figure per bill, 84 px photos | A bill opens to gross, GST, retention, TDS, net; photos open full screen. Still open: change-order approval by the client, payment milestones, contract value, alerts | #270 |
| #24, #25, #26 Portal codes permanent | The builder can change a code and remove everyone who joined (client, supplier, sub-contractor) | #273 |
| #27 Nothing flags workers paid with no photo | A day counted for wages with no roll-call photo goes to the exceptions inbox (only for sites that use the photos). Still open: owner approval for new workers, join-code expiry or approval | #276 |
| #34 Crashes before the app is up are lost | Kept in a file and sent on the next start. A native crash or ANR still needs a native reporter | #271 |
| #38 Kannada, Tamil, Telugu date patterns | Day, month, year, no stray comma | #274 |
| #38 Form refusal messages in English | 23 translated in 13 languages; a test now fails if one is missing | #275 |
| #14 Hold points do not hold | Fixed on the server (live) and the phone; the quality officer can release | #265 |
| #26 Supplier sees unapproved POs | Fixed, live | #258 |
| #28 A stalled photo blocks all sync | Fixed | #254 |
| #29 Sync failure invisible; no backoff | Home banner; backoff and no overlapping syncs | #261, #267 |
| #30 Whole outbox loaded on every pull | Fixed | #260 |
| #33 Spoken report lost on a stray tap | Asks first (**native review of 2 strings**) | #262 |
| #36 Consent wording ("from behind") | Fixed in Hindi, Telugu, Marathi | #250 |
| **New:** RLS cost grew with the whole table (7.3 s at 9,800 tasks) | Fixed: 58 ms, live | #255 |

**Not built, and why**

- #4 (encrypt the phone database): needs a native plugin and a migration for installed phones. (#7, the login session, is done in #269.)
- #7 other money data readable by all members: needs a decision on who sees supplier invoices and PO totals.
- #15 pour cards and statutory safety registers; #16 storekeeper tools screen; #17 accounting depth (Sales, Purchase and Journal vouchers, TDS payable, HSN per line, reverse charge, other states' professional tax); #24, #25 and the client, sub-contractor and supplier portals; #27 owner fraud reports: each is a feature of its own, with its own design and translations.
- #18-#20 paywall order, the 3-day trial, read-only after expiry: product decisions with revenue effect (the trial length is set in the Play and App Store consoles). #22 phone-number sign-in needs an SMS provider account.
- #31, #32 storage clean-up and PDF/XLSX off the main thread, #34, #35: need a real device to measure.
- #37-#39 further translation fixes: need native speakers.
- Money as floating point (25 columns): an integer-paise migration of every calculation.
- Leaked-password protection, custom SMTP, point-in-time recovery: **need the Pro plan.**

## Verified on production, read-only (26 Nov 2026)

Checked with the Supabase CLI against `fieldos-production` (Mumbai, `ap-south-1`) using read-only transactions only. Nothing was changed.

| Check | Result |
|---|---|
| Backups | **None.** `backups: []`, `pitr_enabled: false`. There is nothing to restore from. |
| Scale | 3 companies, 2 projects, 3 members, 17 auth users, 21 MB database, 46 files (586 kB). Pre-launch, so the fix window is open. |
| RLS | On for all 117 public tables. 10 have no policy (deny-all to app users, by design: config, code and counter tables). |
| Anonymous role | No table privileges. |
| Storage | Both buckets (`documents`, `system-logs`) are private. |
| Deleting a site | No DELETE policy on `projects`: no app user can delete one. |
| Migrations | 63 applied, latest `20261125150000`. Matches the repo. |
| PO and requisition updates | UPDATE policies are `has_project_access` with no `WITH CHECK`; no update-guard trigger exists (only `purchase_orders_need_chain`, insert-only). **Finding #2 confirmed live.** |
| Wage column | `authenticated` can still `select workers.daily_wage`. **Finding #6 confirmed live.** `app_config` min builds are 0. |
| Security advisor | No ERROR findings. Warnings: leaked-password protection off (a Pro feature), 25 trigger functions without a fixed search_path, the app's own SECURITY DEFINER RPCs callable by signed-in users (by design), 3 duplicate permissive policies, 1 RLS initplan on `bug_reports`. |
| Sign-in mix | 9 email, 8 Google. |

## P0: customer data and money

1. **Production has no backups and no point-in-time recovery.** [V live][owner] Issue #148; confirmed with `supabase backups list` on 26 Nov (`backups: []`, `pitr_enabled: false`). The terms and privacy policy promise a 30-day backup window that depends on this. Until it is confirmed, one bad migration or accidental delete is unrecoverable. After upgrading, run and document one restore into a branch project. Also consider a nightly off-site `pg_dump` plus a copy of the storage bucket (the repo is public, so never as a workflow artifact).
2. **Any site member can edit or raise a purchase order through the API.** [V][server] `purchase_orders` and `purchase_requisitions` update policies are `has_project_access(project_id)` with no `with check` and no guard trigger (`20260823100000_procurement_sync_alignment.sql:17,22`, `20260823110000_purchase_order_insert_membership.sql:8`). The approval-chain trigger runs on insert only, and only when `requisition_id` is set (`20261110900000_approval_rules.sql:181`). An engineer or storekeeper (or a supplier colluding with one) can change `total_amount`, `vendor_id` or `status`, or raise a PO with no chain. Fix: guard trigger like `site_supplier_invoices_only_void`: immutable once approved or issued except for server-checked status steps, `created_by = auth.uid()`, a chain for every PO.
3. **Approval rules can be skipped by back-dating `created_at`.** [C][server] `approval_chain_complete` applies a rule only if it existed at the row's client-supplied `created_at` (`20261110900000_approval_rules.sql:135`), and `site_expenses` has no server `created_at` stamp. Stamp it server-side.
4. **Approval is a review step, not a gate; no self-approval ban; limits apply per item so splitting beats them.** [C][server] A PM can approve what they recorded. Add `recorded_by <> decided_by` and a per-payee-per-day total.
5. **Expenses can be edited after approval or weekly close, and the change history omits the riskiest tables.** [C][server] `entry_history` covers 8 tables but not `workers` (wage-rate edits), `site_attendance_marks`, `staff_attendance`, `purchase_orders`, `stock_moves`. Lock rows after approval or close and extend the history triggers.
6. **Wage rates were readable by every site member on the API.** [V][owner] **Closed 27 Nov 2026** (`20261128120000_revoke_workers_wage_read.sql`): `min_build` raised to 26 first, production had no users on older builds. Rates are read only through `worker_wage_rates()`. Tests: `supabase/tests/wage_read_closed_test.sql`, `tests/test_workers_column_grants.py`. Other money data (supplier invoices, PO totals, measurement rates, cost-code budgets, bill photos in storage) is also readable by all members, and the finance-privacy rule covers `site_expenses` only. [C]
7. **Money is stored as floating point.** [V] 25 money columns are `RealColumn` (`lib/data/tables.dart:310,341,358,417,776,859,…`), summed as `double` (`billing_calc.dart:94`, `money_book.dart:28`, `billing_reconcile.dart:17`, `wage_sheet.dart:197-203`). `AGENTS.md` forbids float money only for Python. A 1e-6 nudge hides drift. Plan: integer paise (or `decimal`) in storage and sums, round each wage line half-up, document the rule. Needs a schema bump and the `shipped_schema_upgrade_test` pattern.
8. **Phone data is unencrypted and the login session is plain text in the same database.** [V] No SQLCipher; the Supabase refresh token is a row in `settings` (`SettingsSessionStore`, `cloud_sync_providers.dart:114`). `allowBackup=false` helps; Keystore/Keychain storage (`flutter_secure_storage`, migrate-then-wipe) is stronger. There is also no remote sign-out or wipe for a lost phone. [C]
9. **AI consent is recorded on the server but not enforced there.** [V][server] `consent_records` exists, but nothing in `supabase/functions/ai-assistant` reads it. No company-wide switch to turn AI off. Wage figures can reach the AI provider if the local copy holds them.
10. **Bus factor.** [owner] Supabase org has one human member who is not the company owner (#239); one person is incident lead, CERT-In contact and grievance officer; the Play account is personal; no CI runs on push. Add a second Owner, escrow the keystore and secrets, name a backup engineer.
11. **Attendance trust is client-side.** [C][server] Server recomputes distance from client-supplied coordinates, so mock-GPS passes (`Position.isMocked` never read). `check_in`/`day` can be any past value (changed phone clock). Labour punches (`site_attendance`) are not geofenced. Any site member can overwrite anyone's mark in `site_attendance_marks`. Inside-fence selfies are deleted at once, so buddy punching leaves no evidence. Fix: server time window, recompute distance for labour punches, mock-location rejection, keep a hash or a sample of selfies.
12. **Server does not match GRN, PO and invoice.** [C][server] Three-way match is phone-only and circular: invoice-vs-received compares two numbers an engineer typed, GRN amount defaults to the PO balance and quantity to 1, GST on the invoice is never checked (`billing_reconcile.dart:196-249`, `procurement_screen.dart:611-685`). Server unique index per non-cancelled PO per requisition is missing, so two offline awards can create two POs.

## P0: wrong or missing core promises

13. **Cube acceptance is not IS 456.** [V] Each single cube is compared to 65% / 90% / 100% of the grade (`site_ops_rules.dart:23,52-56,66-74`; same rule in `20261125110000_site_ops.sql:119-129`).
    - **[fixed] #248**: a missed 7- or 14-day cube now reads "Below early target" (amber), not "Failed". A missed 28-day cube is still Failed.
    - **[fixed] 28 Nov, #266**: 28-day acceptance now follows IS 456:2000 clauses 15.4 and 16.1 and Tables 8 and 11, read from the standard's own scan: a sample is three cubes (invalid if one is over 15% from the average), each sample must reach fck - 4 (fck - 3 for M15), and each group of four consecutive samples must reach fck + max(0.825 x s.d., 4) (3 for M15). See `docs/CUBE_ACCEPTANCE.md`. **The reviewer's figures were wrong** (an individual limit of fck - 3 for M20+, and fck + 4/5 for fewer than four samples); the standard says fck - 4, and has no separate rule for fewer than four.
    - Still open: the real crushing date and lab certificate number, a photo on the cube record, grades above M40, and pour cards.
14. **Hold points do not hold.** [C] A hold point only adds a "Waiting on N" label in the lookahead (`execution_rules.dart:85-90`); nothing stops a task going to 100% (phone or trigger). Only owner/PM can release one, so a quality officer cannot.
15. **No pour card or statutory safety records.** [C] No slump, volume, truck/challan, mix design, curing log, cover/bar checks; no toolbox talks, PPE register, incident/near-miss, NCR, BOCW registers or permits. Safety breach log has no photo, injured person, root cause or owner. No audit PDF for quality or safety; quality/safety events are missing from the audit trail; test dates can be back-dated 60 days; gallery photos are not stamped.
16. **A storekeeper cannot reach tool issue and return.** [V, narrower than first reported] "Stores and tools" is gated by `Roles.canApprove` (owner or manager) at `home_screen.dart:219`, so the `storekeeper` site role is only a label there. The company-wide screen is not safe to open as is: its *Add store*, *Add tool* and *Receive stock* actions are owner/PM only on the server (`20261110410000_stores_tools_payroll.sql:384-418`), so a storekeeper's writes would save on the phone, fail on sync and end up parked. A storekeeper's receipts and usage already live in each site's Procure tab. The server does allow a site team to issue and return tools and transfer stock out of its own site (`:397,426,430`). Fix: a site-scoped tools and stock-out view for the storekeeper role, with the manager-only buttons hidden, not an unlock of the company screen.
17. **Not a books system: Tally export covers only expenses and client receipts.** [C] No Sales, Purchase or Journal vouchers, no output/input GST ledgers, no vendor party ledgers (`accounts_export.dart:142-198`). No TDS on the payable side (194C/194Q, vendor PAN), no per-line HSN/SAC or GST rate, no India reverse charge, no supplier GSTIN or ITC register. Voucher numbers are per site, not per company and financial year. Professional tax exists only for Telangana and Andhra (`payroll_rules.dart:43-67`). No payroll overtime/Form 16/ECR, no Tally payroll export, no CA/auditor read-only role, no period lock for money.

## P1: why people would not convert

18. **Paywall before any value.** [C] Language, sign-in, company name, then the paywall (`app.dart:106-107`); the empty app, tour and sample site are behind it. Show a sample report before the paywall; consider a preview mode.
19. **3-day trial is too short for the buying cycle** (wages need a payday, cash needs a count). [C] Consider 14 days, or a trial that starts at the first wage run. Per-person store billing multiplies for a 5-person firm and the company plan is not explained in the app.
20. **Expiry locks everything, no read-only for individuals.** [C] `Access.blocked` goes back to the paywall; read-only exists only for company plans (`subscription_access.dart:73-75`). Account deletion is not reachable from the paywall menu.
21. **Play listing and store state.** [C] The listing says "each person signs in with their own email" (actual: Google or a phone-local username), omits Marathi and the trial, phone screenshots are still "needed", and the app is in closed testing so strangers cannot find it.
22. **Phone-local accounts have no password reset, and the team needs a second sign-in.** [C] Sign-up makes a username that lives on the phone; forgot-password says "no reset email" (`login_screen.dart:179`); the invite assumes Google (`invite_team.dart:22`). Make cloud sign-in the default for owners; add phone-number OTP for engineers, sub-contractors, suppliers and clients (all four portals need email plus a 6-character password today).
23. **Too much app for week one.** [C] 12 site tabs, about 25 menu items per site, about 22 on Home. Add a role-based home: owner essentials (cash, wages due, stock and theft flags, bills due); site engineer "my day"; guard and storekeeper tiles. Hide rates from storekeepers. Hide the rest behind "More".
24. **Client portal is a showcase, not a trust tool.** [C] No variation/change-order approval by the client, "milestones" are task-title splits and not payment milestones, no contract value or budget, bills show only a net amount (no lines, retention, GST, PDF), photos are 84 px thumbnails with no zoom, GPS, or download, no push/email/WhatsApp alerts, no web view for family, access code cannot be revoked or rotated, no snag list or handover sign-off, free-text reports can leak internal remarks.
25. **Sub-contractor sees no payments and cannot dispute.** [C] No paid/balance/retention/advance view (`subcontractor_portal.dart:149-166`), no joint measurement or dispute button, rejection needs no reason, claims cannot be edited, engineer certificates and photos are hidden, his gang's attendance and advances are not visible, no way to share his own statement.
26. **Supplier portal gives the supplier nothing.** [C] No PO number or rate/qty/GST breakup, no accepted-quantity or payment status, can see and dispatch unapproved POs (`supplier_portal()` filters only cancelled), no alert when an RFQ arrives, one item per RFQ, permanent codes, a stale award can overwrite a revised quote, GRNs cannot be corrected, freight carries no GST so invoices will not match.
27. **Owner fraud-spotting gaps.** [C] No report of workers paid with no photo, no owner approval for new workers; the Money tab's `canSeeMoneyIn` allows only owner and manager while `HANDOVER.md` says accounts also sees money (docs and code disagree); join code gives immediate membership with no expiry or approval.

## P1: reliability on poor networks and cheap phones

28. **One stuck photo blocks all sync.** [C] `sync_engine.dart:283-285` breaks the queue on any transient error; uploads read the whole file into memory (`:439`). Skip with per-entry backoff, upload files in a second pass, stream or resume, cap bill photos (about 2400 px, q85).
29. **No sync backoff or connectivity check; no visible "waiting to send".** [C] Fixed 5-minute timer, runs only while the app is open (`periodic_sync_trigger.dart:21,51`). Add exponential backoff, a connectivity check and a Home banner ("3 things waiting").
30. **Whole outbox loaded and JSON-decoded on the UI isolate** (`pending()`, `dirtyKeys()`, `_queuedIds()`; `app_database.dart:2564`, `sync_engine.dart:262,335,522,1027,1442`). [C] Page it, select only ids, store `project_id` in its own column, cache the dirty set.
31. **Storage only grows; no free-space check; large decodes on 2 GB phones** (`photo_stamp.dart:33-52`, `Image.file` without `cacheWidth`; drawing sheets at 150 dpi). [C]
32. **PDFs and XLSX are built on the UI isolate**, with unscaled photos (`dpr_report.dart:239`, `week_close_pack.dart:152`, 40-photo packs). [C]
33. **A spoken report is lost if the sheet is dismissed** (`voice_report_sheet.dart:39-46`); Telugu voice needs an offline pack the user does not know about. [C] Autosave drafts; offer the pack and open the right settings screen.
34. **Crash reporting needs the network and misses crashes before first frame.** [C] Persist to a file, upload next launch.
35. **Realtime channels are not torn down per screen; index coverage is partial** (13 `*_id` indexes for 93 tables, none on date columns or `sync_outbox`). [C]

## P2: language quality (all five Indian languages)

36. **Consent wording says "from behind" instead of "in the background"** in Hindi (`strings_consent_hi.dart:9,10`), Telugu (`strings_consent_te.dart:9,10`), Marathi (`strings_consent_mr.dart:9,10`): fix first, it is a privacy promise. Kannada and Marathi say "next camera" for front camera (`strings_consent_kn.dart:10`, `strings_consent_mr.dart:10`). [C]
37. **Tamil:** Punch out "வெளியேற்றம்" means eviction (`strings_ta.dart:301`); "struck through" says underlined (`:1492,1500`); concrete cube, curing and casting use geometry and metalwork words; doubled words in `strings_siteops.dart:485,555`. **Hindi:** In/Out as bare infinitives (`strings_wh_hi.dart:202,312`). **Marathi:** "steps" as physical stairs (`strings_siteops.dart:1068`); "{n} मी दूर" reads "I am far" (`:1052`). **Telugu:** "{n} ని" for minutes (`strings_siteops.dart:425`). [C]
38. **Dates:** Kannada, Tamil and Telugu ICU patterns put the month first or add stray commas; force one `d MMM y` pattern. Backend errors via `tr('${e.message}')` (12 sites) are always English. Cross-references name options that the UI spells differently ("None" vs "कोई नहीं"). Case suffixes are glued to Latin text. Overflow risk: Tamil "Net pay" 3.9x. Hindi, Telugu, Tamil, Kannada and Marathi sampled only about 40 strings each: run a native-speaker pass on the whole siteops and consent files. [C]
39. **Voice report parser knows weather and issue words only for English, Hindi and Telugu.** Tamil, Kannada and Marathi have none (`site_report_parser.dart`). [C]

## P2: documentation and procurement readiness

40. `fieldos_mobile/README.md` is the Flutter template; `docs/README.md` and `MOBILE_GUIDE.md` still say sync is optional. [C]
41. Enterprise buyers will ask for: a signed DPA with subprocessor annex (Anthropic, Sarvam, RevenueCat, Google, Apple, Supabase, GitHub), a published RPO/RTO and SLA, MFA/SSO, a third-party pen test, an ISO 27001 or SOC 2 roadmap, a company-level bulk export and exit procedure, and a liability cap and jurisdiction suited to their size. DPDP breach duties are written for 13 May 2027. [C]

---

## What customers genuinely liked

Cash book with counts and "no bill attached" flags; uneditable change history; material-vs-norm check; daily report with "not received" instead of zero; wages held for days with no report; server-side approval limits; offline-first with WhatsApp sharing; clear paywall (price, trial length, cancel notice, UPI pending handled); camera photos stamped with date, time and GPS; defects closed by someone other than the fixer; one award per request and immutable decided quotes; GSTIN check-character and rule-46 invoice checks; Tally XML validated before export; cancel-not-delete vouchers; strict portal scoping with SQL isolation tests; permissions asked in context.

## Order of attack

1. Owner today: confirm plan and backups (#1), second Owner on Supabase (#10).
2. Server, with a local Postgres to test: PO/requisition guards (#2), server `created_at` stamp (#3), history on wages and attendance (#5), server time window for attendance (#11), unique PO per requisition (#12), AI consent check (#9), supplier portal filters (#26).
3. Phone, low risk: storekeeper access (#16), early-age cube wording (#13, done), draft autosave (#33), sync banner and backoff (#28-#30), storage warning (#31).
4. Product decisions: trial length and paywall order (#18-#20), phone OTP login (#22), role-based home (#23).
5. Bigger builds: IS 456 acceptance, integer-paise money, secure session storage, client and sub-contractor portal upgrades, accounting depth.
