"""
RULE E -- run the chosen crisis config ONCE on the untouched holdout split. Reported whatever it says.

    python eval/holdout_once.py --dry-run                 # plumbing check on DEV data; no lock, holdout not read
    python eval/holdout_once.py --i-checked-the-lock      # THE run. Creates the lock first. Never again.

PRE-REGISTERED (written 2026-10-12, before any holdout number exists; do not edit after the run):
  Config   : scripts/retrieval_pipeline.py CrisisRouter -- pool AUTH_noUS (22), kNN K=7 over the DEV store
             (133 positives + 83 negatives from eval/multilingual_queries.py), me5-small ("passage: "/"query: "),
             gate = top-1 vote share >= 0.5709 (rule G, dev-fitted), items <= 3. Gate NOT re-fitted on holdout.
  Labels   : holdout rows of eval/labels/koi_queries_master_draft.csv, same rule as load_labels.py
             --include-unchecked (no reviewer exists for holdout):
               draft_status exact|partial, consensus = chunk ids -> positive, gold = draft_consensus
               draft_status exact|partial, consensus = NONE      -> negative ("chatgpt-draft-2run-agree")
               draft_status negative_by_design                   -> negative ("by-design")
               draft_status none_flip                            -> EXCLUDED (the two runs disagreed on NONE)
             None human- or clinician-verified. Report them as DRAFT-LABEL results.
  Metrics  : at the frozen gate: coverage (share of positives shown), accepted Hit@1/Hit@3, false-accept rate
             on negatives with exact 95% CI. Ungated: Hit@1, Hit@3, AUC of the gate score. Baseline: fixed
             bundle = the 3 pool chunks most frequent as gold in the DEV store (deployable, not fitted on
             holdout); paired kNN - bundle Hit@1 and Hit@3, scenario-cluster bootstrap 95% CI (B=2000, seed 0).
             Per-language Hit@3. Hit@k = any gold chunk in top-k (super_run definition).
  Preflight: before the lock is created, the dev operating point is recomputed (LOSO) and must reproduce the
             reported rule-G point: threshold 0.5709 (+-0.0001), 133/83 rows, 5 of 83 negatives accepted.
             A mismatch (wrong model revision, max_seq_length, prefixes, data) aborts WITHOUT touching holdout.
  Lock     : eval/results/HOLDOUT_RULE_E.lock.json is created (exclusive create) BEFORE any holdout row is read.
             If it exists, or any eval/results/holdout_once_*.json exists, the script refuses. A crash after
             the lock is created still counts as the one run. The lock is a file: deleting it defeats it, so
             its hashes are also printed for the defense record.
"""
import argparse
import csv
import hashlib
import json
import sys
from collections import Counter
from datetime import datetime
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(ROOT / "scripts"))

MASTER = HERE / "labels" / "koi_queries_master_draft.csv"
EXPECTED = dict(thr=0.5709, thr_tol=1e-4, n_pos=133, n_neg=83, far_k=5)
LOCK_NAME = "HOLDOUT_RULE_E.lock.json"
HASHED = ["scripts/retrieval_pipeline.py", "scripts/language_detector.py", "eval/holdout_once.py",
          "eval/multilingual_queries.py", "eval/labels/koi_queries_master_draft.csv",
          "data/processed/authoritative_chunks.jsonl", "data/processed/mhgap_pk_chunks.jsonl",
          "data/processed/annomi_chunks.jsonl"]


