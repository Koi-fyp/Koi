"""Live smoke for POST /api/v1/speech (koi-speech, PROPOSED). Ahmad runs it; it calls a deployed service. Stdlib only.

Usage (koivenv, cmd):  python -B agent_tasks\\acceptance\\speech_smoke.py <SPEECH_URL>

Sends: one Urdu-script sentence with raza_ur and aisha_ur, one English sentence with raza_en and aisha_en, then
two language-mismatch checks (Urdu text on raza_en, English text on raza_ur) that must return 422 language-mismatch.
Token: env KOI_TOKEN only; never printed. Redirects followed by hand (303 -> GET) via _media_common.post_following.
WAVs are saved under agent_tasks/reports/speech/. Prints ONLY: HTTP status, wall time, server timings_ms,
duration_s, cue count, cue validity (deploy/speech/cue_validator.py); on errors the error code only. Exit 0 always.
"""
import base64
import json
import os
import sys
import time
import uuid
from pathlib import Path

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
sys.path.insert(0, str(HERE))
sys.path.insert(1, str(ROOT / "deploy" / "speech"))
import _media_common as M  # noqa: E402
from cue_validator import validate_cues  # noqa: E402

OUT = ROOT / "agent_tasks" / "reports" / "speech"
UR = "السلام علیکم، آج آپ کیسے ہیں؟"
EN = "Hello, how are you feeling today?"
CASES = [("raza_ur", "ur", UR, 200), ("aisha_ur", "ur", UR, 200), ("raza_en", "en", EN, 200),
         ("aisha_en", "en", EN, 200), ("raza_en", "en", UR, 422), ("raza_ur", "ur", EN, 422)]


def call(url, token, voice_id, language, text):
    body = json.dumps({"text": text, "voice_id": voice_id, "language": language,
                       "generation_id": str(uuid.uuid4())}).encode("utf-8")
    headers = {"Authorization": "Bearer " + token, "Content-Type": "application/json; charset=utf-8",
               "Accept": "application/json"}
    resp, conn, t0 = M.post_following(url.rstrip("/") + "/api/v1/speech", body, headers)
    try:
        raw = resp.read()
    finally:
        conn.close()
    wall = round(time.monotonic() - t0, 2)
    try:
        data = json.loads(raw.decode("utf-8"))
    except ValueError:
        data = None
    return resp.status, wall, data


def main(argv):
    if len(argv) < 1 or argv[0].startswith("-"):
        print(__doc__)
        return 0
    url = argv[0]
    token = os.environ.get("KOI_TOKEN", "").strip()
    if not token:
        print("KOI_TOKEN is not set; nothing sent")
        return 0
    OUT.mkdir(parents=True, exist_ok=True)
    failures = 0
    for voice_id, language, text, expected in CASES:
        label = "%s %s-text" % (voice_id, "ur" if text == UR else "en")
        try:
            status, wall, data = call(url, token, voice_id, language, text)
        except Exception as exc:
            print("%-16s transport error: %s" % (label, type(exc).__name__))
            failures += 1
            continue
        if status != 200:
            code = (data or {}).get("error", {}).get("code") if isinstance(data, dict) else None
            ok = status == expected and (expected != 422 or code == "language-mismatch")
            failures += not ok
            print("%-16s HTTP %s wall=%ss error=%s  %s" % (label, status, wall, code, "EXPECTED" if ok else "UNEXPECTED"))
            continue
        report = validate_cues(data.get("mouth_cues"), data.get("duration_s"))
        wav = OUT / ("%s_%s.wav" % (voice_id, language))
        wav.write_bytes(base64.b64decode(data.get("audio_b64", "")))
        ok = expected == 200 and report.ok
        failures += not ok
        print("%-16s HTTP 200 wall=%ss timings_ms=%s duration_s=%s cues=%s cues_valid=%s  %s" % (
            label, wall, data.get("timings_ms"), data.get("duration_s"), report.cue_count, report.ok,
            "EXPECTED" if ok else "UNEXPECTED"))
    token = None
    print("summary: %d/%d as expected; WAVs in %s" % (len(CASES) - failures, len(CASES), OUT))
    return 0


if __name__ == "__main__":
    try:
        main(sys.argv[1:])
    finally:
        sys.exit(0)
