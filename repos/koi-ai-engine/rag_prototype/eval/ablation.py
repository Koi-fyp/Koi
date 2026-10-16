"""
Ablation: how should the sparse (BM25) leg be handled, per embedder?

Run LOCALLY after embedder_comparison.py (reuses its cached embeddings if you pass the same --cache-dir):
    python ablation.py --cache-dir .emb_cache
    python ablation.py --models minilm me5-small --cache-dir .emb_cache

Arms (all use the pre-filtered eligibility mask, RRF k=60 like the pipeline):
  dense_only                 no BM25. The fair embedder baseline.
  hybrid_ascii (reference)     the pipeline BEFORE 2026-10-12: BM25 over ASCII-only tokens, no empty-token guard.
                             (The pipeline default is now hybrid_unicode_words.)
  hybrid_ascii_skip_empty    same, but when the query has 0 BM25 tokens (all Urdu-script queries)
                             skip the BM25 leg instead of fusing zero scores.
  hybrid_unicode_words       BM25 over Unicode word tokens (Urdu-script words become tokens).
  hybrid_char3               BM25 over character 3-grams of Unicode words (tolerant of spelling
                             variation; the usual suspect for Roman Urdu -- NOT tested on Roman Urdu
                             here because no labelled Roman Urdu queries exist).

Strata (separate, never blended): ENGLISH tier A, ENGLISH tier B, URDU PROBE (label-free smoke test,
see embedder_comparison.py). Hand-labelled multilingual strata print NOT EVALUATED while
multilingual_queries.py is empty. dev_holdout.py is never used.

Also prints, per embedder, how well top-1 cosine separates in-corpus hits from out-of-corpus queries
(in-sample, n tiny -- information for gate calibration, not a validation).

Limits: \\w drops Urdu combining marks (zabar/zer), so diacritised Urdu may split into extra tokens.
This is a harness for choosing what to test next, not a final design.
"""
import argparse
import json
import re
import sys
import time
from datetime import datetime
from pathlib import Path

import numpy as np
from rank_bm25 import BM25Okapi
from sklearn.metrics.pairwise import cosine_similarity

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "scripts"))
sys.path.insert(0, str(HERE))
import embedder_comparison as ec  # noqa: E402
from retrieval_pipeline import load_corpus, HybridRetriever, eligibility_mask, tokenize as tok_ascii  # noqa: E402
from dev_set import DEV_SET  # noqa: E402
from run_dev_eval import matches_gt  # noqa: E402

RRF_K = 60


def tok_unicode(text):
    return re.findall(r"[\w']+", text.lower())


def tok_char3(text):
    out = []
    for w in tok_unicode(text):
        out.extend([w] if len(w) <= 3 else [w[i:i + 3] for i in range(len(w) - 2)])
    return out


BM25_VARIANTS = {"ascii": tok_ascii, "unicode": tok_unicode, "char3": tok_char3}
ARMS = {
    "dense_only": dict(bm25=None, skip_empty=False),
    "hybrid_ascii (reference)": dict(bm25="ascii", skip_empty=False),
    "hybrid_ascii_skip_empty": dict(bm25="ascii", skip_empty=True),
    "hybrid_unicode_words": dict(bm25="unicode", skip_empty=True),
    "hybrid_char3": dict(bm25="char3", skip_empty=True),
}


def build_bm25s(texts):
    return {name: BM25Okapi([f(t) for t in texts]) for name, f in BM25_VARIANTS.items()}


def rank(retriever, bm25s, query, mask, arm, k=10):
    """Returns (top-k chunk indices, cosine array over all chunks)."""
    pool = [i for i, m in enumerate(mask) if m]
    q = retriever.model.encode([retriever.query_prefix + query], convert_to_numpy=True)
    cos = cosine_similarity(q, retriever.embeddings)[0]
    dense = sorted(pool, key=lambda i: -cos[i])
    cfg = ARMS[arm]
    if cfg["bm25"] is None:
        return dense[:k], cos
    toks = BM25_VARIANTS[cfg["bm25"]](query)
    if cfg["skip_empty"] and not toks:
        return dense[:k], cos
    scores = bm25s[cfg["bm25"]].get_scores(toks)
    bm = sorted(pool, key=lambda i: -scores[i])
    rrf = {}
    for r, i in enumerate(bm):
        rrf[i] = rrf.get(i, 0) + 1.0 / (RRF_K + r + 1)
    for r, i in enumerate(dense):
        rrf[i] = rrf.get(i, 0) + 1.0 / (RRF_K + r + 1)
    fused = sorted(rrf.items(), key=lambda x: -x[1])[:k]
    return [i for i, _ in fused], cos


def auc(pos, neg):
    if not pos or not neg:
        return None
    wins = sum((p > n) + 0.5 * (p == n) for p in pos for n in neg)
    return wins / (len(pos) * len(neg))


