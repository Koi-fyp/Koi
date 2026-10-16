"""
Haystack wrapper for the HIGH-tier crisis path (state file v4.27 §1: "Haystack with plain-Python custom components").

Every decision is plain Python from retrieval_pipeline.py; Haystack only wires three components together:

    TierCheck  ->  KnnRoute  ->  ContentBuilder        output: intervention_content (dict) or None (omit field)

  TierCheck       normalises risk_category (unknown strings raise), detects language (language_detector)
  KnnRoute        CrisisRouter.route() only when tier == HIGH; any exception -> no route (=> fallback)
  ContentBuilder  CRITICAL / below-gate / error -> deterministic fallback; HIGH accepted -> <= 3 grounded items

Equivalence with CrisisRouter.respond() is regression-tested (eval/test_haystack_pipeline.py).
Choosing Haystack is a convention-and-testability call, NOT a performance claim (state file §6).

TELEMETRY: Haystack reads HAYSTACK_TELEMETRY_ENABLED once, at import. This module forces it to "False" before
importing haystack and refuses to load if haystack was already imported with telemetry live. The process that
launches FastAPI must import this module (or set the variable) BEFORE anything else imports haystack.
Pinned/tested: haystack-ai 3.3.0.
"""
import os
import sys

_was_imported = "haystack" in sys.modules
os.environ["HAYSTACK_TELEMETRY_ENABLED"] = "False"

from typing import Any, Optional  # noqa: E402

from haystack import Pipeline, component  # noqa: E402

import retrieval_pipeline as rp  # noqa: E402


def telemetry_disabled() -> bool:
    """True iff Haystack's telemetry singleton was never created (it is created at import when enabled)."""
    try:
        from haystack.telemetry import _telemetry
        return _telemetry.telemetry is None
    except Exception:  # private module moved in a future version -> fall back to the env contract
        return os.environ.get("HAYSTACK_TELEMETRY_ENABLED", "").lower() in ("false", "0")


if _was_imported and not telemetry_disabled():
    raise RuntimeError("haystack was imported with telemetry enabled before haystack_pipeline; "
                       "set HAYSTACK_TELEMETRY_ENABLED=False in the launching process")


def normalise_tier(risk_category: str) -> str:
    rc = (risk_category or "").strip().upper()
    if rc in rp._BELOW_HIGH:
        return "OMIT"
    if rc in rp._CRITICAL:
        return "CRITICAL"
    if rc in rp._HIGH:
        return "HIGH"
    raise ValueError(f"unrecognised risk_category {risk_category!r}; refusing to guess a tier")


@component
class TierCheck:
    @component.output_types(tier=str, query=str, language=str)
    def run(self, query: str, risk_category: str, language: Optional[str] = None):
        tier = normalise_tier(risk_category)
        if language is None:
            from language_detector import detect_language
            language = rp.CONTRACT_LANGUAGE[detect_language(query)["primary"].value]
        return {"tier": tier, "query": query, "language": language}


@component
class KnnRoute:
    def __init__(self, router: "rp.CrisisRouter"):
        self.router = router

    @component.output_types(route=Optional[dict])
    def run(self, query: str, tier: str):
        if tier != "HIGH":
            return {"route": None}
        try:
            return {"route": self.router.route(query)}
        except Exception:
            return {"route": None}          # retrieval failure -> ContentBuilder serves the fallback


@component
class ContentBuilder:
    def __init__(self, router: "rp.CrisisRouter", fallback, helpline: dict):
        self.router, self.fallback, self.helpline = router, fallback, dict(helpline)

    @component.output_types(intervention_content=Optional[dict])
    def run(self, tier: str, language: str, route: Optional[dict] = None):
        if tier == "OMIT":
            return {"intervention_content": None}
        idx = [] if route is None else self.router.safe_items(route)    # M2 content filter (if set)
        if tier == "CRITICAL" or route is None or not route["accept"] or not idx:
            return {"intervention_content": rp._fallback_content(language, self.fallback, self.helpline)}
        ch = self.router.chunks
        items = [{"text": ch[i]["text"], "chunk_id": ch[i]["chunk_id"], "source_corpus": ch[i]["source_corpus"],
                  "evidence_role": ch[i]["evidence_role"], "review_status": ch[i].get("review_status")}
                 for i in idx]          # v4.29: votes > 0 only; M2: content filter applied
        return {"intervention_content": {"source": "grounded", "language": language, "items": items,
                                         "helpline": dict(self.helpline)}}


def build_crisis_pipeline(router, fallback, helpline) -> Pipeline:
    p = Pipeline()
    p.add_component("tier", TierCheck())
    p.add_component("route", KnnRoute(router))
    p.add_component("build", ContentBuilder(router, fallback, helpline))
    p.connect("tier.tier", "route.tier")
    p.connect("tier.query", "route.query")
    p.connect("tier.tier", "build.tier")
    p.connect("tier.language", "build.language")
    p.connect("route.route", "build.route")
    return p


def run_crisis(pipe: Pipeline, query: str, risk_category: str, language: Optional[str] = None) -> Optional[dict]:
    """Returns intervention_content, or None when the field must be omitted. Unknown tiers raise."""
    inputs: dict[str, Any] = {"query": query, "risk_category": risk_category}
    if language is not None:
        inputs["language"] = language
    try:
        out = pipe.run({"tier": inputs})
    except Exception as e:  # Haystack wraps component errors; surface an unknown tier as ValueError
        cause = e
        while cause is not None and not isinstance(cause, ValueError):
            cause = cause.__cause__
        raise (cause or e)
    return out["build"]["intervention_content"]
