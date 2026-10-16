"""Modal/vLLM wiring for the KOI chat service."""
import json
import os
import sys
from pathlib import Path

import modal

from chat_core import build_app

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
VOLUME_MOUNT = "/vol"
MODEL_PATH = "/vol/model"
BASE_MODEL_REPO = "Qwen/Qwen3-4B-Instruct-2507"
VLLM_VERSION = "vllm==0.13.0"
MAX_MODEL_LEN = 8192
MAX_REPLY_TOKENS = 512

app = modal.App("koi-chat-api")
image = (
    modal.Image.debian_slim(python_version="3.11")
    .pip_install(VLLM_VERSION, "transformers", "torch", "fastapi", "firebase-admin")
    .add_local_python_source("chat_core", "stream_extract")
    .add_local_dir(str(REPO_ROOT / "koi_policy"), remote_path="/root/koi_policy")
)
volume = modal.Volume.from_name("koi-merged-model")
firebase_secret = modal.Secret.from_name("firebase-service-account")
director_secret = modal.Secret.from_name("koi-director")


@app.cls(
    image=image, gpu="T4", volumes={VOLUME_MOUNT: volume},
    secrets=[firebase_secret, director_secret],
    env={
        "VLLM_ATTENTION_BACKEND": "TRITON_ATTN",
        "KOI_EXERCISES": os.environ.get("KOI_EXERCISES", "0"),
        "KOI_CORS_ORIGINS": os.environ.get("KOI_CORS_ORIGINS", "*"),
        "KOI_DEBUG_TRACE": os.environ.get("KOI_DEBUG_TRACE", "0"),
    },
    scaledown_window=300, min_containers=int(os.environ.get("KOI_MIN_CONTAINERS", "0")),
    timeout=600,
)
@modal.concurrent(max_inputs=8)
class ChatServer:
    @modal.enter()
    def load(self):
        import firebase_admin
        from firebase_admin import auth as fb_auth, credentials
        from transformers import AutoTokenizer
        from vllm import AsyncEngineArgs, AsyncLLMEngine, SamplingParams
        from vllm.sampling_params import StructuredOutputsParams

        firebase_admin.initialize_app(credentials.Certificate(json.loads(os.environ["SERVICE_ACCOUNT_JSON"])))
        self.fb_auth = fb_auth
        self.tokenizer = AutoTokenizer.from_pretrained(BASE_MODEL_REPO)
        self.engine = AsyncLLMEngine.from_engine_args(AsyncEngineArgs(
            model=MODEL_PATH, tokenizer=BASE_MODEL_REPO, max_model_len=MAX_MODEL_LEN,
            dtype="float16", gpu_memory_utilization=0.85))

        def sampling(schema=None, **kwargs):
            values = dict(max_tokens=kwargs.pop("max_tokens", MAX_REPLY_TOKENS),
                          temperature=kwargs.pop("temperature", 0.7),
                          top_p=kwargs.pop("top_p", 0.8), top_k=kwargs.pop("top_k", 20),
                          repetition_penalty=kwargs.pop("repetition_penalty", 1.15))
            if schema is not None:
                values["structured_outputs"] = StructuredOutputsParams(json=schema)
            return SamplingParams(**values)
        self.sampling = sampling

    def _verify(self, token):
        if not token:
            raise ValueError("missing token")
        return self.fb_auth.verify_id_token(token)

    @modal.asgi_app()
    def web(self):
        def verify(token):
            return self._verify(token)
        return build_app(self.engine, self.tokenizer, verify, self.sampling,
                         {"MAX_MODEL_LEN": MAX_MODEL_LEN, "MAX_REPLY_TOKENS": MAX_REPLY_TOKENS,
                          "policy_path": "/root/koi_policy"})
