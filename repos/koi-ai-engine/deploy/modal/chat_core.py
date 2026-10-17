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
    from .stream_extract import StreamExtractor, looks_like_json
except ImportError:
    from stream_extract import StreamExtractor, looks_like_json
try:
    from .crisis_client import CrisisClient
except ImportError:
    from crisis_client import CrisisClient

MAX_MODEL_LEN = 8192
MAX_REPLY_TOKENS = 512
# Crisis score budget: 5 s from request start, never waiting more than 5 s
# after the reply ends; a miss is reported as risk {"status": "unavailable"}.
POST_REPLY_RISK_CAP_S = 5.0
# DRAFT, English only (no native-speaker or clinician review): sent when the model
# gives no usable reply twice.
FALLBACK_REPLY = "I'm sorry, I couldn't put my reply into words just now. Could you say that again?"


def _trace_enabled() -> bool:
    """KOI_DEBUG_TRACE is ON only for 1/true/yes/on; "0", "false", empty or unset = OFF."""
    return os.environ.get("KOI_DEBUG_TRACE", "").strip().lower() in {"1", "true", "yes", "on"}


def _join_text(previous: list[str], text: str) -> str:
    """Separate consecutive deltas (e.g. exercise sentences) with one space, so
    "".join(deltas) == done.full_text reads as normal prose."""
    if previous and text and not previous[-1][-1:].isspace() and not text[:1].isspace():
        return " " + text
    return text
