"""
Phase 2b — RAG Retrieval Smoke Test (KOI_TSD_POC_PLAN_v1.md)

Original scope: index ~50-100 AnnoMI passages, 5-10 hand-authored crisis-
adjacent queries, pass/fail = >=8/10 queries return a genuinely relevant
passage in top-3. Run against the now-RETIERED corpus (all three sources,
locked schema, eligibility-filtered by risk tier) rather than a raw AnnoMI-
only slice, since that work is now done (Day 1).

This is a SMOKE TEST — retrieval plausibility only. It is NOT the full
calibrated sufficiency-gate evaluation (that's Day 3, on a proper 50-150
query labeled dev set with group k-fold, per the locked calibration plan).
"""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts"))
from retrieval_pipeline import load_corpus, HybridRetriever, eligibility_mask, answer_stage_filter

QUERIES = [
    {"id": "q1", "risk_tier": "HIGH", "query": "what should I do if someone says they want to hurt themselves",
     "expect_source_in": ["WHO_mhGAP_2023", "SAMHSA_2025", "AnnoMI"]},
    {"id": "q2", "risk_tier": "CRITICAL", "query": "immediate suicidal thoughts safety plan",
     "expect_source_in": ["WHO_mhGAP_2023", "SAMHSA_2025"]},
    {"id": "q3", "risk_tier": "CRITICAL", "query": "how to ask someone directly if they are thinking about suicide",
     "expect_source_in": ["SAMHSA_2025", "WHO_mhGAP_2023"]},
    {"id": "q4", "risk_tier": "HIGH", "query": "person feels hopeless and wants to reduce their drinking",
     "expect_source_in": ["AnnoMI"]},
    {"id": "q5", "risk_tier": "HIGH", "query": "how to reflect back what someone in distress just told you",
     "expect_source_in": ["AnnoMI"]},
    {"id": "q6", "risk_tier": "CRITICAL", "query": "follow up care after a suicide crisis call",
     "expect_source_in": ["SAMHSA_2025"]},
    {"id": "q7", "risk_tier": "HIGH", "query": "digital self-help tools for someone having suicidal thoughts",
     "expect_source_in": ["WHO_mhGAP_2023"]},
    {"id": "q8", "risk_tier": "CRITICAL", "query": "crisis services should prioritize safety for the person and staff",
     "expect_source_in": ["SAMHSA_2025"]},
    {"id": "q9", "risk_tier": "HIGH", "query": "open-ended question to explore someone's ambivalence about change",
     "expect_source_in": ["AnnoMI"]},
    {"id": "q10", "risk_tier": "CRITICAL", "query": "older adult experiencing a mental health crisis and isolation",
     "expect_source_in": ["SAMHSA_2025"]},
]

def run():
    chunks = load_corpus()
    retriever = HybridRetriever(chunks)

    results = []
    for q in QUERIES:
        mask = eligibility_mask(chunks, q["risk_tier"])
        retrieved = retriever.retrieve(q["query"], k=10, eligible_mask=mask)
        eligible_answers = answer_stage_filter(retrieved, q["risk_tier"])
        top3 = eligible_answers[:3] if eligible_answers else retrieved[:3]

        top3_sources = [r["chunk"]["source_corpus"] for r in top3]
        passed = any(s in q["expect_source_in"] for s in top3_sources)

        results.append({
            "id": q["id"], "query": q["query"], "risk_tier": q["risk_tier"],
            "passed": passed, "top3_sources": top3_sources,
            "top1_text": (top3[0]["chunk"]["text"][:140] + "...") if top3 else "NONE RETRIEVED",
            "top1_rrf": top3[0]["rrf_score"] if top3 else 0.0,
            "eligible_count_after_answer_filter": len(eligible_answers),
        })

    passed_n = sum(r["passed"] for r in results)
    print(f"\n{'='*90}\nPHASE 2B SMOKE TEST RESULTS\n{'='*90}")
    for r in results:
        status = "PASS" if r["passed"] else "FAIL"
        print(f"\n[{status}] {r['id']} ({r['risk_tier']}): \"{r['query']}\"")
        print(f"   top-3 sources: {r['top3_sources']}")
        print(f"   answer-eligible chunks after evidence_role filter: {r['eligible_count_after_answer_filter']}")
        print(f"   top-1 (rrf={r['top1_rrf']:.4f}): {r['top1_text']}")

    print(f"\n{'='*90}")
    print(f"RESULT: {passed_n}/{len(QUERIES)} passed  "
          f"({'PASS' if passed_n >= 8 else 'FAIL'} — threshold is >=8/10 per locked Phase 2b spec)")
    print(f"{'='*90}")
    return results, passed_n

if __name__ == "__main__":
    run()
