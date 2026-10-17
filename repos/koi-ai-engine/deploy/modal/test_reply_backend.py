"""KOI_REPLY_BACKEND=api: hosted reply on ordinary chat turns, local fallback on any failure. Stubbed fetchers only."""
import asyncio
import json
import logging
import time

import httpx
import pytest

import reply_api
from chat_core import CHAT_JSON_SCHEMA, SYSTEM_PROMPT, _clamp_state, build_app
from crisis_client import FakeCrisisClient

KEY = "sk-test-KEY-SENTINEL-9f8e7d"
LOCAL_REPLY = "I am here."
API_REPLY = "That sounds like a lot. What part of tomorrow feels heaviest?"
PROVIDERS = {
    "gemini": {"KOI_LLM_PROVIDER": "gemini", "KOI_LLM_MODEL": "gemini-test"},
    "openai_compat": {"KOI_LLM_PROVIDER": "openai_compat", "KOI_LLM_MODEL": "oai-test",
                      "KOI_LLM_BASE_URL": "https://llm.example.invalid/v1"},
}


class _Output:
    def __init__(self, text):
        self.outputs = [type("Choice", (), {"text": text})()]


class _Engine:
    def __init__(self):
        self.calls = 0

    async def generate(self, prompt, params, request_id):
        self.calls += 1
        yield _Output('{"companion_state":{"emotion":"neutral","intensity":0.3},"reply":"%s"}' % LOCAL_REPLY)


class _Tokenizer:
    def apply_chat_template(self, messages, **kwargs):
        return str(messages)

    def __call__(self, prompt, **kwargs):
        return {"input_ids": list(prompt)}


def provider_body(provider, text=None, blocked=False):
    if text is None:
        text = json.dumps({"companion_state": {"emotion": "sorrow", "intensity": 0.5}, "reply": API_REPLY})
    if provider == "gemini":
        if blocked:
            return {"promptFeedback": {"blockReason": "SAFETY"}}
        return {"candidates": [{"content": {"parts": [{"text": text}]}, "finishReason": "STOP"}]}
    if blocked:
        return {"choices": [{"message": {"content": ""}, "finish_reason": "content_filter"}]}
    return {"choices": [{"message": {"content": text}, "finish_reason": "stop"}]}


class Fetch:
    def __init__(self, status=200, body=None, exc=None, sleep=0):
        self.status, self.body, self.exc, self.sleep, self.calls = status, body, exc, sleep, []

    def __call__(self, url, headers, body, timeout):
        self.calls.append({"url": url, "headers": headers, "body": json.loads(body), "raw": body})
        if self.sleep:
            time.sleep(self.sleep)
        if self.exc:
            raise self.exc
        return self.status, json.dumps(self.body).encode() if self.body is not None else b""


@pytest.fixture
def env(monkeypatch):
    for name in ("KOI_EXERCISES", "KOI_DEBUG_TRACE", "KOI_LLM_BASE_URL", "KOI_LLM_TIMEOUT_S", "KOI_LLM_REASONING_EFFORT"):
        monkeypatch.delenv(name, raising=False)

    def set_provider(provider, backend="api", **extra):
        monkeypatch.setenv("KOI_REPLY_BACKEND", backend)
        for k, v in {**PROVIDERS[provider], "KOI_LLM_API_KEY": KEY, **extra}.items():
            monkeypatch.setenv(k, v)
    return set_provider


def run_turn(fetch, body=None, files=None, risk=None):
    engine = _Engine()
    app = build_app(engine, _Tokenizer(), lambda token: {"sub": "uid-SENTINEL"}, lambda schema, **kw: kw,
                    {"crisis_client": FakeCrisisClient(risk or {"status": "ok", "risk_category": "LOW",
                                                                "crisis_score": 0.987654}),
                     "reply_fetch": fetch})

    async def go():
        async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test") as http:
            kwargs = {"files": files} if files else {"json": body or {"message": "I have a presentation tomorrow."}}
            return await http.post("/api/v1/chat", headers={"Authorization": "Bearer tok-SENTINEL"}, **kwargs)
    response = asyncio.run(go())
    assert response.status_code == 200, response.text
    events = [(f.split("\n", 1)[0][7:], json.loads(f.split("data: ", 1)[1]))
              for f in response.text.split("\n\n") if f.startswith("event: ")]
    return response.text, events, engine


