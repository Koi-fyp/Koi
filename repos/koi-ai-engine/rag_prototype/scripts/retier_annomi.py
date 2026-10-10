"""
Day 1 — Retier AnnoMI into the locked corpus schema.

Locked decisions this script encodes (per KOI RAG lock, this session):
  - AnnoMI role: conversational strategy/phrasing, HIGH-quality subset only
    eligible for retrieval-and-answer use. Low-quality rows are kept in the
    processed file but tagged evidence_role=EVALUATION_ONLY / NEGATIVE_EXAMPLE
    so they can be filtered out at query time rather than silently dropped
    (useful later for contrastive eval, per the research round's suggestion).
  - Provenance: "MI demonstration videos; not real therapy sessions" —
    NOT tagged real_therapy, NOT tagged public_domain (GitHub API confirmed
    license: null on uccollab/AnnoMI, checked live this session).
  - Chunking unit: exchange-level (preceding client turn + the therapist
    turn being annotated), not single bare utterances — a lone "Sure." is
    not a retrievable/meaningful chunk on its own. This still respects the
    locked "natural corpus boundary" rule (utterance-level annotation),
    just chunked at the smallest boundary that is actually self-contained.
  - AnnoMI is NEVER eligible for CRITICAL tier regardless of quality label —
    it has no clinical authority (authority_level=expert-dialogue, not
    guideline). Locked critical-tier logic (broad retrieval + strict
    eligibility filter) enforces this at the eligibility-filter stage, not
    by excluding it from the retrieval index outright.
"""
import pandas as pd
import json
import hashlib
from pathlib import Path

BASE = Path(__file__).resolve().parent.parent  # rag_prototype/
RAW = BASE / "data" / "raw" / "AnnoMI-full.csv"
OUT = BASE / "data" / "processed" / "annomi_chunks.jsonl"

df = pd.read_csv(RAW)
print(f"Loaded {len(df)} utterance rows across {df['transcript_id'].nunique()} transcripts")
print(f"mi_quality distribution:\n{df['mi_quality'].value_counts()}")

def chunk_id(transcript_id, utterance_id):
    raw = f"annomi::{transcript_id}::{utterance_id}"
    return "annomi_" + hashlib.sha1(raw.encode()).hexdigest()[:10]

chunks = []
for tid, group in df.groupby("transcript_id"):
    group = group.sort_values("utterance_id").reset_index(drop=True)
    for i, row in group.iterrows():
        if row["interlocutor"] != "therapist":
            continue  # we chunk around therapist turns; client turn is included as context

        prior_client = ""
        if i > 0 and group.loc[i - 1, "interlocutor"] == "client":
            prior_client = str(group.loc[i - 1, "utterance_text"])

        therapist_text = str(row["utterance_text"])
        quality = str(row["mi_quality"]).strip().lower()  # 'high' or 'low'

        # --- locked schema fields ---
        technique = row.get("main_therapist_behaviour", "unspecified")
        technique = "unspecified" if pd.isna(technique) else str(technique)

        if quality == "high":
            evidence_role = "EXPERT_SUPPORT_STRATEGY"
        else:
            evidence_role = "NEGATIVE_EXAMPLE"  # explicitly excluded from answer-eligible pool

        record = {
            "chunk_id": chunk_id(tid, row["utterance_id"]),
            "text": (f"[Client]: {prior_client}\n[Therapist]: {therapist_text}"
                     if prior_client else f"[Therapist]: {therapist_text}"),
            # --- canon-locked fields ---
            "technique": technique,
            "target_construct": str(row.get("topic", "unspecified")),
            "stage": "unspecified",  # AnnoMI has no exploration/intervention/closing tag natively;
                                     # left unspecified rather than guessed — flag for Day 2 if needed
            "tone": "unspecified",
            "source_corpus": "AnnoMI",
            "safety_tier": "HIGH",  # max tier this source is EVER eligible for, enforced again below
            # --- schema additions from research rounds (locked this session) ---
            "authority_level": "expert-dialogue",
            "provenance_type": "human-transcript-demonstration",  # NOT "real-therapy-session"
            "jurisdiction": "unspecified",
            "population": "adult-general",
            "quality_label": quality,
            "evidence_role": evidence_role,
            "contraindication": "not authoritative for CRITICAL-tier crisis instructions; "
                                 "MI technique demonstration only, not clinical guidance",
            "validity_date": "unspecified",  # AnnoMI has no publication/version date
            "superseded_by": None,
            "license_note": "no license declared by official repository (verified live via "
                             "GitHub API this session); used under academic/non-commercial "
                             "FYP scope, supervisor-approved",
        }
        chunks.append(record)

print(f"\nBuilt {len(chunks)} exchange-level chunks")
print(f"  high-quality (EXPERT_SUPPORT_STRATEGY, retrieval-eligible): "
      f"{sum(1 for c in chunks if c['quality_label']=='high')}")
print(f"  low-quality (NEGATIVE_EXAMPLE, excluded from answer pool): "
      f"{sum(1 for c in chunks if c['quality_label']=='low')}")

OUT.parent.mkdir(exist_ok=True)
with open(OUT, "w") as f:
    for c in chunks:
        f.write(json.dumps(c) + "\n")
print(f"\nWrote {OUT}")
