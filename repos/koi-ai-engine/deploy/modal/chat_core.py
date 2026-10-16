"""Testable FastAPI chat application; deliberately has no Modal or vLLM imports."""
import asyncio
import json
import os
import sys
import time
from typing import Any

from fastapi import FastAPI, Header, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field

try:
    from .stream_extract import StreamExtractor
except ImportError:
    from stream_extract import StreamExtractor

MAX_MODEL_LEN = 8192
MAX_REPLY_TOKENS = 512
SYSTEM_PROMPT = (
    "You are KOI, a warm and emotionally supportive AI companion. "
    # TODO: replace with KOI's approved production prompt.
)
CHAT_JSON_SCHEMA = {
    "type": "object",
    "properties": {
        "companion_state": {
            "type": "object",
            "properties": {
                "emotion": {"type": "string", "enum": ["neutral", "joy", "angry", "sorrow", "fun"]},
                "intensity": {"type": "number", "minimum": 0.0, "maximum": 1.0},
            },
            "required": ["emotion", "intensity"],
        },
        "reply": {"type": "string"},
    },
    "required": ["companion_state", "reply"],
}


def _clamp_state(value: Any) -> dict[str, Any]:
    if not isinstance(value, dict):
        return {"emotion": "neutral", "intensity": 0.4}
    intensity = value.get("intensity", 0.4)
    try:
        intensity = max(0.0, min(1.0, float(intensity)))
    except (TypeError, ValueError):
        intensity = 0.4
    return {"emotion": value.get("emotion", "neutral"), "intensity": intensity}


class ChatMessage(BaseModel):
    role: str
    content: str


class ChatRequest(BaseModel):
    message: str = Field(min_length=1, max_length=4000)
    session_history: list[ChatMessage] = Field(default_factory=list)
    exercise_state: str | None = None
    client_event: str | None = None
    risk: dict[str, Any] | None = None
    policy_event: str | None = None
    crisis_path: str | None = None


def _setting(settings: Any, name: str, default: Any = None) -> Any:
    return settings.get(name, default) if isinstance(settings, dict) else getattr(settings, name, default)


