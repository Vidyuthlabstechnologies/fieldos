"""workers.daily_wage cannot be read by app users (20261128120000): select on
the table is revoked and only listed columns are granted. So a column added to
workers later is unreadable until it is granted too, and the phone, which pulls
workers by an explicit column list, would fail on it or silently go without.
These tests fail the build before that reaches a phone.
"""

import re
from pathlib import Path

ROOT = Path(__file__).parent.parent
MIGRATIONS = sorted((ROOT / "supabase" / "migrations").glob("*.sql"))
WAGE = "daily_wage"


def _read(p: Path) -> str:
    return re.sub(r"--[^\n]*", "", p.read_text(encoding="utf-8"))


def _columns_of_workers() -> set[str]:
    """Every column workers has once all migrations are applied (static read)."""
    cols: set[str] = set()
    for m in MIGRATIONS:
        text = _read(m)
        create = re.search(r"create table (?:if not exists )?(?:public\.)?workers\s*\((.*?)\n\);", text, re.S | re.I)
        if create:
            for line in create.group(1).splitlines():
                line = line.strip().rstrip(",")
                first = line.split()[0] if line else ""
                if first and first.lower() not in {"primary", "unique", "check", "constraint", "foreign"}:
                    cols.add(first.strip('"'))
        for add in re.finditer(r"alter table (?:if exists )?(?:public\.)?workers\s+(.*?);", text, re.S | re.I):
            for col in re.finditer(r"add column (?:if not exists )?\"?(\w+)\"?", add.group(1), re.I):
                cols.add(col.group(1))
    return cols


def _granted_columns() -> set[str]:
    granted: set[str] = set()
    for m in MIGRATIONS:
        for g in re.finditer(r"grant select\s*\(([^)]*)\)\s*on (?:table )?(?:public\.)?workers\s+to authenticated", _read(m), re.I):
            granted |= {c.strip().strip('"') for c in g.group(1).split(",") if c.strip()}
    return granted


def test_the_wage_read_is_closed_by_a_migration():
    revoke = [m.name for m in MIGRATIONS if re.search(r"revoke select on (?:table )?(?:public\.)?workers from authenticated", _read(m), re.I)]
    assert revoke, "no migration revokes select on workers; the wage is readable by every site member"


def test_every_workers_column_but_the_wage_is_granted():
    missing = _columns_of_workers() - _granted_columns() - {WAGE}
    assert not missing, (
        f"workers columns with no read grant: {sorted(missing)}. Select on workers is revoked, so they cannot be read. "
        "Add: grant select (<column>) on workers to authenticated;"
    )


def test_the_wage_itself_is_never_granted():
    assert WAGE not in _granted_columns(), "daily_wage must be read only through worker_wage_rates()"


def test_the_phone_pulls_workers_by_exactly_the_granted_columns():
    engine = (ROOT / "fieldos_mobile" / "lib" / "sync" / "sync_engine.dart").read_text(encoding="utf-8")
    m = re.search(r"pullColumns\s*=\s*\{\s*'workers':\s*'([^']*)'", engine)
    assert m, "SyncEngine.pullColumns for workers was not found"
    pulled = {c.strip() for c in m.group(1).split(",")}
    assert WAGE not in pulled, "the phone must not ask workers for the wage column"
    granted = _granted_columns()
    assert pulled <= granted, f"the phone pulls columns it cannot read: {sorted(pulled - granted)}"
    assert granted <= pulled | set(), f"granted but not pulled (the phone would never see them): {sorted(granted - pulled)}"


def test_a_migration_that_adds_a_workers_column_without_a_grant_is_caught(tmp_path, monkeypatch):
    sql = tmp_path / "20990101000000_add_col.sql"
    sql.write_text("alter table workers add column blood_group text;\n", encoding="utf-8")
    monkeypatch.setitem(globals(), "MIGRATIONS", sorted([*MIGRATIONS, sql]))
    assert "blood_group" in _columns_of_workers()
    assert "blood_group" not in _granted_columns()
