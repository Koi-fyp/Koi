"""
M2 static content review of the 22 crisis-pool passages (no model needed).

    python eval/content_review.py

Prints, per passage: audience tag [PROPOSED], reason, lexical-veto hits, and how many labelled dev positives name it
as gold (store gold = chunk_id strings). Then: how many dev positives have at least one SERVABLE gold passage (an upper bound on how often grounded
content could ever be correct once the content checks are on). Dev labels only; never reads the holdout.
"""
import sys
import types
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(HERE.parent / "scripts"), str(HERE)]
try:
    import sentence_transformers  # noqa: F401
except ImportError:                                  # the review needs no model; allow running without it
    _m = types.ModuleType("sentence_transformers"); _m.SentenceTransformer = object
    sys.modules["sentence_transformers"] = _m
import retrieval_pipeline as rp  # noqa: E402
import content_safety as cs  # noqa: E402


def review():
    chunks = rp.load_corpus()
    pool = rp.crisis_pool(chunks)
    store = rp.load_example_store()
    pos = [r for r in store if not r["neg"]]
    gold_n = {int(i): sum(chunks[i]["chunk_id"] in set(r["gold"]) for r in pos) for i in pool}
    rows = []
    for i in pool:
        c = chunks[i]
        tag, why = cs.AUDIENCE.get(c["chunk_id"], (cs.CLINICIAN, "unknown id"))
        rows.append(dict(idx=int(i), chunk_id=c["chunk_id"], source=c["source_corpus"], tag=tag, reason=why,
                         veto=cs.veto_hits(c["text"]), servable=cs.is_servable(c), gold=gold_n[int(i)],
                         review_status=c.get("review_status"), chars=len(c["text"])))
    servable = {r["chunk_id"] for r in rows if r["servable"]}
    covered = sum(bool(set(r["gold"]) & servable) for r in pos)
    return rows, covered, len(pos)


if __name__ == "__main__":
    rows, covered, npos = review()
    print(f"{'chunk_id':22} {'tag':12} {'serve':5} {'gold':>4} {'chars':>5}  veto hits / reason")
    for r in sorted(rows, key=lambda r: (-r["servable"], -r["gold"])):
        hits = ", ".join(f"{c}:{t}" for c, t in r["veto"]) or "-"
        print(f"{r['chunk_id']:22} {r['tag']:12} {'YES' if r['servable'] else 'no':5} {r['gold']:>4} {r['chars']:>5}"
              f"  [{hits}] {r['reason']} ({r['review_status']})")
    print(f"\nservable passages: {sum(r['servable'] for r in rows)} of {len(rows)}")
    print(f"dev positives with >=1 servable gold passage: {covered}/{npos} = {covered / npos:.0%} "
          f"(ceiling on correct grounded answers with the content checks on)")
