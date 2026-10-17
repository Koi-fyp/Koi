"""koi_rag_hook behind KOI_RAG_ENABLED. Stand-in encoder, sockets blocked, no model download, no pip."""
import csv
import os
import socket
import subprocess
import sys
import time
import types
from pathlib import Path

import pytest

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import koi_crisis_core as core  # noqa: E402
import koi_rag_hook as hook  # noqa: E402

os.environ.setdefault("HF_HUB_OFFLINE", "1")
os.environ.setdefault("HAYSTACK_TELEMETRY_ENABLED", "False")


class StubEncoder:
    """Deterministic char n-gram vectors (same idea as rag_prototype/eval/test_crisis_router.py)."""

    def __init__(self):
        from sklearn.feature_extraction.text import HashingVectorizer
        self.v = HashingVectorizer(n_features=512, analyzer="char_wb", ngram_range=(2, 4), norm="l2",
                                   alternate_sign=False)

    def _e(self, texts):
        return self.v.transform(texts).toarray()

    encode_queries = encode_passages = encode = _e


@pytest.fixture
def no_network(monkeypatch):
    def refuse(*args, **kwargs):
        raise OSError("network disabled in tests")
    monkeypatch.setattr(socket.socket, "connect", refuse)
    monkeypatch.setattr(socket, "create_connection", refuse)


@pytest.fixture
def rag_on(monkeypatch, no_network):
    monkeypatch.setenv("KOI_RAG_ENABLED", "1")
    hook.init(encoder=StubEncoder())
    assert hook.status() == {"rag_enabled": True, "rag_assets_loaded": True}, hook._STATE["error"]
    yield hook
    hook._STATE["pipe"] = None


def test_flag_off_by_default_imports_nothing():
    code = ("import os, sys; os.environ.pop('KOI_RAG_ENABLED', None); sys.path.insert(0, %r); "
            "import koi_rag_hook as h; h.init(); "
            "print(h.status(), h.build_intervention('I want to die', 'HIGH'), "
            "any(m.split('.')[0] in ('haystack', 'retrieval_pipeline', 'sentence_transformers') for m in sys.modules))"
            % str(HERE))
    out = subprocess.run([sys.executable, "-c", code], capture_output=True, text=True, timeout=120)
    assert out.returncode == 0, out.stderr
    assert out.stdout.strip() == "{'rag_enabled': False, 'rag_assets_loaded': False} None False"


@pytest.mark.parametrize("value", ["0", "", "false", "true", "yes"])
def test_only_exactly_1_enables(monkeypatch, value):
    monkeypatch.setenv("KOI_RAG_ENABLED", value)
    hook.init()
    assert hook.status() == {"rag_enabled": False, "rag_assets_loaded": False}
    assert hook.build_intervention("text", "HIGH") is None


def test_missing_assets_leave_static_fallback(monkeypatch, no_network):
    monkeypatch.setenv("KOI_RAG_ENABLED", "1")
    monkeypatch.setattr(hook, "_scripts_dir", lambda: (_ for _ in ()).throw(FileNotFoundError("no bundle")))
    hook.init(encoder=StubEncoder())
    assert hook.status() == {"rag_enabled": True, "rag_assets_loaded": False}
    assert hook._STATE["error"] == "FileNotFoundError"
    assert hook.build_intervention("I feel hopeless", "HIGH") is None


def test_import_error_leaves_static_fallback(monkeypatch, no_network):
    monkeypatch.setenv("KOI_RAG_ENABLED", "1")
    monkeypatch.setitem(sys.modules, "haystack_pipeline", None)  # import -> ImportError
    hook.init(encoder=StubEncoder())
    assert hook.status()["rag_assets_loaded"] is False
    assert hook.build_intervention("I feel hopeless", "HIGH") is None


