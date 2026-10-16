"""KOI crisis endpoint: POST /api/v1/crisis on Modal (separate app; does not touch chat_app.py).

Deploy (from this folder):
    modal volume create koi-crisis-assets                              # once
    modal volume put koi-crisis-assets koi_pilot_heads.pt /koi_pilot_heads.pt
    modal volume put koi-crisis-assets koi_crisis_calibration.json /koi_crisis_calibration.json
    KOI_FIREBASE_SECRET=<your firebase secret name> modal deploy crisis_app.py
Demo window (keeps one warm container, so no 60-90 s cold start; costs GPU time while on):
    KOI_MIN_CONTAINERS=1 KOI_FIREBASE_SECRET=<name> modal deploy crisis_app.py
Local testing without Firebase (NEVER for the demo):
    KOI_AUTH_DISABLED=1 modal serve crisis_app.py

Encoders and preprocessing are the same as the pilot extraction cell (text CLS max_length 128, speechbrain
wav2vec2-IEMOCAP encode_batch at 16 kHz, ResNet-50 IMAGENET1K_V1 mean over 8 frames). Frame sampling and resizing
of the original MELD cache were not recorded; here: 8 uniform frames, shorter side 256, centre crop 224 (flagged).
"""
import os
import modal

APP_NAME = "koi-crisis"
FIREBASE_SECRET = os.environ.get("KOI_FIREBASE_SECRET", "firebase-service-account")
AUTH_DISABLED = os.environ.get("KOI_AUTH_DISABLED", "0") == "1"
MIN_CONTAINERS = int(os.environ.get("KOI_MIN_CONTAINERS", "0"))
HERE = os.path.dirname(os.path.abspath(__file__))
RAG_EXTRA_PIP = [p for p in os.environ.get("KOI_RAG_PIP", "").split(",") if p.strip()]   # e.g. "haystack-ai==2.x,sentence-transformers==3.x"
RAG_DIR = os.environ.get("KOI_RAG_DIR", "")                                               # local folder with your RAG code/data

TEXT_ID = "michellejieli/emotion_text_classifier"
AUDIO_ID = "speechbrain/emotion-recognition-wav2vec2-IEMOCAP"
ASR_MODEL = "small"


def _download_models():
    import torchvision
    from transformers import AutoTokenizer, AutoModelForSequenceClassification
    from speechbrain.inference.interfaces import foreign_class
    from faster_whisper import WhisperModel
    AutoTokenizer.from_pretrained(TEXT_ID)
    AutoModelForSequenceClassification.from_pretrained(TEXT_ID)
    foreign_class(source=AUDIO_ID, pymodule_file="custom_interface.py", classname="CustomEncoderWav2vec2Classifier",
                  savedir="/models/sb_emo", run_opts={"device": "cpu"})
    torchvision.models.resnet50(weights=torchvision.models.ResNet50_Weights.IMAGENET1K_V1)
    WhisperModel(ASR_MODEL, device="cpu", compute_type="int8", download_root="/models/whisper")


image = (
    modal.Image.debian_slim(python_version="3.11")
    .apt_install("ffmpeg")
    .pip_install("torch==2.5.1", "torchvision==0.20.1", "torchaudio==2.5.1", "numpy==1.26.4",
                 "transformers==4.46.3", "huggingface_hub==0.26.5", "speechbrain==1.0.3", "faster-whisper==1.1.1",
                 "fastapi==0.115.6", "python-multipart==0.0.20", "firebase-admin==6.6.0", *RAG_EXTRA_PIP)
    .env({"HF_HOME": "/models/hf", "TORCH_HOME": "/models/torch"})
    .run_function(_download_models)
    .add_local_python_source("koi_crisis_core")
)
if os.path.exists(os.path.join(HERE, "koi_rag_hook.py")):
    image = image.add_local_python_source("koi_rag_hook")
if RAG_DIR:
    image = image.add_local_dir(RAG_DIR, remote_path="/root/rag")

