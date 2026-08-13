from fastapi import FastAPI

from fieldos.routers import companies


def create_fieldos_app() -> FastAPI:
    app = FastAPI(title="FieldOS")
    app.include_router(companies.router)
    return app
