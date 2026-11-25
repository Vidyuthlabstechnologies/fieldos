"""tools/db_backup.py is the safety net while the Supabase plan has no backups
of its own. The ways it can go wrong silently are the ones tested here: it
uploads an empty or cut-short dump and calls it a backup, it writes something
that cannot be opened again, or its clean-up deletes backups it should keep
(or files that are not its own).
"""

import datetime as dt
import importlib.util
import io
import json
import shutil
import sys
import tarfile
from pathlib import Path

import pytest

_SPEC = importlib.util.spec_from_file_location(
    "db_backup", Path(__file__).parent.parent / "tools" / "db_backup.py")
db = importlib.util.module_from_spec(_SPEC)
sys.modules["db_backup"] = db
_SPEC.loader.exec_module(db)

UTC = dt.timezone.utc
NOW = dt.datetime(2026, 11, 26, 21, 30, tzinfo=UTC)
PASS = "a-long-random-test-passphrase-123"

pytestmark = pytest.mark.skipif(shutil.which("openssl") is None, reason="openssl is not installed")


def good_dump(tmp_path):
    (tmp_path / "schema.sql").write_text('CREATE TABLE IF NOT EXISTS "public"."companies" (id uuid);\n' + "-- pad\n" * 1000)
    (tmp_path / "data.sql").write_text('COPY "public"."companies" (id) FROM stdin;\n' + "x" * 300 + "\n\\.\n")
    (tmp_path / "roles.sql").write_text("CREATE ROLE app;\nALTER ROLE app WITH LOGIN;\n")
    return str(tmp_path)


class FakeStorage:
    def __init__(self, existing=None, stored_size=None):
        self.objects = {n: b"old" for n in (existing or [])}
        self.removed = []
        self.stored_size = stored_size
        self.bucket_checked = False

    def ensure_bucket(self):
        self.bucket_checked = True

    def put(self, name, data):
        self.objects[name] = data

    def size_of(self, name):
        return self.stored_size if self.stored_size is not None else len(self.objects[name])

    def list_all(self):
        return list(self.objects)

    def remove(self, names):
        self.removed += names
        for n in names:
            self.objects.pop(n, None)


def test_a_real_dump_passes_and_comes_back_byte_for_byte(tmp_path):
    files = db.check_dump(good_dump(tmp_path))
    blob = db.encrypt(db.pack(files, NOW), PASS)
    assert blob.startswith(b"Salted__")
    tar = tarfile.open(fileobj=io.BytesIO(db.decrypt(blob, PASS)), mode="r:gz")
    assert set(tar.getnames()) == {"schema.sql", "data.sql", "roles.sql", "manifest.json"}
    assert tar.extractfile("data.sql").read() == files["data.sql"]
    manifest = json.load(tar.extractfile("manifest.json"))
    assert manifest["made_at"] == "2026-11-26T21:30:00Z"
    assert manifest["files"]["data.sql"]["bytes"] == len(files["data.sql"])


def test_a_wrong_passphrase_never_yields_a_readable_backup(tmp_path):
    blob = db.encrypt(db.pack(db.check_dump(good_dump(tmp_path)), NOW), PASS)
    try:
        out = db.decrypt(blob, "another-long-random-passphrase-xyz")
    except db.BackupError:
        return
    with pytest.raises(tarfile.TarError):
        tarfile.open(fileobj=io.BytesIO(out), mode="r:gz").getnames()


def test_a_short_passphrase_is_refused():
    with pytest.raises(db.BackupError, match="20 characters"):
        db.encrypt(b"data", "short")


@pytest.mark.parametrize("name,text,message", [
    ("data.sql", "", "only 0 bytes"),
    ("schema.sql", "CREATE TABLE x (id int);" * 400, "does not contain"),
    ("data.sql", "-- empty dump " + "." * 400, "does not contain"),
])
def test_an_empty_or_foreign_dump_is_not_uploaded(tmp_path, name, text, message):
    d = good_dump(tmp_path)
    (tmp_path / name).write_text(text)
    with pytest.raises(db.BackupError, match=message):
        db.check_dump(d)


def test_a_missing_file_is_refused(tmp_path):
    d = good_dump(tmp_path)
    (tmp_path / "roles.sql").unlink()
    with pytest.raises(db.BackupError, match="roles.sql is missing"):
        db.check_dump(d)


def test_run_uploads_once_under_a_dated_name_and_checks_the_stored_size(tmp_path):
    st = FakeStorage()
    name, size, parts = db.run(good_dump(tmp_path), "u", "k", PASS, now=NOW, storage=st)
    assert name == "2026/11/26/fieldos-20261126T213000Z.tar.gz.enc"
    assert st.bucket_checked and list(st.objects) == [name] and size == len(st.objects[name])
    assert parts["data.sql"] > 300


def test_a_truncated_upload_fails_loudly(tmp_path):
    with pytest.raises(db.BackupError, match="does not match"):
        db.run(good_dump(tmp_path), "u", "k", PASS, now=NOW, storage=FakeStorage(stored_size=10))


def test_clean_up_keeps_35_days_and_leaves_foreign_files_alone():
    names = [
        "2026/10/21/fieldos-20261021T213000Z.tar.gz.enc",   # 36 days: goes
        "2026/10/22/fieldos-20261022T213000Z.tar.gz.enc",   # 35 days: stays
        "2026/11/26/fieldos-20261126T213000Z.tar.gz.enc",
        "2026/09/01/notes.txt",                              # not ours
        "2026/13/40/fieldos-x.tar.gz.enc",                   # not a date
        "readme",
    ]
    assert db.old_names(names, NOW) == ["2026/10/21/fieldos-20261021T213000Z.tar.gz.enc"]


def test_run_prunes_old_backups_but_never_the_one_just_written(tmp_path):
    old = "2026/09/01/fieldos-20260901T213000Z.tar.gz.enc"
    st = FakeStorage(existing=[old])
    name, _, _ = db.run(good_dump(tmp_path), "u", "k", PASS, now=NOW, storage=st)
    assert st.removed == [old] and name in st.objects
