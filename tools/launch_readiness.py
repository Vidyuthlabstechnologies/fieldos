"""Reports whether the repo is ready for a store build (issues #50 and #51).

Run by .github/workflows/launch-readiness.yml with every launch secret in
the environment. For each one it says set / missing and, when set, whether
it is the right *kind* of value: the Supabase anon key and not the
service_role key, RevenueCat's public SDK keys and not a secret API key, a
keystore that opens with the given alias and passwords. If the Supabase
project is reachable it also reports what is deployed there (the tables
the last migrations create, email sign-up and confirmation settings).

Secret values are never printed: only names, verdicts and short notes.

Exit status is 1 only when a value that IS set is wrong, because that would
ship a broken or unsafe build. Missing values are reported, not failed; the
Actions tab run is the way a collaborator finds out what the owner still has
to add (Settings -> Secrets is owner-only on a personal repo).
"""

from __future__ import annotations

import base64
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
from dataclasses import dataclass

OK, MISSING, WARN, FAIL = "ok", "missing", "warn", "fail"
_ICON = {OK: "✅", MISSING: "⬜", WARN: "⚠️", FAIL: "❌"}
_RANK = {OK: 0, MISSING: 1, WARN: 2, FAIL: 3}

# Keyed by what the release build needs them for (docs/PLAY_STORE_LAUNCH.md).
GROUPS = {
    "Supabase (accounts, sync, bug reports)": [
        "SUPABASE_URL", "SUPABASE_ANON_KEY", "SUPABASE_ACCESS_TOKEN", "SUPABASE_DB_PASSWORD",
    ],
    "RevenueCat (paywall and 3-day trial)": ["REVENUECAT_ANDROID_KEY", "REVENUECAT_IOS_KEY"],
    "Android upload signing": [
        "ANDROID_KEYSTORE_BASE64", "ANDROID_KEY_ALIAS", "ANDROID_KEY_PASSWORD", "ANDROID_STORE_PASSWORD",
    ],
}
KEYSTORE_SECRETS = GROUPS["Android upload signing"]


@dataclass
class Result:
    name: str
    status: str
    note: str = ""


def project_ref(url: str) -> str | None:
    m = re.fullmatch(r"https://([a-z0-9]+)\.supabase\.co/?", url.strip())
    return m.group(1) if m else None


def check_supabase_url(value: str) -> Result:
    if not value:
        return Result("SUPABASE_URL", MISSING, "https://<ref>.supabase.co, from Project Settings -> API")
    if project_ref(value) is None:
        return Result("SUPABASE_URL", FAIL, "should look like https://abcdefghijkl.supabase.co (no path)")
    return Result("SUPABASE_URL", OK)


def _jwt_payload(token: str) -> dict | None:
    parts = token.strip().split(".")
    if len(parts) != 3:
        return None
    try:
        raw = parts[1] + "=" * (-len(parts[1]) % 4)
        payload = json.loads(base64.urlsafe_b64decode(raw))
    except (ValueError, UnicodeDecodeError):
        return None
    return payload if isinstance(payload, dict) else None


def check_anon_key(value: str, url: str = "") -> Result:
    """The app ships this key, so anything with write-everything power fails."""
    name = "SUPABASE_ANON_KEY"
    if not value:
        return Result(name, MISSING, "the anon / publishable key from Project Settings -> API")
    v = value.strip()
    if v.startswith("sb_secret_"):
        return Result(name, FAIL, "this is a SECRET key; the app must only get the publishable one")
    if v.startswith("sb_publishable_"):
        return Result(name, OK, "publishable key")
    payload = _jwt_payload(v)
    if payload is None:
        return Result(name, WARN, "not a JWT or sb_publishable_ key; check it was copied whole")
    role = payload.get("role")
    if role == "service_role":
        return Result(name, FAIL, "this is the service_role key; it bypasses RLS and must never ship in the app")
    if role != "anon":
        return Result(name, WARN, f"unexpected role {role!r}; expected anon")
    ref = project_ref(url) if url else None
    if ref and payload.get("ref") and payload["ref"] != ref:
        return Result(name, FAIL, "key belongs to a different Supabase project than SUPABASE_URL")
    return Result(name, OK, "anon key" + (", same project as SUPABASE_URL" if ref and payload.get("ref") else ""))


def check_access_token(value: str) -> Result:
    name = "SUPABASE_ACCESS_TOKEN"
    if not value:
        return Result(name, MISSING, "personal access token from supabase.com/dashboard/account/tokens")
    if not value.strip().startswith("sbp_"):
        return Result(name, WARN, "Supabase access tokens start with sbp_; is this the right value?")
    return Result(name, OK)


def check_db_password(value: str) -> Result:
    name = "SUPABASE_DB_PASSWORD"
    if not value:
        return Result(name, MISSING, "the database password chosen when the project was created")
    return Result(name, OK)


