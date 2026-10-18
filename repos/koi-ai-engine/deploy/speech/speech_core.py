"""KOI speech core: POST /api/v1/speech logic, kept free of Modal so it can be tested locally.

PROPOSED, NOT DEPLOYED. Contract: docs/contracts/SPEECH_API_v1_PROPOSED.md.

speech_app.py (Modal app "koi-speech") supplies the real Piper synthesizer, the Rhubarb binary and the
Firebase verifier; test_speech_core.py supplies stubs. Privacy: text, audio and tokens are never logged;
the only log line is voice_id, char count, outcome code and timings.
"""
import base64
import json
import shutil
import subprocess
import tempfile
import threading
import time
import unicodedata
import uuid
import wave
from collections import deque
from pathlib import Path

from cue_validator import validate_rhubarb_document

MAX_TEXT_CHARS = 450
MAX_AUDIO_S = 40.0
MAX_BODY_BYTES = 8 * 1024
RHUBARB_TIMEOUT_S = 30
RATE_LIMIT = 10
RATE_WINDOW_S = 60.0
TMP_PREFIX = "koi-speech-"

# public voice_id -> (Piper model id = <id>.onnx in the voices volume, language, Rhubarb recognizer)
VOICES = {
    "raza_ur": ("ur_PK-fasih-medium", "ur", "phonetic"),
    "aisha_ur": ("ur_PK-aegis_female-medium", "ur", "phonetic"),
    "raza_en": ("en_US-hfc_male-medium", "en", "pocketSphinx"),
    "aisha_en": ("en_US-hfc_female-medium", "en", "pocketSphinx"),
}
REQUEST_FIELDS = {"text", "voice_id", "language", "generation_id"}

# Arabic-script blocks (Urdu is written in them): Arabic, Arabic Supplement, Arabic Extended-A,
# Presentation Forms-A and -B.
_ARABIC_BLOCKS = ((0x0600, 0x06FF), (0x0750, 0x077F), (0x08A0, 0x08FF), (0xFB50, 0xFDFF), (0xFE70, 0xFEFF))


class SpeechError(Exception):
    """A failure the endpoint reports as HTTP status + {"error": {"code": code}}."""

    def __init__(self, status, code, retry_after=None):
        super().__init__(code)
        self.status, self.code, self.retry_after = status, code, retry_after


def _in_arabic_block(ch):
    cp = ord(ch)
    return any(lo <= cp <= hi for lo, hi in _ARABIC_BLOCKS)


def script_counts(text):
    """(urdu_letters, arabic_block_chars, latin_letters, other_script_letters) in text."""
    urdu = arabic = latin = other = 0
    for ch in text:
        if _in_arabic_block(ch):
            arabic += 1
            if ch.isalpha():
                urdu += 1
        elif ch.isalpha():
            if unicodedata.name(ch, "").startswith("LATIN "):
                latin += 1
            else:
                other += 1
    return urdu, arabic, latin, other


def check_language(text, language):
    """ur voices: Urdu-script letters and no Latin letters. en voices: Latin letters and no Arabic-script
    characters. Mixed or other-script text fails both. Roman Urdu is Latin and cannot be told apart from
    English here: the client must keep Roman Urdu text-only."""
    urdu, arabic, latin, other = script_counts(text)
    if language == "ur":
        ok = urdu > 0 and latin == 0 and other == 0
    else:
        ok = latin > 0 and arabic == 0 and other == 0
    if not ok:
        raise SpeechError(422, "language-mismatch")


