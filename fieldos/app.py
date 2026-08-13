from fastapi import FastAPI

from fieldos.routers import companies, dashboard, dpr, estimation, issues, projects, tasks


def create_fieldos_app() -> FastAPI:
    app = FastAPI(title="FieldOS")
    app.include_router(companies.router)
    app.include_router(projects.router)
    app.include_router(tasks.router)
    app.include_router(dpr.router)
    app.include_router(issues.router)
    app.include_router(dashboard.router)
    app.include_router(estimation.router)
    return app
