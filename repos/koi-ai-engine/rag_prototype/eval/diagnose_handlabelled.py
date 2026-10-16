"""
Why is recall on the hand-labelled queries ~0%?  (diagnostic, run LOCALLY after ablation.py)

    python diagnose_handlabelled.py --cache-dir .emb_cache
    python diagnose_handlabelled.py --models minilm bge-m3 --cache-dir .emb_cache

For each embedder and language, with arms dense_only and hybrid_unicode_words:
  FULL pool  = everything eligible at HIGH (6,204 chunks, ~6,178 of them AnnoMI counselling transcripts)
  AUTH pool  = only the non-AnnoMI chunks (the 26 authoritative guideline chunks that all gold labels point to)
Reported: R@1/3/10, median rank of the gold chunk (over rows where gold is ranked), and the share of the
top-10 that is AnnoMI.

Reading it:
  * FULL low, AUTH high  -> the embedder can tell WHICH guideline chunk fits, but AnnoMI transcripts crowd the
                            guideline chunks out. A pool/design question, not an embedder or language problem.
  * FULL low, AUTH low   -> embedder (or the labels) cannot match user-voice text to guideline text.
  * high AnnoMI share in top-10 with ~0% gold recall -> crowding confirmed.
Also prints the same table for rows whose query is plain ASCII (Roman script) so near-English code-switched
rows can be compared with Roman Urdu. Labels are LLM-adjudicated; see gt_labelled_by.
"""
import argparse
import statistics
import sys
from collections import Counter
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "scripts"))
sys.path.insert(0, str(HERE))
import ablation as ab  # noqa: E402
import embedder_comparison as ec  # noqa: E402
from retrieval_pipeline import load_corpus, HybridRetriever, eligibility_mask  # noqa: E402

ARMS = ("dense_only", "hybrid_unicode_words")


def summarise(ranks, annomi_share):
    n = len(ranks)
    hit = lambda k: sum(1 for r in ranks if r is not None and r <= k) / n if n else 0.0
    found = [r for r in ranks if r is not None]
    med = statistics.median(found) if found else None
    return dict(n=n, r1=hit(1), r3=hit(3), r10=hit(10), median_rank=med,
                annomi_top10=(sum(annomi_share) / len(annomi_share)) if annomi_share else 0.0)


def run(model_keys, cache_dir):
    chunks = load_corpus()
    items_all, _ = ec.valid_multilingual(ec.MULTILINGUAL_QUERIES)
    is_annomi = [c["source_corpus"] == "AnnoMI" for c in chunks]
    full_mask = eligibility_mask(chunks, "HIGH")
    auth_mask = [m and not a for m, a in zip(full_mask, is_annomi)]
    print(f"HIGH pool: full={sum(full_mask)}  authoritative-only={sum(auth_mask)}  "
          f"hand-labelled entries={len(items_all)}")
    out = {}
    for key in model_keys:
        cfg = ec.MODELS[key]
        r = HybridRetriever(chunks, model_name=cfg["name"], doc_prefix=cfg["doc"], query_prefix=cfg["query"],
                            max_seq_length=cfg["max_len"], cache_dir=cache_dir)
        bm25s = ab.build_bm25s(r.texts)
        print(f"\n{'=' * 110}\n{key}\n{'=' * 110}")
        print(f"  {'group':26}{'arm':24}{'pool':6}{'n':>4}{'R@1':>6}{'R@3':>6}{'R@10':>6}{'med.rank':>10}{'AnnoMI@10':>11}")
        groups = {lang: [e for e in items_all if e["lang"] == lang]
                  for lang in ("urdu_native", "roman_urdu", "code_switched")}
        groups["ASCII-only (all langs)"] = [e for e in items_all if e["query"].isascii()]
        out[key] = {}
        for gname, items in groups.items():
            if not items:
                continue
            for arm in ARMS:
                for pname, mask in (("FULL", full_mask), ("AUTH", auth_mask)):
                    ranks, share = [], []
                    for it in items:
                        idx, _ = ab.rank(r, bm25s, it["query"], mask, arm, k=len(chunks))
                        ranks.append(ec.first_hit(idx, chunks, it))
                        top = idx[:10]
                        share.append(sum(is_annomi[i] for i in top) / max(len(top), 1))
                    s = summarise(ranks, share)
                    out[key][(gname, arm, pname)] = s
                    med = "-" if s["median_rank"] is None else f"{s['median_rank']:.0f}"
                    print(f"  {gname:26}{arm:24}{pname:6}{s['n']:>4}{s['r1']:>6.0%}{s['r3']:>6.0%}"
                          f"{s['r10']:>6.0%}{med:>10}{s['annomi_top10']:>11.0%}")
    print("\nLabel sources:", dict(Counter(e["gt_labelled_by"] for e in items_all)),
          "(LLM-adjudicated, not human-verified)")
    return out


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--models", nargs="+", default=list(ec.MODELS), choices=list(ec.MODELS))
    ap.add_argument("--cache-dir", default=None)
    a = ap.parse_args()
    run(a.models, a.cache_dir)
