import json
import os

import httpx
import pytest

from chat_core import SYSTEM_PROMPT, build_app
from crisis_client import CrisisClient, FakeCrisisClient, ModalCrisisClient


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


def client(result=None):
    app = build_app(
        Engine(), Tokenizer(), lambda token: {"sub": "test"},
        lambda schema, **kwargs: kwargs,
        {"crisis_client": FakeCrisisClient(result or {"status": "ok", "risk_category": "LOW"})},
    )
    return httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test")


@pytest.mark.asyncio
async def test_multipart_text_video_is_accepted():
    async with client() as http:
        response = await http.post(
            "/api/v1/chat",
            headers={"Authorization": "Bearer test"},
            files={
                "payload": (None, json.dumps({"message": "hello", "language": "en"})),
                "video": ("clip.mp4", b"video"),
            },
        )
    assert response.status_code == 200
    assert "event: risk" in response.text


@pytest.mark.asyncio
async def test_multipart_text_audio_is_rejected():
    async with client() as http:
        response = await http.post(
            "/api/v1/chat",
            headers={"Authorization": "Bearer test"},
            files={
                "payload": (None, json.dumps({"message": "hello"})),
                "audio": ("voice.wav", b"audio"),
            },
        )
    assert response.status_code == 422


@pytest.mark.asyncio
async def test_crisis_client_lookup_failure_is_unavailable():
    def broken(**kwargs):
        raise RuntimeError("lookup failed")

    result = await CrisisClient(broken).score_async(
        text="hello", audio_bytes=None, video_bytes=None,
        language=None, turn_id=None, uid="u",
    )
    assert result == {"status": "unavailable"}


@pytest.mark.asyncio
async def test_slow_risk_fails_closed_for_exercise_start(monkeypatch):
    monkeypatch.setenv("KOI_EXERCISES", "1")
    monkeypatch.setenv("KOI_DIRECTOR_SECRET", "secret")
    seen = {}

    def handle_turn(turn, state, **kwargs):
        seen["tier"] = turn.get("tier")
        return []

    import sys
    import types
    monkeypatch.setitem(sys.modules, "director", types.SimpleNamespace(handle_turn=handle_turn))
    app = build_app(
        Engine(), Tokenizer(), lambda token: {"sub": "test"},
        lambda schema, **kwargs: kwargs,
        {"crisis_client": FakeCrisisClient(
            {"status": "ok", "risk_category": "LOW"}, delay=4.2)},
    )
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test") as http:
        response = await http.post(
            "/api/v1/chat", headers={"Authorization": "Bearer test"},
            json={"message": "start", "client_event": "start_plan"},
        )
    assert response.status_code == 200
    assert seen["tier"] is None


@pytest.mark.asyncio
async def test_high_risk_stops_active_exercise(monkeypatch):
    monkeypatch.setenv("KOI_EXERCISES", "1")
    monkeypatch.setenv("KOI_DIRECTOR_SECRET", "secret")
    import sys
    import types
    monkeypatch.setitem(sys.modules, "director", types.SimpleNamespace(
        on_risk=lambda token, tier, now, **kwargs: [
            {"type": "handoff", "to": "crisis", "reason": "urgent"},
        ],
        handle_turn=lambda *args, **kwargs: [],
    ))
    app = build_app(
        Engine(), Tokenizer(), lambda token: {"sub": "test"},
        lambda schema, **kwargs: kwargs,
        {"crisis_client": FakeCrisisClient(
            {"status": "ok", "risk_category": "HIGH", "crisis_score": 0.9})},
    )
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test") as http:
        response = await http.post(
            "/api/v1/chat", headers={"Authorization": "Bearer test"},
            json={"message": "unsafe", "exercise_state": "signed"},
        )
    assert response.status_code == 200
    assert '"to": "crisis"' in response.text


