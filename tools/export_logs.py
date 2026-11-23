"""Keeps a one-year copy of the Supabase server logs, in India.

Why: the Supabase plan keeps logs for one day. CERT-In's directions
(28 April 2022) ask for ICT system logs kept for 180 days within India, and
the DPDP Rules 2025 ask a data fiduciary to keep logs of access to personal
data for a year. This copies them, every 6 hours, into the private
`system-logs` Storage bucket of the same (Mumbai) project, and deletes
copies older than KEEP_DAYS. See docs/INCIDENT_RESPONSE.md.

Run by .github/workflows/system-logs.yml. Needs:
  SUPABASE_URL           https://<ref>.supabase.co
  SUPABASE_ACCESS_TOKEN  Management API token: reads the logs
  SUPABASE_SERVICE_KEY   service role key: writes the bucket (fetched at run
                         time by the workflow, never stored)

One gzip JSON-lines file per source per 6-hour slot:
  system-logs/<source>/YYYY/MM/DD/HH.jsonl.gz
A slot already in the bucket is skipped, so a re-run, or a run after a
missed one, only fills the gaps that Supabase still has.

Standard library only.
"""

import datetime as dt
import gzip
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

BUCKET = "system-logs"
SOURCES = ["edge_logs", "auth_logs", "postgres_logs", "function_edge_logs", "function_logs"]
SLOT_HOURS = 6
# Supabase keeps a day; slots older than this are not tried again.
LOOKBACK_HOURS = 24
KEEP_DAYS = 400
# Rows per query. A window that comes back full is split in two.
PAGE = 1000
MIN_WINDOW = dt.timedelta(seconds=30)
MGMT = os.environ.get("SUPABASE_MANAGEMENT_API", "https://api.supabase.com")
# The Management API's logs endpoint rate-limits hard (HTTP 429 after about
# ten quick queries). Space log queries out, and wait longer on a 429.
LOG_GAP_SECONDS = float(os.environ.get("LOG_GAP_SECONDS", "6"))


