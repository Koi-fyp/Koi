"""Offline test of agent_tasks/multipart_smoke.py against the local chat app (never the live service)."""
import importlib.util
import socket
import threading
import time
from pathlib import Path

import pytest
import uvicorn

from chat_core import build_app
from crisis_client import CrisisClient

ROOT = Path(__file__).resolve().parent.parent.parent
_spec = importlib.util.spec_from_file_location("multipart_smoke", ROOT / "agent_tasks" / "multipart_smoke.py")
ms = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(ms)


class _Output:
    def __init__(self, text):
        self.outputs = [type("Choice", (), {"text": text})()]


class _Engine:
    async def generate(self, prompt, params, request_id):
        yield _Output('{"companion_state":{"emotion":"neutral","intensity":0.3},"reply":"I am here."}')


class _Tokenizer:
    def apply_chat_template(self, messages, **kwargs):
        return str(messages)

    def __call__(self, prompt, **kwargs):
        return {"input_ids": list(prompt)}


SEEN = []


def _scorer(transcribes):
    def score(**kwargs):
        SEEN.append({k: (len(v) if isinstance(v, bytes) else v) for k, v in kwargs.items()})
        result = {"status": "ok", "risk_category": "LOW", "crisis_score": 0.1,
                  "modalities_used": ["text"], "trigger_flags": []}
        if kwargs["audio_bytes"] and transcribes:
            result.update(transcript="hello from audio", language="en")
        return result
    return score


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
def local_chat(request):
    transcribes = getattr(request, "param", True)
    app = build_app(_Engine(), _Tokenizer(), lambda token: {"sub": "local"},
                    lambda schema, **kwargs: kwargs,
                    {"crisis_client": CrisisClient(_scorer(transcribes))})
    server, thread, base = _serve(app)
    SEEN.clear()
    yield base
    server.should_exit = True
    thread.join(timeout=5)


def test_requires_token(monkeypatch, capsys):
    monkeypatch.delenv("KOI_TOKEN", raising=False)
    assert ms.main(["http://127.0.0.1:1"]) == 2


def test_silent_wav_is_two_seconds():
    import io
    import wave
    with wave.open(io.BytesIO(ms.silent_wav()), "rb") as w:
        assert (w.getnchannels(), w.getframerate(), w.getnframes()) == (1, 16000, 32000)


def test_without_ffmpeg_skips_video_and_runs_audio(local_chat, monkeypatch, capsys):
    monkeypatch.setenv("KOI_TOKEN", "local-test-token")
    assert ms.main([local_chat], ffmpeg="") == 0
    out = capsys.readouterr().out
    assert "ffmpeg: not found (video cases skipped)" in out
    assert out.count("SKIPPED: ffmpeg not found on PATH") == 2
    # Current server order: transcript precedes latency (recorded in HANDOFF_FOR_REDEPLOY.md).
    assert "events: transcript latency companion_state risk delta state done" in out
    assert 'transcript: {"text": "hello from audio", "language": "en"}' in out
    assert "risk: " in out
    assert "RESULT: OK" in out
    assert SEEN[0]["audio_bytes"] == len(ms.silent_wav()) and SEEN[0]["video_bytes"] is None


def test_all_three_combinations_with_generated_video(local_chat, monkeypatch, capsys):
    monkeypatch.setenv("KOI_TOKEN", "local-test-token")
    monkeypatch.setattr(ms, "small_mp4", lambda ffmpeg: b"\x00\x00\x00\x18ftypmp42fake-mp4")
    assert ms.main([local_chat], ffmpeg="ffmpeg") == 0
    out = capsys.readouterr().out
    assert "SKIPPED" not in out
    for name in ("=== audio", "=== text+video", "=== audio+video"):
        assert name in out
    assert out.count("events:") == 3
    assert "RESULT: OK" in out
    assert [(s["text"] is not None, bool(s["audio_bytes"]), bool(s["video_bytes"])) for s in SEEN] == [
        (False, True, False), (True, False, True), (False, True, True)]


@pytest.mark.parametrize("local_chat", [False], indirect=True)
def test_silent_audio_without_transcript_is_reported_not_failed(local_chat, monkeypatch, capsys):
    monkeypatch.setenv("KOI_TOKEN", "local-test-token")
    assert ms.main([local_chat], ffmpeg="") == 0
    out = capsys.readouterr().out
    assert "HTTP 422" in out and "expected for silent audio" in out


def test_check_order_flags_contract_violations():
    assert ms.check_order(["latency", "transcript", "companion_state", "risk", "delta", "state", "done"]) == []
    assert ms.check_order(["latency", "companion_state", "risk", "error", "state", "done"]) == []
    problems = ms.check_order(["latency", "delta", "companion_state", "done"])
    assert "companion_state after first delta/error" in problems
    assert "expected exactly one risk event, got 0" in problems
    assert "state is not immediately before done" in problems
