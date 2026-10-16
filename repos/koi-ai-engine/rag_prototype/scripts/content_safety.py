"""
Content safety for the crisis path (M2, Oct 13 2026). Two fail-closed checks applied to the router's served items
before anything reaches the user. Neither changes the ranking or the gate; they can only REMOVE items. If nothing
survives, the response is the deterministic fallback.

1. AUDIENCE table (state file v1 §10 item 11, "audience split -- undecided"). One row per pool chunk.
   STATUS: [PROPOSED by Claude from a static read of the 22 texts, Oct 13 2026] -- Ahmad has NOT approved it.
   Only rows tagged "user-facing" are ever shown. Unknown chunk ids are treated as "clinician" (fail-closed).
   To change a decision, edit the tag below; nothing else needs to change.
2. LEXICAL VETO (state file v1 §3 item 8, LOCKED: "output validator ... fail-closed"; this is the lexical half,
   the NLI half is cut). Any item whose text matches a pattern is removed, whatever its audience tag.

Run eval/content_review.py to print the table with veto hits.
"""
import re

USER_FACING, CLINICIAN = "user-facing", "clinician"

# chunk_id -> (tag, reason). Reasons are Claude's reading, not a clinician's.
AUDIENCE = {
    # --- user-facing candidates: questions addressed to the person ("you"), no assessment/method content
    "mhgappk_480c27df26": (USER_FACING, "reflective questions about comfort and support, addressed to the person"),
    "mhgappk_bfba6f6671": (USER_FACING, "reflective questions about sources of stress, addressed to the person"),
    "mhgappk_11f0557fbc": (USER_FACING, "reflective questions about worries, coping and family support"),
    # --- clinician / service-design text
    "mhgappk_bf203e39f6": (CLINICIAN, "clinician suicide-assessment script ('MNS assessment'; asks about plans to end life)"),
    "mhgappk_028b8b03ca": (CLINICIAN, "management principles for clinicians and carers"),
    "mhgappk_8ae903049e": (CLINICIAN, "instructs the clinician ('interview the person', 'talk with your supervisor')"),
    "mhgappk_4174e3caad": (CLINICIAN, "advice to clinicians about carers' stress"),
    "who_a53d6078d3": (CLINICIAN, "guideline recommendation with evidence grading"),
    "who_262440fba5": (CLINICIAN, "evidence statement about media campaigns"),
    "who_466ea20335": (CLINICIAN, "guideline recommendation with evidence grading"),
    "who_bea4d647aa": (CLINICIAN, "clinical definition of self-harm (names poisoning)"),
    "who_250f535470": (CLINICIAN, "clinical definition of suicidal ideation"),
    "samhsa_c65d0b35bb": (CLINICIAN, "US crisis-system design; cites 911, HIPAA"),
    "samhsa_983fdc952b": (CLINICIAN, "US crisis-system design; long; names overdose, homicidal thoughts"),
    "samhsa_07f07c54c2": (CLINICIAN, "US crisis-system equity policy"),
    "samhsa_39eaeaebcb": (CLINICIAN, "crisis-system quality improvement"),
    "samhsa_ba841557a7": (CLINICIAN, "service design for children and older adults"),
    "samhsa_d8ce247ecc": (CLINICIAN, "service design, recovery orientation"),
    "samhsa_21fe845e34": (CLINICIAN, "service design, trauma-informed principles"),
    "samhsa_8ebc7bced3": (CLINICIAN, "service design, follow-up teams"),
    "samhsa_28a1f6c98e": (CLINICIAN, "provider-organisation guidance"),
    "samhsa_38dea1e07c": (CLINICIAN, "US service design; Service Members/Veterans"),
}

# Lexical veto. Case-insensitive, matched on the item text. Kept short and auditable.
VETO_PATTERNS = {
    "dosing": [r"\b\d+\s?(mg|ml|mcg)\b", r"\bdos(e|es|age|ing)\b", r"\btablets?\b", r"\bprescri\w*", r"\bmedications?\b"],
    "diagnosis": [r"\bdiagnos\w*", r"\bdisorders?\b", r"\byou (have|suffer from)\b"],
    "means_or_method": [r"\boverdos\w*", r"\bpoison\w*", r"\bhang(ing|ed)?\b", r"\blethal\b", r"\bweapons?\b",
                        r"\bpesticides?\b", r"plans? to end your life", r"ways? to (end|kill)"],
    "foreign_emergency_number": [r"\b911\b", r"\b988\b"],
}
_COMPILED = [(cat, re.compile(p, re.I)) for cat, ps in VETO_PATTERNS.items() for p in ps]


def veto_hits(text):
    """List of (category, matched text) for every veto pattern found in text."""
    return [(cat, m.group(0)) for cat, rx in _COMPILED for m in [rx.search(text or "")] if m]


def is_servable(chunk):
    """True only if the chunk is tagged user-facing AND its text has no veto hit. Unknown ids -> False."""
    tag = AUDIENCE.get(chunk.get("chunk_id"), (CLINICIAN, "unknown id"))[0]
    return tag == USER_FACING and not veto_hits(chunk.get("text", ""))


def filter_indices(indices, chunks):
    """Keep only servable chunk indices, preserving order. Used by CrisisRouter.respond and ContentBuilder."""
    return [int(i) for i in indices if is_servable(chunks[int(i)])]
