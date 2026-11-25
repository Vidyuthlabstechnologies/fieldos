"""Encrypted off-database copy of the production database.

Why: until the Supabase plan has daily backups (issue #148), a bad migration
or an accidental delete cannot be undone. Even with them, a logical copy we
control is a second line. `supabase db dump` writes schema.sql, data.sql and
roles.sql into DUMP_DIR; this checks they are real, packs them, encrypts
them with AES-256 and puts the result in the private `db-backups` Storage
bucket (Mumbai, same project), then deletes copies older than KEEP_DAYS.

It protects against mistakes inside the database. It does not protect
against losing the whole Supabase project, and the Storage files (photos,
bills, selfies) are not in it.

Run by .github/workflows/db-backup.yml. Needs:
  SUPABASE_URL         https://<ref>.supabase.co
  SUPABASE_SERVICE_KEY service role key, fetched at run time, never stored
  BACKUP_PASSPHRASE    repo secret; long and random. Lose it and the backups
                       cannot be opened, so keep a copy in the password manager
  DUMP_DIR             where schema.sql, data.sql and roles.sql are

Object name: db-backups/YYYY/MM/DD/fieldos-YYYYMMDDTHHMMSSZ.tar.gz.enc

Restore: docs/SUPABASE_PRODUCTION_RUNBOOK.md, "Restoring a backup".

Standard library only (and the openssl command).
"""

import datetime as dt
import hashlib
import io
import json
import os
import re
import subprocess
import sys
import tarfile
import urllib.error
import urllib.parse
import urllib.request

BUCKET = "db-backups"
KEEP_DAYS = 35
FILES = ["schema.sql", "data.sql", "roles.sql"]
# What a real dump of this database always contains. A file without it is a
# failed or partial dump, and uploading it would hide that.
COMPANIES = r'"?public"?\."?companies"?'
MUST_CONTAIN = {
    "schema.sql": [r"CREATE TABLE", COMPANIES],
    "data.sql": [r"COPY ", COMPANIES],
    "roles.sql": [r"ROLE"],
}
MIN_BYTES = {"schema.sql": 5_000, "data.sql": 200, "roles.sql": 20}
PBKDF2_ITERATIONS = "600000"


class BackupError(Exception):
    pass


def check_dump(dump_dir):
    """Returns {name: bytes}; raises BackupError for a missing, tiny or odd file."""
    out = {}
    for name in FILES:
        path = os.path.join(dump_dir, name)
        if not os.path.isfile(path):
            raise BackupError(f"{name} is missing from the dump")
        raw = open(path, "rb").read()
        if len(raw) < MIN_BYTES[name]:
            raise BackupError(f"{name} is only {len(raw)} bytes; the dump looks cut short")
        text = raw.decode("utf-8", errors="replace")
        for needle in MUST_CONTAIN[name]:
            if not re.search(needle, text):
                raise BackupError(f"{name} does not contain {needle!r}; not a real dump of this database")
        out[name] = raw
    return out


def pack(files, now):
    """One tar.gz in memory with the dump files and a manifest of their hashes."""
    manifest = {
        "made_at": now.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "files": {n: {"bytes": len(b), "sha256": hashlib.sha256(b).hexdigest()} for n, b in files.items()},
    }
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:gz") as tar:
        for name, data in {**files, "manifest.json": json.dumps(manifest, indent=1).encode()}.items():
            info = tarfile.TarInfo(name)
            info.size = len(data)
            info.mtime = int(now.timestamp())
            tar.addfile(info, io.BytesIO(data))
    return buf.getvalue()


def encrypt(data, passphrase):
    """AES-256-CBC with a salted PBKDF2 key, readable with plain openssl."""
    if len(passphrase) < 20:
        raise BackupError("BACKUP_PASSPHRASE must be at least 20 characters")
    proc = subprocess.run(
        ["openssl", "enc", "-aes-256-cbc", "-pbkdf2", "-iter", PBKDF2_ITERATIONS, "-salt", "-pass", "env:BACKUP_PASSPHRASE"],
        input=data, capture_output=True, env={**os.environ, "BACKUP_PASSPHRASE": passphrase},
    )
    if proc.returncode != 0 or not proc.stdout.startswith(b"Salted__"):
        raise BackupError("openssl could not encrypt the backup")
    return proc.stdout


def decrypt(data, passphrase):
    proc = subprocess.run(
        ["openssl", "enc", "-d", "-aes-256-cbc", "-pbkdf2", "-iter", PBKDF2_ITERATIONS, "-pass", "env:BACKUP_PASSPHRASE"],
        input=data, capture_output=True, env={**os.environ, "BACKUP_PASSPHRASE": passphrase},
    )
    if proc.returncode != 0:
        raise BackupError("wrong passphrase, or the file is damaged")
    return proc.stdout


