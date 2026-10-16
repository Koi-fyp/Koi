"""
Plumbing tests for embedder_comparison.py. Stand-in encoder (hashing vectorizer), so this
verifies CODE PATHS (prefixes, cache, strata handling, label validation), NOT retrieval
quality and NOT any real model. Real numbers need a local run.

Run: python test_embedder_comparison.py
"""
import shutil
import sys
import tempfile
import types
from pathlib import Path

import numpy as np
from sklearn.feature_extraction.text import HashingVectorizer

HERE = Path(__file__).resolve().parent
CALLS = []  # (model_name, [strings encoded])


class _Recorder:
    def __init__(self, name, *a, **k):
        self.name = name
        self.v = HashingVectorizer(n_features=512, analyzer="char_wb", ngram_range=(2, 4),
                                   norm="l2", alternate_sign=False)

    def encode(self, texts, convert_to_numpy=True, show_progress_bar=False):
        CALLS.append((self.name, list(texts)))
        return self.v.transform(texts).toarray()


_fake = types.ModuleType("sentence_transformers")
_fake.SentenceTransformer = _Recorder
sys.modules["sentence_transformers"] = _fake
sys.path.insert(0, str(HERE))

import embedder_comparison as ec  # noqa: E402
import retrieval_pipeline as rp  # noqa: E402

fails = []


def check(name, cond, detail=""):
    print(("PASS " if cond else "FAIL ") + name + (f"  [{detail}]" if detail else ""))
    if not cond:
        fails.append(name)


chunks = rp.load_corpus()
small = chunks[:50] + [c for c in chunks if c["source_corpus"] != "AnnoMI"]

# 1. defaults == reference behaviour: no prefix on docs or queries
CALLS.clear()
r = rp.HybridRetriever(small)
r.retrieve("hello world", k=3, eligible_mask=[True] * len(small))
docs_call, query_call = CALLS[0][1], CALLS[1][1]
check("default: model is MiniLM", CALLS[0][0] == rp.DEFAULT_MODEL)
check("default: docs encoded with no prefix", docs_call[0] == small[0]["text"])
check("default: query encoded with no prefix", query_call == ["hello world"])

# 2. e5-style prefixes reach both docs and queries
CALLS.clear()
r = rp.HybridRetriever(small, model_name="x/e5", doc_prefix="passage: ", query_prefix="query: ")
r.retrieve("hello world", k=3, eligible_mask=[True] * len(small))
check("e5: docs get 'passage: '", all(s.startswith("passage: ") for s in CALLS[0][1]))
check("e5: query gets 'query: '", CALLS[1][1] == ["query: hello world"])

# 3. cache: second construction does not re-encode the docs
tmp = tempfile.mkdtemp()
try:
    CALLS.clear()
    rp.HybridRetriever(small, model_name="x/m", cache_dir=tmp)
    first_calls = len(CALLS)
    CALLS.clear()
    r2 = rp.HybridRetriever(small, model_name="x/m", cache_dir=tmp)
    check("cache: first build encoded docs", first_calls == 1)
    check("cache: second build encoded nothing", len(CALLS) == 0)
    check("cache: embeddings identical", np.allclose(r2.embeddings, np.load(next(Path(tmp).glob("*.npy")))))
    CALLS.clear()
    rp.HybridRetriever(small, model_name="x/m", doc_prefix="passage: ", cache_dir=tmp)
    check("cache: different prefix -> different key -> re-encodes", len(CALLS) == 1)
finally:
    shutil.rmtree(tmp)

# 4. label validation: unlabelled entries are rejected, never scored
ok, rej = ec.valid_multilingual([
    {"id": "good", "lang": "roman_urdu", "query": "q", "gt_chunk_ids": ["a"], "gt_labelled_by": "Ahmad"},
    {"id": "no_labeller", "lang": "roman_urdu", "query": "q", "gt_chunk_ids": ["a"], "gt_labelled_by": ""},
    {"id": "no_gold", "lang": "roman_urdu", "query": "q", "gt_chunk_ids": [], "gt_labelled_by": "Ahmad"},
])
check("validation keeps only fully labelled entries", [e["id"] for e in ok] == ["good"], str(rej))
check("validation reports rejected ids", rej == ["no_labeller", "no_gold"])

# 5. Urdu probe derived from real data
probe = ec.urdu_probe_queries(chunks)
bilingual_ids = {c["chunk_id"] for c in chunks if c.get("language") == "bilingual"}
check("probe: every query is Urdu-script", all(ec.URDU_CHAR.search(p["query"]) for p in probe))
check("probe: gold chunks are exactly bilingual chunks that yielded lines",
      {p["gt_chunk_ids"][0] for p in probe} <= bilingual_ids and len(probe) > 0, f"{len(probe)} queries")
check("probe: queries really occur inside their gold chunk",
      all(p["query"] in next(c for c in chunks if c["chunk_id"] == p["gt_chunk_ids"][0])["text"] for p in probe))
check("probe: BM25 gets 0 tokens for Urdu-script queries (documented tokenizer limit)",
      all(len(rp.tokenize(p["query"])) == 0 for p in probe))

# 6. end-to-end run with the stand-in; empty strata must say NOT EVALUATED (pinned to an empty list so the
#    generated multilingual_queries.py does not change this scenario)
ec.MULTILINGUAL_QUERIES = []
import io, contextlib
before = set((HERE / "results").glob("*")) if (HERE / "results").exists() else set()
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    res = ec.run(["minilm", "me5-small"], cache_dir=None)
out = buf.getvalue()
check("e2e: runs both models", set(res["models"]) == {"minilm", "me5-small"})
check("e2e: roman_urdu stratum NOT EVALUATED",
      res["models"]["minilm"]["strata"]["HAND-LABELLED roman_urdu"] is None and "NOT EVALUATED" in out)
check("e2e: code_switched stratum NOT EVALUATED", res["models"]["me5-small"]["strata"]["HAND-LABELLED code_switched"] is None)
check("e2e: english tier A evaluated with n>0", res["models"]["minilm"]["strata"]["ENGLISH tier A (gold)"]["dense"]["n"] > 0)
check("e2e: holdout queries never evaluated",
      "h01" not in out and all(p["id"] not in {"h01", "h02"} for m in res["models"].values()
                               for s in m["strata"].values() if s for p in s["per_query"]))
check("e2e: warns about 0-token BM25 on Urdu probe", "0 BM25 tokens" in out)
for f in set((HERE / "results").glob("*")) - before:
    f.unlink()

print("\nFAILED: " + ", ".join(fails) if fails else "\nALL PASSED (plumbing only; stand-in encoder)")
sys.exit(1 if fails else 0)
