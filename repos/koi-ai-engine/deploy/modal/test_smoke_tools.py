"""Offline tests of tools/trace_check.py and tools/health_check.py against local apps (never the live service)."""
import importlib.util
import json
import socket
import threading
import time
from pathlib import Path

import pytest
import uvicorn
from fastapi import FastAPI, Request
from fastapi.responses import PlainTextResponse, RedirectResponse

from chat_core import build_app
from crisis_client import FakeCrisisClient

TOOLS = Path(__file__).resolve().parent / "tools"


def _load(name):
    spec = importlib.util.spec_from_file_location(name, TOOLS / (name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


tc = _load("trace_check")
hc = _load("health_check")


class _Output:
    def __init__(self, text):
        self.outputs = [type("Choice", (), {"text": text})()]


class _Engine:
    def __init__(self, text='{"companion_state":{"emotion":"neutral","intensity":0.3},"reply":"I am here."}'):
        self.text = text

    async def generate(self, prompt, params, request_id):
        yield _Output(self.text)


class _Tokenizer:
    def apply_chat_template(self, messages, **kwargs):
        return str(messages)

    def __call__(self, prompt, **kwargs):
        return {"input_ids": list(prompt)}


def _serve(app):
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        port = s.getsockname()[1]
    server = uvicorn.Server(uvicorn.Config(app, host="127.0.0.1", port=port, log_level="error"))
    thread = threading.Thread(target=server.run, daemon=True)
    thread.start()
    for _ in range(100):
        if server.started:
            break
        time.sleep(0.05)
    return server, thread, "http://127.0.0.1:%d" % port


@pytest.fixture
def serve():
    running = []

    def start(app):
        server, thread, base = _serve(app)
        running.append((server, thread))
        return base
    yield start
    for server, thread in running:
        server.should_exit = True
        thread.join(timeout=5)


@pytest.fixture
def exercises_on(monkeypatch):
    monkeypatch.setenv("KOI_EXERCISES", "1")
    monkeypatch.setenv("KOI_DIRECTOR_SECRET", "local-test-secret")
    monkeypatch.delenv("KOI_DEBUG_TRACE", raising=False)


def _chat(engine=None):
    return build_app(engine or _Engine(), _Tokenizer(), lambda token: {"sub": "local"},
                     lambda schema, **kwargs: kwargs,
                     {"crisis_client": FakeCrisisClient({"status": "ok", "risk_category": "LOW", "crisis_score": 0.1})})


def _results(out):
    return {line.split()[1]: line.split()[2] for line in out.splitlines() if line.startswith("RESULT ")}


def test_trace_check_passes_on_trace_off_chat(serve, exercises_on, capsys):
    base = serve(_chat())
    assert tc.run(base, "local-test-token") == 0
    results = _results(capsys.readouterr().out)
    assert results == {name: "PASS" for name in
                       ("trace_absent", "greeting_delta", "spacing_full_text", "risk_present", "contract")}


def test_trace_check_fails_when_trace_is_on(serve, exercises_on, monkeypatch, capsys):
    monkeypatch.setenv("KOI_DEBUG_TRACE", "1")
    base = serve(_chat())
    assert tc.run(base, "local-test-token") == 1
    assert _results(capsys.readouterr().out)["trace_absent"] == "FAIL"


def test_empty_model_reply_still_gives_a_greeting_delta(serve, exercises_on, capsys):
    base = serve(_chat(_Engine("")))
    tc.run(base, "local-test-token")
    assert _results(capsys.readouterr().out)["greeting_delta"] == "PASS"


def test_spacing_check_flags_unspaced_sentences():
    events = [("delta", {"text": "Breathe in."}), ("delta", {"text": "Breathe out."}),
              ("done", {"full_text": "Breathe in.Breathe out."})]
    assert tc.spacing_problems(events) == ["delta 1 has no leading space"]
    assert tc.spacing_problems([("delta", {"text": "one"}), ("done", {"full_text": "one"})])


def test_trace_check_follows_repeated_303_poll_redirects(serve, capsys):
    """Modal answers slow requests with 303 to a poll URL (followed as GET), possibly many times in a row."""
    stream = "".join("event: %s\ndata: %s\n\n" % (name, json.dumps(data)) for name, data in (
        ("companion_state", {"emotion": "neutral", "intensity": 0.4}),
        ("risk", {"status": "ok", "risk_category": "LOW"}),
        ("delta", {"text": "Breathe in."}), ("delta", {"text": " Breathe out."}),
        ("state", {"exercise_state": None}),
        ("done", {"full_text": "Breathe in. Breathe out.", "companion_state": {"emotion": "neutral", "intensity": 0.4},
                  "risk": {"status": "ok", "risk_category": "LOW"}})))
    app, hops = FastAPI(), {"n": 0}

    @app.post("/api/v1/chat")
    async def chat():
        return RedirectResponse("/poll", status_code=303)

    @app.get("/poll")
    async def poll(request: Request):
        hops["n"] += 1
        if hops["n"] % 7:  # 6 same-URL repeats per turn; urllib's default limit gives up after 4
            return RedirectResponse("/poll", status_code=303)
        return PlainTextResponse(stream, media_type="text/event-stream")

    assert tc.run(serve(app), "local-test-token") == 0
    assert hops["n"] == 7 * 5
    assert set(_results(capsys.readouterr().out).values()) == {"PASS"}


def _crisis(body):
    app = FastAPI()

    @app.get("/health")
    async def health():
        return body
    return app


@pytest.mark.parametrize("body,rc", [
    ({"status": "ok", "max_category": "HIGH", "rag_enabled": False, "rag_assets_loaded": False}, 0),
    ({"status": "ok", "max_category": "CRITICAL", "rag_enabled": False}, 1),
    ({"status": "ok", "max_category": "HIGH", "rag_enabled": True}, 1),
    ({"status": "ok", "max_category": "HIGH"}, 1),
])
def test_health_check_no_token(serve, body, rc, capsys):
    assert hc.main([serve(_chat()), serve(_crisis(body))]) == rc
    out = capsys.readouterr().out
    assert ("RESULT health" in out) and (("PASS" if rc == 0 else "FAIL") in out.splitlines()[-1])


def test_health_check_fails_when_crisis_is_down(serve, capsys):
    assert hc.main([serve(_chat()), "http://127.0.0.1:1"]) == 1
