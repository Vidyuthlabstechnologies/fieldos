from fastapi import FastAPI

from fieldos.routers import companies, dpr, issues, projects, tasks


def create_fieldos_app() -> FastAPI:
    app = FastAPI(title="FieldOS")
    app.include_router(companies.router)
    app.include_router(projects.router)
    app.include_router(tasks.router)
    app.include_router(dpr.router)
    app.include_router(issues.router)
    return app