def build_app(engine: Any, tokenizer: Any, verify_token: Any, sampling_factory: Any, settings: Any = None) -> FastAPI:
    settings = settings or {}
    max_len = _setting(settings, "MAX_MODEL_LEN", MAX_MODEL_LEN)
    max_reply = _setting(settings, "MAX_REPLY_TOKENS", MAX_REPLY_TOKENS)
    app = FastAPI()
    origins = os.environ.get("KOI_CORS_ORIGINS", "*").split(",")
    app.add_middleware(CORSMiddleware, allow_origins=[x.strip() for x in origins],
                       allow_methods=["POST", "GET", "OPTIONS"],
                       allow_headers=["Authorization", "Content-Type"])

    def auth(value: str | None) -> str:
        if not value or not value.startswith("Bearer "):
            raise HTTPException(401, "Missing Authorization token")
        try:
            result = verify_token(value[7:].strip())
        except HTTPException:
            raise
        except Exception as exc:
            raise HTTPException(401, f"Invalid token: {exc}") from exc
        return result.get("sub", result) if isinstance(result, dict) else str(result)

    def messages(req: ChatRequest) -> tuple[list[dict[str, str]], int]:
        history = []
        for item in req.session_history:
            role = "assistant" if item.role == "model" else item.role
            if role not in ("user", "assistant"):
                raise HTTPException(422, "invalid message role")
            history.append({"role": role, "content": item.content})
        def render(h: list[dict[str, str]]) -> str:
            return tokenizer.apply_chat_template(
                [{"role": "system", "content": SYSTEM_PROMPT}, *h,
                 {"role": "user", "content": req.message}],
                tokenize=False, add_generation_prompt=True)
        trimmed = 0
        while history:
            prompt = render(history)
            try:
                count = len(tokenizer(prompt, add_special_tokens=False)["input_ids"])
            except Exception:
                count = len(prompt)
            if count <= max_len - max_reply:
                break
            history.pop(0)
            trimmed += 1
        return [{"role": "system", "content": SYSTEM_PROMPT}, *history,
                {"role": "user", "content": req.message}], trimmed

    async def normal_events(req: ChatRequest, uid: str, t0: float):
        msg, trimmed = messages(req)
        prompt = tokenizer.apply_chat_template(msg, tokenize=False, add_generation_prompt=True)
        params = sampling_factory(CHAT_JSON_SCHEMA, max_tokens=max_reply)
        extractor = StreamExtractor()
        previous = ""
        state = None
        reply = ""
        async for output in engine.generate(prompt, params, f"{uid}-{t0}"):
            text = output.outputs[0].text
            chunk = text[len(previous):] if text.startswith(previous) else text
            previous = text
            for kind, value in extractor.feed(chunk):
                if kind == "companion_state":
                    state = _clamp_state(value)
                    yield "companion_state", state
                else:
                    reply = value
                    yield "delta", {"text": value}
            if os.environ.get("KOI_DEBUG_TRACE") == "1":
                yield "_trace", "raw model text len=%d first80=%r" % (len(text), text[:80])
        if state is None:
            state = _clamp_state(None)
        yield "_complete", {"reply": reply, "state": state, "trimmed": trimmed}

    @app.post("/api/v1/chat")
    async def chat(req: ChatRequest, authorization: str | None = Header(default=None)):
        uid = auth(authorization)
        # Validate roles before constructing a streaming response so malformed
        # requests retain the normal JSON 422 contract.
        messages(req)
        t0 = time.monotonic()
        director_events = []
        exercises = os.environ.get("KOI_EXERCISES") == "1"
        if exercises:
            secret = os.environ.get("KOI_DIRECTOR_SECRET")
            if not secret:
                raise HTTPException(503, "director secret is not configured")
            policy_path = _setting(settings, "policy_path", os.path.join(os.path.dirname(__file__), "..", "..", "koi_policy"))
            if policy_path not in sys.path:
                sys.path.insert(0, policy_path)
            import director
            risk = req.risk or {}
            tier = risk.get("risk_category") if risk.get("risk_category") in {"LOW", "MODERATE", "HIGH", "CRITICAL"} else None
            if tier is None and req.policy_event == "crisis_resolved" and req.crisis_path:
                tier = "LOW"
            turn = {"text": req.message, "client_event": req.client_event or "none",
                    "tier": tier, "now": time.time(), "token": req.exercise_state,
                    "policy_event": req.policy_event, "crisis_path": req.crisis_path}
            if risk.get("is_new"):
                turn.update(score=risk.get("crisis_score"), flags=risk.get("trigger_flags") or [])

            loop = asyncio.get_running_loop()

            async def phrase_async(direction):
                prompt = __import__("compose").direction_prompt(direction)
                params = sampling_factory(None, max_tokens=96, temperature=0.7, top_p=0.8, top_k=20,
                                          repetition_penalty=1.15)
                out = ""
                async for item in engine.generate(tokenizer.apply_chat_template(
                        [{"role": "system", "content": prompt}, {"role": "user", "content": direction["user_text"]}],
                        tokenize=False, add_generation_prompt=True), params, f"phrase-{time.monotonic()}"):
                    out = item.outputs[0].text
                return None, iter((out,))
            # Director is synchronous and intentionally isolated from the event loop.
            director_events = await asyncio.to_thread(
                director.handle_turn, turn, req.exercise_state, secret=secret,
                phrase_fn=lambda d: asyncio.run_coroutine_threadsafe(phrase_async(d), loop).result(timeout=20)
            )

        async def stream():
            first = True
            streamed_reply: list[str] = []
            streamed_state = None
            trace: list[str] = []
            emitted_state_tokens: set[str] = set()
            def frame(name, value):
                return f"event: {name}\ndata: {json.dumps(value, ensure_ascii=False)}\n\n"
            for event in director_events:
                if event.get("type") == "ui_action" and first:
                    yield frame("latency", {"latency_ms": round((time.monotonic()-t0)*1000, 1)})
                    first = False
                if event.get("type") in ("ui_action", "companion_state") and event.get("type") == "ui_action":
                    yield frame("ui_action", {k: event[k] for k in ("name", "args")})
                elif event.get("type") == "companion_state":
                    state = _clamp_state(event)
                    streamed_state = state
                    yield frame("companion_state", state)
                elif event.get("type") == "sentence":
                    if first:
                        yield frame("latency", {"latency_ms": round((time.monotonic()-t0)*1000, 1)}); first = False
                    text = event["text"]
                    streamed_reply.append(text)
                    yield frame("delta", {"text": text})
            crisis = next((e for e in director_events if e.get("type") == "handoff" and e.get("to") == "crisis"), None)
            has_director_state = any(e.get("type") == "companion_state" for e in director_events)
            has_director_reply = any(e.get("type") == "sentence" for e in director_events)
            complete = {"reply": "", "state": _clamp_state(None), "trimmed": 0}
            async for name, value in normal_events(req, uid, t0):
                if name == "_trace":
                    trace.append(value)
                elif name == "_complete":
                    complete = value
                elif name == "companion_state" and not has_director_state:
                    streamed_state = value
                    if first:
                        yield frame("latency", {"latency_ms": round((time.monotonic()-t0)*1000, 1)}); first = False
                    yield frame(name, value)
                elif name == "delta" and (not has_director_reply or crisis):
                    streamed_reply.append(value["text"])
                    if first: yield frame("latency", {"latency_ms": round((time.monotonic()-t0)*1000, 1)}); first = False
                    yield frame(name, value)
            handoff = crisis
            for event in director_events:
                if event.get("type") == "handoff" and event.get("to") == "crisis":
                    yield frame("handoff", {"to": "crisis", "reason": event.get("reason", "")})
                elif event.get("type") == "state":
                    token = event["token"]
                    if token in emitted_state_tokens:
                        continue
                    emitted_state_tokens.add(token)
                    yield frame("state", {"exercise_state": token, **({"trace": event.get("trace", [])} if os.environ.get("KOI_DEBUG_TRACE") == "1" else {})})
            done_state = streamed_state or complete["state"]
            payload = {"full_text": "".join(streamed_reply), "companion_state": _clamp_state(done_state),
                                 "exercise_state": next((e["token"] for e in director_events if e.get("type") == "state"), None),
                                 "ui_actions": [e for e in director_events if e.get("type") == "ui_action"],
                                 "handoff": {"to": "crisis", "reason": handoff.get("reason", "")} if handoff else None,
                                 "total_generation_s": round(time.monotonic()-t0, 3),
                                 "history_trimmed": complete["trimmed"]}
            if os.environ.get("KOI_DEBUG_TRACE") == "1":
                payload["trace"] = trace
            yield frame("done", payload)
        return StreamingResponse(stream(), media_type="text/event-stream")

    @app.get("/health")
    async def health():
        return {"status": "ok"}
    return app
