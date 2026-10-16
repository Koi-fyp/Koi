"""
Reading short user replies inside an exercise, in English, Urdu script and Roman Urdu (incl. code-switching).

Two SEPARATE readers (design choice A, Oct 15):
  distress(text)               -> runs FIRST on every message, before anything is generated. If it fires, the
                                  director stops the exercise and hands the turn back to the companion. It is a
                                  cheap early stop for exercise steps, NOT the safety net: the TSD crisis check still
                                  runs every turn in the background exactly as locked (Gate 1b-concurrency).
  read_intent(text, expected)  -> step-aware: only the intents the CURRENT step can accept are considered
                                  ("theek hai" after an offer = accept; "ho gaya" in grounding = next). If unsure it
                                  ABSTAINS (returns None) and the director asks once more, never guesses.

Layers of read_intent (each one replaceable on its own):
  1. normalise (case, punctuation, Arabic/Urdu letter variants, diacritics, repeated letters "haaan" -> "han")
  2. phrase lexicon, longest phrase wins and consumes its words (so "abhi nahi" is not also read as "nahi");
     a contrast word ("but", "lekin", "magar", "لیکن") makes the clause after it decide;
  3. for short unmatched replies only: character-trigram kNN over labelled examples (handles spellings like
     "thk h", "hn", "okk"). The encoder is a parameter: swap in multilingual-e5 later without touching the rest.
Thresholds here are ENGINEERING DEFAULTS, not calibrated on real users. The lexicons and examples are Claude's,
pending native review.
"""
import math
import re
import unicodedata
from collections import Counter

# ---------------------------------------------------------------------------------------------- normalise
_URDU_RANGE = re.compile(r"[؀-ۿݐ-ݿﭐ-﷿ﹰ-﻿]")
_DIACRITICS = re.compile(r"[ً-ٰٟۖ-ۭ]")
_VARIANTS = str.maketrans({"ي": "ی", "ى": "ی", "ك": "ک", "ه": "ہ", "ة": "ہ", "أ": "ا", "إ": "ا", "آ": "آ",
                           "’": "'", "‘": "'"})


def has_urdu_script(text):
    return bool(_URDU_RANGE.search(text or ""))


def normalise(text, keep_breaks=False):
    """keep_breaks=True turns clause punctuation into a '|' token so phrases never match across it
    ("nahi, karna hai" is not the phrase "nahi karna")."""
    t = unicodedata.normalize("NFC", (text or "")).translate(_VARIANTS).lower()
    t = _DIACRITICS.sub("", t)
    t = t.replace("'", "")
    if keep_breaks:
        t = re.sub(r"[,.;:!?\u060C\u061F\u06D4\u061B]+", " | ", t)   # , . ; : ! ? and Urdu ، ؟ ۔ ؛
    t = re.sub(r"[^\w\s|]" if keep_breaks else r"[^\w\s]", " ", t)
    t = re.sub(r"(.)\1+", r"\1", t)             # collapse repeats: haaan->han, okkk->ok, theek->thek
    return " ".join(t.split())