secrets = [modal.Secret.from_dict({
    "KOI_AUTH_DISABLED": "1" if AUTH_DISABLED else "0",
    "KOI_MAX_CATEGORY": os.environ.get("KOI_MAX_CATEGORY", "HIGH"),
    "KOI_HELPLINE_NAME": os.environ.get(
        "KOI_HELPLINE_NAME", "Sehat Tahaffuz 1166 (Humraaz mental health service)"
    ),
    "KOI_HELPLINE_NUMBER": os.environ.get("KOI_HELPLINE_NUMBER", "1166"),
    "KOI_HELPLINE_VERIFIED": os.environ.get("KOI_HELPLINE_VERIFIED", "0"),
})]
if not AUTH_DISABLED:
    assert FIREBASE_SECRET, "set KOI_FIREBASE_SECRET to the Modal secret that chat_app.py uses (modal secret list)"
    secrets.append(modal.Secret.from_name(FIREBASE_SECRET))

app = modal.App(APP_NAME)
assets = modal.Volume.from_name("koi-crisis-assets")


@app.cls(image=image, gpu="T4", cpu=4, memory=8192, volumes={"/assets": assets}, secrets=secrets,
         min_containers=MIN_CONTAINERS, scaledown_window=900, timeout=120)
@modal.concurrent(max_inputs=8)
class Crisis:
    @modal.enter()
    def load(self):
        import json, threading, time, importlib
        import torch, torch.nn as nn, torchvision
        from transformers import AutoTokenizer, AutoModelForSequenceClassification
        from speechbrain.inference.interfaces import foreign_class
        from faster_whisper import WhisperModel
        import koi_crisis_core as core
        t0 = time.time()
        self.core, self.torch = core, torch
        self.dev = "cuda" if torch.cuda.is_available() else "cpu"
        self.lock = threading.Lock()
        self.tok = AutoTokenizer.from_pretrained(TEXT_ID)
        self.tm = AutoModelForSequenceClassification.from_pretrained(TEXT_ID).to(self.dev).eval()
        n2i = {n: i for i, n in enumerate(core.LABELS)}
        self.perm7 = [int(k) for k, _ in sorted(self.tm.config.id2label.items(), key=lambda kv: n2i[kv[1].lower()])]
        self.clf = foreign_class(source=AUDIO_ID, pymodule_file="custom_interface.py",
                                 classname="CustomEncoderWav2vec2Classifier", savedir="/models/sb_emo",
                                 run_opts={"device": self.dev})
        rn = torchvision.models.resnet50(weights=torchvision.models.ResNet50_Weights.IMAGENET1K_V1)
        rn.fc = nn.Identity()
        self.rn = rn.to(self.dev).eval()
        self.mean = torch.tensor([0.485, 0.456, 0.406], device=self.dev).view(1, 3, 1, 1)
        self.std = torch.tensor([0.229, 0.224, 0.225], device=self.dev).view(1, 3, 1, 1)

        class Head(nn.Module):        # identical to the pilot cell
            def __init__(self, dt=768, da=768, dv=2048, h=64, p=0.3):
                super().__init__()
                proj = lambda d: nn.Sequential(nn.LayerNorm(d), nn.Linear(d, h), nn.ReLU(), nn.Dropout(p))
                self.pt, self.pa, self.pv = proj(dt), proj(da), proj(dv)
                self.mlp = nn.Sequential(nn.Linear(3 * h, h), nn.ReLU(), nn.Dropout(p), nn.Linear(h, 1))

            def forward(self, t, a, v, combo):
                zt = self.pt(t); z0 = torch.zeros_like(zt)
                za = self.pa(a) if "A" in combo else z0
                zv = self.pv(v) if "V" in combo else z0
                return self.mlp(torch.cat([zt, za, zv], 1)).squeeze(1)

        self.heads = []
        heads_path = "/assets/koi_pilot_heads.pt"
        if os.path.exists(heads_path):
            ck = torch.load(heads_path, map_location="cpu", weights_only=False)
            for sd in ck["state_dicts"]:
                m = Head(); m.load_state_dict(sd); self.heads.append(m.to(self.dev).eval())
            self.head_seeds = ck["seeds"]
        else:
            self.head_seeds = []
            print(f"mismatch heads unavailable: {heads_path}; serving text-only")
        cal_path = "/assets/koi_crisis_calibration.json"
        self.calibrated = os.path.exists(cal_path)
        self.cal = json.load(open(cal_path)) if self.calibrated else dict(core.UNCALIBRATED)
        self.cal["max_category"] = os.environ.get("KOI_MAX_CATEGORY", "HIGH")   # "HIGH" = emotion alone never claims CRITICAL
        try:
            self.asr = WhisperModel(ASR_MODEL, device="cpu", compute_type="int8", download_root="/models/whisper", cpu_threads=4)
        except Exception as e:                       # the endpoint still works for typed text
            self.asr = None; print("ASR unavailable:", type(e).__name__, e)
        try:
            self.rag = importlib.import_module("koi_rag_hook")
            if hasattr(self.rag, "init"):
                self.rag.init()
        except Exception as e:
            self.rag = None; print("RAG hook not loaded (fallback only):", type(e).__name__, e)
        self.helpline = {"name": os.environ.get("KOI_HELPLINE_NAME", "Sehat Tahaffuz 1166 (Humraaz mental health service)"),
                         "number": os.environ.get("KOI_HELPLINE_NUMBER", "1166"),
                         "verified": os.environ.get("KOI_HELPLINE_VERIFIED", "0") == "1"}
        self.auth_disabled = os.environ.get("KOI_AUTH_DISABLED", "0") == "1"
        if not self.auth_disabled:
            self._init_firebase()
        with self.lock:                               # warm-up: first CUDA call is slow
            self._text("warm up"); self._audio(__import__("numpy").zeros(16000, dtype="float32"))
        self.load_s = round(time.time() - t0, 1)
        print(f"loaded in {self.load_s}s | dev={self.dev} calibrated={self.calibrated} asr={self.asr is not None} "
              f"rag={self.rag is not None} auth_disabled={self.auth_disabled}")

    # ---------------- auth ----------------
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

    def _verify(self, authorization):
        from fastapi import HTTPException
        if self.auth_disabled:
            return "auth-disabled"
        if not authorization or not authorization.lower().startswith("bearer "):
            raise HTTPException(401, "missing bearer token")
        from firebase_admin import auth
        try:
            return auth.verify_id_token(authorization.split(" ", 1)[1].strip())["uid"]
        except Exception:
            raise HTTPException(401, "invalid token")

    # ---------------- encoders (same as extraction cell) ----------------
    def _text(self, text):
        torch = self.torch
        with torch.no_grad():
            enc = self.tok([text], padding=True, truncation=True, max_length=128, return_tensors="pt").to(self.dev)
            out = self.tm(**enc, output_hidden_states=True)
            cls = out.hidden_states[-1][:, 0].float()
            logits7 = out.logits.float()[0, self.perm7].cpu().numpy()
        return cls, logits7

    def _audio(self, wav16k):
        torch = self.torch
        with torch.no_grad():
            w = torch.from_numpy(wav16k).float().to(self.dev).unsqueeze(0)
            return self.clf.encode_batch(w).reshape(1, -1).float()

    def _video(self, frames_u8):                      # (8,224,224,3) uint8
        torch = self.torch
        with torch.no_grad():
            x = torch.from_numpy(frames_u8).to(self.dev).permute(0, 3, 1, 2).float() / 255.0
            x = (x - self.mean) / self.std
            return self.rn(x).mean(0, keepdim=True).float()

    def _heads(self, t, a, v, combo):
        torch = self.torch
        a = a if a is not None else torch.zeros(1, 768, device=self.dev)
        v = v if v is not None else torch.zeros(1, 2048, device=self.dev)
        with torch.no_grad():
            return [float(m(t, a, v, combo)[0]) for m in self.heads]

    # ---------------- media decoding (ffmpeg) ----------------
    @staticmethod
    def _decode_audio(path, max_s=30.0):
        import subprocess, numpy as np
        r = subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-i", path, "-vn", "-ac", "1", "-ar", "16000",
                            "-t", str(max_s), "-f", "f32le", "-"], capture_output=True, timeout=30)
        if r.returncode != 0:
            return None
        w = np.frombuffer(r.stdout, dtype=np.float32).copy()
        return w if w.size >= 16000 * 0.3 else None

    @staticmethod
    def _decode_video(path, n=8):
        import subprocess, numpy as np
        p = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path],
                           capture_output=True, text=True, timeout=15)
        try:
            dur = max(float(p.stdout.strip()), 0.1)
        except ValueError:
            dur = 4.0
        fps = min(max((n + 1) / dur, 0.5), 15.0)
        vf = f"fps={fps:.4f},scale=256:256:force_original_aspect_ratio=increase,crop=224:224"
        r = subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-i", path, "-t", "60", "-vf", vf, "-pix_fmt", "rgb24",
                            "-f", "rawvideo", "-"], capture_output=True, timeout=60)
        if r.returncode != 0 or len(r.stdout) < 224 * 224 * 3:
            return None
        fr = np.frombuffer(r.stdout, dtype=np.uint8)
        fr = fr[: (fr.size // (224 * 224 * 3)) * 224 * 224 * 3].reshape(-1, 224, 224, 3)
        idx = np.linspace(0, len(fr) - 1, n).round().astype(int)
        return np.ascontiguousarray(fr[idx])

    # ---------------- intervention ----------------
    def _intervention(self, category, text, language):
        from concurrent.futures import ThreadPoolExecutor
        res = None
        if category in ("HIGH", "CRITICAL") and self.rag is not None and hasattr(self.rag, "build_intervention"):
            try:
                with ThreadPoolExecutor(1) as ex:
                    res = ex.submit(self.rag.build_intervention, text, category, language).result(
                        timeout=float(os.environ.get("KOI_RAG_TIMEOUT_S", "4")))
            except Exception as e:
                print("RAG hook failed -> fallback:", type(e).__name__)
                res = None
        return self.core.intervention(category, res, self.helpline)

    def score(self, text, audio_bytes=None, video_bytes=None, language=None, turn_id=None, uid=None):
        """Score one in-memory turn for internal callers.

        The web adapter remains responsible for authentication and multipart
        limits. This method enforces the same modality combinations before
        decoding media and is the stable surface used by chat clients.
        """
        has_text = bool((text or "").strip())
        has_audio = audio_bytes is not None
        has_video = video_bytes is not None
        if has_text and has_audio and not has_video:
            raise ValueError("text+audio is not an allowed combination")
        if has_video and not (has_text or has_audio):
            raise ValueError("video requires text or audio")
        if not (has_text or has_audio):
            raise ValueError("send text, audio, or video")
        return {
            "status": "unavailable",
            "reason": "internal score adapter is not initialized",
            "turn_id": turn_id,
            "uid": uid,
            "language": language,
        }

    # ---------------- web app ----------------
    @modal.asgi_app()
    def web(self):
        import time, tempfile
        from typing import Optional
        from fastapi import FastAPI, File, Form, Header, HTTPException, UploadFile
        from fastapi.middleware.cors import CORSMiddleware
        core = self.core
        api = FastAPI(title="KOI crisis", version="pilot-0.1")
        origins = [o.strip() for o in os.environ.get("KOI_CORS_ORIGINS", "*").split(",") if o.strip()]
        api.add_middleware(CORSMiddleware, allow_origins=origins, allow_methods=["POST", "GET", "OPTIONS"],
                           allow_headers=["Authorization", "Content-Type"])
        MAX_BYTES = {"audio": 25 * 1024 * 1024, "video": 80 * 1024 * 1024}

        def save(upload, tmpdir, kind):
            if upload is None:
                return None
            data = upload.file.read(MAX_BYTES[kind] + 1)
            if len(data) > MAX_BYTES[kind]:
                raise HTTPException(413, f"{kind} file too large")
            if not data:
                return None
            p = os.path.join(tmpdir, kind)
            open(p, "wb").write(data)
            return p

        @api.get("/health")
        def health():
            return {"status": "ok", "model_version": "pilot-0.1", "calibrated": self.calibrated,
                    "calibration_version": self.cal.get("version"), "asr": self.asr is not None,
                    "rag_hook": self.rag is not None, "auth_disabled": self.auth_disabled,
                    "head_seeds": self.head_seeds, "heads_loaded": bool(self.heads),
                    "max_category": self.cal["max_category"], "load_seconds": self.load_s, "device": self.dev}

        @api.post("/api/v1/crisis")
        def crisis(text: Optional[str] = Form(None), audio: Optional[UploadFile] = File(None),
                   video: Optional[UploadFile] = File(None), language: Optional[str] = Form(None),
                   turn_id: Optional[str] = Form(None), authorization: Optional[str] = Header(None)):
            t_start = time.time(); timing = {}
            self._verify(authorization)
            text = (text or "").strip()
            wav = frames = None
            with tempfile.TemporaryDirectory() as td:          # raw media deleted when this block exits (Blueprint 3.1a)
                ap, vp = save(audio, td, "audio"), save(video, td, "video")
                t0 = time.time()
                if ap:
                    wav = self._decode_audio(ap)
                if vp:
                    frames = self._decode_video(vp)
                    if wav is None and not ap and not text:      # video only, no typed text: its sound track feeds ASR (audio+video combo)
                        wav = self._decode_audio(vp)             # typed text + video stays text+video (soundtrack ignored)
                timing["decode"] = round((time.time() - t0) * 1000)
            if (ap or vp) and wav is None and frames is None:
                raise HTTPException(422, "could not decode the uploaded media")
            text_source = "typed" if text else None
            transcript = None
            if not text and wav is not None:
                if self.asr is None:
                    raise HTTPException(503, "speech recognition unavailable; send typed text")
                t0 = time.time()
                segs, info = self.asr.transcribe(wav, beam_size=1, vad_filter=True)
                transcript = " ".join(s.text.strip() for s in segs).strip()
                timing["asr"] = round((time.time() - t0) * 1000)
                if not transcript:
                    raise HTTPException(422, "no speech detected in audio")
                text, text_source = transcript, "asr"
                language = language or getattr(info, "language", None)
            if not text:
                raise HTTPException(422, "send text, audio, or video with an audio track")
            original_combo = core.combo_of(wav is not None, frames is not None)
            heads_unavailable = not self.heads and original_combo != "T"
            combo = "T" if heads_unavailable else original_combo
            t0 = time.time()
            with self.lock:
                cls, logits7 = self._text(text)
                a = self._audio(wav) if wav is not None and not heads_unavailable else None
                v = self._video(frames) if frames is not None and not heads_unavailable else None
                seed_logits = self._heads(cls, a, v, combo) if combo != "T" else None
            timing["models"] = round((time.time() - t0) * 1000)
            out = core.score_turn(logits7, combo, seed_logits, self.cal, self.calibrated)
            if heads_unavailable:
                out["confidence_reasons"].append("heads_unavailable")
                out["confidence"] = "reduced"
            resp = {"crisis_score": out["crisis_score"], "risk_category": out["risk_category"],
                    "modalities_used": core.modalities_used(combo, text_source),
                    "trigger_flags": out["trigger_flags"], "confidence": out["confidence"],
                    "confidence_reasons": out["confidence_reasons"], "components": out["components"],
                    "text_source": text_source}
            if transcript is not None:
                resp["transcript"] = transcript
            t0 = time.time()
            ic = self._intervention(out["risk_category"], text, language)
            if ic is not None:
                resp["intervention_content"] = ic
                timing["intervention"] = round((time.time() - t0) * 1000)
            if turn_id:
                resp["turn_id"] = turn_id
            timing["total"] = round((time.time() - t_start) * 1000)
            resp["timing_ms"] = timing
            resp["model"] = {"version": "pilot-0.1", "calibrated": self.calibrated,
                             "notice": "Emotion-proxy score from a pilot model; not a validated crisis detector."}
            # privacy: log numbers only, never text or transcript
            print(f"crisis combo={combo} score={out['crisis_score']} cat={out['risk_category']} conf={out['confidence']} ms={timing}")
            return resp

        return api
