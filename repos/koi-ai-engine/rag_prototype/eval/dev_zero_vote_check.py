"""
v4.29 one-off DEV-ONLY check: effect of dropping zero-vote chunks from the served items.

    python eval/dev_zero_vote_check.py                 # real me5-small
    python eval/dev_zero_vote_check.py --stub          # plumbing only (numbers meaningless)

Reads ONLY the labelled dev store (load_example_store). It never opens the holdout, never touches the rule-E
lock. Leave-scenario-out, at the rule-G gate (0.5709), over accepted dev positives:
  Hit@3 measured (top-3 of the ranking, as reported)  vs  Hit@3 served (votes > 0 only, v4.29)
plus how many items are served. Served Hit@3 can only be <= measured. Holdout figures are NOT re-computed;
for the shipped behaviour the holdout Hit@3 (89%) is an upper bound.
"""
import argparse
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(HERE.parent / "scripts"), str(HERE)]

ap = argparse.ArgumentParser()
ap.add_argument("--stub", action="store_true")
a = ap.parse_args()
encoder = None
if a.stub:
    from test_crisis_router import StubEncoder   # installs a stand-in sentence_transformers module
    encoder = StubEncoder()
import retrieval_pipeline as rp  # noqa: E402

encoder = encoder or rp.E5Encoder()
router = rp.CrisisRouter(rp.load_corpus(), rp.load_example_store(), encoder)
rows = router.loso_scores()
acc = [r for r in rows if not r["neg"] and r["score"] >= router.gate]
n = len(acc)
m3 = sum(any(int(i) in r["gold"] for i in r["order"][:3]) for r in acc)
s3 = sum(any(i in r["gold"] for i in r["served"]) for r in acc)
dist = {k: sum(len(r["served"]) == k for r in acc) for k in (1, 2, 3)}
zero = sum(len(r["served"]) == 0 for r in acc)
print(f"DEV (LOSO), gate {router.gate}: accepted positives {n}")
print(f"  Hit@3 measured (top-3)      {m3}/{n} = {m3 / max(n, 1):.1%}")
print(f"  Hit@3 served (votes > 0)    {s3}/{n} = {s3 / max(n, 1):.1%}   change {s3 - m3:+d}")
print(f"  items served: 1 -> {dist[1]}, 2 -> {dist[2]}, 3 -> {dist[3]}, 0 (must be 0) -> {zero}")