SYSTEM_PROMPT = (
    "You are KOI, a warm and emotionally supportive AI companion. "
    "Reply in the same language and script as the user's latest message "
    "(English, Urdu, or Roman Urdu). "
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
    message: str | None = Field(default=None, max_length=4000)
    session_history: list[ChatMessage] = Field(default_factory=list)
    exercise_state: str | None = None
    client_event: str | None = None
    risk: dict[str, Any] | None = None
    policy_event: str | None = None
    crisis_path: str | None = None
    language: str | None = None
    turn_id: str | None = None


class ParsedChat:
    def __init__(self, request: ChatRequest, audio: bytes | None = None,
                 video: bytes | None = None):
        self.request = request
        self.audio = audio
        self.video = video


def _model_validate(data: dict[str, Any]) -> ChatRequest:
    validator = getattr(ChatRequest, "model_validate", None)
    return validator(data) if validator else ChatRequest.parse_obj(data)


def _normalize_risk(value: Any) -> dict[str, Any]:
    if not isinstance(value, dict) or value.get("status") == "unavailable":
        return {"status": "unavailable"}
    result = {"status": value.get("status", "ok")}
    for key in (
        "risk_category", "crisis_score", "confidence", "confidence_reasons",
        "modalities_used", "trigger_flags", "intervention_content", "model",
        "transcript", "language",
    ):
        if key in value:
            result[key] = value[key]
    return result


async def _parse_chat_request(request: Request) -> ParsedChat:
    content_type = request.headers.get("content-type", "")
    if not content_type.startswith("multipart/form-data"):
        try:
            return ParsedChat(_model_validate(await request.json()))
        except ValueError as exc:
            raise HTTPException(422, "invalid JSON payload") from exc
    form = await request.form()
    raw_payload = form.get("payload")
    if not isinstance(raw_payload, str):
        raise HTTPException(422, "multipart payload must include a JSON payload field")
    try:
        payload = json.loads(raw_payload)
        parsed = _model_validate(payload)
    except (TypeError, ValueError, json.JSONDecodeError) as exc:
        raise HTTPException(422, "payload must be valid JSON") from exc
    limits = {"audio": 25 * 1024 * 1024, "video": 80 * 1024 * 1024}
    media: dict[str, bytes | None] = {}
    for name in ("audio", "video"):
        upload = form.get(name)
        if upload is None:
            media[name] = None
            continue
        data = await upload.read()
        if len(data) > limits[name]:
            raise HTTPException(413, f"{name} file too large")
        media[name] = data or None
    has_text = bool(parsed.message and parsed.message.strip())
    has_audio = media["audio"] is not None
    has_video = media["video"] is not None
    allowed = (
        (has_text and not has_audio and not has_video)
        or (not has_text and has_audio and not has_video)
        or (has_text and not has_audio and has_video)
        or (not has_text and has_audio and has_video)
    )
    if not allowed:
        raise HTTPException(422, "allowed modalities are text, audio, text+video, or audio+video")
    return ParsedChat(parsed, media["audio"], media["video"])


def _setting(settings: Any, name: str, default: Any = None) -> Any:
    return settings.get(name, default) if isinstance(settings, dict) else getattr(settings, name, default)


def build_app(engine: Any, tokenizer: Any, verify_token: Any, sampling_factory: Any, settings: Any = None) -> FastAPI:
    settings = settings or {}
    max_len = _setting(settings, "MAX_MODEL_LEN", MAX_MODEL_LEN)
    max_reply = _setting(settings, "MAX_REPLY_TOKENS", MAX_REPLY_TOKENS)
    risk_cap = float(_setting(settings, "POST_REPLY_RISK_CAP_S", POST_REPLY_RISK_CAP_S))
    crisis_client = _setting(settings, "crisis_client", None) or CrisisClient()
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

    def messages(req: ChatRequest, message: str | None = None) -> tuple[list[dict[str, str]], int]:
        history = []
        for item in req.session_history:
            role = "assistant" if item.role == "model" else item.role
            if role not in ("user", "assistant"):
                raise HTTPException(422, "invalid message role")
            history.append({"role": role, "content": item.content})
        def render(h: list[dict[str, str]]) -> str:
            return tokenizer.apply_chat_template(
                [{"role": "system", "content": SYSTEM_PROMPT}, *h,
                 {"role": "user", "content": message if message is not None else req.message}],
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
                {"role": "user", "content": message if message is not None else req.message}], trimmed

    async def normal_events(req: ChatRequest, uid: str, t0: float, message: str | None = None):
        msg, trimmed = messages(req, message)
        prompt = tokenizer.apply_chat_template(msg, tokenize=False, add_generation_prompt=True)
        params = sampling_factory(CHAT_JSON_SCHEMA, max_tokens=max_reply)
        extractor = StreamExtractor()
        state = None
        reply = ""
        error = None

        def handle(items):
            nonlocal state, reply
            for kind, value in items:
                if kind == "companion_state":
                    if state is None:
                        state = _clamp_state(value)
                        yield "companion_state", state
                    continue
                if looks_like_json(value):
                    continue
                if state is None:
                    # No valid companion_state parsed: neutral before any text.
                    state = _clamp_state(None)
                    yield "companion_state", state
                reply = value
                yield "delta", {"text": value}

        for attempt in range(2):  # empty reply -> retry once, then the fixed fallback line
            extractor = StreamExtractor()
            try:
                # vLLM returns cumulative text that is not always prefix-stable for
                # multibyte scripts (Urdu), so the extractor re-parses the full text.
                async for output in engine.generate(prompt, params, f"{uid}-{t0}-{attempt}"):
                    text = output.outputs[0].text
                    try:
                        items = extractor.update(text)
                    except Exception:
                        items = []
                    for event in handle(items):
                        yield event
                    if _trace_enabled():
                        yield "_trace", "raw model text len=%d first80=%r" % (len(text), text[:80])
            except Exception as exc:
                error = {"code": "generation_failed", "detail": type(exc).__name__}
            if not reply:
                for event in handle(extractor.salvage()):
                    yield event
            if reply:
                break
            if _trace_enabled():
                yield "_trace", "attempt %d: no usable reply (%s)" % (attempt + 1, (error or {}).get("code", "no_reply"))
        if not reply:
            for event in handle([("reply", FALLBACK_REPLY)]):
                yield event
        if state is None:
            state = _clamp_state(None)
        yield "_complete", {"reply": reply, "state": state, "trimmed": trimmed}

    @app.post("/api/v1/chat")
    async def chat(request: Request, authorization: str | None = Header(default=None)):
        uid = auth(authorization)
        parsed = await _parse_chat_request(request)
        req = parsed.request
        score_started = time.monotonic()
        score_task = asyncio.create_task(crisis_client.score_async(
            text=req.message or None, audio_bytes=parsed.audio, video_bytes=parsed.video,
            language=req.language, turn_id=req.turn_id, uid=uid,
        ))
        wait_seconds = 3.0 if (
            parsed.audio is not None
            or req.exercise_state
            or (req.client_event or "").startswith("start_")
        ) else 1.0
        risk = None
        try:
            risk = await asyncio.wait_for(asyncio.shield(score_task), timeout=wait_seconds)
        except asyncio.TimeoutError:
            pass
        except Exception:
            risk = {"status": "unavailable"}
        risk = _normalize_risk(risk) if risk is not None else None
        effective_message = (risk or {}).get("transcript") if isinstance(risk, dict) else None
        effective_message = effective_message or req.message
        if not effective_message:
            raise HTTPException(422, "audio scoring did not return a transcript")
        # Validate roles before constructing a streaming response so malformed
        # requests retain the normal JSON 422 contract.
        messages(req, effective_message)
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
            effective_risk = risk or {}
            tier = effective_risk.get("risk_category") if effective_risk.get("risk_category") in {"LOW", "MODERATE", "HIGH", "CRITICAL"} else None
            if tier is None and req.policy_event == "crisis_resolved" and req.crisis_path:
                tier = "LOW"
            turn = {"text": effective_message, "client_event": req.client_event or "none",
                    "tier": tier, "now": time.time(), "token": req.exercise_state,
                    "policy_event": req.policy_event, "crisis_path": req.crisis_path}
            if effective_risk.get("is_new"):
                turn.update(score=effective_risk.get("crisis_score"), flags=effective_risk.get("trigger_flags") or [])

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
            handler = director.handle_turn
            if tier in {"HIGH", "CRITICAL"} and req.exercise_state:
                handler = director.on_risk
                director_events = await asyncio.to_thread(
                    handler, req.exercise_state, tier, time.time(), secret=secret
                )
            else:
                director_events = await asyncio.to_thread(
                    handler, turn, req.exercise_state, secret=secret,
                    phrase_fn=lambda d: asyncio.run_coroutine_threadsafe(phrase_async(d), loop).result(timeout=20)
                )

        async def stream():
            stream_risk = risk
            first = True
            streamed_reply: list[str] = []
            streamed_state = None
            trace: list[str] = []
            emitted_risk = False
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
                    text = _join_text(streamed_reply, event["text"])
                    streamed_reply.append(text)
                    yield frame("delta", {"text": text})
            crisis = next((e for e in director_events if e.get("type") == "handoff" and e.get("to") == "crisis"), None)
            has_director_state = any(e.get("type") == "companion_state" for e in director_events)
            has_director_reply = any(e.get("type") == "sentence" for e in director_events)
            complete = {"reply": "", "state": _clamp_state(None), "trimmed": 0}
            transcript = stream_risk.get("transcript") if isinstance(stream_risk, dict) else None
            if transcript:
                yield frame("transcript", {"text": transcript, "language": stream_risk.get("language") or req.language})
            async for name, value in normal_events(req, uid, t0, transcript):
                if name == "_trace":
                    trace.append(value)
                elif name == "_complete":
                    complete = value
                elif name == "companion_state" and not has_director_state:
                    streamed_state = value
                    if first:
                        yield frame("latency", {"latency_ms": round((time.monotonic()-t0)*1000, 1)}); first = False
                    yield frame(name, value)
                    if stream_risk is not None and not emitted_risk:
                        yield frame("risk", stream_risk)
                        emitted_risk = True
                elif name == "delta" and (not has_director_reply or crisis):
                    text = _join_text(streamed_reply, value["text"])
                    streamed_reply.append(text)
                    if first: yield frame("latency", {"latency_ms": round((time.monotonic()-t0)*1000, 1)}); first = False
                    yield frame(name, {"text": text})
            if streamed_state is None:
                # Guarantee companion_state before risk even when nothing was streamed.
                streamed_state = _clamp_state(None)
                if first:
                    yield frame("latency", {"latency_ms": round((time.monotonic()-t0)*1000, 1)}); first = False
                yield frame("companion_state", streamed_state)
            if stream_risk is None:
                remaining = min(risk_cap, max(0.0, score_started + risk_cap - time.monotonic()))
                try:
                    if score_task.done() or remaining > 0:
                        stream_risk = await asyncio.wait_for(asyncio.shield(score_task), timeout=remaining or None)
                    else:
                        stream_risk = {"status": "unavailable"}
                except (asyncio.TimeoutError, Exception):
                    stream_risk = {"status": "unavailable"}
                stream_risk = _normalize_risk(stream_risk)
            if stream_risk is None:
                stream_risk = {"status": "unavailable"}
            if not emitted_risk and streamed_state is not None:
                yield frame("risk", stream_risk)
                emitted_risk = True
            handoff = crisis
            for event in director_events:
                if event.get("type") == "handoff" and event.get("to") == "crisis":
                    yield frame("handoff", {"to": "crisis", "reason": event.get("reason", "")})
                elif event.get("type") == "state":
                    token = event["token"]
                    if token in emitted_state_tokens:
                        continue
                    emitted_state_tokens.add(token)
                    yield frame("state", {"exercise_state": token, **({"trace": event.get("trace", [])} if _trace_enabled() else {})})
            if not emitted_state_tokens:
                # Every stream ends with state, done; null means no exercise is active.
                yield frame("state", {"exercise_state": None})
            done_state = streamed_state or complete["state"]
            payload = {"full_text": "".join(streamed_reply), "companion_state": _clamp_state(done_state),
                                 "exercise_state": next((e["token"] for e in director_events if e.get("type") == "state"), None),
                                 "ui_actions": [e for e in director_events if e.get("type") == "ui_action"],
                                 "handoff": {"to": "crisis", "reason": handoff.get("reason", "")} if handoff else None,
                                 "total_generation_s": round(time.monotonic()-t0, 3),
                                 "history_trimmed": complete["trimmed"]}
            payload["risk"] = stream_risk
            # Same precedence as the transcript event: ASR-detected language, else the request's; no detection here.
            payload["language"] = (stream_risk.get("language") if isinstance(stream_risk, dict) else None) or req.language
            if _trace_enabled():
                payload["trace"] = trace
            yield frame("done", payload)
        return StreamingResponse(stream(), media_type="text/event-stream")

    @app.get("/health")
    async def health():
        return {"status": "ok"}
    return app
