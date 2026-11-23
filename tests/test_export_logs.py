"""tools/export_logs.py keeps the one-year copy of the server logs that the
CERT-In directions and the DPDP Rules ask for. A slot it skips is lost for
good once Supabase drops it after a day, and a purge that goes too far
deletes logs that must still be producible, so both get tests here.
"""

import datetime as dt
import gzip
import importlib.util
import json
import sys
from pathlib import Path

_SPEC = importlib.util.spec_from_file_location(
    "export_logs", Path(__file__).parent.parent / "tools" / "export_logs.py")
el = importlib.util.module_from_spec(_SPEC)
sys.modules["export_logs"] = el
_SPEC.loader.exec_module(el)

UTC = dt.timezone.utc


class FakeSupabase:
    def __init__(self, rows_by_source=None, files=None):
        self.rows = rows_by_source or {}
        self.files = dict(files or {})
        self.queries = []

    def logs(self, source, start, end):
        self.queries.append((source, start, end))
        rows = [r for r in self.rows.get(source, []) if start <= r["ts"] < end]
        return [{"id": r["id"], "timestamp": r["ts"].isoformat(), "event_message": r["msg"]} for r in rows][: el.PAGE]

    def list(self, prefix):
        names = set()
        for p in self.files:
            if p.startswith(prefix):
                names.add(p[len(prefix):].split("/")[0])
        return sorted(names)

    def exists(self, path):
        return path in self.files

    def upload(self, path, blob):
        assert path not in self.files, "never overwrite a slot"
        self.files[path] = blob

    def remove(self, paths):
        for p in paths:
            del self.files[p]


def test_slots_are_complete_and_within_a_day():
    now = dt.datetime(2026, 11, 23, 13, 40, tzinfo=UTC)
    got = el.slots(now)
    assert got == [
        dt.datetime(2026, 11, 22, 18, tzinfo=UTC),
        dt.datetime(2026, 11, 23, 0, tzinfo=UTC),
        dt.datetime(2026, 11, 23, 6, tzinfo=UTC),
    ]
    # The slot still running (12:00 to 18:00) is never written half full.
    assert all(s + dt.timedelta(hours=6) <= now for s in got)
    assert all(s >= now - dt.timedelta(hours=24) for s in got)


def test_export_writes_each_slot_once_and_skips_existing():
    now = dt.datetime(2026, 11, 23, 6, 30, tzinfo=UTC)
    t = dt.datetime(2026, 11, 23, 1, 0, tzinfo=UTC)
    sb = FakeSupabase({"edge_logs": [{"id": "a", "ts": t, "msg": "GET /rest/v1/x 200"}]})
    n = el.export(sb, now)
    assert n == len(el.slots(now)) * len(el.SOURCES)
    blob = sb.files["edge_logs/2026/11/23/00.jsonl.gz"]
    lines = gzip.decompress(blob).decode().splitlines()
    assert [json.loads(x)["id"] for x in lines] == ["a"]
    # A second run finds every slot already there and queries nothing.
    sb.queries.clear()
    assert el.export(sb, now) == 0
    assert sb.queries == []


def test_full_window_is_split_until_every_row_is_read(monkeypatch):
    monkeypatch.setattr(el, "PAGE", 10)
    start = dt.datetime(2026, 11, 23, 0, tzinfo=UTC)
    rows = [{"id": str(i), "ts": start + dt.timedelta(minutes=i), "msg": "x"} for i in range(35)]
    sb = FakeSupabase({"auth_logs": rows})
    got = el.fetch_window(sb, "auth_logs", start, start + dt.timedelta(hours=6))
    assert sorted(int(r["id"]) for r in got) == list(range(35))


def test_purge_keeps_400_days_and_nothing_else():
    now = dt.datetime(2026, 11, 23, 6, tzinfo=UTC)
    old = (now - dt.timedelta(days=401)).date()
    keep = (now - dt.timedelta(days=399)).date()
    files = {
        f"edge_logs/{old:%Y/%m/%d}/00.jsonl.gz": b"",
        f"edge_logs/{old:%Y/%m/%d}/06.jsonl.gz": b"",
        f"edge_logs/{keep:%Y/%m/%d}/00.jsonl.gz": b"",
        f"auth_logs/{keep:%Y/%m/%d}/00.jsonl.gz": b"",
    }
    sb = FakeSupabase(files=files)
    assert el.purge(sb, now) == 2
    assert sorted(sb.files) == sorted(f for f in files if f"{keep:%Y/%m/%d}" in f)