def utc(s):
    return s.astimezone(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")


def _wait(code, headers, attempt):
    """Seconds to wait before retry `attempt`: Retry-After on a 429, else backoff."""
    if code == 429:
        try:
            return max(1.0, min(120.0, float((headers or {}).get("Retry-After", ""))))
        except ValueError:
            return min(120.0, 15.0 * 2 ** attempt)
    return 2 ** attempt * 5


def call(url, method="GET", body=None, headers=None, raw=None, tries=4):
    data = raw if raw is not None else (None if body is None else json.dumps(body).encode())
    for attempt in range(tries):
        req = urllib.request.Request(url, data=data, method=method, headers=dict(headers or {}))
        if body is not None:
            req.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                text = r.read().decode() or "null"
                return r.status, json.loads(text) if text.strip()[:1] in "[{n" else text
        except urllib.error.HTTPError as e:
            detail = e.read().decode()[:300]
            if e.code in (429, 500, 502, 503, 504) and attempt < tries - 1:
                time.sleep(_wait(e.code, e.headers, attempt))
                continue
            return e.code, detail
        except urllib.error.URLError:
            if attempt < tries - 1:
                time.sleep(2 ** attempt * 5)
                continue
            raise
    raise RuntimeError("unreachable")


class Supabase:
    def __init__(self, url, token, service_key):
        self.url = url.rstrip("/")
        self.ref = urllib.parse.urlparse(self.url).hostname.split(".")[0]
        self.token = token
        self.key = service_key
        self._last_log_call = 0.0

    # -- logs (Management API) --
    def logs(self, source, start, end):
        sql = (
            "select id, timestamp, event_message, log_attributes from logs "
            f"where source = '{source}' order by timestamp asc limit {PAGE}"
        )
        q = urllib.parse.urlencode({"sql": sql, "iso_timestamp_start": utc(start), "iso_timestamp_end": utc(end)})
        gap = LOG_GAP_SECONDS - (time.monotonic() - self._last_log_call)
        if gap > 0:
            time.sleep(gap)
        try:
            code, data = call(
                f"{MGMT}/v1/projects/{self.ref}/analytics/endpoints/logs?{q}",
                headers={"Authorization": f"Bearer {self.token}"},
                tries=6,
            )
        finally:
            self._last_log_call = time.monotonic()
        if code != 200 or not isinstance(data, dict):
            raise RuntimeError(f"logs {source} {utc(start)}: HTTP {code} {str(data)[:200]}")
        if data.get("error"):
            raise RuntimeError(f"logs {source} {utc(start)}: {str(data['error'])[:200]}")
        return data.get("result") or []

    # -- storage (service role) --
    def _h(self, extra=None):
        h = {"Authorization": f"Bearer {self.key}", "apikey": self.key}
        h.update(extra or {})
        return h

    def list(self, prefix):
        """Names directly under prefix (folders end without a dot)."""
        out, offset = [], 0
        while True:
            code, data = call(
                f"{self.url}/storage/v1/object/list/{BUCKET}",
                method="POST",
                body={"prefix": prefix, "limit": 1000, "offset": offset, "sortBy": {"column": "name", "order": "asc"}},
                headers=self._h(),
            )
            if code != 200:
                raise RuntimeError(f"list {prefix}: HTTP {code} {str(data)[:200]}")
            out += [d["name"] for d in data]
            if len(data) < 1000:
                return out
            offset += 1000

    def exists(self, path):
        folder, name = path.rsplit("/", 1)
        return name in self.list(folder + "/")

    def upload(self, path, blob):
        code, data = call(
            f"{self.url}/storage/v1/object/{BUCKET}/{path}",
            method="POST",
            raw=blob,
            headers=self._h({"Content-Type": "application/gzip", "x-upsert": "false"}),
        )
        if code not in (200, 201):
            raise RuntimeError(f"upload {path}: HTTP {code} {str(data)[:200]}")

    def remove(self, paths):
        for i in range(0, len(paths), 500):
            code, data = call(
                f"{self.url}/storage/v1/object/{BUCKET}",
                method="DELETE",
                body={"prefixes": paths[i : i + 500]},
                headers=self._h(),
            )
            if code != 200:
                raise RuntimeError(f"delete: HTTP {code} {str(data)[:200]}")

    def drain_cleanup(self):
        """Removes queued files (deleted accounts, verified check-in selfies)."""
        code, data = call(f"{self.url}/functions/v1/account-cleanup", method="POST", body={}, headers=self._h())
        return code, data


def fetch_window(sb, source, start, end):
    rows = sb.logs(source, start, end)
    if len(rows) < PAGE or end - start <= MIN_WINDOW:
        if len(rows) >= PAGE:
            print(f"::warning::{source} {utc(start)}: more than {PAGE} rows in {MIN_WINDOW}; kept the first {PAGE}")
        return rows
    mid = start + (end - start) / 2
    return fetch_window(sb, source, start, mid) + fetch_window(sb, source, mid, end)


def slots(now):
    """Complete 6-hour slots that Supabase should still hold, oldest first."""
    top = now.replace(minute=0, second=0, microsecond=0, hour=now.hour - now.hour % SLOT_HOURS)
    out, s = [], top - dt.timedelta(hours=SLOT_HOURS)
    while s >= now - dt.timedelta(hours=LOOKBACK_HOURS):
        out.append(s)
        s -= dt.timedelta(hours=SLOT_HOURS)
    return list(reversed(out))


def slot_path(source, s):
    return f"{source}/{s:%Y/%m/%d/%H}.jsonl.gz"


def export(sb, now):
    written = 0
    for s in slots(now):
        for source in SOURCES:
            path = slot_path(source, s)
            if sb.exists(path):
                continue
            rows = fetch_window(sb, source, s, s + dt.timedelta(hours=SLOT_HOURS))
            seen, lines = set(), []
            for r in rows:
                if r.get("id") in seen:
                    continue
                seen.add(r.get("id"))
                lines.append(json.dumps(r, separators=(",", ":"), ensure_ascii=False, default=str))
            blob = gzip.compress(("\n".join(lines) + ("\n" if lines else "")).encode(), mtime=0)
            sb.upload(path, blob)
            written += 1
            print(f"{path}: {len(lines)} rows, {len(blob)} bytes")
    return written


def purge(sb, now, keep_days=KEEP_DAYS):
    """Deletes day folders older than keep_days. Returns files removed."""
    cutoff = (now - dt.timedelta(days=keep_days)).date()
    old = []
    for source in SOURCES:
        for y in sb.list(f"{source}/"):
            if not y.isdigit():
                continue
            for m in sb.list(f"{source}/{y}/"):
                for d in sb.list(f"{source}/{y}/{m}/"):
                    try:
                        day = dt.date(int(y), int(m), int(d))
                    except ValueError:
                        continue
                    if day < cutoff:
                        old += [f"{source}/{y}/{m}/{d}/{f}" for f in sb.list(f"{source}/{y}/{m}/{d}/")]
    if old:
        sb.remove(old)
    return len(old)


def main():
    sb = Supabase(os.environ["SUPABASE_URL"], os.environ["SUPABASE_ACCESS_TOKEN"], os.environ["SUPABASE_SERVICE_KEY"])
    now = dt.datetime.now(dt.timezone.utc)
    failed = False
    try:
        n = export(sb, now)
        print(f"Exported {n} new slot files.")
    except Exception as e:  # keep going: purge and cleanup still matter
        print(f"::error::export failed: {e}")
        failed = True
    try:
        print(f"Removed {purge(sb, now)} files older than {KEEP_DAYS} days.")
    except Exception as e:
        print(f"::error::purge failed: {e}")
        failed = True
    code, data = sb.drain_cleanup()
    print(f"account-cleanup: HTTP {code} {str(data)[:200]}")
    if code != 200:
        print("::warning::account-cleanup did not finish; queued files are retried on the next run")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
