"""Tests for the crisis router added to scripts/retrieval_pipeline.py (2026-10-12).
Stand-in encoder (no model download): numbers are about plumbing/equivalence, NOT retrieval quality.
Run: python eval/test_crisis_router.py"""
import sys
import types
from pathlib import Path

import numpy as np
from sklearn.feature_extraction.text import HashingVectorizer

HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(HERE.parent / "scripts"), str(HERE)]


class StubEncoder:
    def __init__(self):
        self.v = HashingVectorizer(n_features=512, analyzer="char_wb", ngram_range=(2, 4), norm="l2",
                                   alternate_sign=False)
        self.name = "stub"

    def _e(self, texts):
        return self.v.transform(texts).toarray()

    encode_queries = encode_passages = _e

    # SentenceTransformer-like API so super_run's own code path can use it too
    def encode(self, texts, convert_to_numpy=True, show_progress_bar=False):
        return self._e(texts)


_st = types.ModuleType("sentence_transformers")
_st.SentenceTransformer = lambda *a, **k: StubEncoder()
sys.modules.setdefault("sentence_transformers", _st)
import retrieval_pipeline as rp  # noqa: E402

fails = []


def check(n, c):
    print(("PASS " if c else "FAIL ") + n)
    if not c:
        fails.append(n)


chunks = rp.load_corpus()
store = rp.load_example_store()
enc = StubEncoder()
R = rp.CrisisRouter(chunks, store, enc)
pool_ids = [chunks[i]["chunk_id"] for i in R.pool]
US = {"samhsa_e5b108d46d", "samhsa_068757d34a", "samhsa_0a88eb2fc9", "samhsa_c744348b34"}

# ---- pool and store (real files)
check("pool: 22 chunks (AUTH_noUS)", len(R.pool) == 22)
check("pool: no AnnoMI", all(chunks[i]["source_corpus"] != "AnnoMI" for i in R.pool))
check("pool: none of the 4 US-988 chunks", not (set(pool_ids) & US))
check("store: 133 positives + 83 negatives, ambiguous excluded",
      sum(not r["neg"] for r in R.store) == 133 and sum(r["neg"] for r in R.store) == 83 and R.dropped == 0)
import csv as _csv
_split = {r["id"]: r["split"] for r in _csv.DictReader(open(HERE / "labels" / "koi_queries_master_draft.csv", encoding="utf-8-sig"))}
check("store: every row is dev split in the master CSV (holdout never loaded)",
      all(_split.get(r["id"]) == "dev" for r in R.store))

# ---- exact equivalence with super_run.knn_route on the real store (LOSO), stand-in encoder
_ab = types.ModuleType("ablation"); _ec = types.ModuleType("embedder_comparison")
sys.modules.setdefault("ablation", _ab); sys.modules.setdefault("embedder_comparison", _ec)
import super_run as sr  # noqa: E402
items = sr.build_items(chunks, [dict(id=r["id"], lang=r["lang"], query=r["query"], gt_chunk_ids=r["gold"])
                                for r in store if not r["neg"]],
                       [dict(id=r["id"], lang=r["lang"], query=r["query"]) for r in store if r["neg"]])
Q = sr.l2n(enc.encode([it["query"] for it in items]))
E = sr.l2n(enc.encode([c["text"] for c in chunks]))
qq, cos = Q @ Q.T, Q @ E.T
scen = [it["scen"] for it in items]; golds = [it["gold"] for it in items]; isneg = [it["neg"] for it in items]
mine = R.loso_scores()
same = len(mine) == len(items)
for i in range(len(items)):
    v, _ = sr.knn_votes(i, qq, scen, golds, isneg, len(chunks))
    o = sr.order_by(v + 1e-6 * cos[i], R.pool)
    same &= list(o[:3]) == list(mine[i]["order"][:3]) and abs(float(v[o[0]]) - mine[i]["score"]) < 1e-9
check("LOSO top-3 and gate score identical to super_run.knn_route for all 216 store rows", bool(same))
op = rp.dev_operating_point(R, 0.4)
sw = sr.coverage_sweep(np.array([m["score"] for m in mine if not m["neg"]]),
                       np.array([int(m["order"][0] in m["gold"]) for m in mine if not m["neg"]]),
                       np.array([int(any(x in m["gold"] for x in m["order"][:3])) for m in mine if not m["neg"]]),
                       np.array([m["score"] for m in mine if m["neg"]]), covs=(0.4,))[0]
check("dev_operating_point == super_run.coverage_sweep at 40%",
      abs(op["thr"] - sw["thr"]) < 1e-12 and abs(op["far"] - sw["far"]) < 1e-12 and abs(op["acc_hit3"] - sw["acc_hit3"]) < 1e-12)

# ---- serving behaviour
FB = lambda lang: [{"text": f"FALLBACK-{lang}", "chunk_id": None, "source_corpus": "deterministic",
                    "evidence_role": None, "review_status": "not-required"}]
