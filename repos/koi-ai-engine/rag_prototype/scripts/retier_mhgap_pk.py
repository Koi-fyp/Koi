"""
Chunk mhGAP-HIG-PK (Pakistan-adapted mhGAP-HIG) into the locked corpus schema.

NEW SCHEMA FIELD introduced here: `language` -- one of en / ur / bilingual.
Rationale: every prior corpus source is English-only, so the field was never
needed. mhGAP-HIG-PK is the first genuinely bilingual source, and the field is
required for (a) language-routed retrieval and (b) selecting the correct
CRITICAL-tier fallback text. Added to this source's chunks only; existing
chunks default to `en` at load time (see retrieval_pipeline.load_corpus).

AUTHORITY: this is a government-published, Delphi-validated (per Humayun et al.
2025), clinically-reviewed adaptation -- authority_level=guideline, and the
FIRST source in the corpus with jurisdiction=Pakistan. That makes it the
highest-relevance authoritative source for this project's actual user base.

REVIEW GATE (enforced in the data, not just documented): every chunk carrying
Urdu is tagged review_status=pending-native-review. The answer-stage eligibility
filter must treat pending-native-review Urdu as NOT eligible for CRITICAL-tier
answers until that status changes. Transcription was done carefully from clean
page images, but "carefully transcribed by Claude" is not the same standard as
"verified by a native speaker", and crisis text is exactly where that gap
matters. See the raw file's REVIEW STATUS note.
"""
import json
import hashlib
import re
from pathlib import Path

BASE = Path(__file__).resolve().parent.parent
RAW = BASE / "data" / "raw" / "mhgap_hig_pk_bilingual.txt"
OUT = BASE / "data" / "processed" / "mhgap_pk_chunks.jsonl"


def cid(text):
    return "mhgappk_" + hashlib.sha1(text.encode("utf-8")).hexdigest()[:10]


def parse_blocks(raw_text):
    blocks = []
    for block in raw_text.split("===CHUNK===")[1:]:
        lines = [l.rstrip() for l in block.strip().split("\n") if l.strip()]
        meta = {}
        en_lines, ur_lines, pairs = [], [], []
        pending_en = None
        for line in lines:
            if line.startswith("ID:"):
                meta["id"] = line[3:].strip()
            elif line.startswith("Module:"):
                meta["module"] = line[7:].strip()
            elif line.startswith("Source page:"):
                meta["page"] = line[12:].strip()
            elif line.startswith("Title:"):
                meta["title"] = line[6:].strip()
            elif line.startswith("EN_CONTEXT:"):
                meta["context"] = line[11:].strip()
            elif line.startswith("EN_ONLY:"):
                meta["en_only"] = line[8:].strip()
            elif line.startswith("EN:"):
                pending_en = line[3:].strip()
                en_lines.append(pending_en)
            elif line.startswith("UR:"):
                ur = line[3:].strip()
                ur_lines.append(ur)
                if pending_en:
                    pairs.append((pending_en, ur))
                    pending_en = None
        meta["en_lines"] = en_lines
        meta["ur_lines"] = ur_lines
        meta["pairs"] = pairs
        blocks.append(meta)
    return blocks


def build_chunks(blocks):
    chunks = []
    for b in blocks:
        title = b.get("title", "")
        module = b.get("module", "")
        page = b.get("page", "")
        has_urdu = len(b["ur_lines"]) > 0

        if b.get("en_only"):
            text = f"[{title}] {b['en_only']}"
            language = "en"
        else:
            parts = []
            if b.get("context"):
                parts.append(b["context"])
            for en, ur in b["pairs"]:
                parts.append(f"{en}\n{ur}")
            # any EN line without a UR partner
            paired_en = {en for en, _ in b["pairs"]}
            for en in b["en_lines"]:
                if en not in paired_en:
                    parts.append(en)
            text = f"[{title}] " + "\n".join(parts)
            language = "bilingual" if has_urdu else "en"

        # SUI-assessment content is the crisis-critical chunk; everything else
        # in this batch is supportive/assessment context.
        is_sui = "sui" in b.get("id", "").lower()

        chunks.append({
            "chunk_id": cid(b.get("id", title)),
            "text": text,
            # --- canon-locked fields ---
            "technique": "risk-assessment" if is_sui else
                         "stress-management" if "stress" in b.get("id", "") else
                         "social-support" if "social_support" in b.get("id", "") else
                         "general-principle",
            "target_construct": "self-harm-and-suicide" if is_sui else "psychosocial-support",
            "stage": "assessment" if "assessment" in b.get("id", "") else "intervention",
            "tone": "clinical-authoritative",
            "source_corpus": "mhGAP_HIG_PK_2023",
            "safety_tier": "CRITICAL",
            # --- schema additions ---
            "authority_level": "guideline",
            "provenance_type": "pakistan-government-adapted-guideline",
            "jurisdiction": "Pakistan",
            "population": "general-adult",
            "quality_label": "n/a",
            "evidence_role": "AUTHORITATIVE_PROCEDURE" if is_sui else "AUTHORITATIVE_PRINCIPLE",
            "contraindication": "clinician-facing assessment script, adapted for Pakistani "
                                 "primary-care context; not patient-facing self-help text",
            "validity_date": "2023",
            "superseded_by": None,
            # --- NEW: language + review gate ---
            "language": language,
            "review_status": "pending-native-review" if has_urdu else "not-required",
            "source_page": page,
            "source_module": module,
            "license_note": "Government of Pakistan (MoPD&SI) publication, adapted from WHO/UNHCR "
                             "mhGAP-HIG (CC BY-NC-SA 3.0 IGO). Publicly hosted at pc.gov.pk. "
                             "Used under this project's confirmed non-commercial academic scope. "
                             "Explicit reuse terms not stated in source front matter -- outreach to "
                             "mhpsspk@gmail.com drafted to confirm.",
        })
    return chunks


if __name__ == "__main__":
    raw = RAW.read_text(encoding="utf-8")
    blocks = parse_blocks(raw)
    chunks = build_chunks(blocks)

    OUT.parent.mkdir(exist_ok=True, parents=True)
    with open(OUT, "w", encoding="utf-8") as f:
        for c in chunks:
            f.write(json.dumps(c, ensure_ascii=False) + "\n")

    bilingual = sum(1 for c in chunks if c["language"] == "bilingual")
    en_only = sum(1 for c in chunks if c["language"] == "en")
    pending = sum(1 for c in chunks if c["review_status"] == "pending-native-review")
    print(f"mhGAP-HIG-PK chunks: {len(chunks)}")
    print(f"  bilingual (EN+UR): {bilingual}")
    print(f"  English-only:      {en_only}")
    print(f"  pending native review (NOT CRITICAL-eligible until reviewed): {pending}")
    print(f"Wrote {OUT}")
