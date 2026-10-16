"""
Plumbing tests for ablation.py (stand-in encoder; verifies code paths, NOT retrieval quality).
Run: python test_ablation.py
"""
import contextlib
import io
import sys
import types
from pathlib import Path

from sklearn.feature_extraction.text import HashingVectorizer

HERE = Path(__file__).resolve().parent


class _Stub:
    def __init__(self, *a, **k):
        self.v = HashingVectorizer(n_features=512, analyzer="char_wb", ngram_range=(2, 4),
                                   norm="l2", alternate_sign=False)

    def encode(self, texts, convert_to_numpy=True, show_progress_bar=False):
        return self.v.transform(texts).toarray()


_fake = types.ModuleType("sentence_transformers")
_fake.SentenceTransformer = _Stub
sys.modules["sentence_transformers"] = _fake
sys.path.insert(0, str(HERE))

import ablation as ab  # noqa: E402
import embedder_comparison as ec  # noqa: E402
import retrieval_pipeline as rp  # noqa: E402

fails = []


def check(name, cond, detail=""):
    print(("PASS " if cond else "FAIL ") + name + (f"  [{detail}]" if detail else ""))
    if not cond:
        fails.append(name)


chunks = rp.load_corpus()
small = chunks[:80] + [c for c in chunks if c["source_corpus"] != "AnnoMI"]
r = rp.HybridRetriever(small)
bm25s = ab.build_bm25s(r.texts)
urdu_q = ec.urdu_probe_queries(small)[0]["query"]

# 1. tokenizers
check("ascii tokenizer gives 0 tokens on Urdu script", ab.tok_ascii(urdu_q) == [])
check("unicode tokenizer gives tokens on Urdu script", len(ab.tok_unicode(urdu_q)) > 0)
check("char3 tokenizer gives tokens on Urdu script", len(ab.tok_char3(urdu_q)) > 0)
check("char3 splits long words into 3-grams", ab.tok_char3("hopeless") == ["hop", "ope", "pel", "ele", "les", "ess"])

# 2. harness validity. The pipeline default is now BM25 over Unicode words WITH the empty-token guard
#    (2026-10-12), so the default retriever must equal the 'hybrid_unicode_words' arm; the
#    bm25_tokenizer="ascii" retriever must equal 'hybrid_ascii_skip_empty' (reference BM25 + guard).
ids = lambda idx: [small[i]["chunk_id"] for i in idx]
r_ascii = rp.HybridRetriever(small, bm25_tokenizer="ascii")
same_u = same_a = True
for tier in ("HIGH", "CRITICAL"):
    mask = rp.eligibility_mask(small, tier)
    for q in ["suicidal thoughts safety plan", "ask about drinking", urdu_q, "crisis services prioritize safety"]:
        mine_u, _ = ab.rank(r, bm25s, q, mask, "hybrid_unicode_words")
        theirs_u = [x["chunk"]["chunk_id"] for x in r.retrieve(q, k=10, eligible_mask=mask)]
        same_u &= ids(mine_u) == theirs_u
        mine_a, _ = ab.rank(r_ascii, bm25s, q, mask, "hybrid_ascii_skip_empty")
        theirs_a = [x["chunk"]["chunk_id"] for x in r_ascii.retrieve(q, k=10, eligible_mask=mask)]
        same_a &= ids(mine_a) == theirs_a
check("default retriever == hybrid_unicode_words arm on 8 query/tier cases", same_u)
check("ascii-mode retriever == hybrid_ascii_skip_empty arm on 8 query/tier cases", same_a)
res0 = r_ascii.retrieve(urdu_q, k=5, eligible_mask=rp.eligibility_mask(small, "HIGH"))
check("ascii mode flags bm25_used=False on a zero-token query", all(x["bm25_used"] is False for x in res0))
res1 = r.retrieve(urdu_q, k=5, eligible_mask=rp.eligibility_mask(small, "HIGH"))
check("default mode uses BM25 on an Urdu-script query", all(x["bm25_used"] is True for x in res1))

# 3. skip_empty collapses to dense-only on zero-token queries; other arms still return k
mask = rp.eligibility_mask(small, "HIGH")
d, _ = ab.rank(r, bm25s, urdu_q, mask, "dense_only")
s, _ = ab.rank(r, bm25s, urdu_q, mask, "hybrid_ascii_skip_empty")
check("skip_empty == dense_only when query has 0 BM25 tokens", d == s)
c, _ = ab.rank(r, bm25s, urdu_q, mask, "hybrid_ascii (reference)")
print(f"INFO current-arm top-10 equals dense-only on this Urdu query: {c == d} (stand-in encoder)")
for arm in ab.ARMS:
    idx, _ = ab.rank(r, bm25s, "hopeless and want to give up", mask, arm)
    check(f"arm '{arm}' returns 10 eligible results", len(idx) == 10 and all(mask[i] for i in idx))

# 4. AUC helper
check("auc: perfect separation = 1.0", ab.auc([0.9, 0.8], [0.1, 0.2]) == 1.0)
check("auc: ties count half", ab.auc([0.5], [0.5]) == 0.5)
check("auc: empty -> None", ab.auc([], [0.1]) is None)

# 5. end-to-end with the stand-in. Scenario A: no hand-labelled queries (pinned, independent of the generated file)
_saved_ml = ec.MULTILINGUAL_QUERIES
ec.MULTILINGUAL_QUERIES = []
before = set((HERE / "results").glob("*")) if (HERE / "results").exists() else set()
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    res = ab.run(["minilm"], cache_dir=None)
out = buf.getvalue()
check("e2e: all 5 arms reported", all(a in res["models"]["minilm"]["arms"] for a in ab.ARMS))
check("e2e: roman_urdu NOT EVALUATED", "HAND-LABELLED roman_urdu" in out and "NOT EVALUATED" in out)
check("e2e: holdout never evaluated", "h01" not in out)
check("e2e: cosine separation printed", "AUC=" in out)
# Scenario B: with the generated hand-labelled file, strata are evaluated and label sources are printed
ec.MULTILINGUAL_QUERIES = _saved_ml
if _saved_ml:
    buf2 = io.StringIO()
    with contextlib.redirect_stdout(buf2):
        res2 = ab.run(["minilm"], cache_dir=None)
    out2 = buf2.getvalue()
    check("e2e(populated): roman_urdu stratum evaluated", res2["models"]["minilm"]["arms"]["dense_only"]["HAND-LABELLED roman_urdu"] is not None)
    check("e2e(populated): label sources printed", "label sources" in out2)
for f in set((HERE / "results").glob("*")) - before:
    f.unlink()

print("\nFAILED: " + ", ".join(fails) if fails else "\nALL PASSED (plumbing only; stand-in encoder)")
sys.exit(1 if fails else 0)
