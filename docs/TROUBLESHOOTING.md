# Troubleshooting Guide

## Backend Issues

### Server Won't Start

There's no install target and no `/opt/fieldos` — this always runs from the
repo checkout, using the repo's `.venv` directly (see DEVELOPMENT.md).

**Error: `ModuleNotFoundError: No module named 'fieldos'` / `'fastapi'` / etc.**
- You're very likely running a bare `python`/`pip` on PATH instead of the
  repo's `.venv`. Use `.venv\Scripts\python.exe -m uvicorn api:app --reload`
  explicitly, and confirm the venv actually has the package:
  `.venv\Scripts\python.exe -c "import fastapi; print(fastapi.__file__)"`
  should print a path inside this repo's `.venv`.
- If it's genuinely missing: `.venv\Scripts\python.exe -m pip install -r requirements.txt`

**Error: `sqlalchemy.exc.OperationalError: (sqlite3.OperationalError) unable to open database file`**
- Check `DATABASE_URL` in `.env` (default is `sqlite:///fieldos_dev.db`,
  relative to the repo root in dev). For the packaged desktop app, the real
  DB lives in the OS app-data directory instead — see `fieldos/paths.py`.

**Error: `alembic.util.exc.CommandError: Can't locate revision` / "No 'script_location' key found"**
- The Alembic config file is `alembic.ini` at the **repo root**, not inside
  `fieldos/`. Run migrations with `-c alembic.ini` explicitly:
  `.venv\Scripts\python.exe -m alembic -c alembic.ini upgrade head`
- Don't delete migration files to "reset" — this project's schema is real,
  versioned history (`fieldos/alembic/versions/`); if you think a migration
  is wrong, write a new one that fixes it forward.

### Authentication Issues

**Error: `401 Invalid or expired session`**
- Token expired (30-day TTL) → Re-login
- Clock skew between client/server → Sync NTP
- Token not sent → Check `Authorization: Bearer <token>` header

**Error: `bcrypt.checkpw failed`**
- Password hashed with different method → Re-register user
- Check `_prehash` consistency in `auth.py`

### Database Issues

**Error: `UniqueViolation: duplicate key value violates unique constraint`**
```python
# Check unique constraints in models.py
# Common: username, company_members(company_id,user_id), project_members(project_id,user_id)
```

**Error: `ForeignKeyViolation`**
```python
# Ensure parent record exists before creating child
# Order: Company → Project → (Tasks, DPR, Materials, etc.)
```

### WebSocket Issues

**Connection fails immediately**
```bash
# Check token in query param
ws://localhost:8000/projects/{id}/ws?token=valid_token

# Verify token not expired
# Check CORS origins in app.py ALLOWED_ORIGINS
```

**Messages not received**
```python
# Backend: Check manager.broadcast() called
# Frontend: Check useProjectWebSocket handlers match message.type
# Debug: Add console.log in onmessage handler
```

**Reconnection loops**
```typescript
// lib/realtime.ts - adjust reconnect delay
ws.onclose = () => {
  setTimeout(connect, 3000); // Increase if too aggressive
};
```

### Performance Issues

**Slow API responses**
```bash
# Check query count
# Add indexes to frequently queried columns
# Use selectinload for relationships
```

**High memory usage**
- This runs as a single loopback-only process on the user's own laptop
  (see DEPLOYMENT.md) — there's no multi-worker/Docker deployment to tune.
  Check Task Manager for the actual process (`FieldOS-backend.exe` in the
  packaged app, or `python.exe` running `uvicorn` in dev).

## Frontend Issues

### Build Failures

**Error: `Module not found: Can't resolve '@/lib/api'`**
```json
// tsconfig.json - ensure paths configured
{
  "compilerOptions": {
    "baseUrl": ".",
    "paths": { "@/*": ["./*"] }
  }
}
```

**Error: `TypeScript error: Property 'autoTable' does not exist on type 'jsPDF'`**
```bash
# Install types
npm install --save-dev @types/jspdf-autotable
# Or declare module in pdf.ts
declare module "jspdf" { interface jsPDF { autoTable: any; } }
```

**Error: `ReferenceError: require is not defined in ES module scope`**
```javascript
// next.config.mjs - use dynamic import
const withPWA = (await import('next-pwa')).default({...});
```

### Runtime Errors

**Error: `hydration mismatch`**
```tsx
// Use useEffect for client-only code
useEffect(() => { setIsMobile(window.innerWidth < 768); }, []);
// Or suppressHydrationWarning
<div suppressHydrationWarning>...</div>
```

