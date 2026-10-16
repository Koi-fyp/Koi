"""
Language/script detector — English / native Urdu / Roman Urdu / code-switched.

Single detector, four consumers (per Blueprint's own "reuse the same
language-routing decision" principle, stated for TTS voice selection and
Rhubarb recognizer mode, and now extended to RAG and fallback-text
selection rather than building a second detector for those):
  1. TTS voice selection (English Piper voice vs ur_PK-fasih-medium)
  2. Rhubarb recognizer mode (PocketSphinx vs phonetic)
  3. RAG query normalization (Roman Urdu -> normalized form before retrieval)
  4. CRITICAL-tier deterministic fallback text selection (EN vs UR version)

NOT a trained model -- a fast, dependency-light heuristic, appropriate for
a routing decision that needs to run inline, not a classification task
that needs high accuracy on hard cases. Documented limitation: Roman Urdu
detection is heuristic and will misfire on short or ambiguous text (a
known, disclosed weakness -- see canon's note that "inconsistent,
non-standardized spelling is the real engineering obstacle, not the
modeling" for Roman Urdu specifically).
"""
import re
from enum import Enum


class Language(Enum):
    ENGLISH = "english"
    URDU_NATIVE = "urdu_native"       # Urdu script (Arabic-derived)
    ROMAN_URDU = "roman_urdu"         # Urdu written in Latin script
    CODE_SWITCHED = "code_switched"   # meaningful mix within the same message


# Urdu script Unicode ranges (Arabic block + Arabic Presentation Forms,
# which cover the additional letters Urdu uses beyond standard Arabic)
URDU_SCRIPT_PATTERN = re.compile(r'[\u0600-\u06FF\u0750-\u077F\uFB50-\uFDFF\uFE70-\uFEFF]')

# Common Roman Urdu function words / markers -- deliberately conservative,
# high-precision list (frequent, low-ambiguity words) rather than an
# exhaustive one, since false positives (English flagged as Roman Urdu)
# are worse for this routing decision than false negatives.
ROMAN_URDU_MARKERS = {
    "hai", "hain", "ho", "hoon", "hun", "tha", "thi", "the",
    "nahi", "nahin", "kya", "kyun", "kyu", "kaise", "kahan",
    "mein", "main", "tum", "aap", "hum", "unka", "uska", "iska",
    "yaar", "bohat", "bahut", "acha", "achha", "theek", "thik",
    "karo", "karna", "kiya", "raha", "rahi", "rahe", "wala", "wali",
    "mujhe", "tujhe", "usay", "unhe", "apna", "apni", "sath", "saath",
    "bhai", "behn", "bhen", "abhi", "phir", "lekin", "magar", "agar",
}

# Very common English function words -- used to gauge whether Latin-script
# text is actually English rather than Roman Urdu.
ENGLISH_MARKERS = {
    "the", "is", "are", "was", "were", "and", "but", "if", "then",
    "i", "you", "he", "she", "we", "they", "this", "that", "have",
    "has", "had", "not", "with", "for", "to", "of", "in", "on", "at",
}


def detect_language(text: str) -> dict:
    """Returns {'primary': Language, 'has_urdu_script': bool,
    'has_latin_script': bool, 'roman_urdu_score': float,
    'english_score': float, 'is_mixed': bool}."""
    if not text or not text.strip():
        return {"primary": Language.ENGLISH, "has_urdu_script": False,
                "has_latin_script": False, "roman_urdu_score": 0.0,
                "english_score": 0.0, "is_mixed": False}

    urdu_script_chars = len(URDU_SCRIPT_PATTERN.findall(text))
    total_chars = len(re.sub(r'\s', '', text))
    urdu_script_ratio = urdu_script_chars / max(total_chars, 1)
    has_urdu_script = urdu_script_ratio > 0.15  # allow some punctuation/numerals mixed in

    # tokenize Latin-script words for Roman Urdu / English marker matching
    latin_words = re.findall(r"[a-zA-Z']+", text.lower())
    has_latin_script = len(latin_words) > 0

    roman_urdu_hits = sum(1 for w in latin_words if w in ROMAN_URDU_MARKERS)
    english_hits = sum(1 for w in latin_words if w in ENGLISH_MARKERS)
    n_latin = max(len(latin_words), 1)
    roman_urdu_score = roman_urdu_hits / n_latin
    english_score = english_hits / n_latin

    is_mixed = has_urdu_script and has_latin_script and len(latin_words) >= 2

    # decision logic
    if has_urdu_script and has_latin_script:
        primary = Language.CODE_SWITCHED
    elif has_urdu_script:
        primary = Language.URDU_NATIVE
    elif roman_urdu_score > english_score and roman_urdu_hits >= 1:
        primary = Language.CODE_SWITCHED if (roman_urdu_hits >= 1 and english_hits >= 1) else Language.ROMAN_URDU
    else:
        primary = Language.ENGLISH

    return {
        "primary": primary,
        "has_urdu_script": has_urdu_script,
        "has_latin_script": has_latin_script,
        "roman_urdu_score": round(roman_urdu_score, 3),
        "english_score": round(english_score, 3),
        "is_mixed": is_mixed,
    }


def select_tts_voice(text: str) -> str:
    """Consumer 1: TTS voice routing (message-level, per Blueprint v4.10 --
    NOT locked architecture, this is an implementation of that unconfirmed
    proposal, ready to test once approved)."""
    result = detect_language(text)
    if result["primary"] in (Language.URDU_NATIVE, Language.CODE_SWITCHED):
        return "ur_PK-fasih-medium"
    return "en_US-<voice-tbd>"  # English Piper voice -- vendor still open per canon


def select_rhubarb_recognizer(text_or_lang: str) -> str:
    """Consumer 2: Rhubarb recognizer mode -- reuses the same decision,
    per Blueprint's explicit instruction not to build a second detector."""
    result = detect_language(text_or_lang)
    if result["primary"] == Language.ENGLISH:
        return "pocketsphinx"
    return "phonetic"


def select_fallback_text(text: str, en_text: str, ur_text: str) -> str:
    """Consumer 4: CRITICAL-tier deterministic fallback selection.
    OPEN DECISION (flagged, not resolved here): code-switched input
    currently gets the Urdu version, not a separate Roman Urdu / code-
    switched version -- see accompanying note. Revisit once that's decided."""
    result = detect_language(text)
    if result["primary"] in (Language.URDU_NATIVE, Language.CODE_SWITCHED):
        return ur_text
    return en_text


if __name__ == "__main__":
    test_cases = [
        "I want to hurt myself",
        "مجھے خود کو نقصان پہنچانا ہے",
        "Yaar main bohat overwhelmed feel kar raha hoon",
        "main theek nahi hoon",
        "I'm feeling bohat down today, kya karoon",
        "This is just plain English text with no markers at all",
    ]
    for t in test_cases:
        r = detect_language(t)
        print(f"{r['primary'].value:15} | {t}")
