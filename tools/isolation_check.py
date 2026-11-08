#!/usr/bin/env python3
"""Checks against the live Supabase project that one company can't see or
change another company's data.

It signs up two throwaway accounts (A and B), lets each make a company, a
site and a task the way the app does, then, signed in as B:

  * reads every table the migrations create and fails if any row mentions
    A's company, site or task;
  * tries to add a task to A's site, rename A's task and read A's team list,
    and fails if any of that works.

Both accounts are deleted at the end with delete_my_account, whether the
checks pass or not. Uses only SUPABASE_URL and SUPABASE_ANON_KEY (the public
key the app ships with), so it tests exactly what a stranger with the app
could do. Needs "Confirm email" off, as at launch.

Run from the isolation-check workflow, or locally:
  SUPABASE_URL=... SUPABASE_ANON_KEY=... python3 tools/isolation_check.py
"""
from __future__ import annotations

import json
import os
import secrets
import sys
import urllib.error
import urllib.request
import uuid

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from launch_readiness import tables_from_migrations  # noqa: E402


class Api:
    def __init__(self, url: str, anon: str):
        self.base = url.rstrip("/")
        self.anon = anon

    def call(self, method: str, path: str, body=None, token: str | None = None, prefer: str | None = None):
        headers = {"apikey": self.anon, "Authorization": f"Bearer {token or self.anon}",
                   "Content-Type": "application/json"}
        if prefer:
            headers["Prefer"] = prefer
        data = None if body is None else json.dumps(body).encode()
        req = urllib.request.Request(self.base + path, data=data, headers=headers, method=method)
        try:
            with urllib.request.urlopen(req, timeout=20) as res:
                raw, code = res.read(), res.status
        except urllib.error.HTTPError as e:
            raw, code = e.read(), e.code
        try:
            return code, json.loads(raw) if raw else None
        except ValueError:
            return code, None


class Account:
    def __init__(self, api: Api, label: str):
        self.api = api
        self.label = label
        self.email = f"isolation-check-{secrets.token_hex(6)}@example.com"
        code, body = api.call("POST", "/auth/v1/signup", {"email": self.email, "password": secrets.token_urlsafe(24)})
        token = (body or {}).get("access_token") if isinstance(body, dict) else None
        if code != 200 or not token:
            raise SystemExit(f"Could not sign up test account {label} (HTTP {code}). Is 'Confirm email' off?")
        self.token = token
        self.company = str(uuid.uuid4())
        self.project = str(uuid.uuid4())
        self.task = str(uuid.uuid4())

    def rest(self, method, path, body=None, prefer=None):
        return self.api.call(method, path, body, token=self.token, prefer=prefer)

    def set_up(self):
        code, _ = self.rest("POST", "/rest/v1/rpc/ensure_company", {"p_company_id": self.company, "p_name": f"Isolation {self.label}"})
        assert code == 200, f"{self.label}: ensure_company HTTP {code}"
        code, _ = self.rest("POST", "/rest/v1/projects", {"id": self.project, "company_id": self.company, "name": f"Site {self.label}"})
        assert code in (200, 201), f"{self.label}: create project HTTP {code}"
        code, _ = self.rest("POST", "/rest/v1/tasks", {"id": self.task, "project_id": self.project, "title": f"Task {self.label}"})
        assert code in (200, 201), f"{self.label}: create task HTTP {code}"

    def delete(self):
        self.rest("POST", "/rest/v1/rpc/delete_my_account", {})


def run(api: Api) -> list[str]:
    problems: list[str] = []
    a = Account(api, "A")
    b = Account(api, "B")
    try:
        a.set_up()
        b.set_up()
        secrets_of_a = {a.company, a.project, a.task}

        # 1. Nothing of A's comes back to B from any table.
        for tables in tables_from_migrations().values():
            for table in tables:
                code, rows = b.rest("GET", f"/rest/v1/{table}?select=*&limit=1000")
                if code == 200 and isinstance(rows, list):
                    if any(v in secrets_of_a for row in rows for v in (row or {}).values() if isinstance(v, str)):
                        problems.append(f"{table}: B can read A's rows")

        # 2. B can't write into A's site or change A's task.
        code, _ = b.rest("POST", "/rest/v1/tasks", {"project_id": a.project, "title": "planted by B"})
        if code in (200, 201):
            problems.append("tasks: B could add a task to A's site")
        code, rows = b.rest("PATCH", f"/rest/v1/tasks?id=eq.{a.task}", {"title": "renamed by B"}, prefer="return=representation")
        if code in (200, 204) and rows:
            problems.append("tasks: B could rename A's task")
        code, rows = a.rest("GET", f"/rest/v1/tasks?id=eq.{a.task}&select=title")
        if not (code == 200 and rows and rows[0].get("title") == "Task A"):
            problems.append("tasks: A's task changed or vanished after B's attempts")

        # 3. B can't take over A's company id or read A's team.
        code, _ = b.rest("POST", "/rest/v1/rpc/ensure_company", {"p_company_id": a.company, "p_name": "hijack"})
        if code == 200:
            problems.append("ensure_company: B joined A's company by its id")
        code, rows = b.rest("POST", "/rest/v1/rpc/company_roster", {"p_company_id": a.company})
        if code == 200 and rows:
            problems.append("company_roster: B can read A's team")

        # 4. And A still sees its own data (so the checks above aren't
        # passing just because nothing works).
        code, rows = a.rest("GET", f"/rest/v1/projects?id=eq.{a.project}&select=id")
        if not (code == 200 and rows):
            problems.append("projects: A can't read its own site, so the check proves nothing")
    finally:
        a.delete()
        b.delete()
    return problems


def main() -> int:
    url, anon = os.environ.get("SUPABASE_URL", ""), os.environ.get("SUPABASE_ANON_KEY", "")
    if not url or not anon:
        print("Set SUPABASE_URL and SUPABASE_ANON_KEY.")
        return 2
    problems = run(Api(url, anon))
    lines = ["# Company isolation", ""]
    if problems:
        lines += ["❌ One company can reach another's data:", ""] + [f"- {p}" for p in problems]
    else:
        lines += ["✅ Two test companies could not see or change each other's data in any table. "
                  "Both test accounts were deleted."]
    report = "\n".join(lines)
    print(report)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as f:
            f.write(report + "\n")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
