# Frontend Architecture

## Overview

Next.js 16 (App Router) with React 18, TypeScript, and Tailwind CSS. Static export (`output: "export"`), because the frontend ships loaded directly by the Tauri desktop shell — no Node server in production. (An earlier Capacitor/PWA wrapper of this same static export also exists, `frontend/android/`, but is deprecated — see `frontend/MOBILE.md`. The maintained mobile app is a separate native Flutter project, `fieldos_mobile/`.)

## Project Structure

```
frontend/
├── app/
│   ├── layout.tsx              # Root layout + PWA meta + SW registration
│   ├── globals.css             # Tailwind imports + custom styles
│   ├── page.tsx                # Landing (redirect to /projects)
│   ├── login/page.tsx          # Auth pages
│   ├── projects/
│   │   ├── page.tsx            # Project list
│   │   └── new/page.tsx        # Create project
│   ├── project/                # All project-scoped routes
│   │   ├── page.tsx            # Dashboard (tasks, DPR, feed)
│   │   ├── materials/page.tsx  # Materials + photo upload
│   │   ├── equipment/page.tsx  # Equipment registry + logs
│   │   ├── procurement/page.tsx # 6-tab procurement
│   │   ├── inspections/page.tsx # Checklists + photos
│   │   ├── documents/page.tsx  # Versioned uploads
│   │   ├── workers/page.tsx    # Labour + attendance
│   │   └── estimations/
│   │       ├── page.tsx        # List + create
│   │       └── detail/page.tsx # BOQ + PDF export
│   └── settings/page.tsx       # Sarvam key + portability
├── components/
│   ├── Sidebar.tsx             # Navigation (responsive, collapsible)
│   ├── DashboardWidget.tsx     # Metrics cards
│   ├── TaskList.tsx            # Kanban board
│   ├── DPRForm.tsx             # DPR entry form
│   ├── VoiceDPRRecorder.tsx    # Sarvam voice recording
│   ├── SiteFeed.tsx            # Activity timeline
│   ├── BOQTable.tsx            # BOQ display
│   ├── CostHeadForm.tsx        # Cost head CRUD
│   ├── MeasurementEntryForm.tsx
│   ├── SteelEntryForm.tsx
│   ├── NewProjectForm.tsx
│   └── ProjectCard.tsx
├── lib/
│   ├── api.ts                  # API client (fetch wrapper)
│   ├── auth.ts                 # Token storage (localStorage)
│   ├── pdf.ts                  # jsPDF report generation
│   └── realtime.ts             # WebSocket hook
├── public/
│   ├── manifest.json           # PWA manifest
│   ├── sw.js                   # Service Worker
│   └── icons/                  # PWA icons (72-512px)
├── next.config.mjs             # Next.js config (static export)
├── capacitor.config.ts         # Capacitor config (deprecated path, see frontend/MOBILE.md)
├── tsconfig.json               # TypeScript strict mode
├── tailwind.config.ts          # Tailwind config
└── package.json
```

## Key Patterns

### 1. Page Structure (Project-Scoped)

```tsx
// app/project/materials/page.tsx
"use client";

import { Suspense, useEffect, useState } from "react";
import { useSearchParams } from "next/navigation";
import { Sidebar } from "@/components/Sidebar";
import { listMaterialEntries, createMaterialEntry, ... } from "@/lib/api";

function MaterialsPage({ projectId }: { projectId: string }) {
  // State, effects, handlers
  return (
    <div className="flex min-h-screen">
      <Sidebar />
      <main className="ml-56 flex-1 p-6">
        {/* Content */}
      </main>
    </div>
  );
}

function MaterialsGate() {
  const searchParams = useSearchParams();
  const projectId = searchParams.get("id");
  if (!projectId) return <main>No project selected.</main>;
  return <MaterialsPage projectId={projectId} />;
}

export default function MaterialsPageRoute() {
  return (
    <Suspense fallback={<main>Loading...</main>}>
      <MaterialsGate />
    </Suspense>
  );
}
```

### 2. API Client

```typescript
// lib/api.ts
const API_BASE_URL = process.env.NEXT_PUBLIC_API_BASE_URL ?? "http://localhost:8000";

function getToken(): string | null {
  return localStorage.getItem("fieldos_token");
}

async function apiFetch<T>(path: string, options: RequestInit = {}): Promise<T> {
  const token = getToken();
  const res = await fetch(`${API_BASE_URL}${path}`, {
    ...options,
    headers: {
      "Content-Type": "application/json",
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...options.headers,
    },
  });
  if (!res.ok) throw new Error(`API error ${res.status}: ${await res.text()}`);
  return res.json();
}

// Multipart upload (no Content-Type - browser sets boundary)
export async function uploadMaterialPhoto(projectId, entryId, file, caption) { ... }
```

