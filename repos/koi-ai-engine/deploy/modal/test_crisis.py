"""Smoke test for the deployed crisis endpoint.
    pip install requests
    python test_crisis.py https://<workspace>--koi-crisis-crisis-web.modal.run  [path/to/clip.wav] [path/to/clip.mp4]
Set KOI_TOKEN to a real Firebase ID token (not needed only if deployed with KOI_AUTH_DISABLED=1).
Checks the response against the contract: bands, omitted fields, flags only for processed modalities.
"""
import os, sys, time, json
import requests

BANDS = [(0.90, "CRITICAL"), (0.70, "HIGH"), (0.40, "MODERATE"), (0.0, "LOW")]
URL = sys.argv[1].rstrip("/")
H = {"Authorization": f"Bearer {os.environ['KOI_TOKEN']}"} if os.environ.get("KOI_TOKEN") else {}


def check(r, sent_audio, sent_video, label):
    assert r.status_code == 200, f"{label}: HTTP {r.status_code} {r.text[:300]}"
    j = r.json()
    s, cat = j["crisis_score"], j["risk_category"]
    assert 0.0 <= s <= 1.0, s
    expect = next(c for t, c in BANDS if s >= t)
    if expect == "CRITICAL" and MAXCAT == "HIGH":
        expect = "HIGH"
    assert cat == expect, (s, cat)
    assert ("intervention_content" in j) == (cat in ("HIGH", "CRITICAL")), "intervention_content presence wrong"
    if cat == "CRITICAL":
        assert j["intervention_content"]["source"] == "fallback", "CRITICAL must be fallback"
    if not sent_audio:
        assert "vocal_contradiction" not in j["trigger_flags"] or "audio" in j["modalities_used"], "audio flag without audio"
    assert "facial_distress" not in j["trigger_flags"]
    if "audio" not in j["modalities_used"]:
        assert "p_masked" not in j["components"] or "video" in j["modalities_used"]
    print(f"OK  {label:<28} score={s:.3f} {cat:<9} conf={j['confidence']:<8} modalities={j['modalities_used']} "
          f"flags={j['trigger_flags']} ms={j['timing_ms']}")
    return j


HEALTH = requests.get(f"{URL}/health", timeout=150).json()
print(HEALTH)
MAXCAT = HEALTH.get("max_category", "CRITICAL")
for label, text in (("typed neutral", "I had a nice lunch with my friends today."),
                    ("typed negative", "I feel completely hopeless and alone, nothing matters anymore.")):
    t0 = time.time()
    check(requests.post(f"{URL}/api/v1/crisis", data={"text": text, "turn_id": "t1"}, headers=H, timeout=150), False, False, label)
    print(f"    client round trip {1000 * (time.time() - t0):.0f} ms")
r = requests.post(f"{URL}/api/v1/crisis", data={}, headers=H, timeout=60)
assert r.status_code == 422, f"empty request should be 422, got {r.status_code}"
print("OK  empty request -> 422")
if len(sys.argv) > 2:
    with open(sys.argv[2], "rb") as f:
        check(requests.post(f"{URL}/api/v1/crisis", files={"audio": f}, headers=H, timeout=150), True, False, "audio only (ASR)")
    with open(sys.argv[2], "rb") as f:
        check(requests.post(f"{URL}/api/v1/crisis", data={"text": "I'm fine, really."}, files={"audio": f}, headers=H,
                            timeout=150), True, False, "typed 'I'm fine' + audio")
if len(sys.argv) > 3:
    with open(sys.argv[3], "rb") as f:
        j = check(requests.post(f"{URL}/api/v1/crisis", files={"video": f}, headers=H, timeout=150), True, True, "video clip (+its audio)")
        print(json.dumps(j, indent=2)[:1500])
print("ALL CHECKS PASSED")
