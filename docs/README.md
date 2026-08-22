# FieldOS Documentation Index

Welcome to the FieldOS documentation. This directory contains comprehensive guides for developing, testing, deploying, and troubleshooting the FieldOS construction site management platform.

## Documentation Structure

| Document | Description | Audience |
|----------|-------------|----------|
| [PROJECT_OVERVIEW.md](./PROJECT_OVERVIEW.md) | High-level project description, features, tech stack | All |
| [DEVELOPMENT.md](./DEVELOPMENT.md) | Setup, workflow, adding features | Developers |
| [DATABASE_SCHEMA.md](./DATABASE_SCHEMA.md) | Complete SQL schema with relationships | Backend devs, DBAs |
| [API_REFERENCE.md](./API_REFERENCE.md) | All REST endpoints, WebSocket, auth | Frontend/mobile devs |
| [FRONTEND_ARCHITECTURE.md](./FRONTEND_ARCHITECTURE.md) | Next.js patterns, components, state, styling | Frontend devs |
| [MOBILE_GUIDE.md](./MOBILE_GUIDE.md) | Native Flutter mobile app setup | Mobile devs |
| [DEPLOYMENT.md](./DEPLOYMENT.md) | How FieldOS actually ships: an offline Windows desktop installer, no server | Everyone building/packaging FieldOS |
| [TESTING.md](./TESTING.md) | Unit, integration, E2E, mobile testing | QA, Developers |
| [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) | Common issues and solutions | All |

## Quick Links

### Getting Started
1. [Development Setup](./DEVELOPMENT.md#quick-start)
2. [Backend API Docs](http://localhost:8000/docs) (when running)
3. [Frontend Dev Server](http://localhost:3000) (when running)

### Key Features
- [Dashboard](./PROJECT_OVERVIEW.md#1-project-dashboard)
- [Materials Tracking](./PROJECT_OVERVIEW.md#2-materials-tracking)
- [Equipment Management](./PROJECT_OVERVIEW.md#3-equipment-management)
- [Procurement Workflow](./PROJECT_OVERVIEW.md#4-procurement-workflow)
- [Inspections & Quality](./PROJECT_OVERVIEW.md#5-inspections--quality)
- [Estimations/BOQ](./PROJECT_OVERVIEW.md#6-estimations--boq)
- [Documents](./PROJECT_OVERVIEW.md#7-documents)
- [Workers & Attendance](./PROJECT_OVERVIEW.md#8-workers--attendance)
- [Real-time Collaboration](./PROJECT_OVERVIEW.md#9-real-time-collaboration)
- [Billing (not yet wired to anything real)](./PROJECT_OVERVIEW.md#10-billing-present-in-code-not-currently-wired-to-anything-real)

### Mobile Development
- [Flutter app setup](./MOBILE_GUIDE.md#setup)
- [Features implemented](./MOBILE_GUIDE.md#features-implemented-today)
- [Known gap: no backend sync yet](./MOBILE_GUIDE.md#️-known-architectural-gap-no-backend-sync)

### Building & Packaging
- [Architecture](./DEPLOYMENT.md#architecture)
- [Backend → PyInstaller executable](./DEPLOYMENT.md#1-backend--single-executable-pyinstaller)
- [Frontend → static export](./DEPLOYMENT.md#2-frontend--static-export)
- [Installer (Tauri)](./DEPLOYMENT.md#3-installer-tauri)

## Architecture Diagrams

```
┌─────────────────────────────────────────────────────────────────┐
│                        FIELDOS ARCHITECTURE                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                    │
│  Desktop (the shipped product):                                  │
│    Tauri shell → loads frontend/out (Next.js static export)      │
│      + spawns a PyInstaller-bundled FastAPI backend as a          │
│        loopback-only sidecar process                              │
│      → SQLite (local file, OS app-data directory)                 │
│                                                                    │
│  Mobile (fieldos_mobile/, native Flutter):                        │
│    entirely standalone today -- own local auth, own drift/SQLite  │
│    database, NO connection to the FastAPI backend above           │
│                                                                    │
│  No server, no PostgreSQL, no Redis, no CDN. See DEPLOYMENT.md.   │
│                                                                    │
└─────────────────────────────────────────────────────────────────┘
```

## Contributing

1. Read [DEVELOPMENT.md](./DEVELOPMENT.md) for workflow
2. Follow [API conventions](./API_REFERENCE.md)
3. Write tests (see [TESTING.md](./TESTING.md))
4. Update relevant documentation
5. Run the real test suites before committing: `.venv\Scripts\python.exe -m pytest tests/` and `cd frontend && npm test` (there is currently no linter/formatter configured for either side of the project — see DEVELOPMENT.md's "Common Commands" section before assuming one exists)

## Support

- **Issues**: GitHub Issues
- **Logs**: Backend prints to stdout/stderr of whatever process runs it (`uvicorn`/the packaged `.exe`); frontend errors show in Browser DevTools. There's no systemd service and no `adb logcat` target — this isn't an Android-hosted backend.
- **Debug**: See [TROUBLESHOOTING.md](./TROUBLESHOOTING.md)

## License

Proprietary - FieldOS Construction Management Platform