### 3. Real-time Hook

```typescript
// lib/realtime.ts
export function useProjectWebSocket(projectId: string | null, handlers: Record<string, WSHandler>) {
  const wsRef = useRef<WebSocket | null>(null);
  const [connected, setConnected] = useState(false);

  const connect = useCallback(() => {
    if (!projectId) return;
    const token = getToken();
    const wsUrl = `${API_BASE_URL.replace("http", "ws")}/projects/${projectId}/ws?token=${token}`;
    const ws = new WebSocket(wsUrl);
    // ... onopen, onmessage, onclose, reconnect logic
  }, [projectId]);

  return { connected, send, disconnect };
}

// Usage in page
const { connected } = useProjectWebSocket(projectId, {
  task_update: (msg) => refreshTasks(),
  material_update: (msg) => refreshMaterials(),
  "*": (msg) => console.log("WS:", msg),
});
```

### 4. PDF Generation

```typescript
// lib/pdf.ts
import { jsPDF } from "jspdf";
import autoTable from "jspdf-autotable";

export function generateBOQPDF(project: Project, boq: BOQ): jsPDF {
  const doc = new jsPDF();
  doc.text(project.name, 14, 20);
  doc.autoTable({
    head: [["Description", "Unit", "Raw Qty", "Billing Qty", "Rate", "Amount"]],
    body: boq.lines.map(l => [l.name, l.billing_unit, l.raw_quantity, ...]),
  });
  // Totals
  return doc;
}

// In page
function handleExport() {
  const doc = generateBOQPDF(project, boq);
  doc.save(`${project.name}-BOQ.pdf`);
}
```

### 5. Mobile-Responsive Sidebar

```tsx
// components/Sidebar.tsx
export function Sidebar() {
  const [isOpen, setIsOpen] = useState(false);
  const [isMobile, setIsMobile] = useState(false);

  useEffect(() => {
    const check = () => setIsMobile(window.innerWidth < 768);
    check(); window.addEventListener("resize", check);
    return () => window.removeEventListener("resize", check);
  }, []);

  return (
    <>
      {isMobile && <div className={isOpen ? "opacity-100" : "opacity-0"} onClick={() => setIsOpen(false)} />}
      <aside className={`fixed left-0 top-0 z-40 h-screen transition-transform lg:translate-x-0
        ${isMobile ? (isOpen ? "w-64 translate-x-0" : "w-64 -translate-x-full") : "w-56"}`}>
        {/* Navigation links */}
      </aside>
    </>
  );
}

export function MobileMenuButton({ isOpen, onClick }) {
  return <button className="lg:hidden" onClick={onClick}>...</button>;
}
```

## State Management

- **Server state**: React Query not used - direct `useEffect` + `apiFetch`
- **Client state**: `useState` / `useReducer` per page
- **Auth state**: `localStorage` token + `auth.ts` helpers
- **Real-time**: WebSocket hook with auto-reconnect

## Styling

- **Tailwind CSS** utility-first
- **Custom colors**: `slate` palette, `slate-900` primary
- **Dark mode**: Not implemented (could add via `class` strategy)
- **Responsive**: Mobile-first, breakpoints `sm:`, `lg:`

## Build & Deploy

```bash
# Development
npm run dev

# Production build (static export)
npm run build
# Output: frontend/out/

# Preview production build
npx serve out

# The real production consumer of frontend/out/ is the Tauri desktop shell
# (npx tauri build, from the repo root -- see docs/DEPLOYMENT.md), not a
# web server. `npx cap sync` (Capacitor) is deprecated -- see frontend/MOBILE.md.
```

## TypeScript Config

```json
{
  "compilerOptions": {
    "target": "ES2017",
    "lib": ["dom", "dom.iterable", "esnext"],
    "allowJs": true,
    "skipLibCheck": true,
    "strict": true,
    "noEmit": true,
    "esModuleInterop": true,
    "module": "esnext",
    "moduleResolution": "bundler",
    "resolveJsonModule": true,
    "isolatedModules": true,
    "jsx": "preserve",
    "incremental": true,
    "plugins": [{ "name": "next" }],
    "paths": { "@/*": ["./*"] }
  }
}
```

## Adding New Pages

1. Create `app/project/new-page/page.tsx` following page template
2. Add API functions to `lib/api.ts`
3. Add route to `components/Sidebar.tsx`
4. Test mobile responsiveness
5. Add PDF export if reports needed