**Error: `Can't perform a React state update on an unmounted component`**
```tsx
// Cleanup in useEffect
useEffect(() => {
  let mounted = true;
  fetchData().then(data => { if (mounted) setData(data); });
  return () => { mounted = false; };
}, []);
```

### WebSocket Not Connecting

```typescript
// Check API URL
const wsUrl = `${API_BASE_URL.replace("http", "ws")}/projects/${id}/ws?token=${token}`;

// Ensure token exists
const token = localStorage.getItem("fieldos_token");
if (!token) router.push("/login");
```

### PWA Not Installing

```bash
# Check manifest.json accessible (dev server, not a real deployed domain)
curl http://localhost:3000/manifest.json

# Check Service Worker registered
# DevTools → Application → Service Workers

# Check icons exist
ls frontend/public/icons/
```

### Mobile Layout Broken

```tsx
// Ensure viewport meta
<meta name="viewport" content="width=device-width, initial-scale=1" />

// Check Tailwind responsive classes
<div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3">
```

## Mobile (Flutter) Issues

The mobile app is a native Flutter app (`fieldos_mobile/`), fully offline
and standalone — it has no connection to the FastAPI backend, so backend/
WebSocket/CORS troubleshooting below doesn't apply to it. See
`docs/MOBILE_GUIDE.md` for the full picture, including that gap.

(The old Capacitor wrapper (`frontend/android/`) was removed in November 2026 (issue #155).)

### Analyzer/build errors

```bash
cd fieldos_mobile
flutter clean
flutter pub get
flutter analyze
```

### Drift (local database) codegen out of date

If you changed `lib/data/tables.dart` and see errors referencing
`app_database.g.dart` not matching:
```bash
cd fieldos_mobile
dart run build_runner build --delete-conflicting-outputs
```

### Geolocation (labour attendance geofencing) fails

```bash
# Emulator: Extended controls → Location → Send mock location
# Device: Settings → Location → App permissions → FieldOS → Allow
# Check permissions are requested/declared for your target platform
```

## Stripe/Billing Issues

Billing code exists (`fieldos/routers/billing.py`) but isn't wired to any
frontend UI yet and has no live Stripe account configured by default — this
section only matters if you're actively developing that feature.

### Webhook Not Receiving

```bash
# Test with Stripe CLI
stripe listen --forward-to localhost:8000/billing/webhook

# Check webhook secret in .env
STRIPE_WEBHOOK_SECRET=whsec_xxx

# Verify endpoint accessible publicly (ngrok for dev)
ngrok http 8000
```

### Checkout Session Fails

```bash
# Check STRIPE_SECRET_KEY valid
# Check price ID exists in Stripe Dashboard
# Check success/cancel URLs accessible
```

## Sarvam Voice AI Issues

### Transcription Fails

```bash
# Check SARVAM_API_KEY in .env
# Check audio format (WebM/Opus from browser)
# Check file size < 25MB
# Check language code valid (hi-IN, ta-IN, etc.)
```

### TTS Not Playing

```bash
# Check audio context policy (user gesture required)
# Check speaker name valid (priya, aditya, etc.)
# Check target_language_code in supported list
```

## Common Debug Commands

There's no systemd service, no PostgreSQL, and no Redis anywhere in this
product (see DEPLOYMENT.md) — don't reach for `journalctl`/`psql`/
`redis-cli`. What actually helps:

```powershell
# Backend: runs in the foreground of whatever terminal started it (uvicorn/
# the packaged .exe) -- its stdout/stderr IS the log. No separate log file
# to tail unless you redirected output yourself.

# Inspect the SQLite DB directly (dev) -- the sqlite3 CLI isn't
# guaranteed to be installed, but Python's stdlib sqlite3 module always is:
.venv\Scripts\python.exe -c "import sqlite3; c=sqlite3.connect('fieldos_dev.db'); print(c.execute('SELECT * FROM projects LIMIT 5').fetchall())"
# Packaged app's real DB path: see fieldos/paths.py (OS app-data dir)

# Check what's listening on a port (Windows)
netstat -ano | findstr :8000
netstat -ano | findstr :3000

# Disk space / memory: use Task Manager, or:
Get-PSDrive C
```

## Getting Help

1. Check logs first: the terminal running the backend, browser DevTools for
   the frontend, `flutter run`'s console for the mobile app
2. Search existing issues in repo
3. Create minimal reproduction
4. Include: OS, Python/Node/Flutter versions, error stack trace, steps to reproduce