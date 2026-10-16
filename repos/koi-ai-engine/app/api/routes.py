"""
🆕 [PHASE 2 REBUILD] The previous version of this file had no `/api/v1/`
prefix and no `/chat` endpoint at all — only `/api/health`, `/api/ai/warmup`,
`/api/ai/inference`, none of which match the locked contract
(TRACK_AI_BACKEND_FINAL_v4_13.md line 97: "/api/v1/chat" and "/api/v1/crisis").

`/api/v1/crisis` is deliberately NOT implemented here yet — there is no
TSD crisis-score model to call (Phase 5 / A3 subspace-separation
validation hasn't run). Adding a stub endpoint that returns fake scores
would be worse than not having it — see this project's own
"would look complete but be wrong" concern from the koi-ai-engine audit
that preceded this rebuild.
"""

import asyncio
import logging
import os
import threading
import time
from typing import Any, Dict, List, Optional

import psutil
from fastapi import APIRouter, Depends, HTTPException, status

from app.core.config import settings
from app.core.security import verify_firebase_token
from app.models.schemas import ChatRequest, ChatResponse, HealthStatus
from app.services.inference_service import ModelNotLoadedError, inference_service
from app.services import risk_provider

_MODEL_LOCK = threading.Lock()
_DIRECTOR_SECRET: Optional[str] = None
logger = logging.getLogger(__name__)
router = APIRouter()


def _exercises_enabled() -> bool:
    return os.getenv("KOI_EXERCISES") == "1"


def _director_modules():
    import sys
    from pathlib import Path

    policy_dir = Path(__file__).resolve().parents[2] / "koi_policy"
    if str(policy_dir) not in sys.path:
        sys.path.insert(0, str(policy_dir))
    import adapter_qwen
    import director

    return director, adapter_qwen


def _generate_reply(message, session_history):
    with _MODEL_LOCK:
        return inference_service.generate_reply(message, session_history)


def _director_turn(payload: ChatRequest, risk):
    director, adapter_qwen = _director_modules()
    tier, score, flags = risk
    turn = {
        "text": payload.message,
        "client_event": payload.client_event or "none",
        "tier": tier,
        "score": score,
        "flags": flags,
        "now": time.time(),
    }
    with _MODEL_LOCK:
        return director.handle_turn(
            turn,
            payload.exercise_state,
            secret=_DIRECTOR_SECRET,
            phrase_fn=adapter_qwen.phrase_fn,
        )


def _director_response(events: List[Dict[str, Any]]):
    sentences = [e["text"] for e in events if e.get("type") == "sentence"]
    companion_state = next(
        ({"emotion": e["emotion"], "intensity": e["intensity"]}
         for e in events if e.get("type") == "companion_state"),
        None,
    )
    state = next((e.get("token") for e in events if e.get("type") == "state"), None)
    ui_action = next((e for e in events if e.get("type") == "ui_action"), None)
    if ui_action is not None:
        ui_action = {k: v for k, v in ui_action.items() if k != "type"}
    handoff_event = next((e for e in events if e.get("type") == "handoff"), None)
    handoff = handoff_event.get("to") if handoff_event else None
    return sentences, companion_state, state, ui_action, handoff


@router.on_event("startup")
async def validate_exercise_configuration() -> None:
    global _DIRECTOR_SECRET
    risk_provider.validate_startup()
    if _exercises_enabled():
        _DIRECTOR_SECRET = os.getenv("KOI_DIRECTOR_SECRET")
        if not _DIRECTOR_SECRET:
            raise RuntimeError("KOI_DIRECTOR_SECRET is required when KOI_EXERCISES=1")

@router.get("/health", tags=["system"])
async def health_check() -> HealthStatus:
    cpu_percent = psutil.cpu_percent(interval=0.1)
    memory = psutil.virtual_memory()
    return HealthStatus(
        status="healthy" if cpu_percent < 90 and memory.percent < 85 else "degraded",
        cpu_percent=cpu_percent,
        memory_percent=memory.percent,
        memory_available_mb=int(memory.available / (1024 * 1024)),
        model_loaded=inference_service.is_loaded,
        device=inference_service.device,
    )


@router.post(
    "/api/v1/chat",
    response_model=ChatResponse,
    response_model_exclude_none=True,
    tags=["chat"],
)
async def chat(
    payload: ChatRequest,
    current_user: dict = Depends(verify_firebase_token),
) -> ChatResponse:
    """
    Standard Conversation endpoint — Blueprint §4.1.

    Identity comes ONLY from the verified JWT's `sub`/`uid` claim
    (`current_user`, from `verify_firebase_token`), never from anything
    in `payload` — `ChatRequest` has no user-identity field, by design.

    `session_history` is treated as client-authoritative, stateless
    context per Blueprint §3.1a / §4.1 — this service does not persist
    it, does not look it up server-side, and receives it in plaintext by
    design (the client already decrypted it before this call).
    """
    uid = current_user.get("uid")
    logger.info("Chat request from uid=%s, message_len=%d", uid, len(payload.message))

    if not _exercises_enabled():
        try:
            return inference_service.generate_reply(payload.message, payload.session_history)
        except ModelNotLoadedError as exc:
            logger.error("Structured generation failed for uid=%s: %s", uid, exc)
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail="Companion LLM failed to produce a valid structured response.",
            )

    try:
        risk = await asyncio.to_thread(risk_provider.get_risk, payload.message)
        events = await asyncio.to_thread(_director_turn, payload, risk)
        sentences, companion_state, state, ui_action, handoff = _director_response(events)

        if handoff == "crisis":
            normal = await asyncio.to_thread(
                _generate_reply, payload.message, payload.session_history
            )
            return normal.model_copy(update={
                "exercise_state": state,
                "ui_action": ui_action,
                "handoff": handoff,
            })
        if sentences:
            reply = " ".join(sentences)
        else:
            normal = await asyncio.to_thread(
                _generate_reply, payload.message, payload.session_history
            )
            return normal.model_copy(update={
                "exercise_state": state,
                "ui_action": ui_action,
                "handoff": handoff,
            })

        if companion_state is None:
            companion_state = {"emotion": "neutral", "intensity": 0.4}
        return ChatResponse(
            companion_state=companion_state,
            reply=reply,
            latency_ms=0,
            exercise_state=state,
            ui_action=ui_action,
            handoff=handoff,
        )
    except ModelNotLoadedError as exc:
        logger.error("Structured generation failed for uid=%s: %s", uid, exc)
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Companion LLM failed to produce a valid structured response.",
        )
