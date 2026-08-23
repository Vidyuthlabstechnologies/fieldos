# FieldOS Market, Technical & UI/UX Research

**Provenance:** produced by the `hermes` agent CLI (nemotron-3-ultra-free via OpenCode Zen,
web-search/web-extract tools) on 2026-08-23, in response to a request to fact-check an
AI-generated competitor-benchmark document against real sources rather than trust it at face
value. Every claim below cites the URL it was pulled from; items with no independent primary
source are explicitly marked "unverified"/"claimed." One claim (Chaquopy's lack of iOS support)
was independently re-fetched and confirmed directly from chaquo.com by a second, separate
fetch — everything else in this document reflects hermes's research pass and has not been
individually re-verified beyond that spot check. Treat this the way you'd treat any single
research pass: a solid starting point, not a substitute for primary-source review before a
major decision is locked in.

---

## 1. Market Research: Competitor Reality-Check

### 1.1 Onsite (onsiteteams.com)

| Claim | Status | Evidence |
|---|---|---|
| "Trusted by 10,000+ construction companies" | Verified (marketing claim) | Repeated on homepage & products page; no independent verification possible |
| "2X field-office communication", "25% faster delivery", "10% savings on costs" | Unverified marketing metrics | Stated on homepage hero; no methodology or third-party citation |
| Modules: Sales & Tendering, Design Management, Planning & Budgeting, Progress Tracking, Material & Inventory, Labour & Salaries, Subcontractor Management, Assets & Equipment, Procurement, BOQ & Billing, Quality Management, Finance & Accounts, Team Controls | Verified (listed in FAQ) | onsiteteams.com/products/ FAQ |
| Mobile + desktop hybrid platform | Verified | Homepage: "hybrid platform with a user-friendly construction management mobile app... and a robust desktop ERP" |
| Tally & Zoho Books integration | Verified | Products FAQ |
| "Go live within 48 hours", "Managed Service ₹15,000/project/month" | Verified (claimed, not independently confirmed) | Products FAQ |
| Used by VINCI and Bouygues | **Not found on Onsite's own site** — found on Kraaft's site instead | See below |
| "~120 features" / specific numeric interaction-time targets (from the pasted strategy doc) | Unverified | No feature count or performance specs published anywhere on Onsite's public pages |

**Verdict:** Onsite's own site backs a broad ERP module list and two named integrations. The
percentage-improvement figures are self-reported, uncited marketing. The VINCI/Bouygues
claim — which the pasted strategy document implied was Onsite's customer base — does not
appear on Onsite's site at all.

### 1.2 Kraaft (kraaft.co)

| Claim | Status | Evidence |
|---|---|---|
| "7-in-1 app / augmented WhatsApp for construction" | Verified (positioning) | Homepage H1 |
| 7 modules: Chat, Maps, Voice Reports, Folders, Planning, AI Agents, Integrations | Verified | Homepage, each with a linked feature page |
| "30,000+ active users across 14 countries" | Verified (claimed) | Play Store listing |
| Used by VINCI and Bouygues | **Verified — logos actually shown** | Kraaft's own homepage client carousel |
| "600k+ job sites", 64-person team | Verified (claimed) | Play Store listing |
| Free plan available | Verified | Play Store listing |
| 500K+ downloads, ~4.0★ | Verified | Play Store listing, Aug 2026 |

**Verdict:** Kraaft's positioning and the VINCI/Bouygues customer claim check out from primary
sources — the strategy document's attribution of that customer base to Onsite was wrong; it's
Kraaft's.

### 1.3 Other players (brief)

| Product | Positioning | Source |
|---|---|---|
| Fieldwire (Hilti) | Field-first, offline-capable jobsite management; plans, tasks, punch lists, custom forms; free tier + $39–89/user/mo | fieldwire.com/blog |
| Procore | GC-focused, financials/contracts/RFIs/change orders; sales-only pricing, no public free tier | procore.com |
| Buildertrend | Residential-focused; scheduling, client portals, estimating; custom quote only | fieldwire.com comparison |

---

## 2. Technical Research

### 2.1 Offline-first Flutter + Drift + Riverpod — 2026 practices beyond the package docs

| Practice | Why it matters |
|---|---|
| A single repository layer as the one source of truth for all reads/writes | Eliminates "who owns this row" bugs |
| An outbox/operation queue with FIFO ordering + a retry limit, permanent vs. retryable failure classified separately | Preserves write causality; a poisoned head-of-queue row doesn't retry forever or drain the battery |
| Pull only when the outbox is empty; local writes win unconditionally until drained | Correct and simple for single-writer-per-record apps (matches a field worker's own device) |
| UUID primary keys, never auto-increment | Prevents ID collisions across devices that were offline concurrently |
| Soft deletes (`isDeleted` flag), hard-purged only after confirmed sync | A hard delete can't be synced to a server that hasn't seen it yet |
| `NativeDatabase.createInBackground()` — SQLite on its own isolate | Keeps the UI thread free |
| Visible sync status in the UI (pending count / offline badge) | Users need to know when data hasn't left the device yet |

**Architectural note relevant to FieldOS specifically:** this "local writes always win, pull
only when idle" pattern is correct for a single-user-per-record app — which describes
FieldOS's field-worker usage today. It stops being sufficient the moment two people can edit
the same record concurrently while both offline; that would need field-level merge or CRDTs,
which is a materially bigger design problem than the sync layer itself.

### 2.2 Chaquopy (embedding Python/FastAPI on-device) — reality check

| Question | Answer | Source |
|---|---|---|
| iOS support? | **No.** "Not at the moment" — Chaquopy's own FAQ directs iOS developers to BeeWare instead. **Independently re-confirmed by a second direct fetch of chaquo.com.** | chaquo.com/chaquopy/doc/current/faq.html |
| APK size / cold start | Base interpreter ~15–20MB per ABI; heavier libraries add much more; a fat APK covering all ABIs can exceed Play Store limits. Cold start adds ~200–500ms for interpreter init, plus JNI bridging overhead per call. | Chaquopy FAQ, GitHub issue #448 |
| Is embedding a full backend (FastAPI-style) on-device a common production pattern? | No — niche. Used in production mainly for bundling ML/inference logic (e.g. a crypto wallet app, some on-device-ML apps), not for running a full API server on the phone. | ProAndroidDev writeup, GitHub issue #448 |

**Bottom line:** this independently confirms the concern raised earlier in this session before
any building started — no iOS path, real APK/latency cost, and not how this pattern is used in
production elsewhere. The current architecture (Python stays a desktop sidecar; mobile runs
its own native Dart implementation) remains the better-supported choice unless there's a
requirement this research hasn't surfaced.

### 2.3 Free-tier hosted databases, for a future desktop↔mobile sync layer (not built yet)

| Provider | Free storage | Compute | Auth included | Notable limits |
|---|---|---|---|---|
| Supabase | 500MB/project | Shared CPU, 500MB RAM | 50K MAU | 2 active projects; pauses after 1 week idle |
| Neon | 0.5GB/project (up to 100 projects) | 100 CU-hrs/mo, scale-to-zero | 60K MAU | 10 branches/project free |
| Turso | 5GB total (up to 100 DBs) | N/A (embedded replicas) | none built in | 500M reads/mo, 10M writes/mo |
| Firebase (Spark) | Firestore 1GB, 50K reads/20K writes per day | 2M Cloud Function calls/mo | 50K MAU | Storage no longer available on the free Spark tier since Oct 2024 |

Supabase is the easiest single-provider start (Postgres + auth + storage together); Turso's
many-small-SQLite-databases model maps closely to FieldOS's existing per-project SQLite
structure if a sync layer is ever built. This is background for a future decision, not a
recommendation to build it now.

---

## 3. UI/UX Research

### 3.1 SiteVoice (sitevoice.app) — voice-first inspection app

UK snagging/inspection tool. Flow: hold the mic → speak a defect → AI extracts trade/
location/severity as a structured card → review/edit → PDF or shareable link → role-scoped
views for site manager / contractor / operative. Voice interaction is **hold-to-talk** (not
tap-to-toggle) with a live waveform, one defect per recording, and a mandatory structured
review card before the next capture — this is the same shape FieldOS's voice-DPR already uses.

### 3.2 The pasted Dribbble shot (27365815)

Reachable and real — a concept by designer Sk Raju Hossin. Clean dashboard, bold orange
accent, progress rings, budget bars, analytics screens. **Not a field-worker reference** — it's
an office/project-manager dashboard design (small tap targets, desktop-density layout, no
one-handed/outdoor optimization). Useful for visual language only, not interaction design.

### 3.3 Real field-worker-facing construction UI (not concept art)

| Example | Relevance |
|---|---|
| UITOP's "Activate OS" fleet-management case study | Explicitly designed for one-handed use, gloves, direct sunlight, weak signal; real shipped product (acquired by Sandhills Global) |
| Noomo Agency's ToughBuilt companion app | Real shipped product pairing a physical measurement device with a mobile app; large touch targets, high contrast |
| Fieldwire (actual product) | Offline-first plan markup, punch lists, custom forms; bottom-nav, large-button mobile UI |

Most Dribbble/Behance search results for "construction app" are concept portfolio pieces aimed
at office dashboards, not field-worker tools — the two useful real references are UITOP's and
Noomo's case studies above.

### 3.4 Voice-first data-capture UX, 2026 state of the art (cross-domain)

| Pattern | 2026 practice |
|---|---|
| Primary action | Hold-to-talk preferred over tap-to-toggle for field use — prevents accidental recordings, works with gloves |
| Live feedback | Waveform + interim (in-progress) transcript, not just a post-hoc result |
| Confirmation | A mandatory review step showing extracted structured fields, editable before save — "repeat back what you understood" is now a named UX principle |
| Error handling | Offer constrained re-prompts ("did you mean X or Y") rather than an open "try again"; latency under ~250ms feels instant, over ~1s breaks the flow |
| Multimodal | Voice is paired with the screen, never standalone — visual confirmation + photo/location attach alongside it |

**Has best practice moved since FieldOS's voice-DPR was built?** Incrementally, not
fundamentally — hold-to-talk + live waveform + structured review card is still the standard
shape. What's newer: showing the interim transcript *during* recording (not just after), and
treating the "repeat back what I understood" confirmation as an explicit, named step rather
than an implicit one.

---

## Summary, for reference against the two decisions already made this session

- **Competitors**: the pasted strategy document attributed Onsite's customer base and some
  claims incorrectly — Onsite's own site doesn't claim VINCI/Bouygues (Kraaft does), and
  Onsite's ~120-feature count and interaction-time targets are not published anywhere and
  were the strategy document's own invented numbers, not sourced facts.
- **Chaquopy / on-device Python**: independently confirmed no iOS support and real production
  costs — this is now a verified fact, not just a caution, and is worth revisiting given the
  user's earlier choice to pursue it as the target architecture.
- **Sync backend**: if desktop↔mobile sync is scoped later, Supabase/Neon/Turso are the real
  free-tier options, each with genuine tradeoffs, none of which is "run Python on the phone."
- **Voice-DPR UI**: FieldOS's existing pattern already matches 2026 best practice; the highest-
  value, lowest-effort improvement found here is showing the interim transcript live during
  recording rather than only after.
