"""Smoke test for the deployed crisis service (stdlib only).
Usage:  set KOI_TOKEN=<firebase id token>   then   python smoke_crisis.py <CRISIS_BASE_URL>
Checks /health and POST /api/v1/crisis (multipart) against the fields in contract v1 section 4.
It does NOT judge whether the SCORES are right (the model is an emotion proxy, see contract section 5):
it checks the response shape, the category cap, and that failures are clean 4xx, not 5xx.
Exit 1 on a contract violation.
"""
import io
import json
import os
import struct
import sys
import time
import uuid
import wave
import urllib.error
import urllib.request as _ur
_ur.HTTPRedirectHandler.max_repeats = 200      # Modal answers slow (cold-start) requests with HTTP 303 poll redirects
_ur.HTTPRedirectHandler.max_redirections = 200  # to the SAME url; urllib's default limit (4 repeats) gives up too early
import urllib.request

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

CATS = ["LOW", "MODERATE", "HIGH", "CRITICAL"]
problems = []


def multipart(fields, files):
    b = uuid.uuid4().hex
    out = io.BytesIO()
    for k, v in fields.items():
        out.write(("--%s\r\nContent-Disposition: form-data; name=\"%s\"\r\n\r\n%s\r\n" % (b, k, v)).encode("utf-8"))
    for k, (fn, ct, data) in files.items():
        out.write(("--%s\r\nContent-Disposition: form-data; name=\"%s\"; filename=\"%s\"\r\nContent-Type: %s\r\n\r\n" % (b, k, fn, ct)).encode())
        out.write(data)
        out.write(b"\r\n")
    out.write(("--%s--\r\n" % b).encode())
    return out.getvalue(), "multipart/form-data; boundary=" + b


def call(base, token, fields, files=None):
    body, ctype = multipart(fields, files or {})
    req = urllib.request.Request(base + "/api/v1/crisis", data=body,
                                 headers={"Content-Type": ctype, "Authorization": "Bearer " + token})
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=170) as r:
            return r.status, json.loads(r.read().decode("utf-8")), time.time() - t0
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", "replace")
        try:
            return e.code, json.loads(raw), time.time() - t0
        except ValueError:
            return e.code, {"_raw": raw[:200]}, time.time() - t0


def silence_wav(seconds=2, rate=16000):
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(struct.pack("<h", 0) * (rate * seconds))
    return buf.getvalue()


def check_ok(label, code, js, max_cat):
    print("  HTTP %s" % code)
    if code != 200:
        problems.append("%s: expected 200, got %s %s" % (label, code, str(js)[:120]))
        return
    for k in ("crisis_score", "risk_category", "modalities_used", "trigger_flags", "confidence", "timing_ms", "model"):
        if k not in js:
            problems.append("%s: missing field %s" % (label, k))
    sc, cat = js.get("crisis_score"), js.get("risk_category")
    if not isinstance(sc, (int, float)) or not 0 <= sc <= 1:
        problems.append("%s: crisis_score %r not in 0..1" % (label, sc))
    if cat not in CATS:
        problems.append("%s: risk_category %r invalid" % (label, cat))
    if max_cat in CATS and cat in CATS and CATS.index(cat) > CATS.index(max_cat):
        problems.append("%s: category %s exceeds max_category %s" % (label, cat, max_cat))
    has_iv = "intervention_content" in js and js["intervention_content"] is not None
    if cat in ("HIGH", "CRITICAL") and not has_iv:
        problems.append("%s: %s without intervention_content" % (label, cat))
    if cat in ("LOW", "MODERATE") and has_iv:
        problems.append("%s: intervention_content present at %s" % (label, cat))
    print("  score=%s category=%s modalities=%s confidence=%s reasons=%s calibrated=%s total_ms=%s" % (
        sc, cat, js.get("modalities_used"), js.get("confidence"), js.get("confidence_reasons"),
        (js.get("model") or {}).get("calibrated"), (js.get("timing_ms") or {}).get("total")))
    if has_iv:
        iv = js["intervention_content"]
        print("  intervention source=%s helpline=%s" % (iv.get("source"), iv.get("helpline")))


def main(argv):
    token = os.environ.get("KOI_TOKEN", "")
    if not argv or not token:
        print(__doc__)
        return 2
    base = argv[0].rstrip("/")

    print("GET /health")
    try:
        with urllib.request.urlopen(base + "/health", timeout=170) as r:
            health = json.loads(r.read().decode())
        print(" ", health)
    except Exception as e:
        print("  FAILED:", e)
        health = {}
        problems.append("/health failed: %s" % e)
    max_cat = health.get("max_category")
    if "heads_loaded" not in health:
        print("  note: /health has no heads_loaded field (expected after P2)")

    cases = [
        ("neutral text", {"text": "I had a really nice walk today and then made tea.", "language": "en", "turn_id": "t1"}, None),
        ("low-mood text", {"text": "I feel hopeless and I do not see the point of anything anymore.", "language": "en", "turn_id": "t2"}, None),
        ("roman urdu text", {"text": "Aaj bohat udaas hoon, kisi se baat karne ka mann nahi.", "language": "ur-roman", "turn_id": "t3"}, None),
    ]
    for label, fields, files in cases:
        print("POST text: %s" % label)
        code, js, secs = call(base, token, fields, files)
        check_ok(label, code, js, max_cat)
        if code == 200 and js.get("modalities_used") != ["text"]:
            problems.append("%s: modalities_used %r != ['text']" % (label, js.get("modalities_used")))
        if code == 200 and js.get("turn_id") != fields["turn_id"]:
            problems.append("%s: turn_id not echoed" % label)

    print("POST nothing (no fields) -> must be a clean 4xx")
    code, js, _ = call(base, token, {})
    print("  HTTP %s %s" % (code, str(js)[:100]))
    if not 400 <= code < 500:
        problems.append("empty request returned %s, expected 4xx" % code)

    print("POST 2 s of silence as audio (no typed text) -> 200 or a clean 4xx; never 5xx")
    code, js, secs = call(base, token, {"language": "en", "turn_id": "t4"}, {"audio": ("silence.wav", "audio/wav", silence_wav())})
    print("  HTTP %s %s" % (code, str(js)[:300]))
    if code >= 500:
        problems.append("silence audio returned %s" % code)
    if code == 200:
        check_ok("silence audio", code, js, max_cat)

    print()
    if problems:
        print("PROBLEMS:")
        for p in problems:
            print(" -", p)
        return 1
    print("no contract problems found (scores themselves are NOT validated by this script)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
