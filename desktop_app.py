"""Entrypoint for the packaged desktop build (bundled into the installable
executable by PyInstaller -- see Task 25/26).

Unlike api.py (the dev entrypoint, which uses a relative fieldos_dev.db and
expects `alembic upgrade head` to have been run manually), this:
  - stores the database in the OS-appropriate per-user app-data directory,
    since a packaged app's working directory isn't reliably writable
  - runs migrations automatically on every startup, since there's no
    separate "install step" the end user runs

DATABASE_URL must be set (via fieldos.paths) BEFORE fieldos.config is
imported anywhere -- pydantic-settings reads the environment when the
Settings() singleton is constructed. create_app() below does this itself
rather than at module import time, so importing this module (e.g. from
tests) has no side effects -- run via `uvicorn desktop_app:create_app
--factory`, which calls create_app() lazily at server startup.
"""

import os
import sys
from pathlib import Path


def _alembic_script_location() -> str:
    # When frozen by PyInstaller, bundled data files live under sys._MEIPASS
    # rather than next to this script.
    base = Path(getattr(sys, "_MEIPASS", Path(__file__).parent))
    return str(base / "fieldos" / "alembic")


def run_migrations(database_url: str) -> None:
    from alembic import command
    from alembic.config import Config

    cfg = Config()
    cfg.set_main_option("script_location", _alembic_script_location())
    cfg.set_main_option("sqlalchemy.url", database_url)
    command.upgrade(cfg, "head")


def create_app():
    from fieldos.paths import database_path

    database_url = f"sqlite:///{database_path()}"
    os.environ["DATABASE_URL"] = database_url
    run_migrations(database_url)

    from fieldos.app import create_fieldos_app

    return create_fieldos_app()


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(create_app(), host="127.0.0.1", port=8000, log_level="info")
