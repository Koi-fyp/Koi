"""
Exercise catalogue: loading, validation and eligibility (which exercises may be offered, when). Oct 14 2026.
DRAFT by Claude. Works with policy.py: policy decides WHETHER to offer (OFFER_GROUNDING / OFFER_CBT);
eligible() decides WHICH exercises are allowed for the current tier and context.

Rules:
  E1  CRITICAL -> nothing, in any context (PM+ and THP exclude imminent suicide risk; helplines only).
  E2  HIGH -> only crisis_modal_ok (calm-body) exercises, only inside the crisis modal, below the helplines,
      never auto-started (Decision 2; Ahmad Oct 15: prefer the wider pool).
  E3  LOW / MODERATE -> exercises whose offer_when contains the tier (system offers).
  E4  user_initiated / cbt_module exercises are never system-offered; the user can still choose any exercise
      from the menu (below HIGH), and CBT-module exercises run inside the CBT module.
  E5  Unknown tier -> ValueError (uses policy.parse_tier).
"""
import json
import re
from pathlib import Path

import policy

HERE = Path(__file__).resolve().parent
TYPES = {"paced_breathing", "stepwise", "conversation"}
ANSWERS = {"text", "text_optional", "text_list", "number_0_100", "number_0_10", "yes_no", "choice_or_text",
           "choice_from_options"}
# same categories as koi_rag/scripts/content_safety.py lexical veto (kept local so this package stands alone)
VETO = {
    "dosing": [r"\b\d+\s?(mg|ml|mcg)\b", r"\bdos(e|es|age|ing)\b", r"\btablets?\b", r"\bprescri\w*", r"\bmedications?\b"],
    "diagnosis": [r"\bdiagnos\w*", r"\bdisorders?\b", r"\byou (have|suffer from)\b"],
    "means_or_method": [r"\boverdos\w*", r"\bpoison\w*", r"\bhang(ing|ed)?\b", r"\blethal\b", r"\bweapons?\b",
                        r"\bpesticides?\b", r"plans? to end your life", r"ways? to (end|kill)"],
    "foreign_emergency_number": [r"\b911\b", r"\b988\b"],
}
_VETO = [(c, re.compile(p, re.I)) for c, ps in VETO.items() for p in ps]


def load(path=HERE / "exercises.json"):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def user_facing_text(ex):
    """All strings in an exercise that a user could see."""
    out = [ex.get(k, "") for k in ("title", "what_is_it", "intro", "outro", "reflection", "stop_if")]
    out += ex.get("steps", []) + [p["ask"] for p in ex.get("prompts", [])] + [ph["label"] for ph in ex.get("phases", [])]
    out += ex.get("activity_examples", []) + ex.get("value_examples", []) + ex.get("examples_for_loneliness", [])
    out += ex.get("cautions", [])
    return [s for s in out if s]


def veto_hits(text):
    return [(c, m.group(0)) for c, rx in _VETO for m in [rx.search(text)] if m]


