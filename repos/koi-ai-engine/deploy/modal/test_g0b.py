"""Batch g0b: H03 (start that cannot start), H05 (early 422), H02 (late HIGH risk -> handoff)."""
import asyncio
import json
import os
import sys

import httpx
import pytest

import chat_core
from chat_core import CANNOT_START_REPLY, build_app
from crisis_client import FakeCrisisClient

POLICY_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "koi_policy")
SECRET = "test-secret-g0b"


class Output:
    def __init__(self, text):
        self.outputs = [type("Choice", (), {"text": text})()]


class CountingEngine:
    def __init__(self):
        self.calls = 0

    async def generate(self, prompt, params, request_id):
        self.calls += 1
        yield Output('{"companion_state":{"emotion":"joy","intensity":0.5},"reply":"hello"}')


class Tokenizer:
    def apply_chat_template(self, messages, **kwargs):
        return str(messages)

    def __call__(self, prompt, **kwargs):
        return {"input_ids": list(prompt)}


class RaisingCrisisClient:
    def __init__(self, exc, delay=0.0):
        self.exc, self.delay = exc, delay

    async def score_async(self, **kwargs):
        if self.delay:
            await asyncio.sleep(self.delay)
        raise self.exc


def _app(crisis, engine=None, **settings):
    return build_app(engine or CountingEngine(), Tokenizer(), lambda token: {"sub": "test"},
                     lambda schema, **kwargs: kwargs,
                     {"crisis_client": crisis, "policy_path": POLICY_PATH, **settings})


async def _post(app, **kwargs):
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test") as http:
        headers = {"Authorization": "Bearer test", **kwargs.pop("headers", {})}
        return await http.post("/api/v1/chat", headers=headers, **kwargs)


def _frames(response):
    assert response.status_code == 200, response.text
    out = []
    for part in response.text.strip().split("\n\n"):
        lines = part.splitlines()
        out.append((lines[0][7:], json.loads(lines[1][6:])))
    return out


def _director():
    if POLICY_PATH not in sys.path:
        sys.path.insert(0, POLICY_PATH)
    import director
    import state_token
    return director, state_token


@pytest.fixture
def exercises(monkeypatch):
    monkeypatch.setenv("KOI_EXERCISES", "1")
    monkeypatch.setenv("KOI_DIRECTOR_SECRET", SECRET)
    monkeypatch.delenv("KOI_REPLY_BACKEND", raising=False)


# ---------------------------------------------------------------- H03

def _assert_cannot_start(frames, engine):
    names = [n for n, _ in frames]
    deltas = [p["text"] for n, p in frames if n == "delta"]
    done = frames[-1][1]
    assert deltas == [CANNOT_START_REPLY]
    assert done["full_text"] == CANNOT_START_REPLY
    assert engine.calls == 0
    assert names[-2:] == ["state", "done"]
    assert names.index("companion_state") < names.index("delta")
    assert done["ui_actions"] == [] and done["handoff"] is None
    director, state_token = _director()
    token = done["exercise_state"]
    assert token and dict(frames)["state"]["exercise_state"] == token
    assert state_token.verify(token, SECRET)["ex"] is None
    return done


@pytest.mark.asyncio
@pytest.mark.parametrize("event", ["start_breathing", "start_grounding", "start_plan"])
async def test_h03_start_with_risk_unavailable_sends_one_fixed_delta(exercises, event):
    engine = CountingEngine()
    frames = _frames(await _post(_app(FakeCrisisClient({"status": "unavailable"}), engine),
                                 json={"message": "ok", "client_event": event}))
    done = _assert_cannot_start(frames, engine)
    assert done["risk"] == {"status": "unavailable"}
    assert dict(frames)["risk"] == {"status": "unavailable"}


@pytest.mark.asyncio
async def test_h03_start_with_no_tier_reports_risk_as_is(exercises):
    engine = CountingEngine()
    frames = _frames(await _post(_app(FakeCrisisClient({"status": "ok", "crisis_score": 0.2}), engine),
                                 json={"message": "ok", "client_event": "start_breathing"}))
    done = _assert_cannot_start(frames, engine)
    assert done["risk"] == {"status": "ok", "crisis_score": 0.2}


@pytest.mark.asyncio
async def test_h03_director_error_gives_fresh_state_and_fixed_delta(exercises, monkeypatch):
    director, _ = _director()

    def boom(*args, **kwargs):
        raise RuntimeError("director exploded")
    monkeypatch.setattr(director, "handle_turn", boom)
    engine = CountingEngine()
    response = await _post(_app(FakeCrisisClient({"status": "ok", "risk_category": "LOW"}), engine),
                           json={"message": "ok", "client_event": "start_plan", "exercise_state": "garbage"})
    done = _assert_cannot_start(_frames(response), engine)
    assert done["risk"]["risk_category"] == "LOW"
    assert "director exploded" not in response.text


