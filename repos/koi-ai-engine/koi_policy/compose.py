"""
How one exercise reply is put together (design choice B, Oct 15: sentence-gated release).

  reply = [short acknowledgement written by the companion LLM]  +  [fixed step line(s) from journeys.json]

The LLM never writes the instruction, the safety line, a number or a question inside an exercise: those are the
fixed lines. It only adds a short, warm acknowledgement of what the user said, so the avatar still sounds like
itself. Every LLM sentence is checked the moment it is complete and released only if it passes, which is the same
granularity canon already uses for TTS ("TTS = STREAMED per completed sentence", Blueprint §4.1e). A sentence
that fails stops the LLM part; if nothing was released yet the LLM gets ONE retry, then a reviewed fallback
acknowledgement is used. The user cannot tell which path ran.

phrase_fn contract (what the backend adapter must provide; a stub is used in tests):
    phrase_fn(direction: dict) -> (companion_state: dict | None, tokens: iterable of str)
`direction_prompt(direction)` renders the hidden stage direction the backend appends to the system prompt; with
vLLM structured outputs the reply JSON stays {companion_state, reply} (companion_state first, as locked).
"""
import re

import catalogue as C
import intents as I

EMOTIONS = ("neutral", "joy", "angry", "sorrow", "fun")      # canon: the 5 strict emotion strings
EXERCISE_EMOTIONS = {"neutral", "joy", "sorrow"}              # inside an exercise: never angry or playful
ACK_MAX_WORDS = 25
ACK_MAX_SENTENCES = 2
LANG_NAMES = {"en": "English", "ur": "Urdu (Urdu script)", "ur-roman": "Roman Urdu (Latin script, English mixing is fine)"}

_BANNED = [  # beyond the catalogue veto list: things an acknowledgement must never do inside an exercise
    (re.compile(r"[?؟]"), "asks a question (the fixed line asks)"),
    (re.compile(r"\d|[۰-۹٠-٩]"), "contains a number (timings/counts come from the fixed line)"),
    (re.compile(r"\b(seconds?|minutes?|breaths? per|times a)\b", re.I), "gives a timing"),
    (re.compile(r"\b(deep breaths?|breathe deeply|hold (your|the) breath|gehri saans|saans rok)\b|گہری سانس|سانس روک", re.I),
     "breathing instruction outside the fixed line"),
    (re.compile(r"\b(you look|you seem calmer|i can see you|i see you|i can hear you|dikh rahe|lag rahe ho)\b", re.I),
     "claims to see/observe the user"),
    (re.compile(r"\b(diagnos\w*|disorder|medication|cure|guarantee)\b", re.I), "clinical claim"),
]


def safe_companion_state(cs, default=("neutral", 0.4)):
    try:
        e = cs.get("emotion")
        x = float(cs.get("intensity", default[1]))
    except Exception:  # noqa: BLE001
        return {"emotion": default[0], "intensity": default[1]}
    if e not in EMOTIONS or e not in EXERCISE_EMOTIONS:
        e = default[0]
    return {"emotion": e, "intensity": min(max(x, 0.0), 1.0)}


def check_sentence(s, lang):
    """None if the sentence may be released, else the reason it may not."""
    if not s.strip():
        return "empty"
    for rx, why in _BANNED:
        if rx.search(s):
            return why
    hits = C.veto_hits(s)
    if hits:
        return f"veto: {hits}"
    urdu = I.has_urdu_script(s)
    if lang == "ur" and not urdu:
        return "wrong script (expected Urdu script)"
    if lang in ("en", "ur-roman") and urdu:
        return "wrong script (expected Latin)"
    return None


_END = re.compile(r"([.!۔]+|\n)")


def release_by_sentence(tokens, lang, max_sentences=ACK_MAX_SENTENCES, max_words=ACK_MAX_WORDS):
    """Consume LLM tokens; return (released_sentences, failure_reason_or_None). Released = checked and passed."""
    buf, out, words = "", [], 0
    it = iter(tokens)
    while True:
        tok = next(it, None)
        if tok is not None:
            buf += tok
        parts = _END.split(buf)
        # parts: text, sep, text, sep, ..., tail
        complete = []
        while len(parts) >= 3:
            complete.append((parts[0] + parts[1]).strip())
            parts = parts[2:]
        buf = parts[0] if parts else ""
        if tok is None and buf.strip():
            complete.append(buf.strip())
            buf = ""
        for s in complete:
            if not s:
                continue
            why = check_sentence(s, lang)
            words += len(s.split())
            if why is None and (len(out) >= max_sentences or words > max_words):
                why = "too long"
            if why:
                return out, why
            out.append(s)
        if tok is None:
            return out, None


def direction(goal, lang, user_text, next_line, exercise_title):
    return {"goal": goal, "lang": lang, "user_text": user_text, "next_line": next_line,
            "exercise": exercise_title, "max_words": ACK_MAX_WORDS}


def direction_prompt(d):
    return (f"[Stage direction, never shown to the user] You are KOI, a warm companion, in the middle of "
            f"'{d['exercise']}' with the user. Write ONLY a short acknowledgement of the user's last message: "
            f"{d['goal']} Language: {LANG_NAMES.get(d['lang'], d['lang'])}. At most {d['max_words']} words and two "
            f"sentences. Do not ask a question. Do not give instructions, numbers, timings, advice or diagnoses. "
            f"Do not say you can see or hear the user. Your words will be followed by this fixed line: "
            f"\"{d['next_line']}\"")


def acknowledge(phrase_fn, d, fallbacks, seed, default_state=("neutral", 0.4)):
    """-> (companion_state, sentences, source, notes). source: 'generated' | 'fallback'."""
    notes = []
    if phrase_fn is not None:
        for attempt in (1, 2):
            dd = dict(d, retry=attempt == 2)
            try:
                cs, toks = phrase_fn(dd)
            except Exception as e:  # noqa: BLE001  (model down/timeout -> reviewed fallback)
                notes.append(f"phrase_fn error: {e!r}")
                break
            sents, why = release_by_sentence(toks, d["lang"])
            if sents:
                if why:
                    notes.append(f"attempt {attempt}: kept {len(sents)} sentence(s), cut at: {why}")
                return safe_companion_state(cs or {}, default_state), sents, "generated", notes
            notes.append(f"attempt {attempt} rejected: {why}")
    fb = fallbacks[seed % len(fallbacks)] if fallbacks else ""
    return ({"emotion": default_state[0], "intensity": default_state[1]}, [fb] if fb else [], "fallback", notes)


def split_fixed(text):
    """Fixed lines are released as whole sentences too (they are pre-reviewed, so no check)."""
    parts = [p.strip() for p in re.split(r"(?<=[.!?۔؟])\s+", text or "") if p.strip()]
    return parts
