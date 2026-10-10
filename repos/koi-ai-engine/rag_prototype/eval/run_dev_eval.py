"""
Day 2 — Run the labeled dev set against the retriever, report recall@k.

Reports Tier A (gold), Tier B (silver), and out_of_corpus queries SEPARATELY.
Do not average them into one blended number -- they carry different
evidentiary weight (per dev_set.py's docstring) and averaging would hide
that, which is exactly the kind of "clean-looking number that overclaims"
this project has been explicitly trying to avoid.

NOTE: this does NOT implement the sufficiency gate yet (that's Day 3).
For out_of_corpus queries, this script only reports what got retrieved,
for manual inspection -- there is no calibrated threshold yet to say
whether the system would have correctly abstained.
"""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts"))
from retrieval_pipeline import load_corpus, HybridRetriever, eligibility_mask, answer_stage_filter
from dev_set import DEV_SET


def matches_gt(retrieved_chunk, item):
    if item["gt_tier"] == "A":
        return retrieved_chunk["chunk_id"] in item["gt_chunk_ids"]
    elif item["gt_tier"] == "B":
        if "gt_topic_match" in item:
            field_val = str(retrieved_chunk.get(item["gt_topic_match"], "")).lower()
            return item["gt_topic_value_contains"].lower() in field_val
        elif "gt_text_contains" in item:
            return item["gt_text_contains"].lower() in retrieved_chunk["text"].lower()
    return False


def run():
    chunks = load_corpus()
    retriever = HybridRetriever(chunks)

    tier_a_results, tier_b_results, ooc_results = [], [], []

    for item in DEV_SET:
        mask = eligibility_mask(chunks, item["risk_tier"])
        retrieved = retriever.retrieve(item["query"], k=10, eligible_mask=mask)
        eligible = answer_stage_filter(retrieved, item["risk_tier"])
        ranked_chunks = [r["chunk"] for r in (eligible if eligible else retrieved)]

        if item["gt_tier"] == "N/A":  # out_of_corpus
            top1_retrieved = retrieved[0] if retrieved else None  # unfiltered rank, includes score
            ooc_results.append({
                "id": item["id"], "query": item["query"],
                "top1_chunk_id": ranked_chunks[0]["chunk_id"] if ranked_chunks else None,
                "top1_source": ranked_chunks[0]["source_corpus"] if ranked_chunks else None,
                "top1_text": (ranked_chunks[0]["text"][:100] if ranked_chunks else "NONE"),
                "top1_cosine": top1_retrieved["cosine"] if top1_retrieved else None,
                "top1_rrf": top1_retrieved["rrf_score"] if top1_retrieved else None,
            })
            continue

        hit_at = None
        for rank, c in enumerate(ranked_chunks, start=1):
            if matches_gt(c, item):
                hit_at = rank
                break

        record = {
            "id": item["id"], "category": item["category"], "query": item["query"],
            "hit_at": hit_at,
            "recall@1": hit_at is not None and hit_at <= 1,
            "recall@3": hit_at is not None and hit_at <= 3,
            "recall@5": hit_at is not None and hit_at <= 5,
            "top1_chunk_id": ranked_chunks[0]["chunk_id"] if ranked_chunks else None,
            "top1_text": (ranked_chunks[0]["text"][:80] if ranked_chunks else "NONE"),
        }
        (tier_a_results if item["gt_tier"] == "A" else tier_b_results).append(record)

    def report(name, results):
        n = len(results)
        if n == 0:
            return
        r1 = sum(r["recall@1"] for r in results) / n
        r3 = sum(r["recall@3"] for r in results) / n
        r5 = sum(r["recall@5"] for r in results) / n
        print(f"\n{name} (n={n}):")
        print(f"  Recall@1: {r1:.2%}   Recall@3: {r3:.2%}   Recall@5: {r5:.2%}")
        # full per-query breakdown -- every query, not just misses, so
        # nothing is silently invisible in the aggregate numbers
        print(f"  {'id':4} {'hit@':5} {'top1_chunk_id':16} top1_text")
        for r in sorted(results, key=lambda x: (x["hit_at"] is None, x["hit_at"] or 99)):
            hit_str = str(r["hit_at"]) if r["hit_at"] is not None else "MISS"
            flag = "  <-- not rank 1" if r["hit_at"] and r["hit_at"] > 1 else ("  <-- FULL MISS" if r["hit_at"] is None else "")
            print(f"  {r['id']:4} {hit_str:5} {r['top1_chunk_id'] or 'NONE':16} {r['top1_text']}{flag}")

    print("=" * 90)
    print("DAY 2 DEV-SET EVALUATION")
    print("=" * 90)
    report("TIER A (gold, chunk-exact — authoritative corpus)", tier_a_results)
    report("TIER B (silver, topic-level — AnnoMI)", tier_b_results)

    print(f"\nOUT-OF-CORPUS (n={len(ooc_results)}) — what got retrieved, for manual review "
          f"(no calibrated abstention gate exists yet — that's Day 3):")
    for r in ooc_results:
        print(f"  [{r['id']}] \"{r['query'][:55]}\" -> cosine={r['top1_cosine']:.4f}  "
              f"{r['top1_chunk_id']} ({r['top1_source']}) | {r['top1_text']}")
    seen_top1s = [r["top1_chunk_id"] for r in ooc_results]
    dupes = set(x for x in seen_top1s if seen_top1s.count(x) > 1)
    if dupes:
        print(f"\n  ** FLAG: the same chunk_id was top-1 for multiple UNRELATED out-of-corpus "
              f"queries: {dupes} **")
        print(f"  ** This needs a decision: is this a genuine embedding-space 'hub' effect (a "
              f"passage that sits generically near many distress-adjacent queries), or a code "
              f"bug (e.g. an indexing error reusing the same row)? Check the cosine scores above "
              f"-- if they're meaningfully different per query, it's likely a real effect, not "
              f"a bug. If they're identical or near-identical, investigate the indexing code. **")

    print("\n" + "=" * 90)
    print("Reminder: Tier A and Tier B are NOT averaged together. See dev_set.py docstring for why.")
    print("=" * 90)


if __name__ == "__main__":
    run()
