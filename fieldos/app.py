from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from fieldos.routers import (
    auth,
    billing,
    companies,
    dashboard,
    documents,
    dpr,
    equipment,
    estimation,
    inspections,
    issues,
    materials,
    portability,
    procurement,
    projects,
    realtime,
    settings,
    tasks,
    uploads,
    workers,
)


# The only legitimate callers of this loopback-bound API: the Tauri webview
# and the Next.js dev server. A wildcard here would let ANY website open in
# the user's browser call the unauthenticated /auth/register and
# /auth/login endpoints cross-origin and read the response (username
# enumeration, credential stuffing) -- loopback binding alone doesn't stop
# that without CORS scoping.
#
# tauri://localhost is macOS/Linux's custom-protocol origin. Windows/WebView2
# serves the webview from tauri.localhost instead, and -- verified against
# Tauri's own default HTTP-headers config, not assumed -- over plain HTTP,
# not HTTPS (WebView2 had mixed-content issues with https://tauri.localhost
# talking to a plain http:// loopback backend, so Tauri defaults it to http
# on Windows: https://v2.tauri.app/security/http-headers/). Getting this
# scheme wrong silently breaks every request from the real installed app.
ALLOWED_ORIGINS = [
    "tauri://localhost",
    "http://tauri.localhost",
    "https://tauri.localhost",
    "http://localhost:3000",
]


def create_fieldos_app() -> FastAPI:
    app = FastAPI(title="FieldOS")
    app.add_middleware(
        CORSMiddleware,
        allow_origins=ALLOWED_ORIGINS,
        allow_methods=["GET", "POST", "PATCH", "DELETE", "PUT"],
        allow_headers=["Authorization", "Content-Type"],
    )
    app.include_router(auth.router)
    app.include_router(companies.router)
    app.include_router(projects.router)
    app.include_router(tasks.router)
    app.include_router(dpr.router)
    app.include_router(issues.router)
    app.include_router(dashboard.router)
    app.include_router(estimation.router)
    app.include_router(portability.router)
    app.include_router(settings.router)
    app.include_router(materials.router)
    app.include_router(workers.router)
    app.include_router(workers._attendance_router)
    app.include_router(documents.router)
    app.include_router(procurement.router)
    app.include_router(equipment.router)
    app.include_router(inspections.router)
    app.include_router(realtime.router)
    app.include_router(uploads.router)
    app.include_router(billing.router)
    return app
