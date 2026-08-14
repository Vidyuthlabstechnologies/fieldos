import desktop_app
from fieldos import paths
from sqlalchemy import create_engine, inspect


def test_run_migrations_creates_all_tables(tmp_path):
    db_path = tmp_path / "fresh.db"
    database_url = f"sqlite:///{db_path}"

    desktop_app.run_migrations(database_url)

    assert db_path.exists()
    tables = set(inspect(create_engine(database_url)).get_table_names())
    assert {"companies", "projects", "tasks", "users", "sessions", "estimations"} <= tables


def test_run_migrations_is_idempotent_on_an_already_migrated_db(tmp_path):
    db_path = tmp_path / "fresh.db"
    database_url = f"sqlite:///{db_path}"

    desktop_app.run_migrations(database_url)
    desktop_app.run_migrations(database_url)  # must not raise

    assert db_path.exists()


def test_create_app_uses_the_app_data_directory_and_boots(tmp_path, monkeypatch):
    monkeypatch.setattr(paths, "user_data_dir", lambda *a, **k: str(tmp_path))

    app = desktop_app.create_app()

    assert app.title == "FieldOS"
    assert (tmp_path / "fieldos.db").exists()
