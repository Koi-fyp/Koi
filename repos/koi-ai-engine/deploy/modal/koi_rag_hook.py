"""RAG hook for the KOI crisis endpoint, behind KOI_RAG_ENABLED (default OFF).

OFF (unset / anything but "1"): init() loads nothing, build_intervention() returns None, so every HIGH response
is the endpoint's static fallback, exactly as before.

ON ("1"): init() lazily imports the offline prototype (rag_prototype/scripts: retrieval_pipeline,
haystack_pipeline, content_safety, fallback_bank), builds the kNN router once and the Haystack pipeline.
build_intervention() then calls haystack_pipeline.run_crisis for HIGH only:
    - CRITICAL (or any other tier) -> None. Retrieval is never used at CRITICAL.
    - a "grounded" result -> returned (helpline removed so the endpoint fills its configured helpline).
    - a below-gate "fallback" result, any exception, import error, missing asset, or a run longer than
      KOI_RAG_TIMEOUT_S (default 4 s) -> None, so the endpoint serves its static fallback.
The example store is built from rows whose master-CSV split is exactly "dev"; everything else is dropped
in code. Only the id and split columns of that CSV are read.

Contract (KOI_RAG_SEGMENT_STATE_v1.md section 8): {"source": "grounded", "language", "items": [1-3 dicts]}.
koi_crisis_core.intervention re-validates the result and enforces the CRITICAL rule independently.
"""
import concurrent.futures
import os
import sys
from pathlib import Path

_STATE = {"pipe": None, "error": None}
_EXECUTOR = concurrent.futures.ThreadPoolExecutor(max_workers=2, thread_name_prefix="koi-rag")


def enabled():
    return os.environ.get("KOI_RAG_ENABLED", "0").strip() == "1"


def status():
    """Truthful /health fields: the flag, and whether the pipeline was actually built."""
    return {"rag_enabled": enabled(), "rag_assets_loaded": _STATE["pipe"] is not None}


def _scripts_dir():
    candidates = [os.environ.get("KOI_RAG_SCRIPTS_DIR", ""), "/root/rag/scripts",
                  str(Path(__file__).resolve().parent.parent.parent / "rag_prototype" / "scripts")]
    for path in candidates:
        if path and (Path(path) / "retrieval_pipeline.py").exists():
            return path
    raise FileNotFoundError("rag_prototype scripts not found")


def _dev_ids(master_csv):
    import csv
    with open(master_csv, encoding="utf-8-sig") as fh:
        return {row["id"] for row in csv.DictReader(fh) if row.get("split") == "dev"}


def dev_store(rp):
    """kNN example store restricted to split == "dev" rows of the master CSV (filtered here, in code)."""
    master_csv = rp.EVAL / "labels" / "koi_queries_master_draft.csv"
    dev = _dev_ids(master_csv)
    store = [row for row in rp.load_example_store(master_csv=master_csv) if row["id"] in dev]
    if not store:
        raise ValueError("empty dev example store")
    return store


def init(encoder=None):
    """Build the pipeline once when the flag is ON. Never raises; failures leave rag_assets_loaded false."""
    _STATE["pipe"], _STATE["error"] = None, None
    if not enabled():
        return None
    try:
        for key, value in (("HF_HUB_OFFLINE", "1"), ("TRANSFORMERS_OFFLINE", "1")):
            os.environ.setdefault(key, value)
        os.environ["HAYSTACK_TELEMETRY_ENABLED"] = "False"
        scripts = _scripts_dir()
        if scripts not in sys.path:
            sys.path.insert(0, scripts)
        import content_safety
        import fallback_bank
        import haystack_pipeline as hp
        import retrieval_pipeline as rp
        router = rp.CrisisRouter(rp.load_corpus(), dev_store(rp), encoder or rp.E5Encoder(),
                                 safety_filter=content_safety.filter_indices)
        _STATE["pipe"] = (hp, hp.build_crisis_pipeline(router, fallback_bank.fallback, fallback_bank.HELPLINE))
    except Exception as exc:  # ImportError, missing assets, model load, anything
        _STATE["error"] = type(exc).__name__
        print("RAG init failed -> static fallback only:", type(exc).__name__)
    return None


def build_intervention(text, risk_category, language=None):
    if not enabled() or _STATE["pipe"] is None or risk_category != "HIGH" or not (text or "").strip():
        return None
    hp, pipe = _STATE["pipe"]
    try:
        timeout = float(os.environ.get("KOI_RAG_TIMEOUT_S", "4"))
        result = _EXECUTOR.submit(hp.run_crisis, pipe, text, "HIGH", language).result(timeout=timeout)
    except Exception as exc:  # timeout or any pipeline error
        print("RAG hook failed -> static fallback:", type(exc).__name__)
        return None
    if not isinstance(result, dict) or result.get("source") != "grounded":
        return None
    result = dict(result)
    result.pop("helpline", None)
    return result
