# FieldOS — Foundation + Project & Site Management (Module 1) Design

Status: Approved (2026-08-11)
Working name: **FieldOS** (placeholder, rename anytime)

## 1. Context & Goal

Replicate the shape of [onsiteteams.com](https://onsiteteams.com) — a construction
management ERP for contractors/developers in India & UAE (project management,
materials, labour, billing, subcontractors, approvals, dashboards, "Onsite AI") —
but as a full independent build, differentiated by:

- **Voice-first data capture.** OnsiteTeams' own marketing describes today's
  reality on most sites as WhatsApp + Excel + paper registers. Instead of forms,
  a site engineer records a voice note describing what happened; the system
  turns it into a structured record.
- **A genuinely agentic AI layer**, not just a search/chat assistant. The agent
  reads a transcript, decides what records to create/update, and drafts them —
  a human confirms before anything becomes official.

This is a multi-subsystem product. Per the module breakdown agreed in
brainstorming, this spec covers only the **foundation** (auth, multi-tenancy,
project shell) and **Module 1: Project & Site Management**. Every other module
(materials/inventory, labour & attendance, billing/finance, subcontractor &
vendor management, multi-level approvals, dashboards, native mobile) is
explicitly out of scope here and gets its own spec later.

Existing assets this design builds on: a Python/FastAPI hybrid-retrieval RAG
service (`api.py`, `advanced_kb.py`) already indexing Indian construction codes
(NBC, MoRTH, IRC, CPWD DSR/DAR, IS codes, etc.) in this project folder. That
service is extended, not replaced, and becomes the `check_code_compliance` tool
available to the agent.

## 2. Architecture

**Frontend** — Next.js, built as an installable PWA.
- Mobile-first layouts for site engineers (large voice-record button, camera
  capture, task list, site feed).
- Desktop-friendly layouts for office/PM/owner views (project list, dashboard).
- Service worker + IndexedDB for offline queueing (see §5).

**Backend** — one FastAPI service, extending the existing `api.py`.
- New routers: `/projects`, `/tasks`, `/dpr`, `/agent` (voice note processing),
  `/sync` (offline queue ingestion).
- Existing RAG retriever (`advanced_kb.HybridRetriever`) is kept as-is and
  exposed two ways: the existing `/query` endpoint, and as an agent tool
  (`check_code_compliance`).

**Data / Auth / Storage** — Supabase.
- Postgres for all relational data.
- Supabase Auth for identity — phone number + OTP as the primary sign-in method
  (site workers frequently don't have/use email), email+password as a fallback
  for office/owner users.
- Supabase Storage for DPR photos and voice-note audio files.

**Hosting** — FastAPI service deployed on Railway. Frontend deployed as a
Next.js app (Vercel or equivalent). Supabase is managed.

**Agent** — Claude, called with tool-calling. Tools:
- `create_dpr_draft(project_id, transcript, structured_fields)`
- `update_task_status(task_id, status)`
- `log_issue(project_id, description, severity)`
- `check_code_compliance(query)` → calls the existing RAG retriever

**Speech-to-text** — Sarvam AI (India-focused STT), chosen over generic Whisper
for accuracy on Hindi and regional-language voice notes mixed with construction
terminology and English loanwords, which is expected on Indian job sites.

## 3. Data Model (v1)

Core tables:

- `companies` — tenant root. `id, name, created_at`
- `company_members` — `id, company_id, user_id, role` where role ∈
  `owner | project_manager | site_engineer` (`finance`, `subcontractor` reserved
  for future modules, not enforced yet)
- `projects` — `id, company_id, name, client_name, location (lat/lng), geofence_radius_m, start_date, end_date, status`
- `project_members` — `id, project_id, user_id, role` (project-level assignment, subset of company members)
- `tasks` — `id, project_id, title, assignee_id, due_date, status (todo|in_progress|done|blocked), created_at`
- `dpr_entries` — `id, project_id, created_by, entry_date, work_summary, manpower_count, weather, status (draft|confirmed), source (voice|manual), confirmed_by, confirmed_at`
- `dpr_voice_notes` — `id, dpr_entry_id, audio_url, transcript, language_detected, transcription_status (pending|done|failed)`
- `dpr_photos` — `id, dpr_entry_id, photo_url, caption`
- `issues` — `id, project_id, dpr_entry_id (nullable), description, severity, status (open|resolved), created_at`
- `agent_actions_log` — `id, dpr_entry_id, tool_called, input, output, created_at` (audit trail of what the agent proposed, for trust/debugging)

Client-side sync queue (IndexedDB, not a server table): pending items tagged
with a client-generated UUID, entity type, payload, and timestamp.

## 4. The Voice-First Agentic Flow

1. Site engineer taps the mic button and records a voice note. Works offline —
   audio blob is stored in IndexedDB immediately.
2. When connectivity returns, the client uploads the audio to Supabase Storage
   and posts to `/agent/voice` with the storage URL + client UUID (idempotency key).
3. Backend calls Sarvam STT → transcript + detected language.
4. The agent (Claude + tools) reads the transcript plus context (today's open
   tasks, recent DPRs for that project) and calls `create_dpr_draft`, producing
   a structured draft: work completed, quantities mentioned, manpower count,
   flagged issues/delays. This draft is **not yet an official record**
   (`status = draft`).
5. The site engineer (or PM) reviews the draft in-app, edits any field, and
   taps Confirm. Only then does `status` flip to `confirmed`, `confirmed_by`
   and `confirmed_at` are set, and it becomes part of the official site record.
6. Confirmed DPRs feed the project's site activity feed and the basic
   dashboard. Photos can be attached in the same session or added after.

Design principle: **the agent drafts, a human commits.** No agent action
silently becomes an official record — this matters for trust now and will
matter more once financial/approval modules exist.

## 5. Offline Sync

- All writes (voice notes, photos, task status changes, manual DPR entries)
  go to IndexedDB first as the source of truth on-device, tagged with a
  client-generated UUID.
- A service worker background-sync task pushes queued items to `/sync/push`
  whenever connectivity is available, retrying with backoff otherwise.
- Server-side dedup by client UUID makes retries safe (idempotent).
- No merge/conflict resolution logic in v1: DPRs are per-day-per-project
  (natural append-only pattern) and tasks are single-owner status fields, so
  real conflicts are rare. This is revisited if/when multi-user concurrent
  editing of the same record becomes common.

## 6. Module 1 Scope — Project & Site Management

**In scope:**
- Create/manage projects: name, client, location + geofence, dates, status
- Task list per project: title, assignee, due date, status
- DPR creation: voice-driven (primary) + manual form (fallback), with photos
- Site activity feed: chronological DPRs/tasks/photos per project
- Basic project dashboard: % tasks complete, DPR submission streak, open issue count

**Explicitly deferred (future specs, not built now):**
- Material & inventory management (RFQ→PO→GRN)
- Labour & attendance (GPS punch in/out) + payroll
- Billing & finance (budget vs. actuals, P&L, invoicing)
- Subcontractor & vendor management
- Multi-level approval chains (beyond the single-step DPR draft→confirm)
- Native mobile app (PWA only for now)

## 7. Roles (v1)

- **Owner/Admin** — full access, manages company and all projects
- **Project Manager** — manages assigned projects, confirms/edits DPRs, manages tasks
- **Site Engineer** — creates voice notes/DPRs, views/updates tasks, cannot delete records

`finance` and `subcontractor` roles exist in the schema for forward
compatibility but have no permissions wired until their modules are built.

## 8. Non-Goals for This Spec

- Anything from the deferred module list in §6.
- Multi-tenant billing/subscriptions for FieldOS itself (this is about building
  the product, not selling it yet).
- Native (Capacitor/React Native) mobile app — PWA covers v1.