def done_of(events):
    return next(d for n, d in events if n == "done")


# (a) flag off -------------------------------------------------------------------------------------------------
@pytest.mark.parametrize("backend", ["", "local", "API", "1"])
def test_flag_off_never_calls_api(env, monkeypatch, backend):
    env("gemini", backend=backend)
    fetch = Fetch(body=provider_body("gemini"))
    _, events, engine = run_turn(fetch)
    assert fetch.calls == [] and engine.calls == 1
    done = done_of(events)
    assert done["reply_backend"] == "local" and done["reply_fallback_reason"] is None
    assert done["full_text"] == LOCAL_REPLY


def test_default_deploy_references_no_llm_secret():
    import chat_app
    assert chat_app.reply_backend({}) == "local" and chat_app.llm_secrets({}) == []
    assert chat_app.llm_secrets({"KOI_REPLY_BACKEND": "local"}) == []
    assert chat_app.reply_backend({"KOI_REPLY_BACKEND": "api"}) == "api"
    assert len(chat_app.llm_secrets({"KOI_REPLY_BACKEND": "api"})) == 1


def test_flag_on_but_unconfigured_falls_back(env, monkeypatch):
    env("openai_compat")
    monkeypatch.delenv("KOI_LLM_BASE_URL")
    fetch = Fetch(body=provider_body("openai_compat"))
    _, events, engine = run_turn(fetch)
    assert fetch.calls == [] and engine.calls == 1
    assert (done_of(events)["reply_backend"], done_of(events)["reply_fallback_reason"]) == ("local", "not_configured")


@pytest.mark.parametrize("extra", [
    {"KOI_LLM_PROVIDER": "claude"}, {"KOI_LLM_MODEL": ""}, {"KOI_LLM_API_KEY": ""},
    {"KOI_LLM_TIMEOUT_S": "abc"}, {"KOI_LLM_TIMEOUT_S": "0"},
])
def test_config_invalid_means_disabled(extra):
    base = {**PROVIDERS["gemini"], "KOI_LLM_API_KEY": KEY}
    assert reply_api.config(base) is not None
    assert reply_api.config({**base, **extra}) is None
    assert reply_api.config({**PROVIDERS["openai_compat"], "KOI_LLM_API_KEY": KEY, "KOI_LLM_BASE_URL": "ftp://x"}) is None


# (b) success --------------------------------------------------------------------------------------------------
@pytest.mark.parametrize("provider", list(PROVIDERS))
def test_api_success_single_delta_and_order(env, provider):
    env(provider)
    fetch = Fetch(body=provider_body(provider))
    _, events, engine = run_turn(fetch)
    names = [n for n, _ in events]
    assert len(fetch.calls) == 1 and engine.calls == 0
    assert names.index("companion_state") < names.index("delta") < names.index("done") == len(names) - 1
    assert names.count("delta") == 1 and names.count("companion_state") == 1 and names[-2] == "state"
    done = done_of(events)
    assert done["reply_backend"] == "api" and done["reply_fallback_reason"] is None
    assert done["full_text"] == API_REPLY == next(d for n, d in events if n == "delta")["text"]
    assert done["companion_state"] == {"emotion": "sorrow", "intensity": 0.5}
    assert "risk" in done and "trace" not in done


def test_fenced_json_is_accepted(env):
    env("openai_compat")
    inner = json.dumps({"companion_state": {"emotion": "joy", "intensity": 9}, "reply": API_REPLY})
    _, events, _ = run_turn(Fetch(body=provider_body("openai_compat", text="```json\n" + inner + "\n```")))
    assert done_of(events)["reply_backend"] == "api"
    assert done_of(events)["companion_state"] == {"emotion": "joy", "intensity": 1.0}   # _clamp_state applied


