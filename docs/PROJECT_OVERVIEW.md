# FieldOS - Construction Site Management Platform

## Overview

FieldOS is a comprehensive construction site management platform designed for field engineers, project managers, and site supervisors. It provides offline-first capabilities for managing daily operations at construction sites.

## Core Philosophy

- **Offline-first**: the desktop app (Tauri) and the mobile app (Flutter) both run with zero internet connection required; the only feature that ever needs it is voice-to-DPR, and only when that specific feature is used
- **Voice-first**: Voice-to-text for daily progress reports (DPR)
- **Precision**: Decimal-based calculations for BOQ/estimations (no floating-point errors)
- **Local-first**: SQLite on the desktop app, a local drift/SQLite database on mobile — no shared server, no sync between them yet (see `docs/MOBILE_GUIDE.md`)
- **Mobile-native**: a native Flutter app (`fieldos_mobile/`) with its own offline auth and local database. An earlier Capacitor/Next.js wrapper was removed in November 2026 (issue #155).

## Tech Stack

| Layer | Technology |
|-------|------------|
| Backend | FastAPI (Python 3.12+), SQLAlchemy 2.0, SQLite |
| Frontend | Next.js 16 (App Router), React 18, TypeScript, Tailwind CSS |
| Mobile | Flutter (native, offline-first, drift/SQLite) — see `fieldos_mobile/`. Capacitor/PWA wrapper deprecated. |
| Auth | Session-based (bcrypt + SHA-256 pre-hash), no JWT |
| Real-time | WebSocket per-project rooms |
| PDF | jsPDF + jspdf-autotable |
| Voice AI | Sarvam AI (Indic languages) |

## Project Structure

```
fieldos/
├── fieldos/                 # Backend (FastAPI)
│   ├── app.py              # App factory
│   ├── auth.py             # Authentication
│   ├── db.py               # Database session
│   ├── models.py           # SQLAlchemy models
│   ├── schemas.py          # Pydantic schemas
│   ├── permissions.py      # RBAC
│   ├── estimation_calc.py  # BOQ calculation engine
│   ├── sarvam.py           # Voice AI integration
│   └── routers/            # API endpoints
│       ├── auth.py
│       ├── companies.py
│       ├── projects.py
│       ├── tasks.py
│       ├── dpr.py
│       ├── issues.py
│       ├── dashboard.py
│       ├── estimation.py
│       ├── materials.py
│       ├── workers.py
│       ├── documents.py
│       ├── procurement.py
│       ├── equipment.py
│       ├── inspections.py
│       ├── realtime.py     # WebSocket
│       ├── billing.py      # Stripe
│       ├── settings.py
│       └── portability.py  # Export/Import
├── frontend/               # Frontend (Next.js)
│   ├── app/
│   │   ├── project/        # Project-scoped pages
│   │   │   ├── page.tsx            # Dashboard
│   │   │   ├── materials/page.tsx  # Materials + photos
│   │   │   ├── equipment/page.tsx  # Equipment + logs
│   │   │   ├── procurement/page.tsx # 6-tab procurement
│   │   │   ├── inspections/page.tsx # Checklists + photos
│   │   │   ├── documents/page.tsx   # Versioned uploads
│   │   │   ├── workers/page.tsx     # Labour + attendance
│   │   │   └── estimations/         # BOQ
│   │   ├── projects/       # Project list/create
│   │   ├── login/page.tsx
│   │   └── settings/page.tsx
│   ├── components/         # Reusable UI
│   ├── lib/
│   │   ├── api.ts          # API client
│   │   ├── auth.ts         # Token management
│   │   ├── pdf.ts          # PDF generation
│   │   └── realtime.ts     # WebSocket hook
│   └── public/             # PWA assets
├── fieldos_mobile/          # Native Flutter mobile app (canonical mobile strategy)
│   └── lib/
│       ├── auth/            # Local offline auth
│       ├── data/            # drift/SQLite local database
│       ├── estimation/      # Dart port of the BOQ calc/reconciliation engine
│       ├── agents/          # Voice-DPR intake, cost-control agent
│       └── features/        # Screens: dashboard, procurement, labour, etc.
├── src-tauri/               # Desktop shell (Rust/Tauri) -- wraps frontend/out + the
│                             # PyInstaller backend sidecar into a Windows installer
└── docs/                   # This documentation
```

## Key Features

### 1. Project Dashboard
- Task board (Kanban-style)
- Voice DPR recorder (Sarvam AI)
- Site feed (activity timeline)
- Progress metrics

### 2. Materials Tracking
- Delivery/usage entries with categories
- Photo evidence upload
- Cost aggregation by category

### 3. Equipment Management
- Registry (cranes, excavators, mixers, etc.)
- Usage/maintenance/fuel logs
- Hourly cost tracking

### 4. Procurement Workflow
```
Vendor → Requisition → RFQ → Quotes → PO → GRN
```
- 6-tab interface
- Multi-vendor quote comparison
- Goods Received Notes with condition tracking

### 5. Inspections & Quality
- Checklist-based inspections
- Pass/Fail/NA per item
- Photo evidence
- Overall result (Pass/Fail/Conditional)

### 6. Estimations / BOQ
- Cost heads with calculation types (volume, area, steel weight, count)
- Measurement entries (L×W×H×Nos)
- Steel entries (dia × length × nos)
- Contractor profit %
- PDF export

### 7. Documents
- Versioned file storage
- Categories: drawing, specification, contract, permit, report, photo, correspondence, safety
- Multipart upload

### 8. Workers & Attendance
- Worker registry with roles/wages (create/update/deactivate restricted to owner/PM)
- Daily attendance (Present/Absent/Half-day), plus a same-day summary with wage-cost total

### 9. Real-time Collaboration
- WebSocket per project
- Live updates for tasks, DPR, materials, workers, equipment, inspections, procurement

### 10. Billing (present in code, not currently wired to anything real)
- Backend routes for Stripe subscriptions, checkout/portal sessions, and webhook
  handling exist (`fieldos/routers/billing.py`), but no `STRIPE_SECRET_KEY` is
  configured anywhere and nothing in the frontend calls these endpoints yet.
  See `docs/DEPLOYMENT.md` for why this is intentional, not an oversight.

### 11. Settings
- Sarvam API key management
- Project export/import (portability)

## Getting Started

See [DEVELOPMENT.md](./DEVELOPMENT.md) for setup instructions.