from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from fieldos.routers import companies, dashboard, dpr, estimation, issues, projects, tasks


def create_fieldos_app() -> FastAPI:
    app = FastAPI(title="FieldOS")
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_methods=["*"],
        allow_headers=["*"],
    )
    app.include_router(companies.router)
    app.include_router(projects.router)
    app.include_router(tasks.router)
    app.include_router(dpr.router)
    app.include_router(issues.router)
    app.include_router(dashboard.router)
    app.include_router(estimation.router)
    return app
