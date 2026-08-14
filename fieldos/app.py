from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from fieldos.routers import (
    auth,
    companies,
    dashboard,
    dpr,
    estimation,
    issues,
    portability,
    projects,
    settings,
    tasks,
)


# The only legitimate callers of this loopback-bound API: the Tauri webview
# (tauri://localhost on macOS/Linux, https://tauri.localhost on Windows --
# WebView2 doesn't support custom URI schemes the same way) and the Next.js
# dev server. A wildcard here would let ANY website open in the user's
# browser call the unauthenticated /auth/register and /auth/login endpoints
# cross-origin and read the response (username enumeration, credential
# stuffing) -- loopback binding alone doesn't stop that without CORS scoping.
ALLOWED_ORIGINS = [
    "tauri://localhost",
    "https://tauri.localhost",
    "http://localhost:3000",
]


def create_fieldos_app() -> FastAPI:
    app = FastAPI(title="FieldOS")
    app.add_middleware(
        CORSMiddleware,
        allow_origins=ALLOWED_ORIGINS,
        allow_methods=["*"],
        allow_headers=["*"],
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
    return app