# ---------------------------------------------------------------------------------------------- lexicons
# Phrases are written naturally and normalised the same way as input. Matching is on whole words.
LEX = {
    "accept": ["yes", "yeah", "yep", "yup", "ok", "okay", "sure", "alright", "all right", "lets do it", "lets try",
               "why not", "go ahead", "fine", "sounds good", "ill try", "i will try", "yes please", "ok lets try",
               "haan", "han", "haa", "ji", "jee", "ji haan", "theek hai", "thik hai", "theek", "thik", "chalo",
               "kar lete hain", "karte hain", "kar lein", "kar lo", "karna hai", "try karna hai", "karna chahta hoon",
               "karna chahti hoon", "chalo na", "kar lo na", "karo na", "zaroor", "bilkul", "acha", "achha", "ok ji",
               "ہاں", "جی", "جی ہاں", "ٹھیک ہے", "چلو", "ضرور", "بالکل", "اچھا", "کر لیتے ہیں"],
    "decline": ["no", "nope", "nah", "no thanks", "not really", "i dont want", "i dont want to", "rather not",
                "id rather not", "skip it", "nahi", "nahin", "nhi", "ni", "nai", "nae", "na", "rehne do",
                "rehnay do", "mood nahi", "dil nahi", "nahi karna", "nahi karna hai", "nahi yar", "nahi yaar", "نہیں", "نہ", "رہنے دو", "نہیں کرنا"],
    "not_now": ["not now", "not right now", "maybe later", "later", "another time", "not a good time", "busy",
                "im busy", "abhi nahi", "baad mein", "bad mein", "phir kabhi", "time nahi", "busy hoon",
                "ابھی نہیں", "بعد میں", "پھر کبھی", "وقت نہیں"],
    "not_for_me": ["not my thing", "not for me", "dont like it", "dont like", "doesnt work for me",
                   "never works", "doesnt help", "pasand nahi", "mujhe pasand nahi", "faida nahi", "fayda nahi",
                   "kaam nahi karta", "mera kaam nahi", "پسند نہیں", "فائدہ نہیں", "کام نہیں کرتا"],
    "what_is_it": ["what is it", "whats that", "what is that", "whats it", "how does it work", "what do i do",
                   "explain", "what do you mean", "how", "kaise karte hain", "kaise karna hai", "kya hai", "ye kya hai", "yeh kya hai", "kaise",
                   "kya karna hai", "kya karna ho ga", "kya matlab", "matlab", "کیا ہے", "یہ کیا ہے", "کیسے",
                   "کیا کرنا ہے", "مطلب"],
    "unsure": ["dont know", "not sure", "idk", "maybe", "pata nahi", "nahi pata", "pta nahi", "shayad",
               "پتا نہیں", "پتہ نہیں", "شاید"],
    "stop": ["stop", "enough", "i want to stop", "lets stop", "quit", "cancel", "end it here", "bas",
             "bas karo", "ruk jao", "band karo", "stop karo", "khatam karo", "rehne do ab", "بس", "رکو",
             "رک جاؤ", "بند کرو", "ختم کرو", "بس کرو"],
    "next": ["done", "next", "ok done", "finished", "did it", "ready", "go on", "continue", "ho gaya", "hogaya",
             "ho gya", "kar liya", "kr liya", "agay", "aage", "agey", "ہو گیا", "کر لیا", "آگے"],
    "start_breathing": ["breathing exercise", "breathing", "breathe with me", "help me breathe", "saans",
                        "saans wali", "saans ki exercise", "سانس", "سانس کی مشق"],
    "start_grounding": ["grounding", "ground me", "grounding exercise", "5 4 3 2 1", "گراؤنڈنگ"],
    "start_plan": ["make a plan", "plan something", "small goal", "set a goal", "plan banana", "plan banate",
                   "kuch plan", "goal set", "پلان", "پلان بنانا"],
}
# Words that only count as a control reply when the whole message is short (<= SHORT_ONLY_MAX_WORDS):
# "bas" alone = stop, but "bas thora tired hoon" = "just a bit tired"; "na" alone = no, but "karo na" = please do.
SHORT_ONLY = {"bas", "na", "later", "how", "fine", "maybe", "matlab", "busy", "ok", "okay", "acha", "achha", "thek",
              "thik", "enough", "quit", "ready", "next", "explain", "han", "ji", "ni"}
SHORT_ONLY_MAX_WORDS = 3
CONTRAST = {"but", "lekin", "magar", "par", "however", "لیکن", "مگر", "پر"}

