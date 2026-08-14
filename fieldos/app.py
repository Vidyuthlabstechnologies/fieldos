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


def create_fieldos_app() -> FastAPI:
    app = FastAPI(title="FieldOS")
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
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