def validate(cat):
    """List of problems (empty = valid)."""
    errs, ids = [], set()
    for ex in cat["exercises"]:
        i = ex.get("id", "?")
        if i in ids:
            errs.append(f"{i}: duplicate id")
        ids.add(i)
        for k in ("title", "family", "type", "ux_flows", "activity_type", "source", "licence", "offer_when",
                  "crisis_modal_ok", "what_is_it", "intro"):
            if k not in ex:
                errs.append(f"{i}: missing {k}")
        if ex.get("type") not in TYPES:
            errs.append(f"{i}: unknown type {ex.get('type')}")
        if not set(ex.get("offer_when", [])) <= {"LOW", "MODERATE"}:
            errs.append(f"{i}: offer_when may only contain LOW/MODERATE (HIGH via crisis_modal_ok; never CRITICAL)")
        if (ex.get("user_initiated_only") or ex.get("cbt_module")) and ex.get("offer_when"):
            errs.append(f"{i}: user-initiated/CBT-module exercise must not be system-offered")
        if ex.get("crisis_modal_ok") and (ex.get("family") != "calm_body" or ex.get("user_initiated_only")):
            errs.append(f"{i}: only calm-body, offerable exercises may appear in the crisis modal")
        if ex.get("type") == "paced_breathing":
            if any("hold" in ph["label"].lower() for ph in ex.get("phases", [])):
                errs.append(f"{i}: breath-hold phase not allowed")
            if "deep breath" in json.dumps(ex).lower().replace("not deep ones", ""):
                errs.append(f"{i}: 'deep breath' wording not allowed (WHO DWM dizziness caution)")
        if ex.get("type") == "stepwise" and not ex.get("steps"):
            errs.append(f"{i}: stepwise without steps")
        if ex.get("type") == "conversation":
            ps = ex.get("prompts", [])
            if not ps:
                errs.append(f"{i}: conversation without prompts")
            if len({p["key"] for p in ps}) != len(ps):
                errs.append(f"{i}: duplicate prompt keys")
            errs += [f"{i}: unknown answer type {p['answer']}" for p in ps if p["answer"] not in ANSWERS]
        for s in user_facing_text(ex):
            for c, t in veto_hits(s):
                errs.append(f"{i}: veto {c}:{t!r} in {s[:60]!r}")
    for n in cat.get("NUMBERS", []):
        if not (n.get("status") and n.get("source")):
            errs.append(f"NUMBERS entry {n.get('what')!r} lacks status or source")
    for alt in cat["decline_followup"]["alternatives"].values():
        for x in alt.get("offer_exercises", []):
            if x not in ids:
                errs.append(f"decline alternative points to unknown exercise {x}")
    return errs


def eligible(cat, tier, context="chat"):
    """context: 'chat' (system offer), 'menu' (user browsing), 'crisis_modal', 'cbt_module'. Returns ids."""
    t = policy.parse_tier(tier)
    if context not in ("chat", "menu", "crisis_modal", "cbt_module"):
        raise ValueError(f"unknown context {context!r}")
    if t == "CRITICAL":
        return []                                                    # E1
    exs = cat["exercises"]
    if t == "HIGH":                                                   # E2
        return [e["id"] for e in exs if e["crisis_modal_ok"]] if context == "crisis_modal" else []
    if context == "crisis_modal":
        return []
    if context == "chat":                                             # E3
        return [e["id"] for e in exs if t in e["offer_when"]]
    if context == "menu":                                             # E4: user chooses; everything below HIGH
        return [e["id"] for e in exs]
    return [e["id"] for e in exs if e.get("cbt_module") or e["family"] in ("thoughts", "doing", "connection")]


if __name__ == "__main__":
    c = load()
    problems = validate(c)
    print("catalogue problems:", problems or "none")
    for tier in policy.TIERS:
        for ctx in ("chat", "menu", "crisis_modal", "cbt_module"):
            print(f"{tier:9} {ctx:13} {eligible(c, tier, ctx)}")


# ---- languages ----------------------------------------------------------------------------------------
LANGS = ("en", "ur", "ur-roman")
# Minimal veto terms for translated text (Urdu script / Roman Urdu). Not exhaustive; reviewer should extend.
VETO_I18N = [re.compile(p, re.I) for p in (r"زہر", r"گولیاں", r"پھندا", r"\bzehr\b", r"\bgoliy?an\b", r"\bphanda\b",
                                            r"\boverdose\b", r"\b911\b", r"\b988\b")]
_LIST_FIELDS = ("steps", "cautions", "activity_examples", "value_examples", "examples_for_loneliness")


