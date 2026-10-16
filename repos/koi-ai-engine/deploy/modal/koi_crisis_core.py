"""KOI crisis score: pure scoring logic (numpy only, no torch), so it can be unit-tested anywhere.

Score (A):    crisis_score = p_neg + (1 - p_neg) * p_masked
              p_neg    = calibrated P(text expresses negative emotion: sadness/anger/fear/disgust), surprise renormalised out
              p_masked = calibrated P(audio/video disagree with the text), from the pilot mismatch head ensemble.
              Weighted by (1 - p_neg), it only adds risk when the words are NOT negative but the voice/face is.
              The two events are disjoint, so the score is the probability of "negative affect in at least one channel".
Calibration (C): text temperature fitted on MELD dev; Platt scaling per combo on synthetic validation pairs.
Confidence (B):  "reduced" when the modality set is not full (canon: Confidence Disclosure), the text model is uncertain,
                 the seed ensemble disagrees, or no calibration file is loaded.
This is an emotion-proxy score. It is NOT a validated crisis detector.
"""
import math
import numpy as np

LABELS = ["neutral", "joy", "sadness", "anger", "surprise", "fear", "disgust"]
NEG_IDX = [2, 3, 5, 6]
SURPRISE_IDX = 4
CATEGORIES = ["LOW", "MODERATE", "HIGH", "CRITICAL"]
DEFAULT_BANDS = [0.40, 0.70, 0.90]          # Blueprint 4.1
FULL_COMBO = "TAV"
# Used only when no calibration file is present (then confidence is always "reduced", reason "uncalibrated").
UNCALIBRATED = {"text_temperature": 1.0, "head_platt": {c: {"a": 1.0, "b": 0.0} for c in ("TA", "TV", "TAV")},
                "entropy_threshold": 0.60, "seed_spread_threshold": 0.15, "bands": DEFAULT_BANDS}


def softmax(z):
    z = np.asarray(z, dtype=np.float64)
    z = z - z.max()
    e = np.exp(z)
    return e / e.sum()


def text_probs(logits7, temperature):
    """logits7 in LABELS order -> (7-class probs, p_neg, normalised entropy)."""
    p = softmax(np.asarray(logits7, dtype=np.float64) / float(temperature))
    p_neg = float(p[NEG_IDX].sum() / max(1.0 - p[SURPRISE_IDX], 1e-6))
    p_neg = min(max(p_neg, 0.0), 1.0)
    ent = float(-(p * np.log(np.clip(p, 1e-12, 1.0))).sum() / math.log(len(p)))
    return p, p_neg, ent


def head_prob(seed_logits, platt):
    """seed_logits: per-seed raw logits of the mismatch head -> (calibrated prob of mean logit, spread of per-seed probs)."""
    z = np.asarray(seed_logits, dtype=np.float64)
    p_cal = 1.0 / (1.0 + math.exp(-(platt["a"] * float(z.mean()) + platt["b"])))
    spread = float((1.0 / (1.0 + np.exp(-z))).std())
    return p_cal, spread


def combine(p_neg, p_masked):
    if p_masked is None:
        return float(p_neg)
    return float(min(max(p_neg + (1.0 - p_neg) * p_masked, 0.0), 1.0))


def category(score, bands=DEFAULT_BANDS, max_category="CRITICAL"):
    """max_category lets the deployment cap what an emotion-only score may claim (e.g. "HIGH"), because nothing in
    this pilot detects self-harm content: strongly sad or angry text alone otherwise lands in CRITICAL."""
    i = int(np.digitize([score], bands)[0])
    return CATEGORIES[min(i, CATEGORIES.index(max_category))]


def combo_of(has_audio, has_video):
    return "T" + ("A" if has_audio else "") + ("V" if has_video else "")


