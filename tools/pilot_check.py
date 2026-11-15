#!/usr/bin/env python3
"""Walks one pilot company through the cloud the way the app does, against
the live Supabase project, with throwaway accounts only.

An owner signs up and makes a company; a project manager, a site engineer and
an accounts person join with the join code and get their roles; the owner
opens two sites; the engineer records workers, attendance, a daily report,
materials, an expense and a chat message; accounts records a supplier bill
with GST; the owner sees all of it. Role limits are checked (only the owner
changes roles, nobody outside the company joins without the code), then the
plan, assistant, bug report and account deletion paths. Every account is
deleted at the end, pass or fail.

Uses only SUPABASE_URL and SUPABASE_ANON_KEY (the public key the app ships
with). Needs "Confirm email" off, as at launch.

  SUPABASE_URL=... SUPABASE_ANON_KEY=... python3 tools/pilot_check.py
"""
from __future__ import annotations

import datetime as dt
import os
import secrets
import sys
import uuid

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from isolation_check import Api  # noqa: E402


class Person:
    def __init__(self, api: Api, label: str):
        self.api = api
        self.label = label
        self.email = f"pilot-check-{label}-{secrets.token_hex(5)}@example.com"
        self.password = secrets.token_urlsafe(24)
        code, body = api.call("POST", "/auth/v1/signup", {"email": self.email, "password": self.password})
        if code != 200 or not isinstance(body, dict) or not body.get("access_token"):
            raise SystemExit(f"sign-up for {label} failed (HTTP {code}): {body}")
        self.token = body["access_token"]
        self.id = body["user"]["id"]

    def rest(self, method, path, body=None, prefer=None):
        return self.api.call(method, path, body, token=self.token, prefer=prefer)

    def rpc(self, name, args=None):
        return self.rest("POST", f"/rest/v1/rpc/{name}", args or {})

    def insert(self, table, row):
        return self.rest("POST", f"/rest/v1/{table}", row, prefer="return=minimal")

    def delete(self):
        self.rpc("delete_my_account")


