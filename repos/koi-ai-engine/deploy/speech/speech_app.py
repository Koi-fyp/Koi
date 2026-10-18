"""KOI speech endpoint: POST /api/v1/speech on Modal (separate CPU app "koi-speech"; does not touch chat or crisis).

PROPOSED, NOT DEPLOYED. Contract: docs/contracts/SPEECH_API_v1_PROPOSED.md.

Ahmad runs (never an agent):
    agent_tasks\\upload_voices.bat      # once: modal volume create koi-voices + put the 4 voices
    agent_tasks\\deploy_speech.bat      # modal deploy deploy/speech/speech_app.py
Demo window (keeps one warm CPU container):
    KOI_SPEECH_MIN_CONTAINERS=1 modal deploy deploy/speech/speech_app.py

Text -> Piper 1.8.0 (Python API, CPU ONNX) -> WAV -> Rhubarb Lip Sync 1.14.0 (phonetic for ur voices,
pocketSphinx for en voices, 30 s timeout) -> cues validated with cue_validator.py -> inline base64 JSON.
Firebase verification follows deploy/modal/crisis_app.py (_init_firebase / _verify), same secret name.
"""
import os
import modal

APP_NAME = "koi-speech"
FIREBASE_SECRET = os.environ.get("KOI_FIREBASE_SECRET", "firebase-service-account")
MIN_CONTAINERS = int(os.environ.get("KOI_SPEECH_MIN_CONTAINERS", "0"))

RHUBARB_VERSION = "1.14.0"
RHUBARB_URL = (f"https://github.com/DanielSWolf/rhubarb-lip-sync/releases/download/v{RHUBARB_VERSION}/"
               f"Rhubarb-Lip-Sync-{RHUBARB_VERSION}-Linux.zip")
# TODO(Ahmad): replace with the SHA-256 of Rhubarb-Lip-Sync-1.14.0-Linux.zip from a trusted source
# (compute it on a file you downloaded and checked yourself). While this placeholder is here the build
# prints a WARNING and the download is NOT verified.
RHUBARB_SHA256 = "a9a9074862cff47b2d59b8bf399a678a3b0b74f9452ad6ad94cb292913dd8667"
RHUBARB_DIR = "/opt/rhubarb"
VOICES_DIR = "/voices"

_checksum = (f'if [ "{RHUBARB_SHA256}" = "TODO-RHUBARB-SHA256-NOT-SET" ]; then '
             f'echo "WARNING: RHUBARB_SHA256 is a TODO placeholder; Rhubarb download NOT verified"; '
             f'else echo "{RHUBARB_SHA256}  /tmp/rhubarb.zip" | sha256sum -c - ; fi')

image = (
    modal.Image.debian_slim(python_version="3.11")
    .apt_install("curl", "unzip")
    .run_commands(
        f"curl -fsSL -o /tmp/rhubarb.zip {RHUBARB_URL}",
        _checksum,
        f"mkdir -p {RHUBARB_DIR} && unzip -q /tmp/rhubarb.zip -d {RHUBARB_DIR} && rm /tmp/rhubarb.zip",
        f"chmod +x {RHUBARB_DIR}/*/rhubarb",
    )
    .pip_install("piper-tts==1.8.0", "onnxruntime==1.31.0", "fastapi==0.115.6", "firebase-admin==6.6.0")
    .add_local_python_source("speech_core", "cue_validator")
)

secrets = [modal.Secret.from_name(FIREBASE_SECRET)]
app = modal.App(APP_NAME)
voices = modal.Volume.from_name("koi-voices")


@app.cls(image=image, cpu=2, memory=2048, volumes={VOICES_DIR: voices.read_only()}, secrets=secrets,
         min_containers=MIN_CONTAINERS, scaledown_window=300, timeout=120)
@modal.concurrent(max_inputs=4)
class Speech:
    @modal.enter()
    def load(self):
        import glob, threading, time
        import speech_core as core
        t0 = time.time()
        self.core = core
        core.sweep_stale_tempdirs()
        found = sorted(glob.glob(f"{RHUBARB_DIR}/*/rhubarb"))
        self.rhubarb_bin = found[0] if found else None
        self.voices, self.locks = {}, {}
        for model_id, _, _ in core.VOICES.values():
            onnx = os.path.join(VOICES_DIR, model_id + ".onnx")
            if not (os.path.isfile(onnx) and os.path.isfile(onnx + ".json")):
                print(f"voice missing: {model_id}")
                continue
            try:
                from piper import PiperVoice
                self.voices[model_id] = PiperVoice.load(onnx, config_path=onnx + ".json")
                self.locks[model_id] = threading.Lock()
            except Exception as e:
                print(f"voice load failed: {model_id} {type(e).__name__}")
        self._init_firebase()
        print(f"loaded in {round(time.time() - t0, 1)}s | voices={sorted(self.voices)} rhubarb={self.rhubarb_bin is not None}")

    # ---------------- auth (copied from crisis_app.py) ----------------
    def _init_firebase(self):
        import json, firebase_admin
        from firebase_admin import credentials
        if firebase_admin._apps:
            return
        sa = None
        for k, v in os.environ.items():              # find the service-account JSON whatever the key is called
            if v.strip().startswith("{"):
                try:
                    j = json.loads(v)
                    if j.get("type") == "service_account":
                        sa = j; break
                except Exception:
                    pass
        if sa:
            firebase_admin.initialize_app(credentials.Certificate(sa))
        else:
            pid = os.environ.get("FIREBASE_PROJECT_ID") or os.environ.get("GOOGLE_CLOUD_PROJECT")
            assert pid, "firebase secret has neither a service-account JSON nor FIREBASE_PROJECT_ID"
            firebase_admin.initialize_app(options={"projectId": pid})

    @staticmethod
    def _verify_token(token):
        from firebase_admin import auth
        return auth.verify_id_token(token)

    # ---------------- engines ----------------
    def _synthesize(self, model_id, text, wav_path):
        import wave
        voice = self.voices.get(model_id)
        if voice is None:
            raise self.core.SpeechError(503, "speech-unavailable")
        with self.locks[model_id], wave.open(str(wav_path), "wb") as fh:
            voice.synthesize_wav(text, fh)

    def _rhubarb(self, wav_path, cues_path, recognizer, timeout_s):
        if self.rhubarb_bin is None:
            raise self.core.SpeechError(503, "speech-unavailable")
        self.core.run_rhubarb(self.rhubarb_bin, wav_path, cues_path, recognizer, timeout_s)

    def _health(self):
        return {"voices_found": sorted(v for v, (m, _, _) in self.core.VOICES.items() if m in self.voices),
                "rhubarb_found": self.rhubarb_bin is not None}

    # ---------------- web app ----------------
    @modal.asgi_app()
    def web(self):
        core = self.core
        origins = [o.strip() for o in os.environ.get("KOI_CORS_ORIGINS", "*").split(",") if o.strip()]
        service = core.SpeechService(self._synthesize, self._rhubarb)
        return core.build_app(service, self._verify_token, core.RateLimiter(), self._health, origins)
