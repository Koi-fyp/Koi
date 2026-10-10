"""
Day 1 — Chunk WHO mhGAP + SAMHSA into the locked corpus schema.

Both are the AUTHORITATIVE tier (evidence_role = AUTHORITATIVE_*), the only
tier eligible for CRITICAL-risk queries per the locked critical-tier logic
(broad retrieval + strict eligibility filter at answer-generation stage).
"""
import json
import hashlib
import re
from pathlib import Path

BASE = Path(__file__).resolve().parent.parent
OUT = BASE / "data" / "processed" / "authoritative_chunks.jsonl"

def cid(prefix, text):
    return prefix + "_" + hashlib.sha1(text.encode()).hexdigest()[:10]

chunks = []

# ---------- WHO mhGAP ----------
who_raw = (BASE / "data" / "raw" / "who_mhgap_sui.txt").read_text()
for block in who_raw.split("===CHUNK===")[1:]:
    lines = [l.strip() for l in block.strip().split("\n") if l.strip()]
    fields = {}
    text_lines = []
    in_text = False
    for l in lines:
        if l.startswith("Text:"):
            in_text = True
            text_lines.append(l[len("Text:"):].strip())
        elif in_text:
            text_lines.append(l)
        elif ":" in l:
            k, v = l.split(":", 1)
            fields[k.strip()] = v.strip()
    text = " ".join(text_lines).strip()
    if not text:
        continue

    is_recommendation = "Recommendation" in fields
    chunks.append({
        "chunk_id": cid("who", text),
        "text": text,
        "technique": "safety-planning" if "SUI1" in fields.get("Recommendation", "") else
                     "digital-intervention" if "SUI3" in fields.get("Recommendation", "") else "unspecified",
        "target_construct": "self-harm-and-suicide",
        "stage": "intervention" if is_recommendation else "unspecified",
        "tone": "clinical-authoritative",
        "source_corpus": "WHO_mhGAP_2023",
        "safety_tier": "CRITICAL",  # highest tier this source is eligible for
        "authority_level": "guideline",
        "provenance_type": "who-published-guideline",
        "jurisdiction": "global",
        "population": "general-adult",  # mhGAP targets non-specialist settings broadly; not age-restricted in SUI module
        "quality_label": "n/a",  # not applicable to guideline text
        "evidence_role": "AUTHORITATIVE_RECOMMENDATION" if is_recommendation else "AUTHORITATIVE_DEFINITION",
        "contraindication": fields.get("Certainty of evidence", "") and
                             f"certainty of evidence: {fields.get('Certainty of evidence')} — conditional recommendation, not a strong/universal directive"
                             if fields.get("Strength of recommendation") == "Conditional" else "",
        "validity_date": "2023-11-20",
        "superseded_by": None,
        "license_note": "CC BY-NC-SA 3.0 IGO — non-commercial, share-alike; verified live via WHO's own front-matter "
                         "text this session. Compatible with this project's confirmed non-commercial academic scope.",
    })

# ---------- SAMHSA ----------
samhsa_raw = (BASE / "data" / "raw" / "samhsa_2025_guidelines.txt").read_text()
for block in samhsa_raw.split("===SECTION:")[1:]:
    header_line, _, rest = block.partition("\n")
    title_match = re.search(r"TITLE:\s*(.+)", rest)
    text_match = re.search(r"TEXT:\s*(.+)", rest, re.DOTALL)
    title = title_match.group(1).strip() if title_match else header_line.strip()
    text = text_match.group(1).strip() if text_match else ""
    if not text:
        continue

    is_principle = "Principle" in header_line
    # BUG FIX (Day 2): originally checked `header_line` (the ===SECTION:=== line),
    # but "988"/"Hotline" only appear in the TITLE: line for some sections
    # (e.g. "Suicide Risk Assessment Best Practice" section, whose TITLE is
    # "Other Behavioral Health Crisis Hotlines — Suicide Risk Assessment").
    # Caught during Day 2 dev-set inspection — samhsa_c744348b34 was mistagged
    # AUTHORITATIVE_PRINCIPLE instead of AUTHORITATIVE_PROCEDURE.
    is_988 = "988" in header_line or "Hotline" in header_line or "988" in title or "Hotline" in title

    chunks.append({
        "chunk_id": cid("samhsa", text[:200]),
        "text": f"[{title}] {text}",
        "technique": "safety-planning" if "safety plan" in text.lower() else
                     "risk-assessment" if "risk assessment" in text.lower() else
                     "crisis-line-protocol" if is_988 else "system-principle",
        "target_construct": "crisis-system-principle" if is_principle else "crisis-line-service",
        "stage": "unspecified",
        "tone": "clinical-authoritative",
        "source_corpus": "SAMHSA_2025",
        "safety_tier": "CRITICAL",
        "authority_level": "guideline",
        "provenance_type": "samhsa-published-guideline",
        "jurisdiction": "US",  # explicit — do not treat as globally applicable, per locked jurisdiction field rationale
        "population": "general-adult",
        "quality_label": "n/a",
        "evidence_role": "AUTHORITATIVE_PROCEDURE" if is_988 else "AUTHORITATIVE_PRINCIPLE",
        "contraindication": "US-specific system (988, 911, CCBHC, state-level infrastructure) — "
                             "not directly applicable as jurisdiction-agnostic guidance",
        "validity_date": "2025-01-15",
        "superseded_by": None,
        "license_note": "Public Domain Notice (SAMHSA) — verified live via publication front matter this session. "
                         "Fee-distribution requires separate written authorization; non-fee academic use unrestricted.",
    })

OUT.parent.mkdir(exist_ok=True)
with open(OUT, "w") as f:
    for c in chunks:
        f.write(json.dumps(c) + "\n")

who_n = sum(1 for c in chunks if c["source_corpus"] == "WHO_mhGAP_2023")
samhsa_n = sum(1 for c in chunks if c["source_corpus"] == "SAMHSA_2025")
print(f"WHO mhGAP chunks: {who_n}")
print(f"SAMHSA chunks: {samhsa_n}")
print(f"Total authoritative-tier chunks: {len(chunks)}")
print(f"Wrote {OUT}")
