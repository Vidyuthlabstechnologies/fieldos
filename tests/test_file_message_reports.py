"""The chat-report half of tools/file_bug_reports.py builds a safe issue body."""

import importlib.util
import os
from pathlib import Path


def load():
    for k in ("SUPABASE_URL", "SUPABASE_SERVICE_KEY", "GITHUB_TOKEN", "GITHUB_REPOSITORY"):
        os.environ.setdefault(k, "x")
    path = Path(__file__).resolve().parents[1] / "tools" / "file_bug_reports.py"
    spec = importlib.util.spec_from_file_location("file_bug_reports", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def test_message_report_body_quotes_user_text():
    mod = load()
    body = mod.message_report_body({
        "id": "r1", "created_at": "2026-11-08T10:00:00Z", "message_id": "m1",
        "reason": "spam", "details": "asks for ```money```",
        "project_messages": {"body": "pay me ```now```", "sender_name": "Ravi",
                             "project_id": "p1", "created_at": "2026-11-08T09:00:00Z"},
    })
    assert "**Reason:** Spam or fraud" in body
    assert "pay me '''now'''" in body and "```now```" not in body
    assert "asks for '''money'''" in body
    assert "24 hours" in body and "message m1" in body


def test_deleted_message_still_files():
    mod = load()
    body = mod.message_report_body({"id": "r2", "created_at": "t", "message_id": "m2",
                                    "reason": "other", "details": None, "project_messages": None})
    assert "(the message has been deleted)" in body and "Something else" in body