_RC_PREFIX = {"REVENUECAT_ANDROID_KEY": ("goog_", "Google Play"), "REVENUECAT_IOS_KEY": ("appl_", "App Store")}


def check_revenuecat_key(name: str, value: str) -> Result:
    prefix, store = _RC_PREFIX[name]
    if not value:
        return Result(name, MISSING, f"public SDK key for the {store} app, RevenueCat -> API keys")
    v = value.strip()
    if v.startswith("sk_"):
        return Result(name, FAIL, "this is a secret API key; the app needs the PUBLIC SDK key")
    if v.startswith("test_"):
        return Result(name, WARN, "RevenueCat test-store key: fine for testing, not for the store release")
    if v.startswith(prefix):
        return Result(name, OK, f"{store} public SDK key")
    for other, (p, s) in _RC_PREFIX.items():
        if other != name and v.startswith(p):
            return Result(name, FAIL, f"this is the {s} key, in the wrong secret")
    return Result(name, WARN, f"expected a key starting with {prefix}")


def _keytool_ok(args: list[str]) -> bool:
    try:
        return subprocess.run(args, capture_output=True, timeout=60).returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False


def check_keystore(b64: str, alias: str, key_password: str, store_password: str) -> list[Result]:
    """All four or none: release.yml writes key.properties as soon as the
    base64 is set, so a half-set group breaks the signed build."""
    values = dict(zip(KEYSTORE_SECRETS, (b64, alias, key_password, store_password)))
    present = [n for n, v in values.items() if v]
    if not present:
        return [Result(n, MISSING, "see docs/PLAY_STORE_LAUNCH.md section 1, step 3") for n in KEYSTORE_SECRETS]
    if len(present) < len(values):
        return [
            Result(n, OK if v else FAIL, "" if v else "the other signing secrets are set, so this one is needed too")
            for n, v in values.items()
        ]
    try:
        blob = base64.b64decode(b64, validate=True)
    except ValueError:
        return [Result("ANDROID_KEYSTORE_BASE64", FAIL, "not valid base64; make it with: base64 < upload.keystore")] + [
            Result(n, OK) for n in KEYSTORE_SECRETS[1:]
        ]
    keytool = shutil.which("keytool")
    if keytool is None:
        return [Result(n, WARN, "keytool not available here; not verified") for n in KEYSTORE_SECRETS]
    with tempfile.NamedTemporaryFile(suffix=".keystore", delete=False) as f:
        f.write(blob)
        path = f.name
    try:
        if not _keytool_ok([keytool, "-list", "-keystore", path, "-storepass", store_password]):
            return [
                Result("ANDROID_KEYSTORE_BASE64", FAIL, "the keystore does not open with ANDROID_STORE_PASSWORD"),
                Result("ANDROID_KEY_ALIAS", WARN, "not checked"),
                Result("ANDROID_KEY_PASSWORD", WARN, "not checked"),
                Result("ANDROID_STORE_PASSWORD", FAIL, "wrong for this keystore (or the base64 is of another file)"),
            ]
        if not _keytool_ok([keytool, "-list", "-keystore", path, "-storepass", store_password, "-alias", alias]):
            return [
                Result("ANDROID_KEYSTORE_BASE64", OK),
                Result("ANDROID_KEY_ALIAS", FAIL, "no key with this alias in the keystore"),
                Result("ANDROID_KEY_PASSWORD", WARN, "not checked"),
                Result("ANDROID_STORE_PASSWORD", OK),
            ]
        # A certificate request needs the private key, so it proves the key password.
        key_ok = _keytool_ok([
            keytool, "-certreq", "-keystore", path, "-storepass", store_password,
            "-alias", alias, "-keypass", key_password, "-file", os.devnull,
        ])
        return [
            Result("ANDROID_KEYSTORE_BASE64", OK, "opens, alias found"),
            Result("ANDROID_KEY_ALIAS", OK),
            Result("ANDROID_KEY_PASSWORD", OK if key_ok else FAIL, "" if key_ok else "wrong for this alias"),
            Result("ANDROID_STORE_PASSWORD", OK),
        ]
    finally:
        os.unlink(path)


def _get(url: str, headers: dict[str, str], timeout: int = 15) -> tuple[int, object]:
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as res:
            body = res.read()
            code = res.status
    except urllib.error.HTTPError as e:
        body = e.read()
        code = e.code
    try:
        return code, json.loads(body) if body else None
    except ValueError:
        return code, None


