"""RAG hook for the KOI crisis endpoint. STUB: returns None, so every HIGH/CRITICAL response uses the fallback.

Replace the body of build_intervention with a call into your Haystack pipeline. The endpoint calls it only at
HIGH or CRITICAL, with a timeout (KOI_RAG_TIMEOUT_S, default 4 s). Anything that goes wrong -> fallback.

Contract (KOI_RAG_SEGMENT_STATE_v1.md section 8, confirmed Oct 12):
    return {"source": "grounded" | "fallback",
            "language": "en" | "ur" | "ur-roman" | "mixed",
            "items": [ {"text": ..., "chunk_id": ..., "source_corpus": ..., "evidence_role": ..., "review_status": ...} ],  # 1-3 items
            "helpline": {"name": ..., "number": ...}}    # optional; endpoint fills its configured helpline if missing
    or None (no confident match -> endpoint uses its fallback).

Enforced by the endpoint (koi_crisis_core.intervention), not by you:
    - CRITICAL: only source == "fallback" is accepted (your hardcoded UX-Flows sequence). A "grounded" result at
      CRITICAL is discarded and replaced by the built-in fallback. Never a retrieved span at CRITICAL.
    - more than 3 items, empty text, or a malformed dict -> fallback.

If your pipeline needs extra packages or data, deploy with:
    KOI_RAG_PIP="haystack-ai==<ver>,sentence-transformers==<ver>" KOI_RAG_DIR=./rag modal deploy crisis_app.py
Files in ./rag are available in the container at /root/rag.
"""


def init():
    """Optional: load your embedder / index once when the container starts."""
    return None


def build_intervention(text, risk_category, language=None):
    return None
