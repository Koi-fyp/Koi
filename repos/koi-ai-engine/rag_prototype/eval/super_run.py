"""
SUPER RUN -- every candidate retrieval design, scored on the SAME dev queries, chosen by PRE-REGISTERED rules.

Run LOCALLY (reuses embeddings cached by embedder_comparison.py / ablation.py):
    python super_run.py --cache-dir .emb_cache
    python super_run.py --cache-dir .emb_cache --reranker BAAI/bge-reranker-v2-m3      # + cross-encoder arm
    python super_run.py --models me5-small bge-m3 --cache-dir .emb_cache

Pools (all start from the HIGH eligibility pre-filter):
  FULL       6,204 eligible chunks (~6,178 AnnoMI transcripts + 26 guideline chunks)  -- current behaviour
  AUTH       the 26 guideline chunks only
  AUTH_noUS  AUTH minus chunks that mention the US-only 988 Lifeline (jurisdiction mismatch for Pakistan)

Systems:
  dense            cosine only
  hybrid_unicode   BM25 over Unicode words + dense, RRF k=60 (current pipeline default)
  hybrid_char3     BM25 over char 3-grams + dense, RRF
  script_cond      hybrid_unicode if the query contains Arabic-script characters, else dense
  alias_only       chunk score = max cosine over its 4 synthetic user-voice aliases (aliases.py)
  orig_plus_alias  chunk score = max(chunk cosine, best alias cosine)
  knn_route        K=7 nearest LABELLED dev queries (positives AND negatives), leave-SCENARIO-out, vote for
                   their gold chunks; negatives vote for "nothing" -> natural abstention score
  constant_loso    always the most frequent gold chunks, counted with the query's own scenario left out
                   (the deployable fixed bundle -- the baseline every "smart" system must beat)
  constant_insample same, counted in-sample (optimistic ceiling for a fixed bundle; descriptive only)
  rerank           cross-encoder over the guideline chunks (only with --reranker; embedder-independent)
  random           analytic expectation within the pool

Metrics (positives only unless stated):
  Hit@k     = any gold chunk in top-k   (what earlier reports called "R@k")
  Rec@k     = |top-k ∩ gold| / |gold|   (true recall)
  MRR, non-hub Hit@k (rows whose gold contains none of the 4 most frequent gold chunks)
  Gate (positives vs the labelled negatives): AUC of the top-1 score; at the threshold that keeps 80% of
  positives -> accepted Hit@1 ("prec@80") and false-accept rate on negatives with exact 95% CI.
  Paired: scenario-cluster bootstrap 95% CI of the difference, exact McNemar p.

PRE-REGISTERED DECISION RULES (fixed 2026-10-12, before any super-run number existed):
  A  POOL      AUTH replaces FULL at HIGH if FULL dense top-10 is >=95% AnnoMI on average OR AUTH dense
               Hit@3 >= FULL dense Hit@3 - 0.02.  (Policy reason stands regardless: AnnoMI are demonstration
               transcripts, incl. deliberately low-quality ones, not guidance.)
  B  ADOPT     a challenger replaces `dense` in the chosen pool only if paired Hit@3 gain >= +0.05 AND the
               bootstrap 95% CI lower bound > 0 AND prec@80 does not drop by more than 0.02.
  C  CLAIM     a system may be called "query-sensitive" only if its paired Hit@1 gain over constant_loso has
               a CI lower bound > 0. Otherwise the defense states retrieval did NOT beat a fixed bundle.
  D  EMBEDDER  the model with the highest AUTH `dense` Hit@3 wins only if its paired CI lower bound > 0
               against every other model; otherwise tie -> multilingual-e5-small (smallest multilingual,
               CPU/local-first) is chosen.
  E  FINAL     the chosen config is then run ONCE on the untouched holdout split; reported whatever it says.
  -- added 2026-10-12 07:50, AFTER the first super run (rules A-E above were not changed) --
  F  FUSION    knn_dense_rrf (parameter-free RRF of the kNN order and the dense order) replaces knn_route only
               if paired Hit@3 gain vs knn_route has CI lower bound > 0 AND its Hit@1 point estimate is not lower.
  G  STRICTNESS operating point (pool AUTH_noUS, gate = top-1 kNN vote share) = the LARGEST coverage in the sweep
               whose false-accept rate on negatives is <= 10%. If none, the largest with <= 20%, flagged "weak".
               If none again: "no safe operating point on dev". Thresholds are in-sample; holdout checks them.
Labels are LLM-adjudicated (see gt_labelled_by), aliases are Claude-written and unreviewed. Dev numbers are
in-sample for anything fitted (thresholds, constants, kNN). Treat all of this as evidence, not proof.
"""
import argparse
import csv
import json
import re
import sys
import time
from collections import Counter, defaultdict
from datetime import datetime
from pathlib import Path