def sha256(p):
    h = hashlib.sha256()
    with open(p, "rb") as fh:
        for b in iter(lambda: fh.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def holdout_rows(master=MASTER):
    pos, neg, excluded = [], [], Counter()
    with open(master, encoding="utf-8-sig") as fh:
        for m in csv.DictReader(fh):
            if m["split"] != "holdout":
                continue
            base = dict(id=m["id"], lang=m["lang"], query=m["query"], scenario=m.get("scenario_id") or m["id"])
            st = m["draft_status"]
            cons = [x.strip() for x in (m["draft_consensus"] or "").replace(",", ";").split(";") if x.strip()]
            if st == "negative_by_design":
                neg.append(dict(base, labelled_by="by-design"))
            elif st in ("exact", "partial") and cons == ["NONE"]:
                neg.append(dict(base, labelled_by="chatgpt-draft-2run-agree"))
            elif st in ("exact", "partial") and cons and "NONE" not in cons:
                pos.append(dict(base, gold=cons, labelled_by="chatgpt-draft-2run-agree"))
            else:
                excluded[st] += 1
    return pos, neg, excluded


def exact_ci(k, n):
    from scipy import stats
    return list(stats.binomtest(k, n).proportion_ci(0.95, "exact")) if n else [None, None]


def auc(pos, neg):
    pos, neg = np.asarray(pos, float), np.asarray(neg, float)
    if not len(pos) or not len(neg):
        return None
    gt = (pos[:, None] > neg[None, :]).sum() + 0.5 * (pos[:, None] == neg[None, :]).sum()
    return float(gt / (len(pos) * len(neg)))


def cluster_boot_diff(a, b, clusters, B=2000, seed=0):
    """Same as super_run.cluster_boot_diff."""
    a, b = np.asarray(a, float), np.asarray(b, float)
    ids = sorted(set(clusters)); pos = {c: i for i, c in enumerate(ids)}
    sa, sb, cnt = np.zeros(len(ids)), np.zeros(len(ids)), np.zeros(len(ids))
    for x, y, c in zip(a, b, clusters):
        sa[pos[c]] += x; sb[pos[c]] += y; cnt[pos[c]] += 1
    draw = np.random.default_rng(seed).integers(0, len(ids), size=(B, len(ids)))
    diffs = (sa[draw].sum(1) - sb[draw].sum(1)) / cnt[draw].sum(1)
    return [float((a - b).mean()), float(np.percentile(diffs, 2.5)), float(np.percentile(diffs, 97.5))]


def evaluate(router, chunks, pos, neg, exclude_own_scenario=False):
    id2idx = {c["chunk_id"]: i for i, c in enumerate(chunks)}
    freq = Counter(g for g in (g for gs in router.golds for g in gs) if g in set(router.pool))
    bundle = [g for g, _ in sorted(freq.items(), key=lambda t: (-t[1], t[0]))][:3]

    def run(r):
        return router.route(r["query"], exclude_scenario=r["scenario"] if exclude_own_scenario else None)

    P = []
    for r in pos:
        gold = {id2idx[g] for g in r["gold"] if g in id2idx}
        if not gold:
            continue
        o = run(r)
        P.append(dict(lang=r["lang"], scen=r["scenario"], score=o["gate_score"], accept=o["accept"],
                      h1=int(o["order"][0] in gold), h3=int(any(i in gold for i in o["order"][:3])),
                      b1=int(bundle[0] in gold), b3=int(any(i in gold for i in bundle))))
    N = [dict(score=(o := run(r))["gate_score"], accept=o["accept"]) for r in neg]
    acc = [p for p in P if p["accept"]]
    k = sum(n["accept"] for n in N)
    sc = [p["scen"] for p in P]
    res = dict(
        n_pos=len(P), n_neg=len(N), gate=router.gate,
        coverage=len(acc) / len(P) if P else None,
        acc_hit1=float(np.mean([p["h1"] for p in acc])) if acc else None,
        acc_hit3=float(np.mean([p["h3"] for p in acc])) if acc else None,
        far=k / len(N) if N else None, far_k=k, far_ci=exact_ci(k, len(N)),
        hit1=float(np.mean([p["h1"] for p in P])), hit3=float(np.mean([p["h3"] for p in P])),
        auc=auc([p["score"] for p in P], [n["score"] for n in N]),
        bundle=[chunks[i]["chunk_id"] for i in bundle],
        bundle_hit1=float(np.mean([p["b1"] for p in P])), bundle_hit3=float(np.mean([p["b3"] for p in P])),
        d_hit1_vs_bundle=cluster_boot_diff([p["h1"] for p in P], [p["b1"] for p in P], sc),
        d_hit3_vs_bundle=cluster_boot_diff([p["h3"] for p in P], [p["b3"] for p in P], sc),
        per_lang_hit3={l: dict(n=len(v), hit3=float(np.mean([p["h3"] for p in v])))
                       for l in sorted({p["lang"] for p in P}) for v in [[p for p in P if p["lang"] == l]]},
    )
    return res


def report(res, title):
    pct = lambda x: "-" if x is None else f"{x:.0%}"
    print(f"\n{title}\n  positives {res['n_pos']}  negatives {res['n_neg']}  gate {res['gate']}")
    print(f"  AT GATE : coverage {pct(res['coverage'])}  accepted Hit@1 {pct(res['acc_hit1'])} / Hit@3 "
          f"{pct(res['acc_hit3'])}  FAR {pct(res['far'])} ({res['far_k']}/{res['n_neg']}) "
          f"[{pct(res['far_ci'][0])}-{pct(res['far_ci'][1])}]")
    print(f"  UNGATED : Hit@1 {pct(res['hit1'])}  Hit@3 {pct(res['hit3'])}  AUC "
          f"{'-' if res['auc'] is None else round(res['auc'], 2)}")
    d1, d3 = res["d_hit1_vs_bundle"], res["d_hit3_vs_bundle"]
    print(f"  BUNDLE {res['bundle']}: Hit@1 {pct(res['bundle_hit1'])}  Hit@3 {pct(res['bundle_hit3'])}")
    print(f"  kNN - bundle: dHit@1 {d1[0]:+.0%} [{d1[1]:+.0%},{d1[2]:+.0%}]  dHit@3 {d3[0]:+.0%} [{d3[1]:+.0%},{d3[2]:+.0%}]")
    print("  per-language Hit@3: " + "  ".join(f"{l} {v['hit3']:.0%} (n={v['n']})" for l, v in res["per_lang_hit3"].items()))


def preflight(router, expected):
    import retrieval_pipeline as rp
    op = rp.dev_operating_point(router, 0.4)
    ok = (abs(op["thr"] - expected["thr"]) <= expected["thr_tol"] and op["n_pos"] == expected["n_pos"]
          and op["n_neg"] == expected["n_neg"] and op["far_k"] == expected["far_k"])
    print(f"PREFLIGHT (dev, LOSO, 40% coverage): thr {op['thr']:.6f}  n {op['n_pos']}/{op['n_neg']}  "
          f"FAR {op['far_k']}/{op['n_neg']}  accepted Hit@1 {op['acc_hit1']:.0%} / Hit@3 {op['acc_hit3']:.0%}  "
          f"ungated Hit@1 {op['hit1']:.0%} Hit@3 {op['hit3']:.0%}  -> {'REPRODUCED' if ok else 'MISMATCH'}")
    return ok, op


def main(argv=None, encoder=None, results_dir=HERE / "results", expected=EXPECTED, root=ROOT):
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--i-checked-the-lock", action="store_true")
    ap.add_argument("--max-seq-length", type=int, default=None,
                    help="must equal embedder_comparison.MODELS['me5-small']['max_len']")
    a = ap.parse_args(argv)
    import retrieval_pipeline as rp
    results_dir = Path(results_dir)
    lock = results_dir / LOCK_NAME
    if not a.dry_run:
        if not a.i_checked_the_lock:
            print("Refusing: pass --i-checked-the-lock for the one real run (or --dry-run)."); return 3
        prior = sorted(results_dir.glob("holdout_once_*.json")) if results_dir.exists() else []
        if lock.exists() or prior:
            print(f"Refusing: rule E already used. Lock: {lock if lock.exists() else '-'}  results: {prior}")
            if lock.exists():
                print(lock.read_text(encoding="utf-8"))
            return 2
    chunks = rp.load_corpus()
    store = rp.load_example_store()
    if encoder is None:
        encoder = rp.E5Encoder(max_seq_length=a.max_seq_length)
    router = rp.CrisisRouter(chunks, store, encoder)
    ok, op = preflight(router, expected)
    if a.dry_run:
        dev_pos = [dict(id=r["id"], lang=r["lang"], query=r["query"], scenario=r["scenario"], gold=r["gold"])
                   for r in router.store if not r["neg"]]
        dev_neg = [dict(id=r["id"], lang=r["lang"], query=r["query"], scenario=r["scenario"])
                   for r in router.store if r["neg"]]
        res = evaluate(router, chunks, dev_pos, dev_neg, exclude_own_scenario=True)
        report(res, "DRY RUN -- DEV store, leave-scenario-out (NOT the holdout; nothing locked)")
        hp, hn, hx = holdout_rows()
        print(f"\nholdout would contain: {len(hp)} positives, {len(hn)} negatives, excluded {dict(hx)} (queries not encoded)")
        return 0 if ok else 4
    if not ok:
        print("ABORT before the lock: dev reproduction failed. Holdout untouched. Fix config and rerun.")
        return 4
    results_dir.mkdir(parents=True, exist_ok=True)
    hashes = {p: sha256(Path(root) / p) for p in HASHED if (Path(root) / p).exists()}
    meta = dict(rule="E", started_at=datetime.now().isoformat(timespec="seconds"), status="started",
                model=getattr(encoder, "name", "?"), k=router.k, gate=router.gate, max_items=router.max_items,
                max_seq_length=a.max_seq_length, preflight=op, input_sha256=hashes)
    with open(lock, "x", encoding="utf-8") as fh:            # exclusive create: second process fails here
        json.dump(meta, fh, indent=2)
    print(f"LOCK CREATED {lock} -- from here on this is the one rule-E run.")
    pos, neg, excluded = holdout_rows()
    dev_sc = set(router.scen)
    clash = [r["id"] for r in pos + neg if r["scenario"] in dev_sc]
    if clash:
        raise RuntimeError(f"holdout scenario overlaps dev store: {clash[:5]}")
    res = evaluate(router, chunks, pos, neg)
    res.update(excluded=dict(excluded), label_sources=dict(Counter(r["labelled_by"] for r in pos + neg)))
    out = results_dir / f"holdout_once_{datetime.now():%Y%m%d_%H%M%S}.json"
    out.write_text(json.dumps(dict(meta=meta, holdout=res), indent=2, ensure_ascii=False), encoding="utf-8")
    meta.update(status="completed", results=out.name, results_sha256=sha256(out))
    lock.write_text(json.dumps(meta, indent=2), encoding="utf-8")
    report(res, "RULE E -- HOLDOUT (one run; DRAFT labels, not human-verified)")
    print(f"  excluded rows: {dict(excluded)}  label sources: {res['label_sources']}")
    print(f"\nSaved {out}\nresults sha256 {meta['results_sha256']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