# Distress / crisis language. Detection only (never shown to anyone). A false positive costs little: the exercise
# pauses and the companion simply talks. Deliberately broad.
DISTRESS = ["done with everything", "done with life", "cant take it", "cant take this", "cant do this anymore",
            "cant go on", "want to die", "wanna die", "kill myself", "end it all", "end my life", "no point living",
            "no reason to live", "hurt myself", "harm myself", "better off without me", "give up on life",
            "i give up", "tired of life", "tired of living", "dont want to live", "dont want to be here", "nothing matters anymore",
            "marna chahta", "marna chahti", "mar jaun", "mar jana", "mar jaon", "jeena nahi", "jina nahi",
            "zindagi khatam", "khud ko khatam", "khudkushi", "khud kushi", "khud ko nuqsan", "khud ko nuksan",
            "sab khatam", "bardasht nahi", "aur nahi hota", "jeene ka dil nahi", "jeene ka mann nahi", "zindagi se thak",
            "مرنا چاہتا", "مرنا چاہتی", "مر جاؤں", "مر جانا", "جینا نہیں", "زندگی ختم", "خودکشی", "خود کشی",
            "خود کو ختم", "خود کو نقصان", "سب ختم", "برداشت نہیں", "جینے کا دل نہیں", "زندگی سے تھک"]

_LEX_N = {k: sorted({normalise(p) for p in v}, key=lambda p: -len(p.split())) for k, v in LEX.items()}
_DISTRESS_N = [normalise(p) for p in DISTRESS]
_CONTRAST_N = {normalise(c) for c in CONTRAST}
_SHORT_ONLY_N = {normalise(c) for c in SHORT_ONLY}


def distress(text):
    """Returns the matched phrase or None."""
    t = " " + normalise(text) + " "            # no clause breaks here: broad on purpose
    for p in _DISTRESS_N:
        if " " + p + " " in t:
            return p
    return None


def _match(words):
    """Greedy longest-phrase match; a matched phrase consumes its words. Returns intents in order."""
    phrases = sorted(((len(p.split()), p, k) for k, ps in _LEX_N.items() for p in ps), reverse=True)
    short = sum(w != "|" for w in words) <= SHORT_ONLY_MAX_WORDS
    used = [False] * len(words)
    hits = []
    for n, p, k in phrases:
        if p in _SHORT_ONLY_N and not short:
            continue
        pw = p.split()
        for i in range(len(words) - n + 1):
            if not any(used[i:i + n]) and words[i:i + n] == pw:
                used[i:i + n] = [True] * n
                hits.append((i, k))
    return [k for _, k in sorted(hits)]


# ---------------------------------------------------------------------------------------------- kNN layer
EXAMPLES = {   # short, misspelt, code-switched variants for the fallback layer
    "accept": ["hn", "hanji", "thk h", "thk hai", "theek h", "okk", "okie", "oki", "ya sure", "yea", "ji bilkul",
               "chlo", "chalo krte", "kr lete", "ha ji", "ok krte hain", "yess", "sure ji"],
    "decline": ["nhi yar", "nai yaar", "no yr", "nope sorry", "nhi krna", "ni krna", "nah im good", "na yaar"],
    "what_is_it": ["ye kia h", "kia hai ye", "kesy", "kaisy", "wht is it", "whats this", "kya krna h"],
    "next": ["hogya", "ho gya h", "kr lia", "done hai", "dne", "ok done hai", "agy", "aagay"],
    "stop": ["bs", "bss", "stop kro", "band kro", "ruko", "rukk jao"],
}


class CharNgramEncoder:
    """Default encoder: character trigrams with word-boundary padding. No model download. Swap for e5 later."""
    n = 3

    def encode(self, texts):
        out = []
        for t in texts:
            s = " " + normalise(t) + " "
            c = Counter(s[i:i + self.n] for i in range(len(s) - self.n + 1))
            norm = math.sqrt(sum(v * v for v in c.values())) or 1.0
            out.append({g: v / norm for g, v in c.items()})
        return out


def _cos(a, b):
    if len(a) > len(b):
        a, b = b, a
    return sum(v * b.get(g, 0.0) for g, v in a.items())


KNN_K = 5            # engineering defaults
KNN_MIN_SIM = 0.45
KNN_MIN_SHARE = 0.6
KNN_MAX_WORDS = 4
KNN_MIN_SIM_IN_ANSWER = 0.6   # stricter: inside an answer step a wrong "stop" would cut the exercise short