import numpy as np
from rank_bm25 import BM25Okapi
from scipy import stats

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "scripts"))
sys.path.insert(0, str(HERE))
import ablation as ab  # noqa: E402
import embedder_comparison as ec  # noqa: E402
import multilingual_queries as mq  # noqa: E402
from aliases import ALIASES, ALIAS_PROVENANCE  # noqa: E402
from retrieval_pipeline import load_corpus, HybridRetriever, eligibility_mask  # noqa: E402

RRF_K = 60
KNN_K = 7
ARABIC = re.compile(r"[؀-ۿ]")
US_ONLY = re.compile(r"\b988\b")
MASTER_CSV = HERE / "labels" / "koi_queries_master_draft.csv"
LANGS = ("urdu_native", "roman_urdu", "code_switched")
FULL_SYSTEMS = ("dense", "hybrid_unicode", "script_cond")
AUTH_SYSTEMS = ("dense", "hybrid_unicode", "hybrid_char3", "script_cond", "alias_only", "orig_plus_alias",
                "knn_route", "knn_dense_rrf", "constant_loso", "constant_insample")
CHALLENGERS = ("hybrid_unicode", "hybrid_char3", "script_cond", "alias_only", "orig_plus_alias", "knn_route",
               "knn_dense_rrf",
               "rerank")
TIEBREAK_MODEL = "me5-small"


# ---------------------------------------------------------------- metric / stats helpers (unit-tested)
def hit_at(order, gold, k):
    return int(any(i in gold for i in order[:k]))


def recall_at(order, gold, k):
    return len(set(order[:k]) & gold) / len(gold)


def first_rank(order, gold):
    for r, i in enumerate(order, 1):
        if i in gold:
            return r
    return None


def random_expectation(pool_size, gold_sizes, k):
    """Expected Hit@k and Rec@k for a uniformly random ranking of the pool."""
    from math import comb
    hits = [1 - comb(pool_size - g, k) / comb(pool_size, k) if pool_size - g >= k else 1.0 for g in gold_sizes]
    return float(np.mean(hits)), k / pool_size


def mcnemar_exact(a, b):
    a, b = np.asarray(a), np.asarray(b)
    n01 = int(((a == 0) & (b == 1)).sum())
    n10 = int(((a == 1) & (b == 0)).sum())
    if n01 + n10 == 0:
        return 1.0
    return float(stats.binomtest(min(n01, n10), n01 + n10, 0.5).pvalue)


def cluster_boot_diff(a, b, clusters, B=2000, seed=0):
    """Mean(a-b) with a bootstrap 95% CI that resamples whole scenarios (translations stay together)."""
    a, b = np.asarray(a, float), np.asarray(b, float)
    ids = sorted(set(clusters))
    pos = {c: i for i, c in enumerate(ids)}
    sa, sb, cnt = np.zeros(len(ids)), np.zeros(len(ids)), np.zeros(len(ids))
    for x, y, c in zip(a, b, clusters):
        sa[pos[c]] += x
        sb[pos[c]] += y
        cnt[pos[c]] += 1
    rng = np.random.default_rng(seed)
    draw = rng.integers(0, len(ids), size=(B, len(ids)))
    diffs = (sa[draw].sum(1) - sb[draw].sum(1)) / cnt[draw].sum(1)
    return float((a - b).mean()), float(np.percentile(diffs, 2.5)), float(np.percentile(diffs, 97.5))


def gate_stats(pos_scores, pos_hit1, neg_scores, coverage=0.8):
    pos_scores, pos_hit1, neg_scores = map(np.asarray, (pos_scores, pos_hit1, neg_scores))
    out = {"auc": ab.auc(list(pos_scores), list(neg_scores))}
    thr = float(np.quantile(pos_scores, 1 - coverage))
    acc = pos_scores >= thr
    out["thr"] = thr
    out["prec80"] = float(pos_hit1[acc].mean()) if acc.any() else None
    k = int((neg_scores >= thr).sum())
    n = len(neg_scores)
    out["far80"] = k / n if n else None
    out["far80_ci"] = list(stats.binomtest(k, n).proportion_ci(0.95, "exact")) if n else None
    out["far80_k"], out["n_neg"] = k, n
    return out


