from fastapi import FastAPI

from fieldos.routers import companies, projects, tasks


def create_fieldos_app() -> FastAPI:
    app = FastAPI(title="FieldOS")
    app.include_router(companies.router)
    app.include_router(projects.router)
    app.include_router(tasks.router)
    return app