@pytest.mark.asyncio
async def test_h03_no_hosted_generation_on_cannot_start(exercises, monkeypatch):
    monkeypatch.setenv("KOI_REPLY_BACKEND", "api")
    calls = []
    engine = CountingEngine()
    app = _app(FakeCrisisClient({"status": "unavailable"}), engine,
               reply_fetch=lambda *a, **k: calls.append(a) or (_ for _ in ()).throw(AssertionError("hosted")))
    _assert_cannot_start(_frames(await _post(app, json={"message": "ok", "client_event": "start_breathing"})), engine)
    assert calls == []


@pytest.mark.asyncio
async def test_h03_start_with_low_tier_still_starts(exercises):
    engine = CountingEngine()
    frames = _frames(await _post(_app(FakeCrisisClient({"status": "ok", "risk_category": "LOW"}), engine),
                                 json={"message": "ok", "client_event": "start_breathing"}))
    deltas = [p["text"] for n, p in frames if n == "delta"]
    assert CANNOT_START_REPLY not in deltas


@pytest.mark.asyncio
async def test_h03_plain_turn_with_risk_unavailable_still_generates(exercises):
    engine = CountingEngine()
    frames = _frames(await _post(_app(FakeCrisisClient({"status": "unavailable"}), engine),
                                 json={"message": "hello"}))
    assert [p["text"] for n, p in frames if n == "delta"] == ["hello"]
    assert engine.calls == 1


# ---------------------------------------------------------------- H05

def _assert_422(response):
    assert response.status_code == 422, (response.status_code, response.text)
    body = response.text
    assert "Traceback" not in body and "File \"" not in body


def test_h05_mirrored_enums_match_policy():
    director, _ = _director()
    import policy
    assert chat_core.CLIENT_EVENTS == director.CLIENT_EVENTS
    assert chat_core.CRISIS_PATHS == policy.CRISIS_PATHS


@pytest.mark.asyncio
@pytest.mark.parametrize("exercises_on", ["0", "1"])
@pytest.mark.parametrize("body", [
    {"message": "hi", "client_event": "start_dancing"},
    {"message": "hi", "client_event": "NONE"},
    {"message": "hi", "policy_event": "crisis_resolved", "crisis_path": "went_home"},
    {"message": "hi", "crisis_path": 3},
    {"message": 5},
    {"message": "hi", "session_history": "not a list"},
    {"message": "hi", "session_history": [{"role": "user"}]},
    {"message": "hi", "client_event": ["start_plan"]},
    {"message": "hi", "exercise_state": {"a": 1}},
    {"message": "hi", "language": 1.5},
    {"message": "hi", "risk": "HIGH"},
    ["not", "an", "object"],
    None,
])
async def test_h05_invalid_json_fields_are_422(monkeypatch, exercises_on, body):
    monkeypatch.setenv("KOI_EXERCISES", exercises_on)
    monkeypatch.setenv("KOI_DIRECTOR_SECRET", SECRET)
    engine = CountingEngine()
    _assert_422(await _post(_app(FakeCrisisClient({"status": "ok", "risk_category": "HIGH"}), engine), json=body))
    assert engine.calls == 0


@pytest.mark.asyncio
async def test_h05_valid_crisis_path_is_accepted(exercises):
    response = await _post(_app(FakeCrisisClient({"status": "ok", "risk_category": "LOW"})),
                           json={"message": "hi", "policy_event": "crisis_resolved", "crisis_path": "reached_out"})
    assert response.status_code == 200


@pytest.mark.asyncio
@pytest.mark.parametrize("content, ctype", [
    (b"--zzz\r\nContent-Disposition: form-data; name=\"payload\"\r\n\r\n{\"message\": \"hi\"}", "multipart/form-data; boundary=zzz"),
    (b"garbage without any boundary", "multipart/form-data"),
    (b"\xff\xfe\x00garbage", "multipart/form-data; boundary=abc"),
    (b"not json at all", "application/json"),
    (b"\xff\xfe\xfd", "application/json"),
])
async def test_h05_corrupt_bodies_are_422(content, ctype):
    _assert_422(await _post(_app(FakeCrisisClient()), content=content, headers={"Content-Type": ctype}))


@pytest.mark.asyncio
async def test_h05_media_field_sent_as_text_is_422():
    response = await _post(_app(FakeCrisisClient()), files={"payload": (None, json.dumps({"message": "hi"})),
                                                            "video": (None, "not a file")})
    _assert_422(response)
    assert "must be a file" in response.text


@pytest.mark.asyncio
async def test_h05_multipart_payload_with_bad_client_event_is_422():
    _assert_422(await _post(_app(FakeCrisisClient()), files={
        "payload": (None, json.dumps({"message": "hi", "client_event": "start_x"})),
        "video": ("clip.mp4", b"video")}))


# ---------------------------------------------------------------- H02

