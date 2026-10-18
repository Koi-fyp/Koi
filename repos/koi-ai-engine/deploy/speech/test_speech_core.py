"""Offline tests for speech_core.py: stubbed Piper, Rhubarb and Firebase verifier. No Modal, no network."""
import base64
import io
import json
import subprocess
import uuid
import wave

import pytest
from fastapi.testclient import TestClient

import speech_core as core

UR = "السلام علیکم، آپ کیسے ہیں؟"
EN = "Hello, how are you today?"
TOKEN = "good-token-SECRET-123"
UID = "uid-SECRET-abc"


def _write_wav(path, seconds, rate=22050):
    with wave.open(str(path), "wb") as fh:
        fh.setnchannels(1)
        fh.setsampwidth(2)
        fh.setframerate(rate)
        fh.writeframes(b"\x00\x00" * int(seconds * rate))


def _good_cues(duration):
    half = round(duration / 2, 2)
    return [{"start": 0.0, "end": half, "value": "X"}, {"start": half, "end": round(duration, 2), "value": "B"}]


class Engines:
    """Stub Piper + Rhubarb; records every call and the temp folder it ran in."""

    def __init__(self):
        self.seconds = 1.5
        self.synth_calls, self.rhubarb_calls, self.dirs = [], [], []
        self.synth_error = None
        self.rhubarb_error = None
        self.cues = None  # None -> valid cues covering the audio

    def synthesize(self, model_id, text, wav_path):
        self.synth_calls.append((model_id, text))
        self.dirs.append(wav_path.parent)
        assert wav_path.parent.is_dir()
        if self.synth_error:
            raise self.synth_error
        _write_wav(wav_path, self.seconds)

    def rhubarb(self, wav_path, cues_path, recognizer, timeout_s):
        self.rhubarb_calls.append((recognizer, timeout_s))
        if self.rhubarb_error:
            raise self.rhubarb_error
        cues = self.cues if self.cues is not None else _good_cues(self.seconds)
        cues_path.write_text(json.dumps({"metadata": {}, "mouthCues": cues}), encoding="utf-8")


def _verify(token):
    if token != TOKEN:
        raise ValueError("bad token")
    return {"uid": UID}


class Clock:
    def __init__(self):
        self.now = 1000.0

    def __call__(self):
        return self.now


@pytest.fixture
def env(tmp_path):
    engines, logs, clock = Engines(), [], Clock()
    service = core.SpeechService(engines.synthesize, engines.rhubarb, tmp_root=str(tmp_path), log=logs.append)
    limiter = core.RateLimiter(clock=clock)
    app = core.build_app(service, _verify, limiter, lambda: {"voices_found": sorted(core.VOICES), "rhubarb_found": True})
    client = TestClient(app)

    def post(text=UR, voice_id="raza_ur", language=None, token=TOKEN, **extra):
        body = {"text": text, "voice_id": voice_id,
                "language": core.VOICES.get(voice_id, ("", "ur", ""))[1] if language is None else language,
                "generation_id": str(uuid.uuid4()), **extra}
        headers = {"Authorization": f"Bearer {token}"} if token is not None else {}
        return client.post("/api/v1/speech", content=json.dumps(body), headers=headers)

    class E:
        pass

    e = E()
    e.engines, e.logs, e.clock, e.client, e.post, e.tmp = engines, logs, clock, client, post, tmp_path
    return e


def _code(resp):
    return resp.json()["error"]["code"]


# ---------------- success + response shape ----------------
def test_success_response_shape(env):
    r = env.post(UR, "raza_ur")
    assert r.status_code == 200
    body = r.json()
    assert list(body) == ["generation_id", "voice_id", "audio_format", "sample_rate", "audio_b64", "mouth_cues",
                          "duration_s", "timings_ms"]
    assert body["voice_id"] == "raza_ur" and body["audio_format"] == "wav" and body["sample_rate"] == 22050
    assert body["duration_s"] == 1.5
    with wave.open(io.BytesIO(base64.b64decode(body["audio_b64"]))) as fh:
        assert fh.getframerate() == 22050
    assert body["mouth_cues"] == _good_cues(1.5)
    assert set(body["timings_ms"]) == {"synthesis", "cue_extraction", "total"}
    assert r.headers["cache-control"] == "no-store"


def test_generation_id_echoed(env):
    gid = str(uuid.uuid4())
    r = env.client.post("/api/v1/speech", headers={"Authorization": f"Bearer {TOKEN}"},
                        content=json.dumps({"text": EN, "voice_id": "aisha_en", "language": "en", "generation_id": gid}))
    assert r.status_code == 200 and r.json()["generation_id"] == gid


def test_health_needs_no_token_and_reports_only_voices_and_rhubarb(env):
    r = env.client.get("/health")
    assert r.status_code == 200 and set(r.json()) == {"voices_found", "rhubarb_found"}