HL = {"name": "Humraaz", "number": "1166"}
q_in = store[0]["query"]                                   # a dev positive: its own row is a neighbour at serve time
Ropen = rp.CrisisRouter(chunks, store, enc, gate=0.0)       # gate 0 -> always grounded
out = Ropen.respond(q_in, "HIGH", FB, HL)
check("HIGH + accepted: grounded, 1-3 items, contract keys",
      out["source"] == "grounded" and 1 <= len(out["items"]) <= 3
      and set(out) == {"source", "language", "items", "helpline"}
      and all(set(i) == {"text", "chunk_id", "source_corpus", "evidence_role", "review_status"} for i in out["items"]))
check("HIGH: items only from the 22-chunk pool", all(i["chunk_id"] in pool_ids for i in out["items"]))

# ---- v4.29: zero-vote chunks are never served
_ids = [c["chunk_id"] for c in chunks]
_zero_seen = _all_ok = 0
_all_ok = True
for row in store:
    r = Ropen.route(row["query"])
    v, _ = rp.knn_votes(Ropen.Qs @ rp._l2n(enc.encode_queries([row["query"]]))[0], Ropen.golds, Ropen.is_neg,
                        Ropen.N, Ropen.k)
    _zero_seen += sum(1 for i in r["order"][:3] if v[i] == 0)
    _all_ok &= all(v[i] > 0 for i in r["served"]) and len(r["served"]) <= 3
    _all_ok &= r["served"] == [int(i) for i in r["order"] if v[i] > 0][:3]   # same order as the measured ranking
    o = Ropen.respond(row["query"], "HIGH", FB, HL)
    _all_ok &= (o["source"] == "fallback") if not r["served"] else [i["chunk_id"] for i in o["items"]] == [_ids[i] for i in r["served"]]
check("v4.29: served items all have votes > 0, keep ranking order, empty -> fallback (216 rows)", bool(_all_ok))
check("v4.29: test is not vacuous (zero-vote chunks do occur in the measured top-3)", _zero_seen > 0)
check("v4.29: gate unchanged (route order/gate_score/accept as before)",
      all(k in Ropen.route(q_in) for k in ("order", "gate_score", "accept", "served")))
Rshut = rp.CrisisRouter(chunks, store, enc, gate=1.01)      # gate unreachable -> always fallback
check("HIGH + below gate -> fallback", Rshut.respond(q_in, "HIGH", FB, HL)["source"] == "fallback")
check("CRITICAL -> fallback even when the gate would accept", Ropen.respond(q_in, "CRITICAL", FB, HL)["source"] == "fallback")
check("LOW / MODERATE -> None (field omitted)",
      Ropen.respond(q_in, "LOW", FB, HL) is None and Ropen.respond(q_in, "moderate", FB, HL) is None)
check("HIGH_CRISIS accepted as HIGH (enum still OPEN)", Ropen.respond(q_in, "HIGH_CRISIS", FB, HL)["source"] == "grounded")
try:
    Ropen.respond(q_in, "SEVERE", FB, HL); ok = False
except ValueError:
    ok = True
check("unknown tier string raises", ok)
check("language from language_detector mapped to contract values",
      Ropen.respond("مجھے خود کو نقصان پہنچانا ہے", "HIGH", FB, HL)["language"] == "ur"
      and Ropen.respond("main theek nahi hoon", "HIGH", FB, HL)["language"] == "ur-roman"
      and Ropen.respond("I want to hurt myself", "HIGH", FB, HL)["language"] == "en")
check("fallback items come from the injected fallback, language passed through",
      Ropen.respond("I want to hurt myself", "CRITICAL", FB, HL)["items"][0]["text"] == "FALLBACK-en")
check("helpline passed through unchanged", out["helpline"] == HL)


class Boom(StubEncoder):
    def encode_queries(self, texts):
        if texts == ["boom"]:
            raise RuntimeError("encoder down")
        return super().encode_queries(texts)


check("HIGH: retrieval exception -> fallback, not a crash",
      rp.CrisisRouter(chunks, store, Boom(), gate=0.0).respond("boom", "HIGH", FB, HL)["source"] == "fallback")

# ---- hand-computed knn_votes (same fixture as test_super_run.py)
sims = np.array([[1, .9, .8, .1]], float)[0]
v, nb = rp.knn_votes(sims, [{0}, {1}, {2}, set()], [False, False, False, True], 4, k=2,
                     candidates=np.array([2, 3]))
check("knn_votes: excluded candidates never neighbours; weight-normalised", nb == [2, 3] and abs(v[2] - .8 / .9) < 1e-12)

# ---- script-conditional BM25 option
hr = rp.HybridRetriever(chunks[-26:], bm25_policy="script_cond")
check("script_cond: Latin query skips BM25", not hr.retrieve("safety plan", k=3)[0]["bm25_used"])
check("script_cond: Urdu-script query uses BM25", hr.retrieve("زندگی جینے کے قابل", k=3)[0]["bm25_used"])
check("default policy unchanged (reference behaviour)", rp.HybridRetriever(chunks[-26:]).retrieve("safety plan", k=3)[0]["bm25_used"])

print("\nALL PASSED" if not fails else "\nFAILED: " + ", ".join(fails))
if __name__ == "__main__":
    sys.exit(1 if fails else 0)
elif fails:
    raise SystemExit("test_crisis_router failed")