# (c) failures -> local -----------------------------------------------------------------------------------------
FAILURES = [
    ("timeout", lambda p: Fetch(exc=reply_api.ReplyAPIError("timeout")), "timeout"),
    ("http500", lambda p: Fetch(status=500), "http_5xx"),
    ("http401", lambda p: Fetch(status=401), "http_4xx"),
    ("not_json_body", lambda p: Fetch(body=None), "invalid_json"),
    ("invalid_json_reply", lambda p: Fetch(body=provider_body(p, text="Sure! Here you go")), "invalid_json"),
    ("empty_text", lambda p: Fetch(body=provider_body(p, text="")), "empty"),
    ("empty_reply", lambda p: Fetch(body=provider_body(p, text=json.dumps(
        {"companion_state": {"emotion": "neutral", "intensity": 0.4}, "reply": "  "}))), "empty"),
    ("blocked", lambda p: Fetch(body=provider_body(p, blocked=True)), "blocked"),
    ("bad_emotion", lambda p: Fetch(body=provider_body(p, text=json.dumps(
        {"companion_state": {"emotion": "happy", "intensity": 0.4}, "reply": API_REPLY}))), "bad_emotion"),
    ("no_state", lambda p: Fetch(body=provider_body(p, text=json.dumps({"reply": API_REPLY}))), "bad_shape"),
    ("json_reply", lambda p: Fetch(body=provider_body(p, text=json.dumps(
        {"companion_state": {"emotion": "neutral", "intensity": 0.4}, "reply": '{"reply": "x"}'}))), "invalid_json"),
    ("crash", lambda p: Fetch(exc=RuntimeError("boom " + KEY)), "internal_error"),
]


@pytest.mark.parametrize("provider", list(PROVIDERS))
@pytest.mark.parametrize("label,make,reason", FAILURES, ids=[f[0] for f in FAILURES])
def test_api_failure_falls_back_to_local(env, caplog, provider, label, make, reason):
    env(provider)
    fetch = make(provider)
    with caplog.at_level(logging.DEBUG):
        text, events, engine = run_turn(fetch)
    done = done_of(events)
    assert len(fetch.calls) == 1 and engine.calls == 1
    assert done["reply_backend"] == "local" and done["reply_fallback_reason"] == reason
    assert done["full_text"] == LOCAL_REPLY
    names = [n for n, _ in events]
    assert names.count("companion_state") == 1 and names.count("delta") == 1
    # (e) key, prompt and model output never in frames or logs
    for secret in (KEY, "I have a presentation tomorrow", API_REPLY, "boom"):
        assert secret not in text
        assert secret not in caplog.text
    assert reason in caplog.text


def test_wall_clock_timeout_falls_back(env):
    env("gemini", KOI_LLM_TIMEOUT_S="0.1")   # chat waits timeout + 5 s, the stub hangs longer
    _, events, engine = run_turn(Fetch(body=provider_body("gemini"), sleep=5.6))
    assert (done_of(events)["reply_backend"], done_of(events)["reply_fallback_reason"]) == ("local", "timeout")
    assert engine.calls == 1


# (d) exercise turns never call the API --------------------------------------------------------------------------
@pytest.fixture
def exercises(monkeypatch):
    monkeypatch.setenv("KOI_EXERCISES", "1")
    monkeypatch.setenv("KOI_DIRECTOR_SECRET", "local-test-secret")


@pytest.mark.parametrize("provider", list(PROVIDERS))
def test_exercise_turn_never_calls_api(env, exercises, provider):
    env(provider)
    fetch = Fetch(body=provider_body(provider))
    _, events, _ = run_turn(fetch, body={"message": "can we do a breathing exercise", "client_event": "start_breathing"})
    assert fetch.calls == []
    assert [n for n, _ in events].count("delta") >= 2            # director sentences
    assert done_of(events)["reply_backend"] == "local" and done_of(events)["reply_fallback_reason"] is None


