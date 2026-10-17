"""done.language: ASR language from the server's risk result, else the request's `language`, else null."""
import json

import httpx
import pytest

from chat_core import build_app
from crisis_client import FakeCrisisClient


class Output:
    def __init__(self, text):
        self.outputs = [type("Choice", (), {"text": text})()]


class Engine:
    async def generate(self, prompt, params, request_id):
        yield Output('{"companion_state":{"emotion":"neutral","intensity":0.4},"reply":"hello"}')


class Tokenizer:
    def apply_chat_template(self, messages, **kwargs):
        return str(messages)

    def __call__(self, prompt, **kwargs):
        return {"input_ids": list(prompt)}


async def _done(risk, body):
    app = build_app(Engine(), Tokenizer(), lambda token: {"sub": "test"},
                    lambda schema, **kwargs: kwargs, {"crisis_client": FakeCrisisClient(risk)})
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test") as http:
        response = await http.post("/api/v1/chat", headers={"Authorization": "Bearer test"}, json=body)
    assert response.status_code == 200
    frames = [f for f in response.text.split("\n\n") if f.startswith("event: done")]
    return json.loads(frames[-1].split("data: ", 1)[1])


@pytest.mark.asyncio
async def test_done_language_echoes_request_language():
    done = await _done({"status": "ok", "risk_category": "LOW"}, {"message": "hello", "language": "ur-roman"})
    assert done["language"] == "ur-roman"


@pytest.mark.asyncio
async def test_done_language_prefers_asr_language_from_risk():
    risk = {"status": "ok", "risk_category": "LOW", "transcript": "salaam", "language": "ur"}
    done = await _done(risk, {"message": "salaam", "language": "en"})
    assert done["language"] == "ur"


@pytest.mark.asyncio
async def test_done_language_is_null_without_a_source():
    done = await _done({"status": "unavailable"}, {"message": "hello"})
    assert "language" in done and done["language"] is None
    assert "trace" not in done
