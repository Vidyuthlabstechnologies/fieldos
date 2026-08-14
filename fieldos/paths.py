"""OS-appropriate storage location for the packaged desktop app.

Not used by the dev workflow (fieldos/config.py's relative fieldos_dev.db
default is fine there) -- this is for desktop_app.py, the entrypoint that
gets bundled into the installable executable, where the working directory
can't be relied on to be writable or stable.
"""

from pathlib import Path

from platformdirs import user_data_dir

APP_NAME = "FieldOS"
APP_AUTHOR = "Predictera"


def app_data_dir() -> Path:
    path = Path(user_data_dir(APP_NAME, APP_AUTHOR, roaming=False))
    path.mkdir(parents=True, exist_ok=True)
    return path


def database_path() -> Path:
    return app_data_dir() / "fieldos.db"
