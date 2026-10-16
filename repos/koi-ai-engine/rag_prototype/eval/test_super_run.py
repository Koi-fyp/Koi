"""Tests for super_run.py: metric/stat helpers with hand-computed values + end-to-end plumbing with a
stand-in encoder (no model download). Run: python test_super_run.py"""
import contextlib, io, sys, types
from pathlib import Path

import numpy as np
from sklearn.feature_extraction.text import HashingVectorizer


class _Stub:
    def __init__(self, *a, **k):
        self.v = HashingVectorizer(n_features=512, analyzer="char_wb", ngram_range=(2, 4), norm="l2",
                                   alternate_sign=False)

    def encode(self, texts, convert_to_numpy=True, show_progress_bar=False):
        return self.v.transform(texts).toarray()


_f = types.ModuleType("sentence_transformers"); _f.SentenceTransformer = _Stub
sys.modules["sentence_transformers"] = _f
sys.path.insert(0, str(Path(__file__).resolve().parent))
import super_run as sr  # noqa: E402
import embedder_comparison as ec  # noqa: E402
import multilingual_queries as mq  # noqa: E402
from aliases import ALIASES  # noqa: E402
from retrieval_pipeline import load_corpus  # noqa: E402

fails = []


def check(n, c):
    print(("PASS " if c else "FAIL ") + n)
    if not c:
        fails.append(n)


# ---- metrics
o = [5, 2, 9, 1]
check("hit_at: gold at rank 2 -> Hit@1=0, Hit@3=1", sr.hit_at(o, {2}, 1) == 0 and sr.hit_at(o, {2}, 3) == 1)
check("recall_at: 1 of 2 gold in top-3 -> 0.5 (differs from Hit@3=1)",
      sr.recall_at(o, {2, 1}, 3) == 0.5 and sr.hit_at(o, {2, 1}, 3) == 1)
check("first_rank", sr.first_rank(o, {9, 1}) == 3 and sr.first_rank(o, {7}) is None)
h1, r1 = sr.random_expectation(26, [1], 1)
check("random: 1 gold in 26 -> Hit@1 = 1/26 = Rec@1", abs(h1 - 1 / 26) < 1e-12 and abs(r1 - 1 / 26) < 1e-12)
h3, _ = sr.random_expectation(26, [2], 3)
check("random: 2 gold, k=3 -> 1 - C(24,3)/C(26,3)", abs(h3 - (1 - 2024 / 2600)) < 1e-12)

# ---- stats
check("mcnemar: identical -> p=1", sr.mcnemar_exact([1, 0, 1], [1, 0, 1]) == 1.0)
check("mcnemar: 6 discordant all one way -> p=2/64", abs(sr.mcnemar_exact([1] * 6, [0] * 6) - 2 / 64) < 1e-12)
d, lo, hi = sr.cluster_boot_diff([1, 1, 1, 1], [0, 0, 0, 0], ["a", "a", "b", "b"], B=200)
check("bootstrap: constant +1 difference -> CI [1,1]", d == 1 and lo == 1 and hi == 1)
d, lo, hi = sr.cluster_boot_diff([1, 0, 1, 0], [0, 1, 0, 1], ["a", "b", "c", "d"], B=500)
check("bootstrap: symmetric difference -> mean 0, CI spans 0", d == 0 and lo < 0 < hi)
g = sr.gate_stats([0.9, 0.8, 0.7, 0.6, 0.5], [1, 1, 0, 1, 0], [0.95, 0.4, 0.3, 0.2])
check("gate: 80% coverage threshold keeps 4 of 5 positives", abs(g["prec80"] - 0.75) < 1e-12)
check("gate: 1 of 4 negatives above threshold -> FAR 25% with CI", g["far80"] == 0.25 and g["far80_ci"][1] > 0.25)

# ---- rrf + knn
check("rrf: item ranked 1st by both stays 1st", list(sr.rrf_order(np.array([3, 1, 2]), np.array([3, 2, 1]), 4))[0] == 3)
sims = np.array([[1, .9, .8, .1], [.9, 1, .1, .1], [.8, .1, 1, .1], [.1, .1, .1, 1]], float)
scen = ["s1", "s1", "s2", "s3"]
golds = [{0}, {1}, {2}, set()]
v, nb = sr.knn_votes(0, sims, scen, golds, [False, False, False, True], 4, k=2)
check("knn: same-scenario neighbour (translation) excluded", 1 not in nb and 0 not in nb)
check("knn: votes go to neighbour gold; negative neighbour adds weight only",
      v[2] > 0 and v[1] == 0 and abs(v[2] - .8 / .9) < 1e-12)