def order_by(score, mask_idx):
    return mask_idx[np.argsort(-score[mask_idx], kind="stable")]


def rrf_order(order_a, order_b, n_total):
    s = np.zeros(n_total)
    for o in (order_a, order_b):
        s[o] += 1.0 / (RRF_K + np.arange(1, len(o) + 1))
    pool = np.asarray(order_b)
    return pool[np.argsort(-s[pool], kind="stable")]


def knn_votes(qi, sims, scen, golds, is_neg, n_chunks, k=KNN_K):
    """Leave-scenario-out kNN over labelled queries. Returns (vote vector normalised by total neighbour
    weight, neighbour indices). Negatives contribute weight but no votes -> lower confidence."""
    valid = np.array([scen[j] != scen[qi] for j in range(len(scen))])
    cand = np.flatnonzero(valid)
    if not len(cand):
        return np.zeros(n_chunks), []
    nb = cand[np.argsort(-sims[qi, cand], kind="stable")[:k]]
    w = np.clip(sims[qi, nb], 0, None)
    votes = np.zeros(n_chunks)
    for j, wj in zip(nb, w):
        if not is_neg[j]:
            for g in golds[j]:
                votes[g] += wj
    tot = w.sum()
    return (votes / tot if tot > 0 else votes), list(nb)


def scenario_map(path=MASTER_CSV):
    if not Path(path).exists():
        return {}
    with open(path, encoding="utf-8-sig") as fh:
        return {r["id"]: (r.get("scenario_id") or r["id"]) for r in csv.DictReader(fh)}


# ---------------------------------------------------------------- data
def build_items(chunks, pos_entries, neg_entries):
    id2idx = {c["chunk_id"]: i for i, c in enumerate(chunks)}
    smap = scenario_map()
    items = []
    for e in pos_entries:
        g = {id2idx[c] for c in e.get("gt_chunk_ids", []) if c in id2idx}
        if g:
            items.append(dict(id=e["id"], lang=e["lang"], query=e["query"], gold=g, neg=False,
                              scen=smap.get(e["id"], e["id"])))
    for e in neg_entries:
        items.append(dict(id=e["id"], lang=e["lang"], query=e["query"], gold=set(), neg=True,
                          scen=smap.get(e["id"], e["id"])))
    return items


def l2n(m):
    m = np.asarray(m, float)
    return m / np.clip(np.linalg.norm(m, axis=1, keepdims=True), 1e-12, None)