class IntentReader:
    def __init__(self, encoder=None):
        self.enc = encoder or CharNgramEncoder()
        self.rows = [(k, ex) for k, exs in EXAMPLES.items() for ex in exs] + \
                    [(k, p) for k, ps in LEX.items() if k in EXAMPLES for p in ps]
        self.vecs = self.enc.encode([r[1] for r in self.rows])

    def read(self, text, expected):
        """-> (intent or None, how). `expected` = intents the current step can accept.
        Special: 'answer' in expected means free text is an acceptable answer when no control intent matched."""
        expected = set(expected)
        words = normalise(text, keep_breaks=True).split()
        n_words = sum(w != "|" for w in words)
        if not n_words:
            return None, "empty"
        hits = _match(words)
        # contrast: the clause after the last contrast word decides, if it says anything
        for i in range(len(words) - 1, -1, -1):
            if words[i] in _CONTRAST_N:
                tail = _match(words[i + 1:])
                if tail:
                    hits = tail
                break
        got = set(hits)
        # refinements
        if got & {"not_now", "not_for_me"} and "decline" in expected and not expected & {"not_now", "not_for_me"}:
            got = (got - {"not_now", "not_for_me"}) | {"decline"}
        if "unsure" in got and "what_is_it" in expected:
            got = (got - {"unsure"}) | {"what_is_it"}
        if "stop" in got and "stop" in expected:
            return "stop", "lexicon:stop (control word wins)"
        cand = got & expected
        if len(cand) == 1:
            return cand.pop(), "lexicon"
        if len(cand) > 1:
            return None, f"ambiguous lexicon hits {sorted(cand)}"
        if got - expected and "answer" not in expected:
            return None, f"matched {sorted(got)} but step expects {sorted(expected)}"
        if "answer" in expected:
            if n_words <= 2 and expected & {"stop", "next"}:           # "bss", "hogya" inside an answer step
                k, how = self._knn(text, expected & {"stop", "next"}, min_sim=KNN_MIN_SIM_IN_ANSWER)
                if k:
                    return k, how
            return "answer", "free-text answer"
        if n_words <= KNN_MAX_WORDS:
            return self._knn(text, expected)
        return None, "no match"

    def _knn(self, text, expected, min_sim=None):
        min_sim = KNN_MIN_SIM if min_sim is None else min_sim
        q = self.enc.encode([text])[0]
        scored = sorted(((_cos(q, v), k) for (k, _), v in zip(self.rows, self.vecs) if k in expected), reverse=True)
        top = [(s, k) for s, k in scored[:KNN_K] if s >= min_sim]
        if not top:
            return None, "knn: nothing similar enough"
        votes = Counter(k for _, k in top)
        k, n = votes.most_common(1)[0]
        if n / len(top) >= KNN_MIN_SHARE:
            return k, f"knn {n}/{len(top)} (top sim {top[0][0]:.2f})"
        return None, f"knn split {dict(votes)}"


_ROMAN_CUES = {normalise(w) for w in """hai hain nahi nhi nahin haan han kya kia mein main ho hoon hun kar kr karna karo
theek thik acha achha ji abhi bas yeh ye woh aap ap mujhe mera meri gaya gya raha rahi rahe yaar yar chalo kaise kyun
tha thi ka ki ke se ko bhi aur lekin magar pata kuch sab dil wala wali thora thoda bohat bahut behtar bura lag lagta
lagti raha sach sirf phir bhi apna apni hamesha kabhi zyada kam din raat ghar kaam soch sochta sochti dost log""".split()}
_EN_CUES = {normalise(w) for w in """i im i'm me my you your the a an is are was were it its this that and but so to of in
on for with not dont can cant do does did feel feeling think just really very what why how when maybe yes no okay
better worse little bit today now have has had been be am will would should could about like""".split()}


def detect_lang(text):
    """'ur' for Urdu script; otherwise Roman Urdu vs English by cue-word majority; None if it can't tell (the caller
    then keeps the previous language, so a bare "ok" never switches the conversation's language)."""
    if has_urdu_script(text):
        return "ur"
    words = normalise(text).split()
    if not words:
        return None
    roman = sum(w in _ROMAN_CUES for w in words)
    eng = sum(w in _EN_CUES for w in words)
    if roman > eng:
        return "ur-roman"
    if eng > roman and eng >= 2:
        return "en"
    return None