def test_crisis_turn_stays_local(env, exercises):
    env("gemini")
    fetch = Fetch(body=provider_body("gemini"))
    _, events, _ = run_turn(fetch, body={"message": "hello"}, risk={"status": "ok", "risk_category": "HIGH"})
    assert fetch.calls == []
    assert any(n == "handoff" for n, _ in events) and done_of(events)["reply_backend"] == "local"


def test_ordinary_turn_with_exercises_on_uses_api(env, exercises):
    env("gemini")
    fetch = Fetch(body=provider_body("gemini"))
    _, events, _ = run_turn(fetch, body={"message": "I had a long day at work."})
    assert len(fetch.calls) == 1 and done_of(events)["reply_backend"] == "api"


# (e)+(f) what is sent ---------------------------------------------------------------------------------------------
@pytest.mark.parametrize("provider", list(PROVIDERS))
def test_payload_contains_only_prompt_history_message(env, provider):
    env(provider)
    fetch = Fetch(body=provider_body(provider))
    body = {"message": "What is my name?", "exercise_state": "ex-SENTINEL", "turn_id": "turn-SENTINEL",
            "risk": {"risk_category": "LOW", "crisis_score": 0.123456},
            "session_history": [{"role": "user", "content": "My name is Sam."},
                                {"role": "model", "content": "Nice to meet you, Sam."}]}
    text, events, _ = run_turn(fetch, body=body)
    call = fetch.calls[0]
    raw = call["raw"].decode()
    for banned in ("SENTINEL", "0.123456", "0.987654", "risk_category", "exercise_state", "Bearer tok"):
        assert banned not in raw
    assert KEY not in call["url"] and KEY not in raw and KEY not in text
    if provider == "gemini":
        assert call["headers"]["x-goog-api-key"] == KEY and "Authorization" not in call["headers"]
        assert call["body"]["systemInstruction"]["parts"][0]["text"] == SYSTEM_PROMPT
        assert [(c["role"], c["parts"][0]["text"]) for c in call["body"]["contents"]] == [
            ("user", "My name is Sam."), ("model", "Nice to meet you, Sam."), ("user", "What is my name?")]
        gen = call["body"]["generationConfig"]
        assert gen["responseMimeType"] == "application/json" and "thinkingConfig" not in gen
        assert gen["responseSchema"]["propertyOrdering"] == ["companion_state", "reply"]
        assert gen["responseSchema"]["properties"]["companion_state"]["properties"]["emotion"]["enum"] == \
            CHAT_JSON_SCHEMA["properties"]["companion_state"]["properties"]["emotion"]["enum"]
    else:
        assert call["url"] == "https://llm.example.invalid/v1/chat/completions"
        assert call["headers"]["Authorization"] == "Bearer " + KEY
        msgs = call["body"]["messages"]
        assert msgs[0]["role"] == "system" and msgs[0]["content"].startswith(SYSTEM_PROMPT)
        assert [(m["role"], m["content"]) for m in msgs[1:]] == [
            ("user", "My name is Sam."), ("assistant", "Nice to meet you, Sam."), ("user", "What is my name?")]
        assert call["body"]["response_format"] == {"type": "json_object"}
        assert call["body"]["max_tokens"] >= 2048
        assert set(call["body"]) == {"model", "messages", "response_format", "max_tokens"}   # no reasoning_effort when unset