# ---------------- allowlist ----------------
@pytest.mark.parametrize("voice_id,model_id,text,recognizer", [
    ("raza_ur", "ur_PK-fasih-medium", UR, "phonetic"),
    ("aisha_ur", "ur_PK-aegis_female-medium", UR, "phonetic"),
    ("raza_en", "en_US-hfc_male-medium", EN, "pocketSphinx"),
    ("aisha_en", "en_US-hfc_female-medium", EN, "pocketSphinx"),
])
def test_allowlist_maps_voice_model_and_recognizer(env, voice_id, model_id, text, recognizer):
    r = env.post(text, voice_id)
    assert r.status_code == 200
    assert env.engines.synth_calls == [(model_id, text)]
    assert env.engines.rhubarb_calls == [(recognizer, 30)]


@pytest.mark.parametrize("voice_id", ["fox", "ur_PK-fasih-medium", "RAZA_UR", "", "raza"])
def test_voice_not_allowed(env, voice_id):
    r = env.post(UR, voice_id, language="ur")
    assert r.status_code == 422 and _code(r) == "voice-not-allowed"
    assert env.engines.synth_calls == []


# ---------------- language guard + text limits ----------------
@pytest.mark.parametrize("text,voice_id", [
    (UR, "raza_en"),                                           # Urdu text on an en voice
    (UR, "aisha_en"),
    (EN, "raza_ur"),                                           # Latin text on a ur voice
    (EN, "aisha_ur"),
    ("آج کا weather بہت اچھا ہے", "raza_ur"),                  # mixed
    ("آج کا weather بہت اچھا ہے", "raza_en"),
    ("Hello، how are you۔", "raza_en"),                        # Urdu punctuation inside English
    ("Привет, как дела?", "raza_en"),                          # other script
    ("12345 !!!", "raza_en"),                                  # no letters
    ("۱۲۳", "raza_ur"),                                        # Urdu digits only, no letters
])
def test_language_mismatch(env, text, voice_id):
    r = env.post(text, voice_id)
    assert r.status_code == 422 and _code(r) == "language-mismatch"
    assert env.engines.synth_calls == []


def test_language_field_must_match_voice(env):
    r = env.post(UR, "raza_ur", language="en")
    assert r.status_code == 422 and _code(r) == "language-mismatch"


def test_roman_urdu_is_not_detectable_and_passes_as_latin(env):
    # Documented limitation: the client must keep Roman Urdu text-only; the server cannot tell it from English.
    assert env.post("Aap kaise hain? Main theek hoon.", "raza_en").status_code == 200


@pytest.mark.parametrize("text", ["", "   ", "\n\t"])
def test_empty_text(env, text):
    r = env.post(text, "raza_ur")
    assert r.status_code == 422 and _code(r) == "invalid-request"


def test_451_chars_too_long_450_ok(env):
    r = env.post("ب" * 451, "raza_ur")
    assert r.status_code == 413 and _code(r) == "text-too-long"
    assert env.post("ب" * 450, "raza_ur").status_code == 200


@pytest.mark.parametrize("language", ["ur-Latn", "fr", ""])
def test_unsupported_language(env, language):
    r = env.post(UR, "raza_ur", language=language)
    assert r.status_code == 422 and _code(r) == "invalid-request"


def test_malformed_bodies(env):
    h = {"Authorization": f"Bearer {TOKEN}"}
    assert _code(env.client.post("/api/v1/speech", content=b"not json", headers=h)) == "invalid-request"
    assert env.client.post("/api/v1/speech", content=b"[1]", headers=h).status_code == 400
    assert env.post(UR, "raza_ur", extra="x").status_code == 422
    r = env.client.post("/api/v1/speech", headers=h, content=json.dumps(
        {"text": UR, "voice_id": "raza_ur", "language": "ur", "generation_id": "not-a-uuid"}))
    assert r.status_code == 422 and _code(r) == "invalid-request"
    r = env.client.post("/api/v1/speech", headers=h, content=json.dumps(
        {"text": 5, "voice_id": "raza_ur", "language": "ur", "generation_id": str(uuid.uuid4())}))
    assert r.status_code == 422
    r = env.client.post("/api/v1/speech", headers=h, content=b"{" + b" " * 9000 + b"}")
    assert r.status_code == 413 and _code(r) == "text-too-long"
    assert env.engines.synth_calls == []


def test_validation_errors_do_not_echo_input(env):
    r = env.post("آج کا weather MARKER", "raza_ur")
    assert "MARKER" not in r.text and r.json() == {"error": {"code": "language-mismatch"}}


# ---------------- duration cap ----------------
def test_audio_over_40s_is_413_and_rhubarb_not_run(env):
    env.engines.seconds = 40.5
    r = env.post(UR, "raza_ur")
    assert r.status_code == 413 and _code(r) == "audio-too-long"
    assert env.engines.rhubarb_calls == []


def test_audio_just_under_cap_ok(env):
    env.engines.seconds = 39.9
    assert env.post(UR, "raza_ur").status_code == 200


# ---------------- engine failures -> 503 ----------------
@pytest.mark.parametrize("cues", [
    [],                                                                         # no cues
    [{"start": 0.0, "end": 1.0, "value": "X"}, {"start": 0.5, "end": 1.5, "value": "B"}],   # overlap
    [{"start": 0.0, "end": 3.0, "value": "X"}],                                # beyond audio
    [{"start": 0.0, "end": 1.5, "value": "Z"}],                                # bad shape
    [{"start": 0.0, "end": 0.5, "value": "X"}],                                # does not cover the audio
])
def test_cue_validation_failure_is_503(env, cues):
    env.engines.cues = cues
    r = env.post(UR, "raza_ur")
    assert r.status_code == 503 and _code(r) == "speech-unavailable"