def _handoff_checks(frames):
    names = [n for n, _ in frames]
    done = frames[-1][1]
    assert names[-2:] == ["state", "done"]
    return names, done


@pytest.mark.asyncio
@pytest.mark.parametrize("tier", ["HIGH", "CRITICAL"])
async def test_h02_late_high_score_emits_handoff_before_done(monkeypatch, tier):
    monkeypatch.delenv("KOI_EXERCISES", raising=False)
    crisis = FakeCrisisClient({"status": "ok", "risk_category": tier, "crisis_score": 0.9}, delay=1.3)
    names, done = _handoff_checks(_frames(await _post(_app(crisis), json={"message": "hello"})))
    assert names.count("handoff") == 1
    assert names.index("risk") < names.index("handoff") < names.index("state")
    assert names.index("delta") < names.index("risk")      # the score arrived after the reply
    assert done["handoff"] == {"to": "crisis", "reason": f"tier {tier}"}
    assert done["risk"]["risk_category"] == tier


@pytest.mark.asyncio
async def test_h02_early_high_score_also_emits_handoff(monkeypatch):
    monkeypatch.delenv("KOI_EXERCISES", raising=False)
    frames = _frames(await _post(_app(FakeCrisisClient({"status": "ok", "risk_category": "HIGH"})),
                                 json={"message": "hello"}))
    names, done = _handoff_checks(frames)
    handoff = next(p for n, p in frames if n == "handoff")
    assert handoff == done["handoff"] == {"to": "crisis", "reason": "tier HIGH"}


@pytest.mark.asyncio
async def test_h02_director_handoff_is_not_duplicated(exercises):
    import types
    monkeypatch = pytest.MonkeyPatch()
    monkeypatch.setitem(sys.modules, "director", types.SimpleNamespace(
        on_risk=lambda token, tier, now, **kw: [{"type": "handoff", "to": "crisis", "reason": "urgent"},
                                                {"type": "state", "token": "signed"}],
        handle_turn=lambda *a, **k: []))
    try:
        frames = _frames(await _post(_app(FakeCrisisClient({"status": "ok", "risk_category": "HIGH"})),
                                     json={"message": "x", "exercise_state": "signed"}))
    finally:
        monkeypatch.undo()
    names, done = _handoff_checks(frames)
    assert names.count("handoff") == 1
    assert done["handoff"] == {"to": "crisis", "reason": "urgent"}


@pytest.mark.asyncio
@pytest.mark.parametrize("crisis", [
    RaisingCrisisClient(RuntimeError("scorer down")),
    RaisingCrisisClient(RuntimeError("scorer down late"), delay=1.3),
    FakeCrisisClient({"status": "unavailable"}),
    FakeCrisisClient({"status": "ok", "risk_category": "HIGH"}, delay=60.0),   # never arrives inside the cap
])
async def test_h02_failed_or_unavailable_score_is_never_low_and_no_handoff(monkeypatch, crisis):
    monkeypatch.delenv("KOI_EXERCISES", raising=False)
    frames = _frames(await _post(_app(crisis, POST_REPLY_RISK_CAP_S=2.0), json={"message": "hello"}))
    names, done = _handoff_checks(frames)
    assert done["risk"] == {"status": "unavailable"}
    assert dict(frames)["risk"] == {"status": "unavailable"}
    assert "handoff" not in names and done["handoff"] is None


@pytest.mark.asyncio
async def test_h02_unavailable_risk_does_not_start_exercise(exercises):
    engine = CountingEngine()
    frames = _frames(await _post(_app(FakeCrisisClient({"status": "unavailable"}), engine),
                                 json={"message": "ok", "client_event": "start_grounding"}))
    names, done = _handoff_checks(frames)
    assert done["ui_actions"] == [] and done["risk"] == {"status": "unavailable"}
    assert "LOW" not in json.dumps(done["risk"])


@pytest.mark.asyncio
@pytest.mark.parametrize("delay", [0.0, 1.3])
async def test_h02_cancelled_score_task_still_ends_with_done(monkeypatch, delay):
    monkeypatch.delenv("KOI_EXERCISES", raising=False)
    frames = _frames(await _post(_app(RaisingCrisisClient(asyncio.CancelledError(), delay=delay)),
                                 json={"message": "hello"}))
    names, done = _handoff_checks(frames)
    assert done["risk"] == {"status": "unavailable"}
    assert "handoff" not in names and done["handoff"] is None


@pytest.mark.asyncio
async def test_h02_low_score_emits_no_handoff(monkeypatch):
    monkeypatch.delenv("KOI_EXERCISES", raising=False)
    frames = _frames(await _post(_app(FakeCrisisClient({"status": "ok", "risk_category": "LOW"})),
                                 json={"message": "hello"}))
    names, done = _handoff_checks(frames)
    assert "handoff" not in names and done["handoff"] is None
