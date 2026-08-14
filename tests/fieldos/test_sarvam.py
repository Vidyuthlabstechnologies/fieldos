import httpx
import pytest

from fieldos import sarvam


def test_transcribe_audio_raises_when_not_configured(monkeypatch):
    monkeypatch.setattr(sarvam.settings, "sarvam_api_key", "")
    with pytest.raises(sarvam.SarvamNotConfigured):
        sarvam.transcribe_audio(b"fake audio bytes", "test.wav")


def test_structure_dpr_from_transcript_parses_clean_json(monkeypatch):
    def fake_post(url, **kwargs):
        assert url == sarvam.CHAT_URL
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

    monkeypatch.setattr(sarvam.settings, "sarvam_api_key", "fake-key")
    monkeypatch.setattr(httpx, "post", fake_post)

    result = sarvam.structure_dpr_from_transcript("we poured column footings today with 12 workers")

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

    monkeypatch.setattr(sarvam.settings, "sarvam_api_key", "fake-key")
    monkeypatch.setattr(httpx, "post", fake_post)

    result = sarvam.structure_dpr_from_transcript("some transcript")

    assert result["work_summary"] == "Test"
    assert result["manpower_count"] == 5


def test_structure_dpr_from_transcript_falls_back_on_malformed_json(monkeypatch):
    def fake_post(url, **kwargs):
        return httpx.Response(
            200,
            json={"choices": [{"message": {"content": "not valid json at all"}}]},
            request=httpx.Request("POST", url),
        )

    monkeypatch.setattr(sarvam.settings, "sarvam_api_key", "fake-key")
    monkeypatch.setattr(httpx, "post", fake_post)

    result = sarvam.structure_dpr_from_transcript("the original transcript text")

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

    monkeypatch.setattr(sarvam.settings, "sarvam_api_key", "fake-key")
    monkeypatch.setattr(httpx, "post", fake_post)

    result = sarvam.structure_dpr_from_transcript("the original transcript text")

    assert result["work_summary"] == "the original transcript text"
    assert result["manpower_count"] == 0