def test_example_store_is_dev_rows_only(rag_on):
    import retrieval_pipeline as rp
    store = hook.dev_store(rp)
    with open(rp.EVAL / "labels" / "koi_queries_master_draft.csv", encoding="utf-8-sig") as fh:
        split = {row["id"]: row.get("split") for row in csv.DictReader(fh)}
    assert store
    assert all(split.get(row["id"]) == "dev" for row in store)


def test_critical_and_lower_tiers_never_retrieve(rag_on, monkeypatch):
    hp, _ = hook._STATE["pipe"]
    calls = []
    monkeypatch.setattr(hp, "run_crisis", lambda *a, **k: calls.append(a) or {"source": "grounded"})
    for tier in ("CRITICAL", "MODERATE", "LOW", None, "HIGH_CRISIS"):
        assert hook.build_intervention("I want to end it", tier) is None
    assert calls == []


def test_real_pipeline_with_stub_encoder_returns_grounded_or_none(rag_on):
    for text in ("I keep thinking about ending my life", "mujhe jeena nahi hai", "the weather is nice"):
        result = hook.build_intervention(text, "HIGH", "en")
        assert result is None or (result["source"] == "grounded" and 1 <= len(result["items"]) <= 3
                                  and "helpline" not in result)


@pytest.mark.parametrize("behaviour,expected", [
    (lambda *a: {"source": "grounded", "language": "en",
                 "items": [{"text": "Stay with someone you trust.", "chunk_id": "c1"}],
                 "helpline": {"name": "x", "number": "1"}}, "grounded"),
    (lambda *a: {"source": "fallback", "language": "en", "items": [{"text": "draft"}]}, None),
    (lambda *a: (_ for _ in ()).throw(RuntimeError("pipeline broke")), None),
    (lambda *a: "not a dict", None),
])
def test_result_mapping(rag_on, monkeypatch, behaviour, expected):
    hp, _ = hook._STATE["pipe"]
    monkeypatch.setattr(hp, "run_crisis", behaviour)
    result = hook.build_intervention("I feel hopeless", "HIGH")
    assert (result or {}).get("source") == expected
    if result:
        assert "helpline" not in result


def test_timeout_returns_none_quickly(rag_on, monkeypatch):
    hp, _ = hook._STATE["pipe"]
    monkeypatch.setattr(hp, "run_crisis", lambda *a: time.sleep(2) or {"source": "grounded", "items": [{"text": "x"}]})
    monkeypatch.setenv("KOI_RAG_TIMEOUT_S", "0.2")
    started = time.monotonic()
    assert hook.build_intervention("I feel hopeless", "HIGH") is None
    assert time.monotonic() - started < 1.0


def test_endpoint_rules_with_hook_result(rag_on, monkeypatch):
    hp, _ = hook._STATE["pipe"]
    grounded = {"source": "grounded", "language": "en", "items": [{"text": "Stay with someone you trust."}]}
    monkeypatch.setattr(hp, "run_crisis", lambda *a: dict(grounded))
    helpline = {"name": "configured", "number": "1166", "verified": False}
    high = core.intervention("HIGH", hook.build_intervention("x", "HIGH"), helpline)
    assert high["source"] == "grounded" and high["helpline"] == helpline
    critical = core.intervention("CRITICAL", hook.build_intervention("x", "CRITICAL"), helpline)
    assert critical["source"] == "fallback"


def test_crisis_health_reports_hook_status(monkeypatch):
    import crisis_app
    inst = crisis_app.Crisis._get_user_cls()()
    inst.rag = None
    assert inst._rag_status() == {"rag_enabled": False, "rag_assets_loaded": False}
    inst.rag = types.SimpleNamespace(status=lambda: {"rag_enabled": True, "rag_assets_loaded": False})
    assert inst._rag_status() == {"rag_enabled": True, "rag_assets_loaded": False}
    inst.rag = types.SimpleNamespace(status=lambda: (_ for _ in ()).throw(RuntimeError()))
    assert inst._rag_status() == {"rag_enabled": False, "rag_assets_loaded": False}
