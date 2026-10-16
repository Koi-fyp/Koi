"""
Build multilingual_queries.py from the master CSV (+ Ahmad's filled review CSV).

    python load_labels.py                                   # dry run: counts only, writes nothing
    python load_labels.py --review labels/review_for_ahmad.csv --write
    python load_labels.py --include-unchecked --write       # EXPLORATORY ONLY (see below)

Label quality, recorded in gt_labelled_by (embedder_comparison.valid_multilingual requires it non-empty).
The prefix is --reviewer (default "ahmad"). On 2026-10-12 Ahmad delegated the review to Claude, so that run
uses --reviewer claude-delegated: those labels are LLM-adjudicated, NOT human-verified, and must be described
that way in the limitations section.
  "<reviewer>"                 reviewer filled your_gt_chunk_ids in the review CSV (DISPUTED / AMBIGUOUS rows
                               or a correction on a spot-check row).
  "<reviewer>-accepted-draft"  SPOT-CHECK row, your_gt_chunk_ids left blank = reviewer accepted the draft.
  "chatgpt-draft-2run-agree"   two ChatGPT runs agreed (exact or partial overlap; gold = the overlap),
                               NOT looked at by Ahmad. Only written with --include-unchecked.
Default output = reviewed rows only. DISPUTED rows left unresolved are always excluded.
Review value "AMBIGUOUS" = message too vague to label (e.g. "sab khatam bas ab"). Such rows are written to
MULTILINGUAL_AMBIGUOUS: not recall entries and NOT negatives (a gate that rejects "i cant do this anymore"
would be the wrong safety behaviour). They are probes for the router, not for retrieval.

Rules enforced here:
  * dev split only. The holdout split is never written (dev_holdout.py rule: one post-selection use).
  * Ground-truth NONE rows (and the 100 by-design negatives) go to MULTILINGUAL_NEGATIVES, not to the
    recall list -- they have no gold chunk. They are for gate calibration.
  * risk_tier is "HIGH" for every entry: CRITICAL always fails closed to the fallback, and the 4 Urdu
    chunks are ineligible there, so retrieval quality is measured at HIGH. The reviewer's tier for ambiguous
    rows is kept as reviewer_risk_tier and is not used for retrieval.
  * Chunk ids are checked against data/processed/*.jsonl; unknown ids are dropped and reported.
"""
import argparse
import csv
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
MASTER = HERE / "labels" / "koi_queries_master_draft.csv"
OUT = HERE / "multilingual_queries.py"


def corpus_ids():
    ids = set()
    for f in (ROOT / "data" / "processed").glob("*.jsonl"):
        for line in open(f, encoding="utf-8"):
            if line.strip():
                ids.add(json.loads(line)["chunk_id"])
    return ids


def split_ids(v):
    return [x for x in (v or "").replace(",", ";").split(";") if x.strip()]


def build(master_path, review_path=None, include_unchecked=False, known_ids=None, reviewer="ahmad"):
    known = known_ids if known_ids is not None else corpus_ids()
    review = {}
    if review_path:
        for r in csv.DictReader(open(review_path, encoding="utf-8-sig")):
            review[r["id"]] = r
    pos, neg, amb, report = [], [], [], {"dropped_ids": [], "excluded_unresolved": [], "excluded_unchecked": [],
                                "excluded_holdout": 0}
    for m in csv.DictReader(open(master_path, encoding="utf-8-sig")):
        if m["split"] != "dev":
            report["excluded_holdout"] += 1
            continue
        i = m["id"]
        base = {"id": i, "lang": m["lang"], "category": m["category"], "risk_tier": "HIGH", "gt_tier": "A",
                "query": m["query"], "source_batch": m["source_batch"], "stratum": m["stratum"]}
        if m["draft_status"] == "negative_by_design":
            neg.append(dict(base, gt_tier="N/A", gt_labelled_by="by-design"))
            continue
        rv = review.get(i)
        draft = split_ids(m["draft_consensus"])
        who = None
        if rv is not None:
            mine = split_ids(rv.get("your_gt_chunk_ids"))
            if rv.get("your_risk_tier"):
                base["reviewer_risk_tier"] = rv["your_risk_tier"].strip().upper()
            if mine == ["AMBIGUOUS"]:
                amb.append(dict(base, gt_tier="N/A", gt_labelled_by=reviewer))
                continue
            if mine:
                chosen, who = mine, reviewer
            elif rv["why"].startswith("SPOT-CHECK"):
                chosen, who = draft, reviewer + "-accepted-draft"
            else:
                report["excluded_unresolved"].append(i)
                continue
        else:
            if not include_unchecked or m["draft_status"] not in ("exact", "partial") or not draft:
                report["excluded_unchecked"].append(i)
                continue
            chosen, who = draft, "chatgpt-draft-2run-agree"
        bad = [c for c in chosen if c != "NONE" and c not in known]
        if bad:
            report["dropped_ids"] += [(i, b) for b in bad]
            chosen = [c for c in chosen if c not in bad]
        if not chosen:
            report["excluded_unresolved"].append(i)
        elif chosen == ["NONE"]:
            neg.append(dict(base, gt_tier="N/A", gt_labelled_by=who))
        else:
            pos.append(dict(base, gt_chunk_ids=[c for c in chosen if c != "NONE"], gt_labelled_by=who))
    return pos, neg, amb, report


def render(pos, neg, amb=()):
    head = ('"""GENERATED by load_labels.py -- do not hand-edit. See that file for label-quality rules.\n'
            'Dev split only. Holdout is never written here."""\n\n')
    return (head + "MULTILINGUAL_QUERIES = " + json.dumps(pos, indent=2, ensure_ascii=False) +
            "\n\nMULTILINGUAL_NEGATIVES = " + json.dumps(neg, indent=2, ensure_ascii=False) +
            "\n\nMULTILINGUAL_AMBIGUOUS = " + json.dumps(list(amb), indent=2, ensure_ascii=False) + "\n")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--master", default=str(MASTER))
    ap.add_argument("--review")
    ap.add_argument("--include-unchecked", action="store_true")
    ap.add_argument("--reviewer", default="ahmad")
    ap.add_argument("--write", action="store_true")
    a = ap.parse_args()
    pos, neg, amb, rep = build(a.master, a.review, a.include_unchecked, reviewer=a.reviewer)
    from collections import Counter
    print("recall entries:", len(pos), dict(Counter((p["lang"], p["gt_labelled_by"]) for p in pos)))
    print("ambiguous    :", len(amb), "(router probes, not retrieval)")
    print("negatives     :", len(neg), dict(Counter(n["gt_labelled_by"] for n in neg)))
    print("excluded: holdout", rep["excluded_holdout"], "| unresolved", len(rep["excluded_unresolved"]),
          "| unchecked", len(rep["excluded_unchecked"]), "| unknown chunk ids", rep["dropped_ids"])
    if a.include_unchecked:
        print("WARNING: --include-unchecked mixes unverified ChatGPT labels into the evaluation. "
              "Report such numbers as DRAFT-LABEL results, never as Ahmad-verified.")
    if a.write:
        OUT.write_text(render(pos, neg, amb), encoding="utf-8")
        print("wrote", OUT)