def cosine_separation(retriever, chunks):
    pos, neg = [], []
    for it in DEV_SET:
        mask = eligibility_mask(chunks, it["risk_tier"])
        top, cos = rank(retriever, None, it["query"], mask, "dense_only", k=1)
        top1_cos = float(cos[top[0]])
        if it["gt_tier"] == "N/A":
            neg.append(top1_cos)
        elif matches_gt(chunks[top[0]], it):
            pos.append(top1_cos)
    return pos, neg


def run(model_keys, cache_dir):
    chunks = load_corpus()
    tier_a = [d for d in DEV_SET if d["gt_tier"] == "A"]
    tier_b = [d for d in DEV_SET if d["gt_tier"] == "B"]
    probe = ec.urdu_probe_queries(chunks)
    ml_ok, ml_rejected = ec.valid_multilingual(ec.MULTILINGUAL_QUERIES)
    strata = {"ENGLISH tier A (gold)": tier_a, "ENGLISH tier B (silver)": tier_b,
              "URDU PROBE (label-free, smoke test only)": probe}
    for lang in ("urdu_native", "roman_urdu", "code_switched"):
        strata[f"HAND-LABELLED {lang}"] = [e for e in ml_ok if e["lang"] == lang]

    from collections import Counter
    for lang in ("urdu_native", "roman_urdu", "code_switched"):
        items = strata[f"HAND-LABELLED {lang}"]
        if items:
            print(f"  label sources {lang}: {dict(Counter(e['gt_labelled_by'] for e in items))}  "
                  f"(only 'ahmad*' = human-verified)")
    results = {"run_at": datetime.now().isoformat(timespec="seconds"), "models": {}}
    for key in model_keys:
        cfg = ec.MODELS[key]
        t0 = time.time()
        print(f"\n{'=' * 100}\n{key}  ({cfg['name']})\n{'=' * 100}")
        r = HybridRetriever(chunks, model_name=cfg["name"], doc_prefix=cfg["doc"],
                            query_prefix=cfg["query"], max_seq_length=cfg["max_len"], cache_dir=cache_dir)
        bm25s = build_bm25s(r.texts)
        entry = {"arms": {}}
        names = [n for n, items in strata.items() if items]
        print(f"  {'arm':28}" + "".join(f"{n.split(' (')[0][:18]:>26}" for n in names))
        print(f"  {'':28}" + "".join(f"{'R@1  R@3  R@10 (n)':>26}" for _ in names))
        for arm in ARMS:
            entry["arms"][arm] = {}
            cells = []
            for name, items in strata.items():
                if not items:
                    entry["arms"][arm][name] = None
                    continue
                hits = []
                for it in items:
                    mask = eligibility_mask(chunks, it["risk_tier"])
                    idx, _ = rank(r, bm25s, it["query"], mask, arm)
                    hits.append(ec.first_hit(idx, chunks, it))
                row = ec.recall_row(hits)
                entry["arms"][arm][name] = row
                cells.append(f"{row['r@1']:>4.0%} {row['r@3']:>4.0%} {row['r@10']:>4.0%} ({row['n']})")
            print(f"  {arm:28}" + "".join(f"{c:>26}" for c in cells))
        for name, items in strata.items():
            if not items:
                print(f"  {name:28} NOT EVALUATED (no labelled queries)")
        pos, neg = cosine_separation(r, chunks)
        a = auc(pos, neg)
        entry["cosine_separation"] = {"pos": pos, "neg": neg, "auc": a}
        if pos and neg:
            above = sum(1 for p in pos if p > max(neg))
            print(f"  top-1 cosine (dense), IN-SAMPLE, n tiny: in-corpus hits n={len(pos)} "
                  f"[{min(pos):.3f}..{max(pos):.3f}]  out-of-corpus n={len(neg)} [{min(neg):.3f}..{max(neg):.3f}]  "
                  f"AUC={a:.2f}  hits above highest OOC={above}/{len(pos)}")
        entry["seconds"] = round(time.time() - t0, 1)
        results["models"][key] = entry

    if ml_rejected:
        print(f"\nREJECTED multilingual entries: {ml_rejected}")
    outdir = HERE / "results"
    outdir.mkdir(exist_ok=True)
    out = outdir / f"ablation_{datetime.now():%Y%m%d_%H%M%S}.json"
    out.write_text(json.dumps(results, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"\nSaved: {out}")
    print("Reminder: Tier B n=5, Urdu probe n=14 (4 gold chunks, correlated). One query is 7-20 points. "
          "Look for large, consistent gaps across models, not single-query differences.")
    return results


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--models", nargs="+", default=list(ec.MODELS), choices=list(ec.MODELS))
    ap.add_argument("--cache-dir", default=None)
    a = ap.parse_args()
    run(a.models, a.cache_dir)
