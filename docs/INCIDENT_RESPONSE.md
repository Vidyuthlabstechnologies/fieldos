# Security incident and personal data breach runbook (India)

What to do when something may have gone wrong with security or with personal
data. Written 23 November 2026 from the CERT-In directions of 28 April 2022
(under section 70B(6) of the IT Act, 2000) and the Digital Personal Data
Protection Act, 2023 with the DPDP Rules, 2025. **Not legal advice and not
reviewed by a lawyer.** The company must fill in the names below and have a
lawyer read this before relying on it.

## Who

| Role | Person | Contact |
|---|---|---|
| Incident lead (decides, starts the clocks) | _owner to name_ | |
| CERT-In Point of Contact (must be designated and sent to CERT-In) | _owner to name_ | |
| Grievance Officer / person who answers data questions | _owner to name_ | info@mldynamic.com |
| Supabase (database, storage, functions) | developer with Supabase access | |
| Lawyer | _owner to name_ | |

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

Today's position: the Supabase project is on the free tier, whose API and
function logs are kept only for a short time. The auth audit log is a table
in the Mumbai database and stays until deleted. **Owner decision:** move to a
plan with longer log retention, or export logs to storage in India each day,
so that 180 days (CERT-In) and one year (DPDP) can be produced.