def modalities_used(combo, text_source):
    """Modalities the user actually supplied. ASR-derived text is reported as audio, not as typed text."""
    out = []
    if text_source == "typed":
        out.append("text")
    if "A" in combo:
        out.append("audio")
    if "V" in combo:
        out.append("video")
    return out


def confidence(combo, entropy, spread, cal, calibrated):
    reasons = []
    if combo != FULL_COMBO:
        reasons.append("reduced_modality_set")
    if entropy > cal["entropy_threshold"]:
        reasons.append("text_model_uncertain")
    if spread is not None and spread > cal["seed_spread_threshold"]:
        reasons.append("ensemble_disagreement")
    if not calibrated:
        reasons.append("uncalibrated")
    return ("reduced" if reasons else "standard"), reasons


def trigger_flags(combo, p_neg, p_masked):
    """Only flags whose modality was processed can appear (canon: omitted, never false).
    vocal_contradiction: audio processed, words not negative, mismatch head says the audio/video disagree.
    facial_distress is never emitted: video showed no measurable signal on MELD, so the system does not claim to read faces."""
    flags = []
    if "A" in combo and p_masked is not None and p_masked >= 0.5 and p_neg < 0.5:
        flags.append("vocal_contradiction")
    return flags


def score_turn(logits7, combo, seed_logits, cal, calibrated):
    """Everything except encoders. seed_logits is None for combo 'T'."""
    _, p_neg, ent = text_probs(logits7, cal["text_temperature"])
    p_masked, spread = (None, None)
    if combo != "T":
        p_masked, spread = head_prob(seed_logits, cal["head_platt"][combo])
    s = combine(p_neg, p_masked)
    conf, reasons = confidence(combo, ent, spread, cal, calibrated)
    comp = {"p_text_negative": round(p_neg, 4), "text_uncertainty": round(ent, 4)}
    if p_masked is not None:
        comp["p_masked"] = round(p_masked, 4)
        comp["ensemble_spread"] = round(spread, 4)
    return {"crisis_score": round(s, 4),
            "risk_category": category(s, cal.get("bands", DEFAULT_BANDS), cal.get("max_category", "CRITICAL")),
            "trigger_flags": trigger_flags(combo, p_neg, p_masked), "confidence": conf,
            "confidence_reasons": reasons, "components": comp}


# ---------------- intervention_content (fail-closed) ----------------
def builtin_fallback(helpline):
    """PLACEHOLDER safety message. Replace with the RAG segment's vetted CRITICAL sequence (UX Flows Locked) via the hook."""
    return {"source": "fallback", "language": "en",
            "items": [{"text": "It sounds like things are really hard right now. You don't have to go through this alone. "
                               "Please reach out to someone you trust, or contact a helpline now.",
                       "chunk_id": "builtin-fallback-v0", "source_corpus": "koi-builtin-placeholder",
                       "evidence_role": "safety-message", "review_status": "not-required"}],
            "helpline": dict(helpline)}


def valid_content(c):
    if not isinstance(c, dict) or c.get("source") not in ("grounded", "fallback"):
        return False
    items = c.get("items")
    if not isinstance(items, list) or not (1 <= len(items) <= 3):
        return False
    return all(isinstance(i, dict) and isinstance(i.get("text"), str) and i["text"].strip() for i in items)


def intervention(risk_category, hook_result, helpline):
    """Below HIGH: None (field omitted). HIGH: hook result if valid, else fallback.
    CRITICAL: only a result with source == 'fallback' is accepted (the RAG team's hardcoded sequence); anything else
    -> builtin fallback. Never a retrieved span at CRITICAL."""
    if risk_category not in ("HIGH", "CRITICAL"):
        return None
    ok = valid_content(hook_result)
    if risk_category == "CRITICAL" and ok and hook_result["source"] != "fallback":
        ok = False
    out = dict(hook_result) if ok else builtin_fallback(helpline)
    if not isinstance(out.get("helpline"), dict) or not out["helpline"].get("number"):
        out["helpline"] = dict(helpline)
    return out
