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

import logging

import psutil
from fastapi import APIRouter, Depends, HTTPException, status

from app.core.config import settings
from app.core.security import verify_firebase_token
from app.models.schemas import ChatRequest, ChatResponse, HealthStatus
from app.services.inference_service import ModelNotLoadedError, inference_service

logger = logging.getLogger(__name__)
router = APIRouter()


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


@router.post("/api/v1/chat", response_model=ChatResponse, tags=["chat"])
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

    try:
        return inference_service.generate_reply(payload.message, payload.session_history)
    except ModelNotLoadedError as exc:
        # Structured-output generation genuinely failed after retries —
        # surfaced as a real error, not papered over with a fabricated
        # reply. See inference_service.py's _generate_structured().
        logger.error("Structured generation failed for uid=%s: %s", uid, exc)
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Companion LLM failed to produce a valid structured response.",
        )
