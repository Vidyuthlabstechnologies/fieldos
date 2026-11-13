"""tools/launch_readiness.py decides, from a secret's shape alone, whether it
is the right kind of key. A wrong verdict here either blocks a good launch
or lets the service_role key ship inside the APK, so each rule gets a test.
"""

import base64
import importlib.util
import json
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

# tools/ is not a package; load the script by path (registered in sys.modules
# first, which @dataclass needs to resolve its annotations).
_SPEC = importlib.util.spec_from_file_location(
    "launch_readiness", Path(__file__).parent.parent / "tools" / "launch_readiness.py")
lr = importlib.util.module_from_spec(_SPEC)
sys.modules["launch_readiness"] = lr
_SPEC.loader.exec_module(lr)

URL = "https://abcdefghijklmnopqrst.supabase.co"


def jwt(payload: dict) -> str:
    def part(obj):
        return base64.urlsafe_b64encode(json.dumps(obj).encode()).decode().rstrip("=")
    return f"{part({'alg': 'HS256', 'typ': 'JWT'})}.{part(payload)}.signature"


def test_supabase_url_must_be_the_bare_project_url():
    assert lr.check_supabase_url("").status == lr.MISSING
    assert lr.check_supabase_url(URL).status == lr.OK
    assert lr.check_supabase_url(URL + "/").status == lr.OK
    assert lr.check_supabase_url(URL + "/rest/v1").status == lr.FAIL
    assert lr.check_supabase_url("http://abcdefghijklmnopqrst.supabase.co").status == lr.FAIL
    assert lr.check_supabase_url("https://supabase.com/dashboard/project/abc").status == lr.FAIL


def test_anon_key_accepts_anon_jwt_and_publishable_key():
    assert lr.check_anon_key(jwt({"role": "anon", "ref": "abcdefghijklmnopqrst"}), URL).status == lr.OK
    assert lr.check_anon_key(jwt({"role": "anon"}), URL).status == lr.OK
    assert lr.check_anon_key("sb_publishable_abc123", URL).status == lr.OK


def test_anon_key_rejects_keys_that_must_never_ship_in_the_app():
    r = lr.check_anon_key(jwt({"role": "service_role", "ref": "abcdefghijklmnopqrst"}), URL)
    assert r.status == lr.FAIL and "service_role" in r.note
    assert lr.check_anon_key("sb_secret_abc123", URL).status == lr.FAIL


def test_anon_key_for_another_project_fails():
    r = lr.check_anon_key(jwt({"role": "anon", "ref": "zzzzzzzzzzzzzzzzzzzz"}), URL)
    assert r.status == lr.FAIL and "different" in r.note


def test_anon_key_that_is_not_a_key_only_warns():
    assert lr.check_anon_key("", URL).status == lr.MISSING
    assert lr.check_anon_key("hello", URL).status == lr.WARN
    assert lr.check_anon_key("a.b.c", URL).status == lr.WARN  # three parts but not base64 JSON


def test_access_token_shape():
    assert lr.check_access_token("").status == lr.MISSING
    assert lr.check_access_token("sbp_" + "0" * 40).status == lr.OK
    assert lr.check_access_token(jwt({"role": "anon"})).status == lr.WARN


def test_revenuecat_keys_must_be_the_public_sdk_key_for_that_store():
    assert lr.check_revenuecat_key("REVENUECAT_ANDROID_KEY", "goog_abc").status == lr.OK
    assert lr.check_revenuecat_key("REVENUECAT_IOS_KEY", "appl_abc").status == lr.OK
    assert lr.check_revenuecat_key("REVENUECAT_ANDROID_KEY", "sk_abc").status == lr.FAIL
    assert lr.check_revenuecat_key("REVENUECAT_IOS_KEY", "sk_abc").status == lr.FAIL
    # Swapped keys would make one store's app talk to the other's product list.
    assert lr.check_revenuecat_key("REVENUECAT_ANDROID_KEY", "appl_abc").status == lr.FAIL
    assert lr.check_revenuecat_key("REVENUECAT_IOS_KEY", "goog_abc").status == lr.FAIL
    assert lr.check_revenuecat_key("REVENUECAT_ANDROID_KEY", "test_abc").status == lr.WARN
    assert lr.check_revenuecat_key("REVENUECAT_ANDROID_KEY", "").status == lr.MISSING


def test_signing_secrets_are_all_or_nothing():
    assert [r.status for r in lr.check_keystore("", "", "", "")] == [lr.MISSING] * 4
    half = lr.check_keystore("QUJD", "upload", "", "")
    assert [r.status for r in half] == [lr.OK, lr.OK, lr.FAIL, lr.FAIL]


def test_keystore_base64_must_decode():
    r = lr.check_keystore("not base64!!", "upload", "kp", "sp")
    assert r[0].status == lr.FAIL and "base64" in r[0].note


KEYTOOL = shutil.which("keytool")