# ---------------------------------------------------------------- main
def run(model_keys, cache_dir, pos_entries=None, neg_entries=None, ce_scorer=None, ce_name=None,
        retriever_factory=None, save=True, B=2000):
    t_start = time.time()
    chunks = load_corpus()
    N = len(chunks)
    if pos_entries is None:
        pos_entries, rejected = ec.valid_multilingual(ec.MULTILINGUAL_QUERIES)
    if neg_entries is None:
        neg_entries = list(getattr(mq, "MULTILINGUAL_NEGATIVES", []))
    items = build_items(chunks, pos_entries, neg_entries)
    P = [i for i, it in enumerate(items) if not it["neg"]]
    Ng = [i for i, it in enumerate(items) if it["neg"]]
    scen = [it["scen"] for it in items]
    golds = [it["gold"] for it in items]
    is_neg = [it["neg"] for it in items]

    is_annomi = np.array([c["source_corpus"] == "AnnoMI" for c in chunks])
    full = np.array(eligibility_mask(chunks, "HIGH"))
    auth = full & ~is_annomi
    nous = auth & np.array([not US_ONLY.search(c["text"]) for c in chunks])
    pools = {"FULL": np.flatnonzero(full), "AUTH": np.flatnonzero(auth), "AUTH_noUS": np.flatnonzero(nous)}

    gold_freq = Counter(g for i in P for g in golds[i])
    hub = {g for g, _ in gold_freq.most_common(4)}
    nonhub = [i for i in P if not (golds[i] & hub)]
    us_ids = [chunks[i]["chunk_id"] for i in np.flatnonzero(auth & ~nous)]
    lost_rows = sum(1 for i in P if golds[i] and golds[i] <= set(np.flatnonzero(auth & ~nous)))

    print(f"SUPER RUN  positives={len(P)}  negatives={len(Ng)}  scenarios={len(set(scen))}")
    print(f"  pools: FULL={len(pools['FULL'])}  AUTH={len(pools['AUTH'])}  AUTH_noUS={len(pools['AUTH_noUS'])}"
          f"  (US-only 988 chunks: {us_ids}; positive rows whose ONLY gold is US-only: {lost_rows})")
    print(f"  hub chunks (4 most frequent gold): {[chunks[g]['chunk_id'] for g in hub]}  non-hub rows: {len(nonhub)}")
    print(f"  label sources: {dict(Counter(e.get('gt_labelled_by') for e in pos_entries))} (LLM-adjudicated)")
    print(f"  aliases: {sum(len(v) for v in ALIASES.values())} for {len(ALIASES)} chunks, {ALIAS_PROVENANCE}")

    # BM25 legs: shared by every model
    texts = [c["text"] for c in chunks]
    bm25 = {name: BM25Okapi([ab.BM25_VARIANTS[name](t) for t in texts]) for name in ("unicode", "char3")}
    bm25_scores = {}
    for name in bm25:
        bm25_scores[name] = []
        for it in items:
            toks = ab.BM25_VARIANTS[name](it["query"])
            bm25_scores[name].append(bm25[name].get_scores(toks) if toks else None)

    # alias index
    alias_chunk, alias_text = [], []
    id2idx = {c["chunk_id"]: i for i, c in enumerate(chunks)}
    for cid, al in ALIASES.items():
        if cid in id2idx:
            for a in al:
                alias_chunk.append(id2idx[cid])
                alias_text.append(a)
    alias_chunk = np.array(alias_chunk, int)

    # leakage check: alias vs dev query token Jaccard
    def toks(s):
        return set(ab.tok_unicode(s))
    near = [(alias_text[a], items[i]["id"]) for a in range(len(alias_text)) for i in P
            if len(toks(alias_text[a]) | toks(items[i]["query"])) and
            len(toks(alias_text[a]) & toks(items[i]["query"])) / len(toks(alias_text[a]) | toks(items[i]["query"])) >= 0.5]
    print(f"  leakage check: alias/dev-query pairs with token Jaccard >= 0.5: {len(near)}"
          + (f"  e.g. {near[:3]}" if near else ""))

    # reranker matrix (embedder-independent)
    ce = None
    if ce_scorer is not None:
        t0 = time.time()
        aidx = pools["AUTH"]
        ce = np.full((len(items), N), -np.inf)
        pairs = [(it["query"], texts[j]) for it in items for j in aidx]
        sc = np.asarray(ce_scorer(pairs), float).reshape(len(items), len(aidx))
        ce[:, aidx] = sc
        ce_ms = (time.time() - t0) / len(items) * 1000
        print(f"  reranker {ce_name}: {ce_ms:.0f} ms/query over {len(aidx)} chunks (this machine)")

    results = {"run_at": datetime.now().isoformat(timespec="seconds"), "n_pos": len(P), "n_neg": len(Ng),
               "hub": [chunks[g]["chunk_id"] for g in hub], "n_nonhub": len(nonhub), "models": {},
               "alias_leak_pairs": len(near), "reranker": ce_name}
    hits_store = {}  # (model, pool, system) -> dict(h1, h3) arrays over P

    def evaluate(model_key, pool_name, system, get):
        pidx = pools[pool_name]
        h1, h3, r3, rr, fr, a10, gate = [], [], [], [], [], [], {}
        for i in range(len(items)):
            order, g = get(i, pidx)
            gate[i] = g
            if items[i]["neg"]:
                continue
            gd = golds[i]
            h1.append(hit_at(order, gd, 1))
            h3.append(hit_at(order, gd, 3))
            r3.append(recall_at(order, gd, 3))
            f = first_rank(order, gd)
            fr.append(f)
            rr.append(1.0 / f if f else 0.0)
            a10.append(float(is_annomi[order[:10]].mean()))
        h1, h3 = np.array(h1), np.array(h3)
        pos_map = {i: k for k, i in enumerate(P)}
        row = dict(n=len(P), hit1=h1.mean(), hit3=h3.mean(), rec3=float(np.mean(r3)), mrr=float(np.mean(rr)),
                   annomi10=float(np.mean(a10)),
                   median_rank=float(np.median([f for f in fr if f])) if any(fr) else None)
        nh = [pos_map[i] for i in nonhub]
        row["nonhub_hit1"] = float(h1[nh].mean()) if nh else None
        row["nonhub_hit3"] = float(h3[nh].mean()) if nh else None
        for lang in LANGS:
            li = [pos_map[i] for i in P if items[i]["lang"] == lang]
            row[f"{lang}_hit3"] = float(h3[li].mean()) if li else None
            row[f"{lang}_n"] = len(li)
        row.update(gate_stats([gate[i] for i in P], h1, [gate[i] for i in Ng]))
        hits_store[(model_key, pool_name, system)] = dict(h1=h1, h3=h3, prec80=row["prec80"],
                                                          pos_s=np.array([gate[i] for i in P]),
                                                          neg_s=np.array([gate[i] for i in Ng]))
        return row

    def print_table(title, rows):
        print(f"\n  {title}")
        print(f"  {'pool':10}{'system':18}{'Hit@1':>6}{'Hit@3':>6}{'Rec@3':>6}{'MRR':>6}{'nhH@1':>6}{'nhH@3':>6}"
              f"{'AUC':>6}{'prec80':>7}{'FAR80 [95% CI]':>20}{'AnnoMI@10':>10}{'medRk':>7}")
        for (pool, system), r in rows.items():
            f = lambda x: "  -  " if x is None else f"{x:>5.0%}"
            far = "-" if r["far80"] is None else f"{r['far80']:.0%} [{r['far80_ci'][0]:.0%}-{r['far80_ci'][1]:.0%}]"
            auc = "-" if r["auc"] is None else f"{r['auc']:.2f}"
            med = "-" if r["median_rank"] is None else f"{r['median_rank']:.0f}"
            print(f"  {pool:10}{system:18}{f(r['hit1']):>6}{f(r['hit3']):>6}{f(r['rec3']):>6}{r['mrr']:>6.2f}"
                  f"{f(r['nonhub_hit1']):>6}{f(r['nonhub_hit3']):>6}{auc:>6}{f(r['prec80']):>7}{far:>20}"
                  f"{r['annomi10']:>9.0%}{med:>7}")

    # embedder-independent systems
    gold_sizes = [len(golds[i]) for i in P]
    rand = {p: {k: random_expectation(len(pools[p]), gold_sizes, k) for k in (1, 3)} for p in pools}
    results["random"] = {p: {f"hit{k}": v[0] for k, v in d.items()} for p, d in rand.items()}
    print("\n  random baseline (analytic): " + "  ".join(
        f"{p}: Hit@1 {d[1][0]:.0%} Hit@3 {d[3][0]:.0%}" for p, d in rand.items()))

    if ce is not None:
        def get_rr(i, pidx):
            o = order_by(ce[i], pidx)
            return o, float(1 / (1 + np.exp(-ce[i, o[0]])))
        rows = {(p, "rerank"): evaluate("_none_", p, "rerank", get_rr) for p in ("AUTH", "AUTH_noUS")}
        results["models"]["_reranker_"] = {f"{p}|{s}": v for (p, s), v in rows.items()}
        print_table(f"RERANKER {ce_name}", rows)

    factory = retriever_factory or (lambda cfg: HybridRetriever(
        chunks, model_name=cfg["name"], doc_prefix=cfg["doc"], query_prefix=cfg["query"],
        max_seq_length=cfg["max_len"], cache_dir=cache_dir))

    for key in model_keys:
        cfg = ec.MODELS[key]
        t0 = time.time()
        r = factory(cfg)
        E = l2n(r.embeddings)
        Q = l2n(r.model.encode([r.query_prefix + it["query"] for it in items], convert_to_numpy=True))
        A = l2n(r.model.encode([cfg["doc"] + a for a in alias_text], convert_to_numpy=True))
        cos = Q @ E.T
        amax = np.full((len(items), N), -1.0)
        ca = Q @ A.T
        for a_i, c_i in enumerate(alias_chunk):
            amax[:, c_i] = np.maximum(amax[:, c_i], ca[:, a_i])
        qq = Q @ Q.T
        lat_ms = (time.time() - t0)

        def dense(i, pidx):
            o = order_by(cos[i], pidx)
            return o, float(cos[i, o[0]])

        def hybrid(name):
            def f(i, pidx):
                d = order_by(cos[i], pidx)
                if bm25_scores[name][i] is None:
                    return d, float(cos[i, d[0]])
                o = rrf_order(order_by(bm25_scores[name][i], pidx), d, N)
                return o, float(cos[i, o[0]])
            return f

        def script_cond(i, pidx):
            return hybrid("unicode")(i, pidx) if ARABIC.search(items[i]["query"]) else dense(i, pidx)

        def alias_only(i, pidx):
            o = order_by(amax[i], pidx)
            return o, float(amax[i, o[0]])

        def orig_plus_alias(i, pidx):
            s = np.maximum(cos[i], amax[i])
            o = order_by(s, pidx)
            return o, float(s[o[0]])

        def knn_route(i, pidx):
            v, _ = knn_votes(i, qq, scen, golds, is_neg, N)
            o = order_by(v + 1e-6 * cos[i], pidx)
            return o, float(v[o[0]])

        def knn_dense_rrf(i, pidx):
            v, _ = knn_votes(i, qq, scen, golds, is_neg, N)
            o = rrf_order(order_by(v + 1e-6 * cos[i], pidx), order_by(cos[i], pidx), N)
            return o, float(v[pidx].max())  # gate = strongest kNN vote (same signal knn_route uses)

        freq_all = np.zeros(N)
        for i in P:
            for g in golds[i]:
                freq_all[g] += 1
        by_scen = defaultdict(lambda: np.zeros(N))
        for i in P:
            for g in golds[i]:
                by_scen[scen[i]][g] += 1
        static_tb = -1e-6 * np.arange(N)

        def constant_loso(i, pidx):
            o = order_by(freq_all - by_scen[scen[i]] + static_tb, pidx)
            return o, 0.0

        def constant_insample(i, pidx):
            return order_by(freq_all + static_tb, pidx), 0.0

        sysfn = dict(dense=dense, hybrid_unicode=hybrid("unicode"), hybrid_char3=hybrid("char3"),
                     script_cond=script_cond, alias_only=alias_only, orig_plus_alias=orig_plus_alias,
                     knn_route=knn_route, knn_dense_rrf=knn_dense_rrf, constant_loso=constant_loso, constant_insample=constant_insample)
        print(f"\n{'=' * 118}\n{key}  ({cfg['name']})   encode+setup {lat_ms:.1f}s\n{'=' * 118}")
        rows = {}
        for s in FULL_SYSTEMS:
            rows[("FULL", s)] = evaluate(key, "FULL", s, sysfn[s])
        for p in ("AUTH", "AUTH_noUS"):
            for s in AUTH_SYSTEMS:
                rows[(p, s)] = evaluate(key, p, s, sysfn[s])
        print_table("all positives (nh = non-hub rows)", rows)
        print(f"\n  per-language Hit@3 (AUTH):  " + "  ".join(
            f"{lang}(n={rows[('AUTH', 'dense')][lang + '_n']})" for lang in LANGS))
        for s in AUTH_SYSTEMS:
            r_ = rows[("AUTH", s)]
            print(f"    {s:18}" + "".join(f"{'-':>14}" if r_[lang + '_hit3'] is None
                                          else f"{r_[lang + '_hit3']:>14.0%}" for lang in LANGS))

        # paired comparisons in AUTH
        pairs = {}
        print(f"\n  paired vs baselines (AUTH, scenario-cluster bootstrap B={B}):")
        print(f"    {'system':18}{'ΔHit@1 vs constant_loso [CI]':>34}{'p':>7}{'ΔHit@3 vs dense [CI]':>30}{'p':>7}")
        P_scen = [scen[i] for i in P]
        cands = [s for s in AUTH_SYSTEMS if s not in ("constant_insample",)] + (["rerank"] if ce is not None else [])
        for s in cands:
            hs = hits_store[("_none_" if s == "rerank" else key, "AUTH", s)]
            base_c = hits_store[(key, "AUTH", "constant_loso")]
            base_d = hits_store[(key, "AUTH", "dense")]
            d1 = cluster_boot_diff(hs["h1"], base_c["h1"], P_scen, B=B)
            d3 = cluster_boot_diff(hs["h3"], base_d["h3"], P_scen, B=B)
            p1, p3 = mcnemar_exact(hs["h1"], base_c["h1"]), mcnemar_exact(hs["h3"], base_d["h3"])
            pairs[s] = dict(d_hit1_vs_const=d1, p1=p1, d_hit3_vs_dense=d3, p3=p3)
            print(f"    {s:18}{d1[0]:>+10.0%} [{d1[1]:+.0%},{d1[2]:+.0%}]{'':>8}{p1:>9.3f}"
                  f"{d3[0]:>+10.0%} [{d3[1]:+.0%},{d3[2]:+.0%}]{p3:>9.3f}")
        # fusion vs knn_route (rule F) and strictness sweep (rule G), pool AUTH_noUS
        kf, kr = hits_store[(key, "AUTH_noUS", "knn_dense_rrf")], hits_store[(key, "AUTH_noUS", "knn_route")]
        f3 = cluster_boot_diff(kf["h3"], kr["h3"], P_scen, B=B)
        f1 = cluster_boot_diff(kf["h1"], kr["h1"], P_scen, B=B)
        pairs["fusion_vs_knn"] = dict(d_hit1=f1, d_hit3=f3)
        print(f"\n  fusion vs knn_route (AUTH_noUS): ΔHit@1 {f1[0]:+.0%} [{f1[1]:+.0%},{f1[2]:+.0%}]   "
              f"ΔHit@3 {f3[0]:+.0%} [{f3[1]:+.0%},{f3[2]:+.0%}]")
        sweeps = {}
        print(f"\n  STRICTNESS SWEEP (AUTH_noUS; gate = top-1 score; accepted = shown, rest = 'no good match')")
        print(f"    {'system':16}{'target':>7}{'actual':>7}{'accH@1':>8}{'accH@3':>8}{'FAR [95% CI]':>22}")
        for s_ in ("dense", "knn_route", "knn_dense_rrf"):
            hs = hits_store[(key, "AUTH_noUS", s_)]
            sweeps[s_] = coverage_sweep(hs["pos_s"], hs["h1"], hs["h3"], hs["neg_s"])
            for r_ in sweeps[s_]:
                print(f"    {s_:16}{r_['cov']:>7.0%}{r_['cov_actual']:>7.0%}{r_['acc_hit1']:>8.0%}{r_['acc_hit3']:>8.0%}"
                      f"{r_['far']:>9.0%} [{r_['far_ci'][0]:.0%}-{r_['far_ci'][1]:.0%}]")
        results["models"][key] = {"sweeps": sweeps, "rows": {f"{p}|{s}": v for (p, s), v in rows.items()}, "pairs": pairs,
                                  "seconds": round(time.time() - t0, 1)}

    results["verdicts"] = verdicts(results, hits_store, model_keys, [scen[i] for i in P], ce is not None, B)
    results["seconds"] = round(time.time() - t_start, 1)
    if save:
        outdir = HERE / "results"
        outdir.mkdir(exist_ok=True)
        out = outdir / f"super_run_{datetime.now():%Y%m%d_%H%M%S}.json"
        out.write_text(json.dumps(results, indent=2, ensure_ascii=False, default=float), encoding="utf-8")
        print(f"\nSaved: {out}")
    return results


