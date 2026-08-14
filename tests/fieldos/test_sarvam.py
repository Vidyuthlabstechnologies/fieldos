import httpx

from fieldos import sarvam
from fieldos.models import AppSetting


def test_get_effective_api_key_prefers_db_setting_over_env(db_session, monkeypatch):
    monkeypatch.setattr(sarvam.settings, "sarvam_api_key", "env-key")
    db_session.add(AppSetting(key=sarvam.SETTING_KEY, value="db-key"))
    db_session.commit()

    assert sarvam.get_effective_api_key(db_session) == "db-key"


def test_get_effective_api_key_falls_back_to_env_when_no_db_setting(db_session, monkeypatch):
    monkeypatch.setattr(sarvam.settings, "sarvam_api_key", "env-key")

    assert sarvam.get_effective_api_key(db_session) == "env-key"


def test_get_effective_api_key_is_none_when_neither_is_set(db_session, monkeypatch):
    monkeypatch.setattr(sarvam.settings, "sarvam_api_key", "")

    assert sarvam.get_effective_api_key(db_session) is None


def test_structure_dpr_from_transcript_parses_clean_json(monkeypatch):
    def fake_post(url, **kwargs):
        assert url == sarvam.CHAT_URL
        assert kwargs["headers"]["api-subscription-key"] == "test-key"
        return httpx.Response(
            200,
            json={
                "choices": [
                    {
                        "message": {
                            "content": '{"work_summary": "Poured column footings", "manpower_count": 12, "weather": "clear"}'
                        }
                    }
                ]
            },
            request=httpx.Request("POST", url),
        )

    monkeypatch.setattr(httpx, "post", fake_post)

    result = sarvam.structure_dpr_from_transcript("we poured column footings today with 12 workers", "test-key")

    assert result == {"work_summary": "Poured column footings", "manpower_count": 12, "weather": "clear"}


def test_structure_dpr_from_transcript_strips_markdown_code_fence(monkeypatch):
    def fake_post(url, **kwargs):
        return httpx.Response(
            200,
            json={
                "choices": [
                    {"message": {"content": '```json\n{"work_summary": "Test", "manpower_count": 5}\n```'}}
                ]
            },
            request=httpx.Request("POST", url),
        )

    monkeypatch.setattr(httpx, "post", fake_post)

    result = sarvam.structure_dpr_from_transcript("some transcript", "test-key")

    assert result["work_summary"] == "Test"
    assert result["manpower_count"] == 5


def test_structure_dpr_from_transcript_falls_back_on_malformed_json(monkeypatch):
    def fake_post(url, **kwargs):
        return httpx.Response(
            200,
            json={"choices": [{"message": {"content": "not valid json at all"}}]},
            request=httpx.Request("POST", url),
        )

    monkeypatch.setattr(httpx, "post", fake_post)

    result = sarvam.structure_dpr_from_transcript("the original transcript text", "test-key")

    # Falls back to the raw transcript rather than losing the engineer's report.
    assert result["work_summary"] == "the original transcript text"
    assert result["manpower_count"] == 0


def test_structure_dpr_from_transcript_falls_back_when_content_is_none(monkeypatch):
    # Real Sarvam behavior, not hypothetical: sarvam-105b is a reasoning model
    # with a separate reasoning_content field -- if max_tokens is too low it
    # gets cut off (finish_reason: "length") before emitting `content` at all,
    # and `content` comes back None. Caught by a live call during development.
    def fake_post(url, **kwargs):
        return httpx.Response(
            200,
            json={
                "choices": [
                    {
                        "finish_reason": "length",
                        "message": {"content": None, "reasoning_content": "still thinking...", "role": "assistant"},
                    }
                ]
            },
            request=httpx.Request("POST", url),
        )

    monkeypatch.setattr(httpx, "post", fake_post)

    result = sarvam.structure_dpr_from_transcript("the original transcript text", "test-key")

    assert result["work_summary"] == "the original transcript text"
    assert result["manpower_count"] == 0