def parse_request(body):
    """Validate the raw request body; returns the four fields. Never echoes input in errors."""
    if len(body) > MAX_BODY_BYTES:
        raise SpeechError(413, "text-too-long")
    try:
        data = json.loads(body.decode("utf-8"))
    except (UnicodeDecodeError, ValueError):
        raise SpeechError(400, "invalid-request")
    if not isinstance(data, dict):
        raise SpeechError(400, "invalid-request")
    if set(data) != REQUEST_FIELDS or not all(isinstance(data[k], str) for k in REQUEST_FIELDS):
        raise SpeechError(422, "invalid-request")
    try:
        uuid.UUID(data["generation_id"])
    except ValueError:
        raise SpeechError(422, "invalid-request")
    if data["voice_id"] not in VOICES:
        raise SpeechError(422, "voice-not-allowed")
    if data["language"] not in ("ur", "en"):
        raise SpeechError(422, "invalid-request")
    text = data["text"].strip()
    if not text:
        raise SpeechError(422, "invalid-request")
    if len(data["text"]) > MAX_TEXT_CHARS:
        raise SpeechError(413, "text-too-long")
    if data["language"] != VOICES[data["voice_id"]][1]:
        raise SpeechError(422, "language-mismatch")
    check_language(text, data["language"])
    return {"text": text, "voice_id": data["voice_id"], "language": data["language"],
            "generation_id": data["generation_id"]}


def uid_from_authorization(authorization, verify_token):
    """Same pattern as deploy/modal/crisis_app.py Crisis._verify; verify_token(token) returns the decoded claims."""
    if not authorization or not authorization.lower().startswith("bearer "):
        raise SpeechError(401, "unauthenticated")
    try:
        return verify_token(authorization.split(" ", 1)[1].strip())["uid"]
    except Exception:
        raise SpeechError(401, "unauthenticated")


class RateLimiter:
    """Sliding window, in memory, per container: at most `limit` requests per `window_s` per uid."""

    def __init__(self, limit=RATE_LIMIT, window_s=RATE_WINDOW_S, clock=time.monotonic):
        self.limit, self.window_s, self.clock = limit, window_s, clock
        self.lock = threading.Lock()
        self.hits = {}

    def check(self, uid):
        now = self.clock()
        with self.lock:
            for key in [k for k, q in self.hits.items() if not q or now - q[-1] >= self.window_s]:
                del self.hits[key]
            q = self.hits.setdefault(uid, deque())
            while q and now - q[0] >= self.window_s:
                q.popleft()
            if len(q) >= self.limit:
                raise SpeechError(429, "rate-limited", retry_after=max(1, int(self.window_s - (now - q[0])) + 1))
            q.append(now)


def run_rhubarb(binary, wav_path, cues_path, recognizer, timeout_s):
    """Rhubarb as in voice_bench.py; subprocess.run kills the child when the timeout expires."""
    subprocess.run([str(binary), "-r", recognizer, "-f", "json", "-o", str(cues_path), str(wav_path)],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=timeout_s, check=True)


def sweep_stale_tempdirs(root=None):
    """Remove koi-speech-* folders left by a killed container (as voice_service.py does at start-up)."""
    for path in Path(root or tempfile.gettempdir()).glob(TMP_PREFIX + "*"):
        shutil.rmtree(path, ignore_errors=True)


def _wav_info(path):
    with wave.open(str(path), "rb") as fh:
        rate = fh.getframerate()
        return rate, (fh.getnframes() / rate if rate else 0.0)


