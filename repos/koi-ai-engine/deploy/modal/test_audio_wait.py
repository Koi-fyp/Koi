"""KOI_AUDIO_WAIT_S: pre-reply score wait for audio turns only; a late transcript is a 422, never a 500."""
import json
import sys

import httpx
import pytest

import chat_core
from chat_core import build_app
from crisis_client import FakeCrisisClient

TRANSCRIPT_RISK = {"status": "ok", "risk_category": "LOW", "transcript": "hello from audio", "language": "en"}
LATE_DETAIL = "audio transcription did not complete in time"


class Output:
    def __init__(self, text):
        self.outputs = [type("Choice", (), {"text": text})()]


class Engine:
    async def generate(self, prompt, params, request_id):
        yield Output('{"companion_state":{"emotion":"joy","intensity":0.5},"reply":"hello"}')


class Tokenizer:
    def apply_chat_template(self, messages, **kwargs):
        return str(messages)

    def __call__(self, prompt, **kwargs):
        return {"input_ids": list(prompt)}


async def _post(crisis, payload, audio=True):
    app = build_app(Engine(), Tokenizer(), lambda token: {"sub": "test"},
                    lambda schema, **kwargs: kwargs, {"crisis_client": crisis})
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test") as http:
        headers = {"Authorization": "Bearer test"}
        if not audio:
            return await http.post("/api/v1/chat", headers=headers, json=payload)
        return await http.post("/api/v1/chat", headers=headers, files={
            "payload": (None, json.dumps(payload)), "audio": ("voice.wav", b"audio")})


@pytest.fixture
def plain_env(monkeypatch):
    for name in ("KOI_AUDIO_WAIT_S", "KOI_EXERCISES", "KOI_REPLY_BACKEND"):
        monkeypatch.delenv(name, raising=False)
    return monkeypatch


@pytest.fixture
def waits(plain_env):
    """Records the pre-reply timeout chat() passes to asyncio.wait_for."""
    seen = []
    original = chat_core.asyncio.wait_for

    def spy(awaitable, timeout):
        if sys._getframe(1).f_code.co_name == "chat":
            seen.append(timeout)
        return original(awaitable, timeout)

    plain_env.setattr(chat_core.asyncio, "wait_for", spy)
    return seen


@pytest.mark.parametrize("value", [None, "", "abc", "0", "-1", "-0.5", "nan", "inf"])
def test_invalid_or_unset_audio_wait_falls_back_to_3(plain_env, value):
    if value is not None:
        plain_env.setenv("KOI_AUDIO_WAIT_S", value)
    assert chat_core._audio_wait_s() == 3.0


@pytest.mark.parametrize("value,expected", [("10", 10.0), ("0.5", 0.5), ("4.25", 4.25)])
def test_valid_audio_wait_is_used(plain_env, value, expected):
    plain_env.setenv("KOI_AUDIO_WAIT_S", value)
    assert chat_core._audio_wait_s() == expected


@pytest.mark.asyncio
@pytest.mark.parametrize("env,audio,payload,expected", [
    (None, True, {"language": "en"}, 3.0),
    (None, False, {"message": "hi"}, 1.0),
    (None, False, {"message": "hi", "exercise_state": "tok"}, 3.0),
    (None, False, {"message": "hi", "client_event": "start_breathing"}, 3.0),
    ("10", True, {"language": "en"}, 10.0),
    ("10", False, {"message": "hi"}, 1.0),
    ("10", False, {"message": "hi", "exercise_state": "tok"}, 3.0),
    ("10", False, {"message": "hi", "client_event": "start_plan"}, 3.0),
    ("1", True, {"language": "en", "client_event": "start_breathing"}, 3.0),
    ("abc", True, {"language": "en"}, 3.0),
])
async def test_pre_reply_wait_by_turn_kind(waits, plain_env, env, audio, payload, expected):
    if env is not None:
        plain_env.setenv("KOI_AUDIO_WAIT_S", env)
    response = await _post(FakeCrisisClient(TRANSCRIPT_RISK), payload, audio=audio)
    assert response.status_code == 200, response.text
    assert waits[0] == expected


@pytest.mark.asyncio
async def test_env_10_accepts_transcript_at_6s(plain_env):
    plain_env.setenv("KOI_AUDIO_WAIT_S", "10")
    response = await _post(FakeCrisisClient(TRANSCRIPT_RISK, delay=6), {"language": "en"})
    assert response.status_code == 200, response.text
    frames = [part.splitlines() for part in response.text.strip().split("\n\n")]
    events = {lines[0][7:]: json.loads(lines[1][6:]) for lines in frames}
    assert events["transcript"]["text"] == "hello from audio"
    assert events["done"]["full_text"] == "hello"


@pytest.mark.asyncio
async def test_default_wait_rejects_transcript_at_6s_with_422(plain_env):
    response = await _post(FakeCrisisClient(TRANSCRIPT_RISK, delay=6), {"language": "en"})
    assert response.status_code == 422
    assert response.json() == {"detail": LATE_DETAIL}
    assert "Traceback" not in response.text


@pytest.mark.asyncio
async def test_audio_scored_without_transcript_is_422_not_late(plain_env):
    response = await _post(FakeCrisisClient({"status": "unavailable"}), {"language": "en"})
    assert response.status_code == 422
    assert response.json() == {"detail": "audio transcription returned no transcript"}


@pytest.mark.asyncio
async def test_empty_text_message_422_does_not_mention_audio_scoring(plain_env):
    response = await _post(FakeCrisisClient({"status": "ok", "risk_category": "LOW"}), {"message": ""}, audio=False)
    assert response.status_code == 422
    assert response.json() == {"detail": "message is required"}
    assert "audio scoring" not in response.text
