"""
Day 3 — FROZEN HOLDOUT. Do not use any query in this file for threshold
calibration (that's dev_set.py + calibrate_gate.py). Evaluate ONCE, after
the threshold is chosen and frozen, per the locked calibration methodology.

DISCLOSED SHORTFALL: locked target was 30-50 fresh queries. This has 10.
Reason: the authoritative corpus is 19 chunks total; Day 2's dev_set.py
already targets 12 of them, leaving 7 genuinely untested chunks to build
fresh single-hop queries against. Building past that would mean either
(a) re-targeting already-calibration-tested chunks with new phrasing --
which tests paraphrase robustness, not true held-out generalization, or
(b) reusing AnnoMI's silver-tier topic matching, which is a weaker label
type already flagged as such. Both are legitimate but shouldn't be
silently blended into a "frozen holdout" claim without saying so. This
file is what a corpus this size honestly supports for TRUE held-out
generalization testing.
"""

FROZEN_HOLDOUT = [
    {"id": "h01", "category": "single_hop", "risk_tier": "HIGH", "gt_tier": "A",
     "query": "crisis systems need strong partnerships across different sectors and agencies",
     "gt_chunk_ids": ["samhsa_e5b108d46d"]},
    {"id": "h02", "category": "single_hop", "risk_tier": "HIGH", "gt_tier": "A",
     "query": "letting the person in crisis decide for themselves what counts as an emergency",
     "gt_chunk_ids": ["samhsa_c65d0b35bb"]},
    {"id": "h03", "category": "paraphrase", "risk_tier": "HIGH", "gt_tier": "A",
     "query": "crisis care should not discriminate and must reach underserved communities",
     "gt_chunk_ids": ["samhsa_07f07c54c2"]},
    {"id": "h04", "category": "single_hop", "risk_tier": "HIGH", "gt_tier": "A",
     "query": "reviewing suicide deaths afterward to improve the crisis system",
     "gt_chunk_ids": ["samhsa_39eaeaebcb"]},
    {"id": "h05", "category": "single_hop", "risk_tier": "HIGH", "gt_tier": "A",
     "query": "peer support workers sharing their own lived experience of recovery",
     "gt_chunk_ids": ["samhsa_d8ce247ecc"]},
    {"id": "h06", "category": "single_hop", "risk_tier": "HIGH", "gt_tier": "A",
     "query": "staff need proper training and supervision to deliver evidence-based crisis care",
     "gt_chunk_ids": ["samhsa_28a1f6c98e"]},
    {"id": "h07", "category": "single_hop", "risk_tier": "HIGH", "gt_tier": "A",
     "query": "crisis services for veterans and people with intellectual or developmental disabilities",
     "gt_chunk_ids": ["samhsa_38dea1e07c"]},
    {"id": "h08", "category": "paraphrase", "risk_tier": "HIGH", "gt_tier": "A",
     "query": "the person experiencing the crisis, not the system, should define whether it's an emergency",
     "gt_chunk_ids": ["samhsa_c65d0b35bb"]},  # deliberate paraphrase pair with h02

    # -- fresh out-of-corpus negatives, confirmed absent this session --
    {"id": "h09", "category": "out_of_corpus", "risk_tier": "HIGH", "gt_tier": "N/A",
     "query": "supporting someone through grief after losing a family member",
     "gt_chunk_ids": [], "confirmed_absent_by": "regex: grief|bereave -> 0 hits"},
    {"id": "h10", "category": "out_of_corpus", "risk_tier": "CRITICAL", "gt_tier": "N/A",
     "query": "identifying a potential victim of human trafficking",
     "gt_chunk_ids": [], "confirmed_absent_by": "regex: human traffick -> 0 hits"},
]

if __name__ == "__main__":
    from collections import Counter
    print(f"Frozen holdout: {len(FROZEN_HOLDOUT)} queries "
          f"(locked target: 30-50 -- disclosed shortfall, see module docstring)")
    print(Counter(q["category"] for q in FROZEN_HOLDOUT))