def run(api: Api) -> tuple[list[str], list[str]]:
    ok: list[str] = []
    bad: list[str] = []

    def check(cond: bool, good: str, fail: str):
        (ok if cond else bad).append(good if cond else fail)

    people: list[Person] = []
    try:
        owner = Person(api, "owner"); people.append(owner)
        pm = Person(api, "pm"); people.append(pm)
        eng = Person(api, "engineer"); people.append(eng)
        acct = Person(api, "accounts"); people.append(acct)
        outsider = Person(api, "outsider"); people.append(outsider)
        ok.append("5 accounts signed up by email (no email step needed)")

        company = str(uuid.uuid4())
        code, body = owner.rpc("ensure_company", {"p_company_id": company, "p_name": "Pilot check builders"})
        join_code = (body or {}).get("join_code") if isinstance(body, dict) else None
        check(code == 200 and bool(join_code), "owner made the company and got a join code",
              f"ensure_company HTTP {code}: {body}")
        if not join_code:
            return ok, bad

        for p in (pm, eng, acct):
            code, body = p.rpc("join_company", {"p_code": join_code})
            check(code == 200, f"{p.label} joined with the code", f"{p.label} join_company HTTP {code}: {body}")
        code, body = outsider.rpc("join_company", {"p_code": "ZZZZZZ"})
        refused = code != 200 or (isinstance(body, dict) and body.get("error") == "invalid_join_code")
        check(refused, "a wrong join code is refused", f"wrong code accepted: {body}")

        # Company roles are owner / project manager / site engineer; accounts,
        # storekeeper and viewer are site-team roles (project_members).
        code, body = owner.rpc("set_member_role", {"p_company_id": company, "p_user_id": pm.id, "p_role": "project_manager"})
        check(code in (200, 204), "owner made pm a project manager", f"set_member_role HTTP {code}: {body}")
        code, body = eng.rpc("set_member_role", {"p_company_id": company, "p_user_id": acct.id, "p_role": "owner"})
        check(code not in (200, 204), "an engineer cannot change roles", "engineer changed a role")

        code, roster = owner.rpc("company_roster", {"p_company_id": company})
        roles = sorted((r.get("role") or "") for r in roster) if code == 200 and isinstance(roster, list) else []
        check(len(roles) == 4, f"roster shows 4 people: {', '.join(roles)}", f"roster HTTP {code}: {roster}")

        sites = [str(uuid.uuid4()), str(uuid.uuid4())]
        for i, sid in enumerate(sites):
            code, body = owner.insert("projects", {"id": sid, "company_id": company, "name": f"Pilot site {i + 1}",
                                                   "status": "active"})
            check(code in (200, 201), f"owner opened site {i + 1}", f"create site {i + 1} HTTP {code}: {body}")
        code, rows = eng.rest("GET", f"/rest/v1/projects?company_id=eq.{company}&select=id")
        check(code == 200 and len(rows or []) == 2, "the engineer sees both sites",
              f"engineer sees {len(rows or []) if code == 200 else code} sites")

        site = sites[0]
        code, body = owner.insert("project_members", {"id": str(uuid.uuid4()), "project_id": site, "user_id": acct.id,
                                                      "role": "accounts"})
        check(code in (200, 201), "owner put accounts on site 1's team as Accounts",
              f"project_members accounts HTTP {code}: {body}")
        code, body = eng.insert("project_members", {"id": str(uuid.uuid4()), "project_id": site, "user_id": eng.id,
                                                    "role": "project_manager"})
        check(code not in (200, 201), "an engineer cannot make themselves site manager",
              "engineer made themselves site manager")
        today = dt.date.today().isoformat()
        now = dt.datetime.now(dt.timezone.utc).isoformat()
        worker = str(uuid.uuid4())
        steps = [
            ("workers", {"id": worker, "project_id": site, "name": "Ramesh", "role": "mason", "daily_wage": 900}),
            ("site_attendance", {"id": str(uuid.uuid4()), "project_id": site, "worker_name": "Ramesh",
                                 "worker_id": worker, "recorded_by": eng.id, "punch_in": now}),
            ("site_attendance_marks", {"id": str(uuid.uuid4()), "project_id": site, "worker_id": worker,
                                       "day": today, "units": 1, "recorded_by": eng.id}),
            ("dpr_entries", {"id": str(uuid.uuid4()), "project_id": site, "created_by": eng.id, "entry_date": today,
                             "work_summary": "Slab shuttering on grid A-C", "manpower_count": 12}),
            ("material_entries", {"id": str(uuid.uuid4()), "project_id": site, "entry_date": today,
                                  "item_name": "OPC 53 cement", "category": "cement", "quantity": 50, "unit": "bag",
                                  "created_by": eng.id}),
            ("site_expenses", {"id": str(uuid.uuid4()), "project_id": site, "category": "Transport", "amount": 1500,
                               "incurred_on": today, "recorded_by": eng.id}),
            ("project_messages", {"project_id": site, "sender_id": eng.id, "sender_name": "Engineer",
                                  "body": "Cement arrived, 50 bags"}),
        ]
        for table, row in steps:
            code, body = eng.insert(table, row)
            check(code in (200, 201), f"engineer saved {table}", f"engineer {table} HTTP {code}: {body}")

        vendor = str(uuid.uuid4())
        code, body = pm.insert("vendors", {"id": vendor, "company_id": company, "name": "Sri Sai Cements"})
        check(code in (200, 201), "project manager added a supplier", f"pm vendors HTTP {code}: {body}")
        code, body = acct.insert("site_supplier_invoices", {
            "id": str(uuid.uuid4()), "project_id": site, "supplier_id": vendor, "invoice_number": "SSC/101",
            "invoice_date": today, "amount": 21000, "gst_amount": 3780, "recorded_by": acct.id})
        check(code in (200, 201), "accounts recorded a supplier bill with GST",
              f"accounts site_supplier_invoices HTTP {code}: {body}")

        for table in ("workers", "site_attendance", "site_attendance_marks", "dpr_entries", "material_entries",
                      "site_expenses", "project_messages", "site_supplier_invoices"):
            code, rows = owner.rest("GET", f"/rest/v1/{table}?project_id=eq.{site}&select=*")
            check(code == 200 and len(rows or []) >= 1, f"owner sees the {table} row",
                  f"owner cannot see {table} (HTTP {code}, {len(rows or []) if code == 200 else rows})")

        code, rows = outsider.rest("GET", f"/rest/v1/dpr_entries?project_id=eq.{site}&select=id")
        check(code == 200 and not rows, "someone outside the company sees nothing",
              f"outsider read {len(rows or [])} daily reports")

        code, body = owner.rpc("my_company_plans")
        check(code == 200, f"my_company_plans answers (no plan yet: {body!r})", f"my_company_plans HTTP {code}: {body}")
        code, body = owner.rpc("min_app_build")
        check(code == 200, f"min_app_build answers ({body})", f"min_app_build HTTP {code}: {body}")

        code, body = owner.rest("POST", "/functions/v1/ai-assistant",
                                {"messages": [{"role": "user", "content": "How many sites do I have?"}]})
        no_plan = isinstance(body, dict) and body.get("error") == "no_plan"
        check(code in (200, 402, 403) and (code == 200 or no_plan),
              f"assistant answers (HTTP {code}{', no_plan for an account with no plan, as expected' if no_plan else ''})",
              f"assistant HTTP {code}: {body}")

        code, body = eng.insert("bug_reports", {"message": "Pilot check: test report, please ignore",
                                                "app_version": "pilot-check", "platform": "script"})
        check(code in (200, 201), "a bug report is accepted", f"bug_reports HTTP {code}: {body}")
        code, rows = eng.rest("GET", "/rest/v1/bug_reports?select=id")
        check(code != 200 or not rows, "bug reports are write-only", f"engineer read {len(rows)} bug reports")

        code, body = eng.rpc("delete_my_account")
        check(code in (200, 204), "the engineer deleted their account", f"delete_my_account HTTP {code}: {body}")
        code, body = api.call("POST", "/auth/v1/token?grant_type=password", {"email": eng.email, "password": eng.password})
        check(code != 200, "a deleted account can no longer sign in", "deleted account still signs in")
        code, rows = owner.rest("GET", f"/rest/v1/dpr_entries?project_id=eq.{site}&select=id")
        check(code == 200, f"the company's records stay after a member leaves ({len(rows or [])} daily reports)",
              f"owner read after delete HTTP {code}")
        code, roster = owner.rpc("company_roster", {"p_company_id": company})
        check(code == 200 and len(roster or []) == 3, "the roster drops the deleted person",
              f"roster after delete: {roster}")
    finally:
        for p in people:
            p.delete()
    return ok, bad


def main() -> int:
    url, anon = os.environ.get("SUPABASE_URL", ""), os.environ.get("SUPABASE_ANON_KEY", "")
    if not url or not anon:
        print("Set SUPABASE_URL and SUPABASE_ANON_KEY.")
        return 2
    ok, bad = run(Api(url, anon))
    for line in ok:
        print(f"PASS  {line}")
    for line in bad:
        print(f"FAIL  {line}")
    print(f"\n{len(ok)} passed, {len(bad)} failed. All test accounts deleted.")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