def object_name(now):
    return f"{now:%Y/%m/%d}/fieldos-{now:%Y%m%dT%H%M%SZ}.tar.gz.enc"


def _request(base, key, method, path, body=None, raw=None, headers=None):
    data = raw if raw is not None else (None if body is None else json.dumps(body).encode())
    h = {"Authorization": f"Bearer {key}", "apikey": key, **(headers or {})}
    if body is not None:
        h["Content-Type"] = "application/json"
    req = urllib.request.Request(base + path, data=data, method=method, headers=h)
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            text = r.read().decode() or "null"
            return r.status, json.loads(text) if text.strip()[:1] in "[{n" else text
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()[:300]


class Storage:
    def __init__(self, url, key):
        self.base = url.rstrip("/") + "/storage/v1"
        self.key = key

    def ensure_bucket(self):
        code, body = _request(self.base, self.key, "POST", "/bucket", {"id": BUCKET, "name": BUCKET, "public": False})
        if code not in (200, 201, 400, 409):
            raise BackupError(f"could not create the {BUCKET} bucket: HTTP {code} {body}")
        code, body = _request(self.base, self.key, "GET", f"/bucket/{BUCKET}")
        if code != 200 or (isinstance(body, dict) and body.get("public")):
            raise BackupError(f"the {BUCKET} bucket must exist and be private (HTTP {code})")

    def put(self, name, data):
        path = f"/object/{BUCKET}/{urllib.parse.quote(name)}"
        code, body = _request(self.base, self.key, "POST", path, raw=data, headers={"Content-Type": "application/octet-stream"})
        if code not in (200, 201):
            raise BackupError(f"upload failed: HTTP {code} {body}")

    def size_of(self, name):
        path = f"/object/info/{BUCKET}/{urllib.parse.quote(name)}"
        code, body = _request(self.base, self.key, "GET", path)
        if code != 200 or not isinstance(body, dict):
            return None
        return int((body.get("metadata") or {}).get("size") or body.get("size") or 0)

    def list_all(self, prefix=""):
        """Every object name under prefix, walking the year/month/day folders."""
        found = []
        code, body = _request(self.base, self.key, "POST", f"/object/list/{BUCKET}",
                              {"prefix": prefix, "limit": 1000, "offset": 0})
        if code != 200 or not isinstance(body, list):
            raise BackupError(f"could not list {BUCKET}: HTTP {code} {body}")
        for item in body:
            full = f"{prefix}{item['name']}"
            if item.get("id") is None:
                found.extend(self.list_all(full + "/"))
            else:
                found.append(full)
        return found

    def remove(self, names):
        if not names:
            return
        code, body = _request(self.base, self.key, "DELETE", f"/object/{BUCKET}", {"prefixes": names})
        if code not in (200, 204):
            raise BackupError(f"could not delete old backups: HTTP {code} {body}")


def old_names(names, now, keep_days=KEEP_DAYS):
    """Backups whose folder date is older than keep_days. Anything that does not
    look like one of ours is left alone."""
    cutoff = (now - dt.timedelta(days=keep_days)).date()
    out = []
    for n in names:
        parts = n.split("/")
        if len(parts) != 4 or not parts[3].startswith("fieldos-") or not parts[3].endswith(".tar.gz.enc"):
            continue
        try:
            day = dt.date(int(parts[0]), int(parts[1]), int(parts[2]))
        except ValueError:
            continue
        if day < cutoff:
            out.append(n)
    return out


def run(dump_dir, url, key, passphrase, now=None, storage=None):
    now = now or dt.datetime.now(dt.timezone.utc)
    files = check_dump(dump_dir)
    blob = encrypt(pack(files, now), passphrase)
    st = storage or Storage(url, key)
    st.ensure_bucket()
    name = object_name(now)
    st.put(name, blob)
    stored = st.size_of(name)
    if stored != len(blob):
        raise BackupError(f"stored size {stored} does not match what was sent ({len(blob)} bytes)")
    st.remove(old_names(st.list_all(), now))
    return name, len(blob), {n: len(b) for n, b in files.items()}


def main():
    missing = [v for v in ("SUPABASE_URL", "SUPABASE_SERVICE_KEY", "BACKUP_PASSPHRASE", "DUMP_DIR") if not os.environ.get(v)]
    if missing:
        print("Missing: " + ", ".join(missing), file=sys.stderr)
        return 1
    try:
        name, size, parts = run(os.environ["DUMP_DIR"], os.environ["SUPABASE_URL"],
                                os.environ["SUPABASE_SERVICE_KEY"], os.environ["BACKUP_PASSPHRASE"])
    except BackupError as e:
        print(f"Backup FAILED: {e}", file=sys.stderr)
        return 1
    print(f"Backup written: {BUCKET}/{name} ({size:,} bytes encrypted)")
    for n, b in parts.items():
        print(f"  {n}: {b:,} bytes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