def coverage_sweep(pos_s, h1, h3, neg_s, covs=(1.0, 0.9, 0.8, 0.7, 0.6, 0.5, 0.4, 0.3)):
    """For each target coverage of positives: threshold, accepted Hit@1/Hit@3, false-accept rate (exact CI)."""
    pos_s, h1, h3, neg_s = map(np.asarray, (pos_s, h1, h3, neg_s))
    out = []
    for c in covs:
        thr = -np.inf if c >= 1 else float(np.quantile(pos_s, 1 - c))
        acc = pos_s >= thr
        k, n = int((neg_s >= thr).sum()), len(neg_s)
        ci = list(stats.binomtest(k, n).proportion_ci(0.95, "exact")) if n else [None, None]
        out.append(dict(cov=c, cov_actual=float(acc.mean()), thr=thr if np.isfinite(thr) else None,
                        acc_hit1=float(h1[acc].mean()) if acc.any() else 0.0,
                        acc_hit3=float(h3[acc].mean()) if acc.any() else 0.0,
                        far=k / n if n else 0.0, far_k=k, n_neg=n, far_ci=ci))
    return out


def operating_point(sweep):
    """Rule G."""
    for lim, tag in ((0.10, "ok"), (0.20, "weak")):
        ok = [r for r in sweep if r["far"] <= lim]
        if ok:
            return dict(max(ok, key=lambda r: r["cov_actual"]), status=tag)
    return dict(status="none")