def cloud_checks(url: str, anon_key: str) -> list[Result]:
    """What the production project itself says, using only the anon key."""
    base = url.strip().rstrip("/")
    headers = {"apikey": anon_key, "Authorization": f"Bearer {anon_key}"}
    out: list[Result] = []
    try:
        code, settings = _get(f"{base}/auth/v1/settings", headers)
    except (urllib.error.URLError, OSError, TimeoutError) as e:
        return [Result("Supabase project", FAIL, f"not reachable: {getattr(e, 'reason', e)}")]
    if code != 200 or not isinstance(settings, dict):
        return [Result("Supabase project", FAIL, f"auth settings returned HTTP {code}; is the anon key for this project?")]
    out.append(Result("Supabase project", OK, "reachable with the anon key"))
    email_on = bool((settings.get("external") or {}).get("email")) and not settings.get("disable_signup")
    out.append(Result("Email sign-up", OK if email_on else FAIL,
                      "on" if email_on else "off: Authentication -> Sign In / Providers -> Email, allow sign-ups"))
    autoconfirm = bool(settings.get("mailer_autoconfirm"))
    out.append(Result("Confirm email", OK if autoconfirm else WARN,
                      "off (people can sign in straight away)" if autoconfirm
                      else "required: the built-in mailer sends only a few emails an hour; "
                           "turn it off for launch or set up custom SMTP (section 1, step 1)"))
    # A table the migrations create answers 404 only when it is not there;
    # anything else (200, or 401/403 from RLS and grants) means it exists.
    for table, migration in (("companies", "initial_schema"), ("project_messages", "project_messages"),
                             ("bug_reports", "bug_reports")):
        code, body = _get(f"{base}/rest/v1/{table}?select=id&limit=1", headers)
        if code == 404:
            out.append(Result(f"Table {table}", FAIL, f"not deployed ({migration} migration): run the supabase-deploy workflow"))
        elif table == "bug_reports" and code == 200:
            out.append(Result(f"Table {table}", FAIL, "anyone can READ bug reports; the migration only grants insert"))
        else:
            out.append(Result(f"Table {table}", OK, "deployed"))
    return out


def worst(results: list[Result]) -> str:
    return max((r.status for r in results), key=_RANK.get, default=OK)


def render(sections: list[tuple[str, list[Result]]]) -> str:
    lines = ["# Launch readiness", ""]
    for title, results in sections:
        lines += [f"## {title}", "", "| | Name | Note |", "|---|---|---|"]
        lines += [f"| {_ICON[r.status]} | `{r.name}` | {r.note} |" for r in results]
        lines.append("")
    legend = "✅ set and looks right · ⬜ not set · ⚠️ set, check it · ❌ set but wrong (this run fails)"
    lines += [legend, "", ""]
    return "\n".join(lines)


def next_steps(sections: list[tuple[str, list[Result]]]) -> list[str]:
    steps: list[str] = []
    by_title = dict(sections)
    for title, results in sections:
        missing = [r.name for r in results if r.status == MISSING]
        if missing and title in GROUPS:
            steps.append(f"{title}: the owner adds {', '.join(missing)} (tools/set_launch_secrets.sh), then re-runs this.")
    if "Supabase (accounts, sync, bug reports)" in by_title:
        sb = by_title["Supabase (accounts, sync, bug reports)"]
        if all(r.status == OK for r in sb) and "Production Supabase project" not in by_title:
            steps.append("Supabase secrets are set: run the supabase-deploy workflow, then re-run this to see the tables.")
    if any(r.status == FAIL for _, rs in sections for r in rs):
        steps.append("Fix every ❌ before tagging a release; the release workflow builds with whatever is set.")
    if not steps:
        steps.append("Everything checks out. Tag or run the release workflow, then upload the .aab to internal testing.")
    return steps


def main(argv: list[str]) -> int:
    env = os.environ.get
    url = env("SUPABASE_URL", "")
    anon = env("SUPABASE_ANON_KEY", "")
    sections: list[tuple[str, list[Result]]] = [
        ("Supabase (accounts, sync, bug reports)", [
            check_supabase_url(url),
            check_anon_key(anon, url),
            check_access_token(env("SUPABASE_ACCESS_TOKEN", "")),
            check_db_password(env("SUPABASE_DB_PASSWORD", "")),
        ]),
        ("RevenueCat (paywall and 3-day trial)", [
            check_revenuecat_key(n, env(n, "")) for n in GROUPS["RevenueCat (paywall and 3-day trial)"]
        ]),
        ("Android upload signing", check_keystore(*(env(n, "") for n in KEYSTORE_SECRETS))),
    ]
    online = "--offline" not in argv
    if online and project_ref(url) and check_anon_key(anon, url).status == OK:
        sections.append(("Production Supabase project", cloud_checks(url, anon)))

    report = render(sections) + "## Next\n\n" + "\n".join(f"- {s}" for s in next_steps(sections)) + "\n"
    print(report)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as f:
            f.write(report)
    return 1 if any(worst(rs) == FAIL for _, rs in sections) else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
