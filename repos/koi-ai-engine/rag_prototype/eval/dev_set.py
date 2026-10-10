"""
Day 2 — Labeled dev set for retrieval evaluation.

GROUND TRUTH CONFIDENCE — two tiers, disclosed, do not conflate them:

  TIER A (gold, chunk-exact): the AUTHORITATIVE corpus is fully enumerable
  (19 chunks total, all read and hand-verified this session — see the
  chunk listing in the Day 2 session log). Ground truth here is the exact
  correct chunk_id(s), verified by direct inspection, not inference.

  TIER B (silver, topic-level): the AnnoMI corpus (6,178 eligible chunks)
  is NOT exhaustively hand-readable at this scale. Ground truth here is
  "any chunk whose target_construct/technique field matches," found via
  targeted keyword search and spot-checked, NOT individually verified
  chunk-by-chunk. This is a weaker label and recall numbers computed
  against it should be reported as such — a query "passing" against a
  Tier B topic match is not the same evidentiary strength as passing
  against a Tier A gold chunk_id.

Categories (per locked Day 2 build order): single_hop, paraphrase,
out_of_corpus, critical, adversarial. out_of_corpus topics below were
confirmed absent via direct regex search of the full corpus this session
(not assumed) — see Day 2 session log.
"""

DEV_SET = [
    # ============ TIER A — AUTHORITATIVE, gold chunk-exact ============
    # -- single_hop --
    {"id": "a01", "category": "single_hop", "risk_tier": "CRITICAL", "gt_tier": "A",
     "query": "definition of self-harm",
     "gt_chunk_ids": ["who_bea4d647aa"]},
    {"id": "a02", "category": "single_hop", "risk_tier": "CRITICAL", "gt_tier": "A",
     "query": "definition of suicidal ideation",
     "gt_chunk_ids": ["who_250f535470"]},
    {"id": "a03", "category": "single_hop", "risk_tier": "CRITICAL", "gt_tier": "A",
     "query": "the 988 suicide and crisis lifeline phone service",
     "gt_chunk_ids": ["samhsa_068757d34a"]},
    {"id": "a04", "category": "single_hop", "risk_tier": "CRITICAL", "gt_tier": "A",
     "query": "digital CBT and DBT tools for suicidal thoughts",
     "gt_chunk_ids": ["who_466ea20335"]},
    {"id": "a05", "category": "single_hop", "risk_tier": "HIGH", "gt_tier": "A",
     "query": "crisis services should be trauma-informed",
     "gt_chunk_ids": ["samhsa_21fe845e34"]},
    {"id": "a06", "category": "single_hop", "risk_tier": "HIGH", "gt_tier": "A",
     "query": "older adults and dementia in crisis care",
     "gt_chunk_ids": ["samhsa_ba841557a7"]},

    # -- paraphrase (same intent as an 'a0x' query above, different wording) --
    {"id": "a07", "category": "paraphrase", "risk_tier": "CRITICAL", "gt_tier": "A",
     "query": "how to ask someone directly if they are thinking about suicide",
     "gt_chunk_ids": ["samhsa_c744348b34"]},  # ASIST/risk-assessment chunk, NOT sui2 -- see Day 1 finding
    {"id": "a08", "category": "paraphrase", "risk_tier": "CRITICAL", "gt_tier": "A",
     "query": "what does it mean when someone is thinking about ending their life",
     "gt_chunk_ids": ["who_250f535470"]},  # paraphrase of a02, avoids the literal phrase "suicidal ideation"
    {"id": "a09", "category": "paraphrase", "risk_tier": "CRITICAL", "gt_tier": "A",
     "query": "phone or text number to call during a mental health emergency",
     "gt_chunk_ids": ["samhsa_068757d34a"]},  # paraphrase of a03, no "988" or "lifeline" literal terms
    {"id": "a10", "category": "paraphrase", "risk_tier": "HIGH", "gt_tier": "A",
     "query": "making sure crisis care accounts for someone's past traumatic experiences",
     "gt_chunk_ids": ["samhsa_21fe845e34"]},  # paraphrase of a05
    {"id": "a11", "category": "paraphrase", "risk_tier": "HIGH", "gt_tier": "A",
     "query": "apps or online programs someone could use if they're having thoughts of self-harm",
     "gt_chunk_ids": ["who_466ea20335"]},  # paraphrase of a04

    # -- critical (deliberately maximal risk framing) --
    {"id": "a12", "category": "critical", "risk_tier": "CRITICAL", "gt_tier": "A",
     "query": "someone just told me they have a plan to end their life tonight, what evidence-based options exist",
     "gt_chunk_ids": ["who_a53d6078d3", "who_466ea20335"]},  # safety planning + digital intervention both relevant
    {"id": "a13", "category": "critical", "risk_tier": "CRITICAL", "gt_tier": "A",
     "query": "keeping a person and staff physically safe during a crisis intervention",
     "gt_chunk_ids": ["samhsa_983fdc952b"]},
    {"id": "a14", "category": "critical", "risk_tier": "CRITICAL", "gt_tier": "A",
     "query": "what happens after someone calls a crisis line, do they get follow-up support",
     "gt_chunk_ids": ["samhsa_8ebc7bced3", "samhsa_0a88eb2fc9"]},
    {"id": "a15", "category": "critical", "risk_tier": "CRITICAL", "gt_tier": "A",
     "query": "evidence that follow-up calls after a crisis actually reduce suicide risk",
     "gt_chunk_ids": ["samhsa_0a88eb2fc9"]},

    # -- adversarial (deliberately shares vocabulary with a WRONG chunk) --
    {"id": "a16", "category": "adversarial", "risk_tier": "CRITICAL", "gt_tier": "A",
     "query": "media awareness campaign about suicide prevention",
     "gt_chunk_ids": ["who_262440fba5"],  # SUI2 IS correct here -- the trap is the opposite direction of a07
     "distractor_chunk_ids": ["samhsa_068757d34a"],
     "note": "mirror case of a07/Day1-q3: here the media-campaign chunk (who_262440fba5) is the CORRECT "
             "answer, testing whether the fix that solved q3 didn't overcorrect into ignoring this chunk "
             "entirely when it's actually the right one"},
    {"id": "a17", "category": "adversarial", "risk_tier": "HIGH", "gt_tier": "A",
     "query": "safety planning process for someone in crisis",
     "gt_chunk_ids": ["who_a53d6078d3", "samhsa_983fdc952b"],
     "distractor_chunk_ids": ["samhsa_e5b108d46d"],
     "note": "'safety' appears in both the correct safety-PLANNING chunks and the general "
             "'safe places' system-principle chunk (samhsa_e5b108d46d) -- lexical overlap trap"},
    {"id": "a18", "category": "adversarial", "risk_tier": "CRITICAL", "gt_tier": "A",
     "query": "children experiencing a crisis in an emergency department",
     "gt_chunk_ids": ["samhsa_ba841557a7"],
     "distractor_chunk_ids": ["samhsa_983fdc952b"],
     "note": "'developmentally appropriate/children' chunk is correct; 'safety' chunk also mentions "
             "EDs/interpersonal violence and could wrongly rank higher on word overlap"},

    # ============ TIER B — AnnoMI, silver topic-level ============
    # -- single_hop --
    {"id": "b01", "category": "single_hop", "risk_tier": "HIGH", "gt_tier": "B",
     "query": "person wants to reduce how much alcohol they drink",
     "gt_topic_match": "target_construct", "gt_topic_value_contains": "alcohol"},
    {"id": "b02", "category": "single_hop", "risk_tier": "HIGH", "gt_tier": "B",
     "query": "someone talking about cutting themselves",
     "gt_text_contains": "cutting"},
    {"id": "b03", "category": "single_hop", "risk_tier": "HIGH", "gt_tier": "B",
     "query": "client feeling ambivalent about making a change",
     "gt_text_contains": "ambivalen"},

    # -- paraphrase --
    {"id": "b04", "category": "paraphrase", "risk_tier": "HIGH", "gt_tier": "B",
     "query": "somebody unsure whether they actually want to quit drinking",
     "gt_topic_match": "target_construct", "gt_topic_value_contains": "alcohol"},
    {"id": "b05", "category": "paraphrase", "risk_tier": "HIGH", "gt_tier": "B",
     "query": "person self-harming by cutting their skin",
     "gt_text_contains": "cutting"},

    # -- out_of_corpus (confirmed absent via direct regex search this session) --
    {"id": "c01", "category": "out_of_corpus", "risk_tier": "HIGH", "gt_tier": "N/A",
     "query": "what to do if someone is showing signs of anorexia or bulimia",
     "gt_chunk_ids": [], "confirmed_absent_by": "regex search: eating disorder|anorexi|bulimi -> 0 hits"},
    {"id": "c02", "category": "out_of_corpus", "risk_tier": "HIGH", "gt_tier": "N/A",
     "query": "supporting someone experiencing domestic violence from a partner",
     "gt_chunk_ids": [], "confirmed_absent_by": "regex search: domestic violence|intimate partner violence -> 0 hits"},
    {"id": "c03", "category": "out_of_corpus", "risk_tier": "CRITICAL", "gt_tier": "N/A",
     "query": "someone is having a psychotic episode with hallucinations",
     "gt_chunk_ids": [], "confirmed_absent_by": "regex search: psychosis|hallucinat|delusion -> 0 hits"},
    {"id": "c04", "category": "out_of_corpus", "risk_tier": "HIGH", "gt_tier": "N/A",
     "query": "LGBTQ-specific crisis resources and considerations",
     "gt_chunk_ids": [], "confirmed_absent_by": "regex search: LGBTQ|transgender -> 0 hits"},
    {"id": "c05", "category": "out_of_corpus", "risk_tier": "CRITICAL", "gt_tier": "N/A",
     "query": "mandatory reporting requirements for suspected child abuse",
     "gt_chunk_ids": [], "confirmed_absent_by": "regex search: child abuse|mandatory report -> 0 hits"},
    {"id": "c06", "category": "out_of_corpus", "risk_tier": "HIGH", "gt_tier": "N/A",
     "query": "helping someone through a panic attack in the moment",
     "gt_chunk_ids": [], "confirmed_absent_by": "regex search: panic attack -> 0 hits"},
]

if __name__ == "__main__":
    import json
    from collections import Counter
    print(f"Total queries: {len(DEV_SET)}")
    print(Counter(q["category"] for q in DEV_SET))
    print(Counter(q["risk_tier"] for q in DEV_SET))
    print(Counter(q["gt_tier"] for q in DEV_SET))