def verdicts(results, hits_store, model_keys, P_scen, have_ce, B):
    print(f"\n{'#' * 118}\nPRE-REGISTERED VERDICTS (dev split; rule E = one holdout run still to do)\n{'#' * 118}")
    V = {}
    for key in model_keys:
        rows = results["models"][key]["rows"]
        full_d, auth_d = rows["FULL|dense"], rows["AUTH|dense"]
        a = full_d["annomi10"] >= 0.95 or auth_d["hit3"] >= full_d["hit3"] - 0.02
        V.setdefault(key, {})["A_pool"] = "AUTH" if a else "FULL"
        adopted = []
        for s in CHALLENGERS:
            if s == "rerank" and not have_ce:
                continue
            p = results["models"][key]["pairs"].get(s)
            if not p:
                continue
            d, lo, _ = p["d_hit3_vs_dense"]
            hs = hits_store[("_none_" if s == "rerank" else key, "AUTH", s)]
            base = hits_store[(key, "AUTH", "dense")]
            prec_ok = (hs["prec80"] or 0) >= (base["prec80"] or 0) - 0.02
            if d >= 0.05 and lo > 0 and prec_ok:
                adopted.append(s)
        V[key]["B_adopted"] = adopted
        V[key]["C_query_sensitive"] = [s for s, p in results["models"][key]["pairs"].items()
                                       if "d_hit1_vs_const" in p and s != "constant_loso"
                                       and p["d_hit1_vs_const"][1] > 0]
        fp = results["models"][key]["pairs"]["fusion_vs_knn"]
        V[key]["F_fusion_adopted"] = bool(fp["d_hit3"][1] > 0 and fp["d_hit1"][0] >= 0)
        best_knn = "knn_dense_rrf" if V[key]["F_fusion_adopted"] else "knn_route"
        op = operating_point(results["models"][key]["sweeps"][best_knn])
        V[key]["G_operating_point"] = {"system": best_knn, **op}
        print(f"  {key:12} F fusion adopted: {V[key]['F_fusion_adopted']}   G operating point ({best_knn}): "
              + ("NO SAFE POINT on dev" if op["status"] == "none" else
                 f"coverage {op['cov_actual']:.0%}, accepted Hit@1 {op['acc_hit1']:.0%} / Hit@3 {op['acc_hit3']:.0%}, "
                 f"FAR {op['far']:.0%} [{op['far_ci'][0]:.0%}-{op['far_ci'][1]:.0%}], thr={op['thr']} ({op['status']})"))
        print(f"  {key:12} A pool -> {V[key]['A_pool']:5}  B adopted over dense: {adopted or 'none'}"
              f"   C beats fixed bundle on Hit@1: {V[key]['C_query_sensitive'] or 'NONE'}")
    if len(model_keys) > 1:
        best = max(model_keys, key=lambda k: results["models"][k]["rows"]["AUTH|dense"]["hit3"])
        wins = all(cluster_boot_diff(hits_store[(best, "AUTH", "dense")]["h3"],
                                     hits_store[(o, "AUTH", "dense")]["h3"], P_scen, B=B)[1] > 0
                   for o in model_keys if o != best)
        choice = best if wins else (TIEBREAK_MODEL if TIEBREAK_MODEL in model_keys else best)
        V["D_embedder"] = {"best_point": best, "clear_win": wins, "chosen": choice}
        print(f"  D embedder: best point estimate {best}; clear win={wins} -> CHOSEN {choice}")
    print("  Reminder: thresholds/constants/kNN are fitted on dev; only the holdout run (rule E) is clean.")
    return V


def make_ce_scorer(name):
    from sentence_transformers import CrossEncoder
    model = CrossEncoder(name, max_length=512)
    return lambda pairs: model.predict(pairs, batch_size=16, show_progress_bar=True)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--models", nargs="+", default=list(ec.MODELS), choices=list(ec.MODELS))
    ap.add_argument("--cache-dir", default=None)
    ap.add_argument("--reranker", default=None, help="e.g. BAAI/bge-reranker-v2-m3 (downloads ~2 GB)")
    ap.add_argument("--bootstrap", type=int, default=2000)
    a = ap.parse_args()
    scorer = make_ce_scorer(a.reranker) if a.reranker else None
    run(a.models, a.cache_dir, ce_scorer=scorer, ce_name=a.reranker, B=a.bootstrap)
