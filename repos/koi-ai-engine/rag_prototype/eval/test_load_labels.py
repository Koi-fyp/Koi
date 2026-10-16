"""Plumbing test for load_labels.py using SYNTHETIC rows (no real labels). Run: python test_load_labels.py"""
import csv, tempfile
from pathlib import Path
import sys; sys.path.insert(0, str(Path(__file__).resolve().parent))
import load_labels as ll

fails = []
def check(n, c):
    print(("PASS " if c else "FAIL ") + n)
    if not c: fails.append(n)

cols = ["id","lang","category","stratum","scenario_id","source_batch","split","query","risk_tier","gt_tier",
        "gt_chunk_ids","gt_labelled_by","draft_run1","draft_run2","draft_status","draft_consensus"]
rows = [
 dict(id="X1",split="dev",draft_status="exact",draft_consensus="c1"),
 dict(id="X2",split="dev",draft_status="partial",draft_consensus="c1"),
 dict(id="X3",split="dev",draft_status="none_flip",draft_consensus=""),
 dict(id="X4",split="holdout",draft_status="exact",draft_consensus="c1"),
 dict(id="X5",split="dev",draft_status="negative_by_design",draft_consensus=""),
 dict(id="X6",split="dev",draft_status="exact",draft_consensus="c1"),
 dict(id="X7",split="dev",draft_status="none_flip",draft_consensus=""),
 dict(id="X8",split="dev",draft_status="none_flip",draft_consensus=""),
]
d = Path(tempfile.mkdtemp())
with open(d/"m.csv","w",encoding="utf-8-sig",newline="") as f:
    w = csv.DictWriter(f, fieldnames=cols); w.writeheader()
    for r in rows:
        base = dict(lang="roman_urdu",category="c",stratum="s",scenario_id=r["id"],source_batch="C",query="q "+r["id"])
        w.writerow({**{k:"" for k in cols}, **base, **r})
rc = ["id","why","lang","query","run1","run2","your_gt_chunk_ids","your_risk_tier"]
with open(d/"r.csv","w",encoding="utf-8-sig",newline="") as f:
    w = csv.DictWriter(f, fieldnames=rc); w.writeheader()
    w.writerow(dict(id="X1",why="SPOT-CHECK:exact",your_gt_chunk_ids=""))          # accept draft
    w.writerow(dict(id="X2",why="SPOT-CHECK:partial",your_gt_chunk_ids="c2"))       # correction
    w.writerow(dict(id="X3",why="DISPUTED:none_flip",your_gt_chunk_ids="NONE"))     # resolved to negative
    w.writerow(dict(id="X7",why="DISPUTED:none_flip",your_gt_chunk_ids=""))         # unresolved
    w.writerow(dict(id="X6",why="SPOT-CHECK:exact",your_gt_chunk_ids="c1;ghost"))   # unknown id dropped
    w.writerow(dict(id="X8",why="DISPUTED:none_flip",your_gt_chunk_ids="AMBIGUOUS",your_risk_tier="high-proposed"))
known = {"c1","c2"}
pos, neg, amb, rep = ll.build(d/"m.csv", d/"r.csv", False, known)
by = {p["id"]: p for p in pos}
check("spot-check blank accepts draft", by["X1"]["gt_chunk_ids"] == ["c1"] and by["X1"]["gt_labelled_by"] == "ahmad-accepted-draft")
check("correction recorded as ahmad", by["X2"]["gt_chunk_ids"] == ["c2"] and by["X2"]["gt_labelled_by"] == "ahmad")
check("ground-truth NONE goes to negatives", any(n["id"] == "X3" for n in neg) and "X3" not in by)
check("by-design negative present", any(n["id"] == "X5" and n["gt_tier"] == "N/A" for n in neg))
check("unresolved disputed row excluded", "X7" in rep["excluded_unresolved"] and "X7" not in by)
check("holdout never written", "X4" not in by and not any(n["id"] == "X4" for n in neg) and rep["excluded_holdout"] == 1)
check("unknown chunk id dropped and reported", by["X6"]["gt_chunk_ids"] == ["c1"] and rep["dropped_ids"] == [("X6","ghost")])
check("AMBIGUOUS goes to its own list, not recall/negatives, tier kept",
      [a["id"] for a in amb] == ["X8"] and amb[0]["reviewer_risk_tier"] == "HIGH-PROPOSED" and "X8" not in by and not any(n["id"] == "X8" for n in neg))
posr, _, _, _ = ll.build(d/"m.csv", d/"r.csv", False, known, reviewer="claude-delegated")
check("reviewer tag is configurable", {p["gt_labelled_by"] for p in posr} == {"claude-delegated", "claude-delegated-accepted-draft"})
check("every entry is HIGH tier", all(p["risk_tier"] == "HIGH" for p in pos))
pos2, _, _, rep2 = ll.build(d/"m.csv", None, False, known)
check("no review file + default = zero recall entries", pos2 == [])
pos3, _, _, _ = ll.build(d/"m.csv", None, True, known)
check("include-unchecked adds only agreed rows, tagged as draft",
      {p["id"] for p in pos3} == {"X1","X2","X6"} and all(p["gt_labelled_by"] == "chatgpt-draft-2run-agree" for p in pos3))
print("\nALL PASSED" if not fails else "\nFAILED: " + ", ".join(fails))