class SpeechService:
    """synthesize(model_id, text, wav_path) writes a WAV; rhubarb(wav_path, cues_path, recognizer, timeout_s)
    writes Rhubarb JSON. Both run inside a per-request TemporaryDirectory that is removed on every exit."""

    def __init__(self, synthesize, rhubarb, tmp_root=None, max_audio_s=MAX_AUDIO_S,
                 rhubarb_timeout_s=RHUBARB_TIMEOUT_S, log=print):
        self.synthesize, self.rhubarb, self.tmp_root = synthesize, rhubarb, tmp_root
        self.max_audio_s, self.rhubarb_timeout_s, self.log = max_audio_s, rhubarb_timeout_s, log

    def speak(self, req):
        model_id, _, recognizer = VOICES[req["voice_id"]]
        timings, outcome, t_start = {}, "speech-unavailable", time.perf_counter()
        try:
            with tempfile.TemporaryDirectory(prefix=TMP_PREFIX, dir=self.tmp_root) as td:
                wav_path, cues_path = Path(td) / "speech.wav", Path(td) / "cues.json"
                t0 = time.perf_counter()
                self._stage(self.synthesize, model_id, req["text"], wav_path)
                sample_rate, duration = self._stage(_wav_info, wav_path)
                timings["synthesis"] = round((time.perf_counter() - t0) * 1000)
                if duration <= 0:
                    raise SpeechError(503, "speech-unavailable")
                if duration > self.max_audio_s:
                    raise SpeechError(413, "audio-too-long")
                t0 = time.perf_counter()
                self._stage(self.rhubarb, wav_path, cues_path, recognizer, self.rhubarb_timeout_s)
                document = self._stage(lambda p: json.loads(p.read_text(encoding="utf-8")), cues_path)
                timings["cue_extraction"] = round((time.perf_counter() - t0) * 1000)
                if not validate_rhubarb_document(document, duration).ok:
                    raise SpeechError(503, "speech-unavailable")
                cues = [{"start": c["start"], "end": c["end"], "value": c["value"]} for c in document["mouthCues"]]
                audio = wav_path.read_bytes()
            timings["total"] = round((time.perf_counter() - t_start) * 1000)
            outcome = "ok"
        except SpeechError as exc:
            outcome = exc.code
            raise
        finally:
            self.log(f"speech voice_id={req['voice_id']} chars={len(req['text'])} outcome={outcome} "
                     f"timings_ms={timings}")
        return {"generation_id": req["generation_id"], "voice_id": req["voice_id"], "audio_format": "wav",
                "sample_rate": sample_rate, "audio_b64": base64.b64encode(audio).decode("ascii"),
                "mouth_cues": cues, "duration_s": round(duration, 3), "timings_ms": timings}

    def _stage(self, fn, *args):
        """Run one engine step; any failure other than SpeechError is 503 with only its type logged."""
        try:
            return fn(*args)
        except SpeechError:
            raise
        except Exception as exc:
            self.log(f"speech stage failed: {type(exc).__name__}")
            raise SpeechError(503, "speech-unavailable")


def build_app(service, verify_token, limiter, health, cors_origins=("*",)):
    """FastAPI app: GET /health (no token), POST /api/v1/speech (Firebase Bearer)."""
    from fastapi import FastAPI, Request
    from fastapi.middleware.cors import CORSMiddleware
    from fastapi.responses import JSONResponse
    from starlette.concurrency import run_in_threadpool

    api = FastAPI(title="KOI speech", version="proposed-1", docs_url=None, redoc_url=None, openapi_url=None)
    api.add_middleware(CORSMiddleware, allow_origins=list(cors_origins), allow_methods=["POST", "GET", "OPTIONS"],
                       allow_headers=["Authorization", "Content-Type"])
    no_store = {"Cache-Control": "no-store"}

    def error(exc):
        headers = dict(no_store)
        if exc.retry_after:
            headers["Retry-After"] = str(exc.retry_after)
        return JSONResponse({"error": {"code": exc.code}}, status_code=exc.status, headers=headers)

    @api.get("/health")
    def health_route():
        return JSONResponse(health(), headers=no_store)

    @api.post("/api/v1/speech")
    async def speech(request: Request):
        try:
            uid = await run_in_threadpool(uid_from_authorization, request.headers.get("authorization"), verify_token)
            limiter.check(uid)
            req = parse_request(await request.body())
            return JSONResponse(await run_in_threadpool(service.speak, req), headers=no_store)
        except SpeechError as exc:
            return error(exc)
        except Exception as exc:
            service.log(f"speech failed: {type(exc).__name__}")
            return error(SpeechError(503, "speech-unavailable"))

    return api
