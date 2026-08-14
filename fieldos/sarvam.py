"""Sarvam AI integration for voice-to-DPR (Track B of the automation
roadmap). This is the one place FieldOS calls out to the internet -- the
rest of the app is fully offline by design. If SARVAM_API_KEY isn't
configured, voice-to-DPR simply isn't offered; nothing else depends on it.
"""

import json

import httpx

from fieldos.config import settings

STT_URL = "https://api.sarvam.ai/speech-to-text"
CHAT_URL = "https://api.sarvam.ai/v1/chat/completions"

STRUCTURE_SYSTEM_PROMPT = """You turn a construction site engineer's spoken \
daily progress report into structured JSON. Extract only what's actually \
said -- don't invent details. Output ONLY a JSON object, no other text, \
with exactly these keys:
{
  "work_summary": "<a clean written summary of the work described, in English>",
  "manpower_count": <integer number of workers mentioned, or 0 if not mentioned>,
  "weather": "<one word/short phrase for weather if mentioned, else null>"
}"""


class SarvamNotConfigured(Exception):
    pass


def _require_key() -> str:
    if not settings.sarvam_api_key:
        raise SarvamNotConfigured("SARVAM_API_KEY is not set")
    return settings.sarvam_api_key


def transcribe_audio(audio_bytes: bytes, filename: str, language_code: str = "unknown") -> str:
    resp = httpx.post(
        STT_URL,
        headers={"api-subscription-key": _require_key()},
        data={"model": "saaras:v3", "language_code": language_code, "with_timestamps": "false"},
        files={"file": (filename, audio_bytes)},
        timeout=120.0,
    )
    resp.raise_for_status()
    return resp.json()["transcript"]


def structure_dpr_from_transcript(transcript: str) -> dict:
    resp = httpx.post(
        CHAT_URL,
        headers={"api-subscription-key": _require_key()},
        json={
            "model": "sarvam-105b",
            "messages": [
                {"role": "system", "content": STRUCTURE_SYSTEM_PROMPT},
                {"role": "user", "content": transcript},
            ],
            "temperature": 0.1,
            # sarvam-105b is a reasoning model -- it spends tokens on a separate
            # reasoning_content field before emitting the final `content`. Too
            # low a budget here means it gets cut off (finish_reason: "length")
            # mid-thought and `content` comes back None. 500 was nowhere near
            # enough; this was found by an actual truncated response, not a guess.
            "max_tokens": 2000,
        },
        timeout=60.0,
    )
    resp.raise_for_status()
    content = resp.json()["choices"][0]["message"].get("content")
    if not content:
        # Truncated before producing an answer, or some other malformed
        # response -- never lose the engineer's report over it.
        return {"work_summary": transcript, "manpower_count": 0, "weather": None}
    try:
        # Models occasionally wrap JSON in a fenced code block despite instructions.
        cleaned = content.strip().removeprefix("```json").removeprefix("```").removesuffix("```").strip()
        parsed = json.loads(cleaned)
    except (json.JSONDecodeError, ValueError):
        return {"work_summary": transcript, "manpower_count": 0, "weather": None}

    return {
        "work_summary": parsed.get("work_summary") or transcript,
        "manpower_count": int(parsed.get("manpower_count") or 0),
        "weather": parsed.get("weather") or None,
    }
