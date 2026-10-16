"""
Real before/after of the eligibility pre-filter: frozen reference pipeline vs fixed pipeline,
same corpus, same real MiniLM embeddings (run LOCALLY; needs sentence-transformers).

Runs two query sets, reported separately:
  SMOKE  phase2b_smoke_test.py QUERIES (10) -- the queries that originally exposed the bug
  DEV    dev_set.py (29)                    -- gold-labelled; written FROM the chunks, so it
                                              is expected to be insensitive to crowd-out
Never touches dev_holdout.py.

Per query: how many ELIGIBLE chunks survive in the top-10 (old vs new), whether the top-1 /
top-3 eligible chunk ids changed, and for gold-labelled queries the gold rank among eligible.

    python compare_prefilter_real.py > compare_prefilter_real.txt
"""
import importlib.util
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(ROOT / "scripts"))
sys.path.insert(0, str(HERE))


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


new = load(ROOT / "scripts" / "retrieval_pipeline.py", "rp_new")
old = load(ROOT / "reference" / "retrieval_pipeline_REFERENCE_v0.py", "rp_old")
from phase2b_smoke_test import QUERIES as SMOKE  # noqa: E402
from dev_set import DEV_SET  # noqa: E402
from run_dev_eval import matches_gt  # noqa: E402

chunks = new.load_corpus()
print(f"corpus: {len(chunks)} chunks")
r_old = old.HybridRetriever(chunks)
r_new = new.HybridRetriever(chunks)


def run(mod, retriever, item):
    tier = item["risk_tier"]
    ret = retriever.retrieve(item["query"], k=10, eligible_mask=mod.eligibility_mask(chunks, tier))
    return mod.answer_stage_filter(ret, tier)


def ids(res, n):
    return [r["chunk"]["chunk_id"] for r in res[:n]]


def gold_rank(res, item):
    if item.get("gt_tier") not in ("A", "B"):
        return None
    for rank, r in enumerate(res, start=1):
        if matches_gt(r["chunk"], item):
            return rank
    return None


def compare(title, items):
    print(f"\n{'=' * 100}\n{title}\n{'=' * 100}")
    print(f"{'id':5}{'tier':9}{'elig/10 old':>12}{'new':>5}  {'top1':>8}  {'top3':>8}  {'gold old':>9}{'new':>5}")
    lost = top1_changed = top3_changed = gold_changed = 0
    for it in items:
        a, b = run(old, r_old, it), run(new, r_new, it)
        t1 = ids(a, 1) == ids(b, 1)
        t3 = ids(a, 3) == ids(b, 3)
        ga, gb = gold_rank(a, it), gold_rank(b, it)
        lost += len(a) < len(b)
        top1_changed += not t1
        top3_changed += not t3
        gold_changed += ga != gb
        gs = lambda g: "-" if g is None else str(g)
        print(f"{it['id']:5}{it['risk_tier']:9}{len(a):>12}{len(b):>5}  {'same' if t1 else 'CHANGED':>8}  "
              f"{'same' if t3 else 'CHANGED':>8}  {gs(ga):>9}{gs(gb):>5}")
    print(f"-> old pipeline kept fewer eligible results on {lost}/{len(items)} queries; "
          f"top-1 changed {top1_changed}, top-3 changed {top3_changed}, gold rank changed {gold_changed}")


compare("SMOKE queries (phase2b_smoke_test.py) -- the queries that exposed the bug", SMOKE)
compare("DEV set (dev_set.py) -- gold queries written from the chunks themselves", DEV_SET)
print("\nNote: elig/10 = eligible chunks left in top-10 after the old post-filter; the new pipeline "
      "fills top-10 from the eligible pool only. 'gold' = rank of the gold chunk among eligible results ('-' = none/not applicable).")
