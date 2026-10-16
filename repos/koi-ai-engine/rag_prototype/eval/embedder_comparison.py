"""
Embedder comparison: MiniLM (current) vs multilingual-e5-small/base vs bge-m3.

Run LOCALLY (needs sentence-transformers, torch, internet for the model download):
    python embedder_comparison.py                      # all four models
    python embedder_comparison.py --models minilm bge-m3
    python embedder_comparison.py --cache-dir .emb_cache   # reuse embeddings on reruns

What it measures (reported SEPARATELY, never blended):
  ENGLISH  Tier A (gold, chunk-exact) and Tier B (silver, topic-level) from dev_set.py.
           dense-only (the fair embedder comparison) and hybrid (BM25+dense+RRF).
  URDU PROBE  label-free self-retrieval: each Urdu-script line inside the 4 bilingual
           mhGAP-HIG-PK chunks is a query, gold = the chunk containing it. This is a
           smoke test that the model embeds Urdu script sensibly. NOT retrieval quality
           on real user queries: tiny n, correlated queries, and the answer chunk contains
           the query verbatim.
  ROMAN URDU / CODE-SWITCHED / hand-labelled Urdu: from multilingual_queries.py, which
           is EMPTY. Those strata print NOT EVALUATED. No data, no number.

Deliberately NOT used: dev_holdout.py (frozen; evaluate once AFTER an embedder is chosen).

Caveats that matter when reading the output:
  * Cosine scales differ per model, so the gate threshold from calibrate_gate.py is
    model-specific. Changing the embedder invalidates it (it was already "not validated").
  * BM25 tokenize() is ASCII-only, so Urdu-script queries give BM25 ZERO tokens; the
    hybrid number for Urdu is dense + corpus-order noise. Dense-only is the honest column.
  * Model IDs and the e5 'query: '/'passage: ' prefixes are from the model cards as
    remembered, not verified in this session. Check them. Model revisions are NOT pinned.
  * MiniLM keeps its default max_seq_length so it matches existing results; the other
    models are capped at 512 (bge-m3's default 8192 would be needlessly slow on CPU).
"""
import argparse
import json
import re
import sys
import time
from datetime import datetime
from pathlib import Path

import numpy as np
from sklearn.metrics.pairwise import cosine_similarity

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "scripts"))
sys.path.insert(0, str(HERE))
from retrieval_pipeline import load_corpus, HybridRetriever, eligibility_mask, tokenize  # noqa: E402
from run_dev_eval import matches_gt  # noqa: E402
from dev_set import DEV_SET  # noqa: E402
from multilingual_queries import MULTILINGUAL_QUERIES  # noqa: E402

URDU_CHAR = re.compile(r"[؀-ۿݐ-ݿﭐ-﷿ﹰ-﻿]")
KS = (1, 3, 5, 10)

MODELS = {
    "minilm":    dict(name="sentence-transformers/all-MiniLM-L6-v2", doc="", query="", max_len=None),
    "me5-small": dict(name="intfloat/multilingual-e5-small", doc="passage: ", query="query: ", max_len=512),
    "me5-base":  dict(name="intfloat/multilingual-e5-base", doc="passage: ", query="query: ", max_len=512),
    "bge-m3":    dict(name="BAAI/bge-m3", doc="", query="", max_len=512),
}


def urdu_probe_queries(chunks):
    """Label-free probe set derived from the data. Urdu-script lines of bilingual chunks."""
    out = []
    for c in chunks:
        if c.get("language") != "bilingual":
            continue
        n = 0
        for line in c["text"].split("\n"):
            s = line.strip()
            letters = re.sub(r"\s", "", s)
            if len(letters) >= 10 and len(URDU_CHAR.findall(s)) / len(letters) > 0.5:
                n += 1
                out.append({"id": f"{c['chunk_id']}#{n}", "lang": "urdu_native", "query": s,
                            "risk_tier": "HIGH", "gt_tier": "A", "gt_chunk_ids": [c["chunk_id"]]})
    return out


def valid_multilingual(entries):
    ok, rejected = [], []
    for e in entries:
        if e.get("gt_chunk_ids") and e.get("gt_labelled_by") and e.get("query") and e.get("lang"):
            ok.append(e)
        else:
            rejected.append(e.get("id", "?"))
    return ok, rejected


def first_hit(ranked_idx, chunks, item):
    for rank, i in enumerate(ranked_idx, start=1):
        if matches_gt(chunks[i], item):
            return rank
    return None


def dense_rank(retriever, query, mask, k=10):
    q = retriever.model.encode([retriever.query_prefix + query], convert_to_numpy=True)
    cos = cosine_similarity(q, retriever.embeddings)[0]
    pool = [i for i, m in enumerate(mask) if m]
    top = sorted(pool, key=lambda i: -cos[i])[:k]
    return top, cos


def hybrid_rank(retriever, query, mask, k=10):
    res = retriever.retrieve(query, k=k, eligible_mask=mask)
    idx_of = {c["chunk_id"]: i for i, c in enumerate(retriever.chunks)}
    return [idx_of[r["chunk"]["chunk_id"]] for r in res]


def recall_row(hits):
    n = len(hits)
    return {"n": n, **{f"r@{k}": (sum(1 for h in hits if h is not None and h <= k) / n if n else None)
                        for k in KS}}


