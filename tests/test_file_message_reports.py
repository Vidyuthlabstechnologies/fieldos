"""tools/file_bug_reports.py builds issue bodies safe for a public repository."""

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


def test_message_report_body_leaves_people_out():
    mod = load()
    body = mod.message_report_body({
        "id": "r1", "created_at": "2026-11-08T10:00:00Z", "message_id": "m1",
        "reason": "spam", "details": "asks for ```money```",
        "project_messages": {"body": "pay me ```now```", "sender_name": "Ravi",
                             "project_id": "p1", "created_at": "2026-11-08T09:00:00Z"},
    })
    assert "**Reason:** Spam or fraud" in body
    # The repository is public: the chat text, its sender and the note stay in Supabase.
    for leak in ("pay me", "Ravi", "asks for"):
        assert leak not in body
    assert "still in the chat" in body and "added a note:** yes" in body
    assert "24 hours" in body and "message m1" in body


def test_deleted_message_still_files():
    mod = load()
    body = mod.message_report_body({"id": "r2", "created_at": "t", "message_id": "m2",
                                    "reason": "other", "details": None, "project_messages": None})
    assert "deleted since" in body and "Something else" in body


def test_redact_masks_emails_and_phones_but_not_dates():
    mod = load()
    out = mod.redact("call +91 98480 12345 or 9848012345, mail ravi.k@example.co.in, at 2026-11-08 21:03:37, v1.7.7+22")
    assert "98480" not in out and "9848012345" not in out and "ravi.k@" not in out
    assert "2026-11-08 21:03:37" in out and "1.7.7+22" in out
