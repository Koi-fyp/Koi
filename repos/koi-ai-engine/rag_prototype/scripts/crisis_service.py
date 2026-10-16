"""
Production entry point for intervention_content on /api/v1/crisis (M3, Oct 13 2026).

    from crisis_service import CrisisContentService
    svc = CrisisContentService.load()                    # once, at app startup (FastAPI lifespan)
    content = svc.intervention_content(message_text, risk_category)
    if content is not None:                              # None => OMIT the field (below HIGH)
        response["intervention_content"] = content

What it fixes in one place, so the route stays three lines:
  - offline + no telemetry: sets HF_HUB_OFFLINE=1, TRANSFORMERS_OFFLINE=1, HAYSTACK_TELEMETRY_ENABLED=False
    BEFORE importing anything that loads models or Haystack (the egress audit showed the model load otherwise
    contacts huggingface.co). Import this module first in the process that launches FastAPI.
  - the model, corpus and example store are loaded ONCE (load()), not per request.
  - the content checks (content_safety) are ON: only user-facing, veto-clean passages are served.
  - the fallback text and helpline come from fallback_bank (DRAFT, unreviewed).
  - risk_category is passed through as given; unknown strings raise ValueError (enum still OPEN) -- the route
    should turn that into a 5xx/log, never into a guessed tier.

NOT done here (needs Ahmad's route file): the actual edit of the /api/v1/crisis handler, and how the message text
is taken from its request (the request shape is multipart per the client tracks; not seen by the RAG side).
"""
import os
import sys
import time
from pathlib import Path

for _k, _v in (("HF_HUB_OFFLINE", "1"), ("TRANSFORMERS_OFFLINE", "1"), ("HAYSTACK_TELEMETRY_ENABLED", "False")):
    os.environ.setdefault(_k, _v)

_HERE = Path(__file__).resolve().parent
if str(_HERE) not in sys.path:
    sys.path.insert(0, str(_HERE))

import content_safety  # noqa: E402
import fallback_bank  # noqa: E402
import haystack_pipeline as hp  # noqa: E402
import retrieval_pipeline as rp  # noqa: E402


class CrisisContentService:
    def __init__(self, router, fallback=fallback_bank.fallback, helpline=fallback_bank.HELPLINE):
        if router.safety_filter is None:
            raise ValueError("production router must have the content filter on (content_safety.filter_indices)")
        self.router = router
        self.pipe = hp.build_crisis_pipeline(router, fallback, helpline)
        self.load_seconds = None

    @classmethod
    def load(cls, encoder=None):
        """Build everything once. encoder=None -> real multilingual-e5-small from the local HF cache."""
        t0 = time.perf_counter()
        encoder = encoder or rp.E5Encoder()
        router = rp.CrisisRouter(rp.load_corpus(), rp.load_example_store(), encoder,
                                 safety_filter=content_safety.filter_indices)
        svc = cls(router)
        svc.load_seconds = time.perf_counter() - t0
        return svc

    def intervention_content(self, message, risk_category, language=None):
        """dict for the response field, or None = omit the field. Unknown risk_category raises ValueError."""
        return hp.run_crisis(self.pipe, message, risk_category, language)


def fastapi_lifespan(state_attr="crisis_content"):
    """FastAPI lifespan that loads the service once: FastAPI(lifespan=fastapi_lifespan()).
    The handler then uses request.app.state.crisis_content.intervention_content(...)."""
    from contextlib import asynccontextmanager

    @asynccontextmanager
    async def lifespan(app):
        setattr(app.state, state_attr, CrisisContentService.load())
        yield

    return lifespan