def test_audio_turn_sends_transcript_text_only(env):
    env("gemini")
    fetch = Fetch(body=provider_body("gemini"))
    risk = {"status": "ok", "risk_category": "LOW", "transcript": "salaam, mera din bura tha", "language": "ur-roman"}
    files = {"payload": (None, json.dumps({"language": "ur-roman"})), "audio": ("a.wav", b"RIFF-AUDIO-SENTINEL")}
    _, events, _ = run_turn(fetch, files=files, risk=risk)
    raw = fetch.calls[0]["raw"].decode()
    assert "AUDIO-SENTINEL" not in raw and "RIFF" not in raw
    assert fetch.calls[0]["body"]["contents"][-1]["parts"][0]["text"] == "salaam, mera din bura tha"
    assert done_of(events)["reply_backend"] == "api"


# (g) history cap ----------------------------------------------------------------------------------------------
@pytest.mark.parametrize("provider", list(PROVIDERS))
def test_history_capped_at_16_turns(env, provider):
    env(provider)
    fetch = Fetch(body=provider_body(provider))
    history = [{"role": "user" if i % 2 == 0 else "assistant", "content": "turn-%02d" % i} for i in range(20)]
    run_turn(fetch, body={"message": "latest", "session_history": history})
    body = fetch.calls[0]["body"]
    if provider == "gemini":
        texts = [c["parts"][0]["text"] for c in body["contents"]]
    else:
        texts = [m["content"] for m in body["messages"][1:]]
    assert texts == ["turn-%02d" % i for i in range(4, 20)] + ["latest"]


@pytest.mark.parametrize("value,sent", [("", None), ("  ", None), ("low", "low"), ("minimal", "minimal")])
def test_openai_reasoning_effort_only_when_set(env, value, sent):
    env("openai_compat", KOI_LLM_REASONING_EFFORT=value)
    fetch = Fetch(body=provider_body("openai_compat"))
    run_turn(fetch)
    assert fetch.calls[0]["body"].get("reasoning_effort") == sent
    assert fetch.calls[0]["body"]["max_tokens"] >= 2048


def test_gemini_never_sends_reasoning_or_thinking(env):
    env("gemini", KOI_LLM_REASONING_EFFORT="low")
    fetch = Fetch(body=provider_body("gemini"))
    run_turn(fetch)
    raw = fetch.calls[0]["raw"].decode()
    assert "reasoning" not in raw and "thinking" not in raw


def test_reasoning_content_is_ignored_and_not_logged(env, caplog):
    env("openai_compat", KOI_LLM_REASONING_EFFORT="low")
    body = provider_body("openai_compat")
    body["choices"][0]["message"]["reasoning_content"] = "HIDDEN-REASONING-SENTINEL"
    with caplog.at_level(logging.DEBUG):
        text, events, _ = run_turn(Fetch(body=body))
    assert done_of(events)["reply_backend"] == "api" and done_of(events)["full_text"] == API_REPLY
    assert "HIDDEN-REASONING-SENTINEL" not in text and "HIDDEN-REASONING-SENTINEL" not in caplog.text
    only_reasoning = {"choices": [{"message": {"content": "", "reasoning_content": "HIDDEN-REASONING-SENTINEL"},
                                   "finish_reason": "length"}]}
    with caplog.at_level(logging.DEBUG):
        text, events, _ = run_turn(Fetch(body=only_reasoning))
    assert (done_of(events)["reply_backend"], done_of(events)["reply_fallback_reason"]) == ("local", "empty")
    assert "HIDDEN-REASONING-SENTINEL" not in text and "HIDDEN-REASONING-SENTINEL" not in caplog.text


def test_generate_unit_parse_and_clamp():
    cfg = reply_api.config({**PROVIDERS["gemini"], "KOI_LLM_API_KEY": KEY})
    fetch = Fetch(body=provider_body("gemini"))
    state, reply = reply_api.generate(cfg, "sys", [], "hi", CHAT_JSON_SCHEMA, _clamp_state, fetch)
    assert state == {"emotion": "sorrow", "intensity": 0.5} and reply == API_REPLY
    with pytest.raises(reply_api.ReplyAPIError) as err:
        reply_api.generate(None, "sys", [], "hi", CHAT_JSON_SCHEMA, _clamp_state, fetch)
    assert err.value.reason == "not_configured"