@pytest.fixture(scope="module")
def keystore_b64(tmp_path_factory):
    if KEYTOOL is None:
        pytest.skip("keytool (a JDK) is not installed here")
    path = tmp_path_factory.mktemp("ks") / "upload.keystore"
    subprocess.run([
        KEYTOOL, "-genkeypair", "-keystore", str(path), "-storetype", "PKCS12", "-storepass", "store-pw",
        "-alias", "upload", "-keypass", "store-pw", "-keyalg", "RSA", "-keysize", "2048", "-validity", "1",
        "-dname", "CN=test",
    ], check=True, capture_output=True)
    return base64.b64encode(path.read_bytes()).decode()


def test_real_keystore_opens_with_the_right_alias_and_passwords(keystore_b64):
    results = lr.check_keystore(keystore_b64, "upload", "store-pw", "store-pw")
    assert [r.status for r in results] == [lr.OK] * 4, results


def test_real_keystore_wrong_store_password_fails(keystore_b64):
    results = {r.name: r.status for r in lr.check_keystore(keystore_b64, "upload", "store-pw", "nope-nope")}
    assert results["ANDROID_STORE_PASSWORD"] == lr.FAIL


def test_real_keystore_unknown_alias_fails(keystore_b64):
    results = {r.name: r.status for r in lr.check_keystore(keystore_b64, "release", "store-pw", "store-pw")}
    assert results["ANDROID_KEY_ALIAS"] == lr.FAIL
    assert results["ANDROID_STORE_PASSWORD"] == lr.OK


def test_report_never_contains_a_secret_value_and_fails_only_on_wrong_values(monkeypatch, capsys):
    service_key = jwt({"role": "service_role", "ref": "abcdefghijklmnopqrst"})
    monkeypatch.setenv("SUPABASE_URL", URL)
    monkeypatch.setenv("SUPABASE_ANON_KEY", service_key)
    monkeypatch.setenv("REVENUECAT_ANDROID_KEY", "goog_very_distinctive_value")
    for name in ("SUPABASE_ACCESS_TOKEN", "SUPABASE_DB_PASSWORD", "REVENUECAT_IOS_KEY", *lr.KEYSTORE_SECRETS):
        monkeypatch.delenv(name, raising=False)
    monkeypatch.delenv("GITHUB_STEP_SUMMARY", raising=False)

    assert lr.main(["--offline"]) == 1
    out = capsys.readouterr().out
    assert service_key not in out and "very_distinctive" not in out
    assert "service_role" in out and "⬜" in out

    monkeypatch.setenv("SUPABASE_ANON_KEY", jwt({"role": "anon", "ref": "abcdefghijklmnopqrst"}))
    assert lr.main(["--offline"]) == 0, "missing secrets are reported, not failed"


def test_report_is_appended_to_the_actions_step_summary(monkeypatch, tmp_path):
    summary = tmp_path / "summary.md"
    monkeypatch.setenv("GITHUB_STEP_SUMMARY", str(summary))
    for name in [n for names in lr.GROUPS.values() for n in names]:
        monkeypatch.delenv(name, raising=False)
    assert lr.main(["--offline"]) == 0
    text = summary.read_text()
    assert text.startswith("# Launch readiness") and "SUPABASE_URL" in text and "## Next" in text


def test_tables_are_read_from_every_migration_file(tmp_path):
    (tmp_path / "20260101000000_first.sql").write_text(
        'CREATE TABLE companies (id uuid);\ncreate table if not exists public."Quoted_Name" (id int);\n'
        'create table public.projects(\n  id uuid\n);\n-- create table commented_out (x int);\n')
    (tmp_path / "20260102000000_policies_only.sql").write_text("alter table companies enable row level security;\n")
    (tmp_path / "20260103000000_site_records.sql").write_text(
        "create table if not exists site_attendance (id uuid);\ncreate table if not exists site_expenses (id uuid);\n")
    (tmp_path / "notes.txt").write_text("create table ignored (x int);")
    assert lr.tables_from_migrations(str(tmp_path)) == {
        "first": ["companies", "quoted_name", "projects"],
        "site_records": ["site_attendance", "site_expenses"],
    }
    assert lr.tables_from_migrations(str(tmp_path / "missing")) == {}


def test_the_repo_migrations_parse():
    found = lr.tables_from_migrations()
    assert "companies" in found["initial_schema"]
    assert found["project_messages"] == ["project_messages"]
    assert found["bug_reports"] == ["bug_reports"]


