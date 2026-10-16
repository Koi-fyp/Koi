import json
import random
import sys
import types

import httpx
import pytest

from chat_core import build_app
from stream_extract import extract


@pytest.mark.parametrize("payload", [
    {"companion_state": {"emotion": "neutral", "intensity": 0.2}, "reply": 'say "hi"'},
    {"companion_state": {"emotion": "joy", "intensity": 0.8}, "reply": "slash \\\\ and /"},
    {"companion_state": {"emotion": "sorrow", "intensity": 0.4}, "reply": "line\nbreak"},
    {"companion_state": {"emotion": "fun", "intensity": 0.5}, "reply": "\u00e9"},
    {"companion_state": {"emotion": "joy", "intensity": 0.5}, "reply": "\U0001f600"},
    {"companion_state": {"emotion": "neutral", "intensity": 0.3}, "reply": "اردو"},
])
def test_extractor_chunk_boundaries(payload):
    raw = json.dumps(payload, ensure_ascii=True)
    for seed in range(200):
        random.seed(seed)
        cuts, i = [], 0
        while i < len(raw):
            n = random.randint(1, 5)
            cuts.append(raw[i:i+n])
            i += n
        result = extract(cuts)
        assert result[0][1] == payload["companion_state"]
        assert result[1][1] == payload["reply"]


class _Output:
    def __init__(self, text):
        self.outputs = [type("Choice", (), {"text": text})()]


class _Engine:
    async def generate(self, prompt, params, request_id):
        yield _Output('{"companion_state":{"emotion":"joy","intensity":0.5},"reply":"hello"}')


class _Tokenizer:
    def apply_chat_template(self, messages, **kwargs):
        return str(messages)

    def __call__(self, prompt, **kwargs):
        return {"input_ids": list(prompt)}


async def _client(risk=None):
    app = build_app(_Engine(), _Tokenizer(), lambda token: {"sub": "test"},
                    lambda schema, **kwargs: kwargs,
                    {"crisis_client": __import__("crisis_client").FakeCrisisClient(
                        risk or {"status": "unavailable"})})
    return httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test")


@pytest.mark.asyncio
async def test_normal_event_contract():
    async with await _client({"status": "ok", "risk_category": "LOW", "is_new": True}) as client:
        response = await client.post("/api/v1/chat", headers={"Authorization": "Bearer t"},
                                     json={"message": "hi"})
    events = [line[7:] for line in response.text.splitlines() if line.startswith("event: ")]
    assert events == ["latency", "companion_state", "risk", "delta", "state", "done"]
    frames = response.text.strip().split("\n\n")
    delta = json.loads(next(frame.split("data: ", 1)[1] for frame in frames if frame.startswith("event: delta")))
    assert "{" not in delta["text"]


@pytest.mark.asyncio
async def test_invalid_role_and_auth():
    async with await _client() as client:
        assert (await client.post("/api/v1/chat", json={"message": "x"})).status_code == 401
        assert (await client.post("/api/v1/chat", headers={"Authorization": "Bearer " + "test"},
                                  json={"message": "x", "session_history": [{"role": "system", "content": "x"}]})).status_code == 422


def _frames(text):
    frames = []
    for raw in text.strip().split("\n\n"):
        lines = raw.splitlines()
        events = [line[7:] for line in lines if line.startswith("event: ")]
        data = [line[6:] for line in lines if line.startswith("data: ")]
        assert len(events) == 1
        assert len(data) == 1
        frames.append((events[0], json.loads(data[0])))
    return frames


@pytest.mark.asyncio
async def test_real_shaped_stream_and_director_fallback_contract(monkeypatch):
    def handle_turn(*args, **kwargs):
        return [
            {"type": "companion_state", "emotion": "joy", "intensity": 1.043729},
            {"type": "sentence", "text": "Reviewed line one."},
            {"type": "state", "token": "signed-state"},
            {"type": "state", "token": "signed-state"},
        ]

    monkeypatch.setitem(sys.modules, "director", types.SimpleNamespace(handle_turn=handle_turn))
    monkeypatch.setenv("KOI_EXERCISES", "1")
    monkeypatch.setenv("KOI_DIRECTOR_SECRET", "test-secret")
    monkeypatch.setenv("KOI_DEBUG_TRACE", "1")

    async with await _client({"status": "ok", "risk_category": "LOW", "is_new": True}) as client:
        response = await client.post(
            "/api/v1/chat",
            headers={"Authorization": "Bearer " + "test"},
            json={"message": "hello", "risk": {"risk_category": "LOW", "is_new": True}},
        )
    frames = _frames(response.text)
    names = [name for name, _ in frames]
    deltas = [payload["text"] for name, payload in frames if name == "delta"]
    streamed_state = next(payload for name, payload in frames if name == "companion_state")
    done = next(payload for name, payload in frames if name == "done")
    assert names.count("state") == 1
    assert deltas == ["Reviewed line one."]
    assert done["full_text"] == "".join(deltas)
    assert done["companion_state"] == streamed_state
    assert streamed_state["intensity"] == 1.0
    assert done["companion_state"]["intensity"] == 1.0
    assert any("raw model text len=" in line for line in done["trace"])


@pytest.mark.asyncio
async def test_normal_reply_is_not_suppressed_by_director_state(monkeypatch):
    def handle_turn(*args, **kwargs):
        return [{"type": "state", "token": "signed-state"}]

    monkeypatch.setitem(sys.modules, "director", types.SimpleNamespace(handle_turn=handle_turn))
    monkeypatch.setenv("KOI_EXERCISES", "1")
    monkeypatch.setenv("KOI_DIRECTOR_SECRET", "test-secret")
    monkeypatch.delenv("KOI_DEBUG_TRACE", raising=False)

    async with await _client() as client:
        response = await client.post(
            "/api/v1/chat",
            headers={"Authorization": "Bearer " + "test"},
            json={"message": "hello", "risk": {"risk_category": "LOW", "is_new": True}},
        )
    frames = _frames(response.text)
    deltas = [payload["text"] for name, payload in frames if name == "delta"]
    done = next(payload for name, payload in frames if name == "done")
    assert deltas == ["hello"]
    assert done["full_text"] == "hello"
    return

    async with await _client() as client:
        assert (await client.post("/api/v1/chat", json={"message": "x"})).status_code == 401
        assert (await client.post("/api/v1/chat", headers={"Authorization": "Bearer t"},
                                  json={"message": "x", "session_history": [{"role": "system", "content": "x"}]})).status_code == 422