@pytest.mark.asyncio
async def test_risk_post_reply_cap_emits_unavailable():
    app = build_app(
        Engine(), Tokenizer(), lambda token: {"sub": "test"},
        lambda schema, **kwargs: kwargs,
        {"crisis_client": FakeCrisisClient(
            {"status": "ok", "risk_category": "LOW"}, delay=6.0)},
    )
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test") as http:
        response = await http.post(
            "/api/v1/chat", headers={"Authorization": "Bearer test"},
            json={"message": "hello"},
        )
    frames = [json.loads(part.split("data: ", 1)[1])
              for part in response.text.strip().split("\n\n")
              if part.startswith("event: risk") or part.startswith("event: done")]
    assert frames[0] == {"status": "unavailable"}
    assert frames[-1]["risk"] == {"status": "unavailable"}


@pytest.mark.asyncio
async def test_audio_emits_transcript_before_companion_state():
    result = {
        "status": "ok", "risk_category": "LOW", "transcript": "hello from audio",
        "language": "en", "crisis_score": 0.1,
    }
    app = build_app(
        Engine(), Tokenizer(), lambda token: {"sub": "test"},
        lambda schema, **kwargs: kwargs,
        {"crisis_client": FakeCrisisClient(result)},
    )
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test") as http:
        response = await http.post(
            "/api/v1/chat", headers={"Authorization": "Bearer test"},
            files={
                "payload": (None, json.dumps({"language": "en"})),
                "audio": ("voice.wav", b"audio"),
            },
        )
    assert response.status_code == 200
    names = [part.splitlines()[0][7:] for part in response.text.strip().split("\n\n")]
    assert names.index("transcript") < names.index("companion_state")


@pytest.mark.asyncio
async def test_deprecated_client_risk_is_ignored():
    import sys
    import types
    seen = {}

    def handle_turn(turn, state, **kwargs):
        seen["tier"] = turn.get("tier")
        return []

    monkeypatch = pytest.MonkeyPatch()
    monkeypatch.setenv("KOI_EXERCISES", "1")
    monkeypatch.setenv("KOI_DIRECTOR_SECRET", "secret")
    monkeypatch.setitem(sys.modules, "director", types.SimpleNamespace(handle_turn=handle_turn))
    try:
        app = build_app(
            Engine(), Tokenizer(), lambda token: {"sub": "test"},
            lambda schema, **kwargs: kwargs,
            {"crisis_client": FakeCrisisClient({"status": "ok", "risk_category": "HIGH"})},
        )
        async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test") as http:
            response = await http.post(
                "/api/v1/chat", headers={"Authorization": "Bearer test"},
                json={"message": "hello", "risk": {"risk_category": "LOW"}},
            )
        assert response.status_code == 200
        assert seen["tier"] == "HIGH"
    finally:
        monkeypatch.undo()


def test_system_prompt_preserves_language_and_script():
    assert "same language and script" in SYSTEM_PROMPT
    assert "English, Urdu, or Roman Urdu" in SYSTEM_PROMPT


@pytest.mark.asyncio
async def test_modal_crisis_client_uses_lookup_and_remote(monkeypatch):
    class Remote:
        def remote(self, **kwargs):
            return {"status": "ok", "risk_category": "LOW"}

    class Service:
        score = Remote()

        def lookup(self):
            return self

    class Modal:
        class Function:
            @staticmethod
            def from_name(app, name):
                assert (app, name) == ("koi-crisis", "Crisis")
                return Service()

    import sys
    monkeypatch.setitem(sys.modules, "modal", Modal)
    result = await ModalCrisisClient().score_async(
        text="hello", audio_bytes=None, video_bytes=None,
        language=None, turn_id=None, uid="u",
    )
    assert result["risk_category"] == "LOW"


@pytest.mark.asyncio
async def test_unavailable_crisis_client_does_not_block_health():
    app = build_app(
        Engine(), Tokenizer(), lambda token: {"sub": "test"},
        lambda schema, **kwargs: kwargs,
        {"crisis_client": FakeCrisisClient({"status": "unavailable"})},
    )
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test") as http:
        response = await http.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}
