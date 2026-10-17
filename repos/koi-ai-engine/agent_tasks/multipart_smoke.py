"""Multipart chat smoke: one POST /api/v1/chat per allowed media combination.

    set KOI_TOKEN=<firebase id token>      (read from the environment only; never printed)
    python agent_tasks\\multipart_smoke.py <CHAT_URL>

Cases: audio | text+video | audio+video (text-only is covered by smoke_chat.py).
Audio is a generated 2-second silent 16 kHz mono WAV. Video is a small mp4 generated with
ffmpeg if ffmpeg is on PATH; otherwise both video cases are SKIPPED and the script says so.
Prints the SSE event names and every `transcript`, `risk`, `error` event; checks the v1.1 order.
Exit code: 0 all run cases ok, 1 a case failed, 2 usage. Silence has no speech, so for the audio
cases the server is expected to answer 422 (no transcript) or risk "unavailable"; both are reported,
not treated as failures. Stdlib only, plus frames() from deploy/modal/tools/trace_check.py.
"""
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
import uuid
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "deploy" / "modal" / "tools"))
from trace_check import frames  # noqa: E402

# Modal answers slow (cold-start) requests with 303 poll redirects to the same URL (as in emotion_probe.py).
urllib.request.HTTPRedirectHandler.max_repeats = 200
urllib.request.HTTPRedirectHandler.max_redirections = 200


def silent_wav(seconds=2.0, rate=16000):
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(b"\x00\x00" * int(seconds * rate))
    return buf.getvalue()


def small_mp4(ffmpeg):
    """2 s, 64x64 black video with a silent audio track; None if generation fails."""
    with tempfile.TemporaryDirectory() as td:
        out = os.path.join(td, "clip.mp4")
        cmd = [ffmpeg, "-nostdin", "-v", "error", "-f", "lavfi", "-i", "color=c=black:s=64x64:d=2:r=10",
               "-f", "lavfi", "-i", "anullsrc=r=16000:cl=mono", "-t", "2", "-shortest",
               "-pix_fmt", "yuv420p", "-movflags", "+faststart", out]
        result = subprocess.run(cmd, capture_output=True, timeout=60)
        if result.returncode != 0 or not os.path.exists(out):
            return None
        return Path(out).read_bytes()


def cases(ffmpeg=None):
    wav = silent_wav()
    video = small_mp4(ffmpeg) if ffmpeg else None
    out = [("audio", {"language": "en"}, {"audio": ("voice.wav", "audio/wav", wav)})]
    if video is None:
        reason = "ffmpeg not found on PATH" if not ffmpeg else "ffmpeg failed to generate the mp4"
        out.append(("text+video", None, "SKIPPED: " + reason))
        out.append(("audio+video", None, "SKIPPED: " + reason))
    else:
        out.append(("text+video", {"message": "hello, this is a video turn", "language": "en"},
                    {"video": ("clip.mp4", "video/mp4", video)}))
        out.append(("audio+video", {"language": "en"},
                    {"audio": ("voice.wav", "audio/wav", wav), "video": ("clip.mp4", "video/mp4", video)}))
    return out


def encode_multipart(payload, files):
    boundary = "koi" + uuid.uuid4().hex
    parts = [b"--" + boundary.encode(),
             b'Content-Disposition: form-data; name="payload"', b"",
             json.dumps({"session_history": [], **payload}).encode()]
    for field, (filename, ctype, data) in files.items():
        parts += [b"--" + boundary.encode(),
                  f'Content-Disposition: form-data; name="{field}"; filename="{filename}"'.encode(),
                  f"Content-Type: {ctype}".encode(), b"", data]
    parts += [b"--" + boundary.encode() + b"--", b""]
    return b"\r\n".join(parts), "multipart/form-data; boundary=" + boundary


def check_order(names):
    problems = []
    if "companion_state" not in names:
        problems.append("no companion_state")
    if "done" not in names or names[-1] != "done":
        problems.append("done is not last")
    if names.count("risk") != 1:
        problems.append("expected exactly one risk event, got %d" % names.count("risk"))
    if "delta" not in names and "error" not in names:
        problems.append("no delta and no error event")
    if "companion_state" in names:
        cs = names.index("companion_state")
        first_text = min([names.index(n) for n in ("delta", "error") if n in names] or [len(names)])
        if cs > first_text:
            problems.append("companion_state after first delta/error")
        if "risk" in names and names.index("risk") < cs:
            problems.append("risk before companion_state")
        if "transcript" in names and names.index("transcript") > cs:
            problems.append("transcript after companion_state")
    if len(names) >= 2 and names[-2] != "state":
        problems.append("state is not immediately before done")
    return problems


def run_case(base, token, payload, files, timeout=180):
    body, ctype = encode_multipart(payload, files)
    req = urllib.request.Request(base.rstrip("/") + "/api/v1/chat", data=body,
                                 headers={"Authorization": "Bearer " + token, "Content-Type": ctype})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.status, list(frames(resp)), None
    except urllib.error.HTTPError as exc:
        return exc.code, [], exc.read().decode("utf-8", "replace")[:300]


def main(argv, ffmpeg=None):
    token = os.environ.get("KOI_TOKEN", "")
    if not argv or not token:
        print(__doc__)
        return 2
    base = argv[0]
    ffmpeg = ffmpeg if ffmpeg is not None else shutil.which("ffmpeg")
    print("ffmpeg:", ffmpeg or "not found (video cases skipped)")
    failed = False
    for name, payload, files in cases(ffmpeg):
        print("=== %s" % name)
        if payload is None:
            print("  " + files)
            continue
        status, events, detail = run_case(base, token, payload, files)
        if status != 200:
            expected = name.startswith("audio") and status == 422
            print("  HTTP %d %s%s" % (status, detail, "  (expected for silent audio: no speech)" if expected else ""))
            failed = failed or not expected
            continue
        names = [event for event, _ in events]
        print("  events:", " ".join(names))
        for event, data in events:
            if event in ("transcript", "risk", "error"):
                print("  %s: %s" % (event, json.dumps(data, ensure_ascii=False)))
        problems = check_order(names)
        for problem in problems:
            print("  PROBLEM:", problem)
        failed = failed or bool(problems)
    print("RESULT:", "FAIL" if failed else "OK")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
