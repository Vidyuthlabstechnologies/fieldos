# Security incident and personal data breach runbook (India)

What to do when something may have gone wrong with security or with personal
data. Written 23 November 2026 from the CERT-In directions of 28 April 2022
(under section 70B(6) of the IT Act, 2000) and the Digital Personal Data
Protection Act, 2023 with the DPDP Rules, 2025. Not legal advice: have the
company's lawyer read it with the privacy policy and terms.

## Who

| Role | Person | Contact |
|---|---|---|
| Incident lead (decides, starts the clocks) | Varshini CB | info@mldynamic.com |
| CERT-In Point of Contact (details to be sent to CERT-In) | Varshini CB | info@mldynamic.com, ML Dynamic Solutions Private Limited, 606, 6th Floor, Gowra Fountainhead, Patrika Nagar, Madhapur, Hi-Tech City, Hyderabad, Telangana 500081 |
| Grievance Officer / person who answers data questions | Varshini CB | info@mldynamic.com |
| Supabase (database, storage, functions) | developer with Supabase access | |
| Lawyer | the company's lawyer | |

## The clocks

| Who to tell | Deadline | How |
|---|---|---|
| CERT-In | **Within 6 hours** of noticing a reportable cyber security incident (the directions' annexure lists them: data breach or leak, unauthorised access to systems or data, compromise of accounts, malicious code, attacks on servers, databases and APIs, among others) | Email incident@cert-in.org.in, using the form on cert-in.org.in. Send what you know; more can follow. |
| Data Protection Board of India | **Without delay** an intimation of a personal data breach, then **within 72 hours** of becoming aware a detailed report (what happened, the facts, the likely effect, what was done to reduce harm, the findings about who caused it, what stops it happening again, and the notices sent to people). The Board can allow longer if asked in writing. | Through the Board's online process. These DPDP Rules duties apply from 13 May 2027; follow them now. |
| Each affected person | **Without delay** | Email, or in the app: what happened, when, how far it goes, the likely consequences for them, what we are doing, what they can do to protect themselves, and who to contact (the Grievance Officer). |
| Companies whose records are involved (FieldOS is their processor) | **Without undue delay** (terms of use s.4) | Email the company owner. They may have their own duty to tell the Board and their workers. |

A personal data breach under DPDP is any unauthorised processing, or any
accidental disclosure, use, change or loss of access to personal data that
affects its confidentiality, integrity or availability. A lost phone with an
unlocked FieldOS app, a wrong row-level security policy, a leaked service key
and an exported spreadsheet sent to the wrong person can all be breaches.

## Steps

1. **Contain.** Rotate any leaked key (Supabase service role, function
   secrets, Anthropic, Sarvam, RevenueCat, GitHub tokens). Revoke sessions of
   affected accounts. Turn off the affected function or policy. Keep notes of
   every step with the time (IST).
2. **Keep the evidence.** Do not delete logs. Export the Supabase auth audit
   log (`auth.audit_log_entries`), API and function logs for the period
   before they roll off, and keep them with the incident notes.
3. **Decide within the first hour** whether it is a reportable incident and
   whether personal data is involved. If in doubt, report.
4. **Report to CERT-In** inside 6 hours.
5. **Tell the Board and the people affected** (and the companies), then send
   the Board's detailed report inside 72 hours.
6. **Fix and check.** Run `tools/isolation_check.py` (the isolation-check workflow) and the
   SQL tests after any policy change.
7. **Write up** what happened and what changed, and keep it with the notes.

## Logs we must be able to produce

- **CERT-In:** logs of all ICT systems kept for a rolling **180 days**, within
  India (a copy accessible in India), with clocks synchronised to NTP (NIC or
  NPL servers or ones traceable to them).
- **DPDP Rules 2025 (rule 6):** logs that let a breach be detected and dealt
  with, and the personal data, traffic data and logs of processing kept for
  at least **one year** (rule 8 and the Seventh Schedule purposes).

How we meet it: Supabase keeps API gateway, auth, database and edge
function logs for one day. The `system-logs` workflow runs
`tools/export_logs.py` every 6 hours and copies them, one gzip JSON-lines
file per source per 6 hours, into the private `system-logs` Storage bucket
of the same project, in Mumbai. Copies older than 400 days are deleted. The
bucket has no access policies, so only the service role can read it. The
auth audit log (`auth.audit_log_entries`) is a table in the Mumbai database
and stays until deleted. Supabase's servers keep time with NTP.

To produce logs: download the files for the dates you need from the
`system-logs` bucket (Supabase dashboard, Storage) and `zcat` them. If a run
fails, the workflow shows red in Actions; a gap is only lost if no run
succeeds for a whole day, so check it after any GitHub or Supabase outage.