def eval_set(retriever, chunks, items):
    """Returns {'dense': row, 'hybrid': row, 'per_query': [...]}. gt_tier N/A items are skipped."""
    dh, hh, per = [], [], []
    for it in items:
        if it.get("gt_tier") == "N/A":
            continue
        mask = eligibility_mask(chunks, it["risk_tier"])
        d_idx, _ = dense_rank(retriever, it["query"], mask)
        h_idx = hybrid_rank(retriever, it["query"], mask)
        d, h = first_hit(d_idx, chunks, it), first_hit(h_idx, chunks, it)
        dh.append(d)
        hh.append(h)
        per.append({"id": it["id"], "dense_hit": d, "hybrid_hit": h,
                    "bm25_tokens": len(tokenize(it["query"]))})
    return {"dense": recall_row(dh), "hybrid": recall_row(hh), "per_query": per}


def fmt(row):
    if not row["n"]:
        return "n=0"
    return f"n={row['n']:<3} " + "  ".join(f"R@{k}={row[f'r@{k}']:.0%}" for k in KS)


def run(model_keys, cache_dir):
    chunks = load_corpus()
    tier_a = [d for d in DEV_SET if d["gt_tier"] == "A"]
    tier_b = [d for d in DEV_SET if d["gt_tier"] == "B"]
    ooc = [d for d in DEV_SET if d["gt_tier"] == "N/A"]
    probe = urdu_probe_queries(chunks)
    ml_ok, ml_rejected = valid_multilingual(MULTILINGUAL_QUERIES)
    strata = {"ENGLISH tier A (gold)": tier_a, "ENGLISH tier B (silver)": tier_b,
              "URDU PROBE (label-free, smoke test only)": probe}
    for lang in ("urdu_native", "roman_urdu", "code_switched"):
        strata[f"HAND-LABELLED {lang}"] = [e for e in ml_ok if e["lang"] == lang]
        if strata[f"HAND-LABELLED {lang}"]:
            from collections import Counter
            print(f"label sources {lang}: "
                  f"{dict(Counter(e['gt_labelled_by'] for e in strata[f'HAND-LABELLED {lang}']))} "
                  f"(only 'ahmad*' = human-verified; claude-delegated = LLM-adjudicated; chatgpt-draft = unreviewed)")

    results = {"run_at": datetime.now().isoformat(timespec="seconds"), "n_chunks": len(chunks),
               "models": {}, "rejected_multilingual_entries": ml_rejected}
    for key in model_keys:
        cfg = MODELS[key]
        t0 = time.time()
        print(f"\n{'=' * 92}\n{key}  ({cfg['name']})  prefixes doc={cfg['doc']!r} query={cfg['query']!r}\n{'=' * 92}")
        r = HybridRetriever(chunks, model_name=cfg["name"], doc_prefix=cfg["doc"],
                            query_prefix=cfg["query"], max_seq_length=cfg["max_len"], cache_dir=cache_dir)
        entry = {"config": cfg, "strata": {}, "ooc_top1_cosine": []}
        for name, items in strata.items():
            if not items:
                print(f"  {name:44} NOT EVALUATED (no labelled queries)")
                entry["strata"][name] = None
                continue
            ev = eval_set(r, chunks, items)
            entry["strata"][name] = ev
            print(f"  {name:44} dense : {fmt(ev['dense'])}")
            print(f"  {'':44} hybrid: {fmt(ev['hybrid'])}")
            empties = sum(1 for p in ev["per_query"] if p["bm25_tokens"] == 0)
            if empties:
                print(f"  {'':44} NOTE: {empties}/{len(ev['per_query'])} queries have 0 BM25 tokens "
                      f"(ASCII tokenizer) -> hybrid column unreliable here")
        for it in ooc:  # informational only: cosine scales differ per model
            mask = eligibility_mask(chunks, it["risk_tier"])
            _, cos = dense_rank(r, it["query"], mask)
            pool = [i for i, m in enumerate(mask) if m]
            entry["ooc_top1_cosine"].append({"id": it["id"], "top1_cos": float(max(cos[i] for i in pool))})
        vals = [o["top1_cos"] for o in entry["ooc_top1_cosine"]]
        if vals:
            print(f"  OOC top-1 cosine (n={len(vals)}, info only, scale is model-specific): "
                  f"min={min(vals):.3f} max={max(vals):.3f}")
        entry["seconds"] = round(time.time() - t0, 1)
        results["models"][key] = entry

    if ml_rejected:
        print(f"\nREJECTED multilingual entries (missing gt_chunk_ids / gt_labelled_by / query / lang): {ml_rejected}")
    outdir = HERE / "results"
    outdir.mkdir(exist_ok=True)
    out = outdir / f"embedder_comparison_{datetime.now():%Y%m%d_%H%M%S}.json"
    out.write_text(json.dumps(results, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"\nSaved: {out}")
    print("Reminder: tiny n everywhere (corpus has 26 authoritative chunks, 4 with Urdu). "
          "Differences of one query are noise. Do not pick a winner on this alone.")
    return results


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--models", nargs="+", default=list(MODELS), choices=list(MODELS))
    ap.add_argument("--cache-dir", default=None)
    a = ap.parse_args()
    run(a.models, a.cache_dir)