# ---------------------------------------------------------------------------------------------- answers
_MOOD = {"worse": ["worse", "not better", "still bad", "bad", "terrible", "awful", "no different", "same as before",
                   "bura", "bura lag raha", "kharab", "behtar nahi", "ab bhi bura", "waisa hi", "wesa hi", "worse hai",
                   "برا", "خراب", "بہتر نہیں", "ویسا ہی"],
         "better": ["better", "good", "calmer", "calm", "relaxed", "lighter", "not bad", "okay now", "fine now",
                    "behtar", "acha lag raha", "acha hai", "sukoon", "halka", "پرسکون", "بہتر", "اچھا لگ رہا", "ہلکا"]}
_MOOD_N = {k: sorted({normalise(p) for p in v}, key=lambda p: -len(p.split())) for k, v in _MOOD.items()}


def mood(text):
    """'worse' | 'better' | None. Only 'worse' changes the flow (no go-to question, offer to talk instead)."""
    words = normalise(text, keep_breaks=True).split()
    phrases = sorted(((len(p.split()), p, k) for k, ps in _MOOD_N.items() for p in ps), reverse=True)
    used, hits = [False] * len(words), set()
    for n, p, k in phrases:
        pw = p.split()
        for i in range(len(words) - n + 1):
            if not any(used[i:i + n]) and words[i:i + n] == pw:
                used[i:i + n] = [True] * n
                hits.add(k)
    if "worse" in hits and "better" not in hits:
        return "worse"
    return "better" if "better" in hits else None


_NUM_WORDS = {"zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8,
              "nine": 9, "ten": 10, "sifar": 0, "ek": 1, "aik": 1, "teen": 3, "char": 4, "chaar": 4, "panch": 5,
              "paanch": 5, "che": 6, "chay": 6, "chhe": 6, "chhay": 6, "saat": 7, "sat": 7, "aath": 8, "ath": 8,
              "nau": 9, "das": 10, "dus": 10, "صفر": 0, "ایک": 1, "دو": 2, "تین": 3, "چار": 4, "پانچ": 5, "چھ": 6,
              "سات": 7, "آٹھ": 8, "نو": 9, "دس": 10}
_DIGITS = str.maketrans("۰۱۲۳۴۵۶۷۸۹٠١٢٣٤٥٦٧٨٩", "01234567890123456789")


def number_0_10(text):
    """First number 0-10 in digits (Latin/Urdu/Arabic) or words (en / Roman Urdu / Urdu). No repeat-collapsing here:
    Roman 'teen' (3) must not become English 'ten'. 'do' (2) is not read as a word: too common in English."""
    t = unicodedata.normalize("NFC", text or "").translate(_DIGITS).lower()
    m = re.search(r"\d+", t)
    if m:
        n = int(m.group())
        return n if 0 <= n <= 10 else None
    for w in re.findall(r"[^\W\d_]+", t):
        if w in _NUM_WORDS:
            return _NUM_WORDS[w]
    return None


_NEG_OR_QUESTION = {normalise(w) for w in ["hate", "dont", "never", "not", "no", "nahi", "nhi", "na", "what", "why",
                                             "how", "kya", "kia", "kyun", "kaise", "نہیں", "کیا", "کیوں", "کیسے"]}


def read_start(text, max_words=8):
    """Did the user ask to start an exercise in plain chat? Ignores negative mentions ("I hate breathing")."""
    words = normalise(text, keep_breaks=True).split()
    if not words or sum(w != "|" for w in words) > max_words:
        return None
    if set(words) & _NEG_OR_QUESTION:
        return None
    hits = set(_match(words))
    if hits & {"decline", "not_now", "not_for_me", "unsure", "what_is_it", "stop"}:
        return None
    starts = hits & {"start_breathing", "start_grounding", "start_plan"}
    return starts.pop() if len(starts) == 1 else None