def test_cloud_checks_report_one_row_per_migration(monkeypatch, tmp_path):
    (tmp_path / "20260101000000_initial_schema.sql").write_text("create table companies (id uuid);\ncreate table projects (id uuid);\n")
    (tmp_path / "20260102000000_bug_reports.sql").write_text("create table if not exists bug_reports (id uuid);\n")
    (tmp_path / "20260103000000_site_records.sql").write_text(
        "create table if not exists site_attendance (id uuid);\ncreate table if not exists site_expenses (id uuid);\n")
    deployed = {"companies": 401, "projects": 200, "bug_reports": 200, "site_attendance": 404, "site_expenses": 404}

    def fake_get(url, headers, timeout=15):
        if url.endswith("/auth/v1/settings"):
            return 200, {"external": {"email": True}, "disable_signup": False, "mailer_autoconfirm": True}
        table = url.rsplit("/rest/v1/", 1)[1].split("?")[0]
        return deployed[table], None

    monkeypatch.setattr(lr, "_get", fake_get)
    rows = {r.name: r for r in lr.cloud_checks(URL, "sb_publishable_x", str(tmp_path))}
    assert rows["Migration initial_schema"].status == lr.OK and "2 tables" in rows["Migration initial_schema"].note
    assert rows["Migration bug_reports"].status == lr.OK
    # 200 with no rows: RLS hides them, but select should be revoked too.
    assert rows["Table bug_reports"].status == lr.WARN
    assert rows["Migration site_records"].status == lr.FAIL
    assert "site_attendance, site_expenses" in rows["Migration site_records"].note
    assert rows["Confirm email"].status == lr.OK


def test_cloud_checks_fail_when_rows_come_back_without_signing_in(monkeypatch, tmp_path):
    (tmp_path / "20260101000000_initial_schema.sql").write_text("create table companies (id uuid);\ncreate table projects (id uuid);\n")

    def fake_get(url, headers, timeout=15):
        if url.endswith("/auth/v1/settings"):
            return 200, {"external": {"email": True}, "disable_signup": False, "mailer_autoconfirm": True}
        table = url.rsplit("/rest/v1/", 1)[1].split("?")[0]
        # RLS hides rows from anon (empty list); a table with no policy leaks.
        return 200, ([{"id": "x"}] if table == "projects" else [])

    monkeypatch.setattr(lr, "_get", fake_get)
    rows = {r.name: r for r in lr.cloud_checks(URL, "sb_publishable_x", str(tmp_path))}
    leak = rows["Data without signing in"]
    assert leak.status == lr.FAIL and "projects" in leak.note and "companies" not in leak.note


def test_cloud_checks_pass_when_nothing_is_readable_without_signing_in(monkeypatch, tmp_path):
    (tmp_path / "20260101000000_initial_schema.sql").write_text("create table companies (id uuid);\n")
    monkeypatch.setattr(lr, "_get", lambda url, headers, timeout=15: (
        (200, {"external": {"email": True}, "mailer_autoconfirm": True}) if url.endswith("/settings") else (401, None)))
    rows = {r.name: r for r in lr.cloud_checks(URL, "sb_publishable_x", str(tmp_path))}
    assert rows["Data without signing in"].status == lr.OK


def test_bug_reports_readable_rows_fail(monkeypatch, tmp_path):
    (tmp_path / "20260102000000_bug_reports.sql").write_text("create table if not exists bug_reports (id uuid);\n")
    monkeypatch.setattr(lr, "_get", lambda url, headers, timeout=15: (
        (200, {"external": {"email": True}, "mailer_autoconfirm": True}) if url.endswith("/settings")
        else (200, [{"message": "someone's report"}])))
    rows = {r.name: r for r in lr.cloud_checks(URL, "sb_publishable_x", str(tmp_path))}
    assert rows["Table bug_reports"].status == lr.FAIL and "READ" in rows["Table bug_reports"].note


def test_play_service_account_key_must_be_a_whole_service_account_json():
    good = json.dumps({"type": "service_account", "client_email": "fieldos-play@vidyuthlabs.iam.gserviceaccount.com",
                       "private_key": "-----BEGIN PRIVATE KEY-----\nabc\n-----END PRIVATE KEY-----\n"})
    r = lr.check_play_service_account(good)
    assert r.status == lr.OK and "fieldos-play@" in r.note and "PRIVATE KEY" not in r.note
    assert lr.check_play_service_account("").status == lr.MISSING
    assert lr.check_play_service_account("{not json").status == lr.FAIL
    assert lr.check_play_service_account(json.dumps({"type": "authorized_user"})).status == lr.FAIL
    assert lr.check_play_service_account(json.dumps({"type": "service_account"})).status == lr.FAIL


def test_report_never_prints_the_play_private_key(monkeypatch, capsys):
    for name in [n for names in lr.GROUPS.values() for n in names]:
        monkeypatch.delenv(name, raising=False)
    monkeypatch.delenv("GITHUB_STEP_SUMMARY", raising=False)
    monkeypatch.setenv("PLAY_SERVICE_ACCOUNT_JSON", json.dumps({
        "type": "service_account", "client_email": "x@p.iam.gserviceaccount.com",
        "private_key": "very_distinctive_private_key"}))
    assert lr.main(["--offline"]) == 0
    out = capsys.readouterr().out
    assert "very_distinctive_private_key" not in out and "PLAY_SERVICE_ACCOUNT_JSON" in out