def load_i18n(path=HERE / "exercises_i18n.json"):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def localize(cat, i18n, lang):
    """Return a copy of the catalogue with every user-facing string in `lang` (English is the source)."""
    import copy
    if lang not in LANGS:
        raise ValueError(f"unknown language {lang!r}")
    c = copy.deepcopy(cat)
    c["ui"] = i18n["ui"][lang]
    c["lang"] = lang
    if lang == "en":
        return c
    t = i18n[lang]
    c["offer"].update(t["offer"])
    alts = list(c["decline_followup"]["alternatives"].values())
    c["decline_followup"]["text"] = t["decline_followup"]["text"]
    c["decline_followup"]["alternatives"] = {}
    for btn, alt, tr in zip(t["decline_followup"]["buttons"], alts, t["decline_followup"]["alternatives"]):
        c["decline_followup"]["alternatives"][btn] = {**alt, **tr}
    c["decline_followup"]["buttons"] = t["decline_followup"]["buttons"]
    c["safety_note"] = t["safety_note"]
    pc = t["post_check"]
    c["post_check"].update({k: v for k, v in pc.items() if k != "scale"})
    c["post_check"]["scale"].update(pc["scale"])
    for ex in c["exercises"]:
        tr = t["exercises"][ex["id"]]
        for k in ("title", "what_is_it", "intro", "outro", "reflection", "stop_if", "save") + _LIST_FIELDS:
            if k in tr:
                ex[k] = tr[k]
        for ph, lab in zip(ex.get("phases", []), tr.get("phases", [])):
            ph["label"] = lab
        for o, lab in zip(ex.get("duration_options", []), tr.get("duration_options", [])):
            o["label"] = lab
        for p, ask in zip(ex.get("prompts", []), tr.get("prompts", [])):
            p["ask"] = ask
            if "if_no" in p and "if_no" in tr:
                p["if_no"] = tr["if_no"]
        if "if_commitment_below" in ex:
            ex["if_commitment_below"]["say"] = tr["if_commitment_below"]
    return c


def validate_i18n(cat, i18n):
    """Every English user-facing string has a translation of the same shape in each language."""
    errs = []
    ui_keys = set(i18n["ui"]["en"])
    for lang in ("ur", "ur-roman"):
        if set(i18n["ui"][lang]) != ui_keys:
            errs.append(f"{lang}: ui keys differ from en")
        t = i18n.get(lang, {})
        if len(t["offer"]["buttons"]) != len(cat["offer"]["buttons"]):
            errs.append(f"{lang}: offer buttons count")
        if len(t["decline_followup"]["buttons"]) != len(cat["decline_followup"]["buttons"]):
            errs.append(f"{lang}: decline buttons count")
        if len(t["decline_followup"]["alternatives"]) != len(cat["decline_followup"]["alternatives"]):
            errs.append(f"{lang}: decline alternatives count")
        for ex in cat["exercises"]:
            i = ex["id"]
            tr = t["exercises"].get(i)
            if tr is None:
                errs.append(f"{lang}: {i} missing")
                continue
            for k in ("title", "what_is_it", "intro", "outro", "reflection", "stop_if", "save"):
                if k in ex and not str(tr.get(k, "")).strip():
                    errs.append(f"{lang}: {i}.{k} missing")
            for k in _LIST_FIELDS:
                if len(ex.get(k, [])) != len(tr.get(k, [])):
                    errs.append(f"{lang}: {i}.{k} has {len(tr.get(k, []))} items, English has {len(ex.get(k, []))}")
            for k, src in (("phases", ex.get("phases", [])), ("duration_options", ex.get("duration_options", [])),
                           ("prompts", ex.get("prompts", []))):
                if len(src) != len(tr.get(k, [])):
                    errs.append(f"{lang}: {i}.{k} has {len(tr.get(k, []))} items, English has {len(src)}")
            if any("if_no" in p for p in ex.get("prompts", [])) and not tr.get("if_no"):
                errs.append(f"{lang}: {i}.if_no missing")
            if "if_commitment_below" in ex and not tr.get("if_commitment_below"):
                errs.append(f"{lang}: {i}.if_commitment_below missing")
        loc = localize(cat, i18n, lang)
        for ex in loc["exercises"]:
            for s in user_facing_text(ex):
                if any(rx.search(s) for rx in VETO_I18N):
                    errs.append(f"{lang}: {ex['id']}: veto term in {s[:50]!r}")
    return errs