@pytest.mark.parametrize("error", [subprocess.TimeoutExpired(["rhubarb"], 30),
                                   subprocess.CalledProcessError(1, ["rhubarb"]), OSError("missing")])
def test_rhubarb_failure_is_503(env, error):
    env.engines.rhubarb_error = error
    r = env.post(EN, "raza_en")
    assert r.status_code == 503 and _code(r) == "speech-unavailable"


def test_piper_failure_is_503(env):
    env.engines.synth_error = RuntimeError("onnx exploded")
    r = env.post(UR, "raza_ur")
    assert r.status_code == 503 and _code(r) == "speech-unavailable"


def test_run_rhubarb_uses_hard_timeout_and_recognizer(monkeypatch, tmp_path):
    seen = {}

    def fake_run(argv, **kwargs):
        seen.update(argv=argv, **kwargs)

    monkeypatch.setattr(core.subprocess, "run", fake_run)
    core.run_rhubarb("/opt/rhubarb/x/rhubarb", tmp_path / "a.wav", tmp_path / "c.json", "phonetic", core.RHUBARB_TIMEOUT_S)
    assert seen["argv"][1:5] == ["-r", "phonetic", "-f", "json"]
    assert seen["timeout"] == 30 and seen["check"] is True


# ---------------- auth ----------------
@pytest.mark.parametrize("headers", [{}, {"Authorization": "Basic abc"}, {"Authorization": "Bearer "},
                                     {"Authorization": "Bearer wrong"}, {"Authorization": TOKEN}])
def test_auth_missing_or_invalid_is_401(env, headers):
    body = json.dumps({"text": UR, "voice_id": "raza_ur", "language": "ur", "generation_id": str(uuid.uuid4())})
    r = env.client.post("/api/v1/speech", content=body, headers=headers)
    assert r.status_code == 401 and _code(r) == "unauthenticated"
    assert env.engines.synth_calls == []


def test_auth_checked_before_body(env):
    r = env.client.post("/api/v1/speech", content=b"not json")
    assert r.status_code == 401


# ---------------- rate limit ----------------
def test_rate_limit_10_per_minute_per_uid(env):
    for _ in range(10):
        assert env.post(UR, "raza_ur").status_code == 200
    r = env.post(UR, "raza_ur")
    assert r.status_code == 429 and _code(r) == "rate-limited" and int(r.headers["retry-after"]) >= 1
    env.clock.now += 60
    assert env.post(UR, "raza_ur").status_code == 200


def test_rate_limit_is_per_uid():
    limiter = core.RateLimiter(clock=Clock())
    for _ in range(10):
        limiter.check("a")
    with pytest.raises(core.SpeechError):
        limiter.check("a")
    limiter.check("b")


# ---------------- privacy ----------------
def test_no_text_token_uid_or_audio_in_logs(env, capsys):
    marker = "رازدارانہ جملہ"
    ok = env.post(marker, "raza_ur")
    env.engines.synth_error = RuntimeError(marker)          # an engine error message that contains the text
    env.post(marker, "raza_ur")
    env.engines.synth_error = None
    env.engines.cues = []
    env.post(marker, "raza_ur")
    env.post(marker, "raza_ur", token="wrong-SECRET")
    logged = "\n".join(env.logs) + capsys.readouterr().out
    assert env.logs, "expected log lines"
    for secret in (marker, TOKEN, "wrong-SECRET", UID, ok.json()["audio_b64"][:40]):
        assert secret not in logged
    assert all(line.startswith("speech ") for line in env.logs)
    assert any("voice_id=raza_ur chars=14 outcome=ok" in line for line in env.logs)


# ---------------- temp-dir cleanup ----------------
@pytest.mark.parametrize("setup", ["ok", "too_long", "rhubarb_fails", "cues_invalid", "piper_fails"])
def test_temp_dir_removed_on_every_exit(env, setup):
    if setup == "too_long":
        env.engines.seconds = 41
    elif setup == "rhubarb_fails":
        env.engines.rhubarb_error = subprocess.TimeoutExpired(["rhubarb"], 30)
    elif setup == "cues_invalid":
        env.engines.cues = []
    elif setup == "piper_fails":
        env.engines.synth_error = RuntimeError("x")
    env.post(UR, "raza_ur")
    assert len(env.engines.dirs) == 1 and env.engines.dirs[0].name.startswith(core.TMP_PREFIX)
    assert not env.engines.dirs[0].exists()
    assert list(env.tmp.iterdir()) == []


def test_sweep_stale_tempdirs(tmp_path):
    (tmp_path / (core.TMP_PREFIX + "old")).mkdir()
    (tmp_path / "keep-me").mkdir()
    core.sweep_stale_tempdirs(str(tmp_path))
    assert [p.name for p in tmp_path.iterdir()] == ["keep-me"]