# ---- coverage sweep + operating point (rule G)
sw = sr.coverage_sweep([0.9, 0.8, 0.7, 0.6, 0.5], [1, 1, 0, 1, 0], [1, 1, 1, 1, 0], [0.95, 0.4, 0.3, 0.2],
                       covs=(1.0, 0.6))
check("sweep: coverage 100% accepts all positives and all negatives", sw[0]["cov_actual"] == 1 and sw[0]["far"] == 1)
check("sweep: coverage 60% keeps top-3 positives, 1 of 4 negatives", abs(sw[1]["cov_actual"] - 0.6) < 1e-9
      and abs(sw[1]["acc_hit1"] - 2 / 3) < 1e-9 and sw[1]["far"] == 0.25)
op = sr.operating_point(sw)
check("rule G: no point with FAR<=20% -> 'none'", op["status"] == "none")
op = sr.operating_point([dict(cov=.5, cov_actual=.5, far=.08), dict(cov=.7, cov_actual=.7, far=.15),
                         dict(cov=.3, cov_actual=.3, far=0.0)])
check("rule G: picks LARGEST coverage with FAR<=10%", op["status"] == "ok" and op["cov_actual"] == .5)

# ---- aliases
chunks = load_corpus()
auth_ids = {c["chunk_id"] for c in chunks if c["source_corpus"] != "AnnoMI"}
check("aliases: exactly the 26 guideline chunks", set(ALIASES) == auth_ids and len(ALIASES) == 26)
check("aliases: 4 each, one per language slot, Urdu slot is Arabic script",
      all(len(v) == 4 and sr.ARABIC.search(v[2]) and not sr.ARABIC.search(v[1]) for v in ALIASES.values()))

# ---- end-to-end plumbing (stand-in encoder; numbers are meaningless)
pos, _ = ec.valid_multilingual(ec.MULTILINGUAL_QUERIES)
neg = list(mq.MULTILINGUAL_NEGATIVES)
calls = {}


def fake_ce(pairs):
    calls["n"] = len(pairs)
    return np.random.default_rng(0).normal(size=len(pairs))


buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    res = sr.run(["minilm", "me5-small"], None, pos_entries=pos[:30], neg_entries=neg[:15],
                 ce_scorer=fake_ce, ce_name="fake", save=False, B=200)
out = buf.getvalue()
check("e2e: all pools reported", all(p in out for p in ("FULL", "AUTH ", "AUTH_noUS")))
check("e2e: all systems reported", all(s in out for s in sr.AUTH_SYSTEMS + ("rerank",)))
check("e2e: reranker scored every query x 26 guideline chunks", calls.get("n") == 45 * 26)
rows = res["models"]["minilm"]["rows"]
check("e2e: AUTH pools never return AnnoMI", all(v["annomi10"] == 0 for k, v in rows.items() if k.startswith("AUTH")))
check("e2e: AUTH_noUS pool has 26 - 4 = 22 chunks", "AUTH_noUS=22" in out)
check("e2e: constant_insample >= constant_loso on Hit@3 (in-sample is optimistic)",
      rows["AUTH|constant_insample"]["hit3"] >= rows["AUTH|constant_loso"]["hit3"])
check("e2e: constant gate gives AUC 0.5 and accepts every negative",
      rows["AUTH|constant_loso"]["auc"] == 0.5 and rows["AUTH|constant_loso"]["far80"] == 1.0)
check("e2e: verdicts for every rule printed", all(x in out for x in ("A pool", "B adopted", "C beats", "D embedder")))
check("e2e: embedder choice present", "chosen" in res["verdicts"]["D_embedder"])
check("e2e: leakage check printed", "leakage check" in out)
check("e2e: fusion arm + strictness sweep + rules F/G printed",
      all(x in out for x in ("knn_dense_rrf", "STRICTNESS SWEEP", "F fusion adopted", "G operating point")))
check("e2e: sweep stored per model", len(res["models"]["minilm"]["sweeps"]["knn_route"]) == 8)
print("\nALL PASSED" if not fails else "\nFAILED: " + ", ".join(fails))
sys.exit(1 if fails else 0)
