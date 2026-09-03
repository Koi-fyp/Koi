"""
KOI AI Engine — FastAPI service, Companion LLM inference.

🆕 [PHASE 2 REBUILD] The previous version of this file was explicitly
built as a "decoupled microservice" for Render/Hugging Face Spaces
free-tier hosting (its own docstring said so), with a `/ai/warmup`
endpoint specifically to fight Render's free-tier spin-down delay. That
does not match this project's locked deployment target — AWS
`g4dn.xlarge`, a dedicated GPU instance with no spin-down behavior to
work around (Blueprint §6 "EC2 Deployment"; TRACK_AI_BACKEND_FINAL_v4_13
line 202). This rebuild drops the free-tier-specific framing entirely.
It also removed the duplicate/near-circular routing this file previously
had (inline `/health`+`/ai/*` routes AND a separately-mounted router
defining near-identical `/api/*` versions of the same endpoints) — there
is now exactly one router, one set of routes.

This is still PHASE 2 scope (local dev / core text engine) — NOT the
full Phase 3 production deployment (no streaming yet, no EC2/Docker
production hardening done here, no LoRA adapter since none has been
trained). See inference_service.py's module docstring for the full,
explicit scope statement.
"""

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.core.config import settings
from app.api.routes import router as api_router

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info(
        "KOI AI Engine starting up (Phase 2 — local dev). Model loads "
        "LAZILY on first /api/v1/chat request, not at startup."
    )
    yield
    logger.info("KOI AI Engine shutting down.")


app = FastAPI(
    title="KOI AI Engine",
    description="Self-hosted Companion LLM inference service.",
    version="0.2.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.allowed_origins,
    allow_credentials=True,
    allow_methods=["GET", "POST"],
    allow_headers=["*"],
)

app.include_router(api_router)


@app.get("/", tags=["root"])
async def root():
    return {
        "service": "KOI AI Engine",
        "version": "0.2.0",
        "docs": "/docs",
        "health": "/health",
    }


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        "main:app",
        host=settings.host,
        port=settings.port,
        reload=settings.debug,
        log_level="info",
    )
