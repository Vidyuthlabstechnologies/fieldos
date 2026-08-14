from fieldos import paths


def test_app_data_dir_creates_and_returns_the_directory(tmp_path, monkeypatch):
    target = tmp_path / "Predictera" / "FieldOS"
    monkeypatch.setattr(paths, "user_data_dir", lambda *a, **k: str(target))

    result = paths.app_data_dir()

    assert result == target
    assert target.is_dir()


def test_database_path_is_inside_the_app_data_dir(tmp_path, monkeypatch):
    monkeypatch.setattr(paths, "user_data_dir", lambda *a, **k: str(tmp_path))

    result = paths.database_path()

    assert result == tmp_path / "fieldos.db"
