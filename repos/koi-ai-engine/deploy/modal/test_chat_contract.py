import json
import random

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


async def _client():
    app = build_app(_Engine(), _Tokenizer(), lambda token: {"sub": "test"},
                    lambda schema, **kwargs: kwargs)
    return httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test")


@pytest.mark.asyncio
async def test_normal_event_contract():
    async with await _client() as client:
        response = await client.post("/api/v1/chat", headers={"Authorization": "Bearer t"},
                                     json={"message": "hi"})
    events = [line[7:] for line in response.text.splitlines() if line.startswith("event: ")]
    assert events == ["latency", "companion_state", "delta", "done"]
    frames = response.text.strip().split("\n\n")
    delta = json.loads(next(frame.split("data: ", 1)[1] for frame in frames if frame.startswith("event: delta")))
    assert "{" not in delta["text"]


@pytest.mark.asyncio
async def test_invalid_role_and_auth():
    async with await _client() as client:
        assert (await client.post("/api/v1/chat", json={"message": "x"})).status_code == 401
        assert (await client.post("/api/v1/chat", headers={"Authorization": "Bearer t"},
                                  json={"message": "x", "session_history": [{"role": "system", "content": "x"}]})).status_code == 422
