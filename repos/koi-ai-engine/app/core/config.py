"""
🆕 [PHASE 2 REBUILD] Rebuilt from scratch — see chat session record for the
full audit that preceded this. The previous version of this file had two
real problems, not just staleness:

  1. `model_name` defaulted to 'distilbert-base-uncased' — an encoder-only
     classification model, architecturally incapable of generating
     conversational replies at all. Corrected to the actually-locked
     Companion LLM: `Qwen/Qwen3-4B-Instruct-2507`
     (TRACK_AI_BACKEND_FINAL_v4_13.md, v4.11 addition, line 17/136).

  2. `google_ai_studio_key` existed as a config field. Confirmed via grep
     (chat session) that nothing in the codebase actually reads it — it
     was dead, not a live external-API violation — but it has no
     legitimate purpose in this architecture (Companion LLM is
     self-hosted, no external generation API permitted for core
     components). Dropped entirely, on purpose, so it can't quietly get
     wired in later by someone who doesn't know it shouldn't be.

`huggingface_api_key` is KEPT — unlike the Google key, it has a real,
legitimate purpose here: authenticating to the Hub to download gated
model weights, if `Qwen/Qwen3-4B-Instruct-2507` (or a future escalation
candidate within the same family, per the locked escalation path) ever
requires it. Currently unused by the code either, same as before — kept
because it has a real reason to exist, not by default inertia.
"""

from functools import lru_cache
from typing import List, Optional

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file='.env', env_file_encoding='utf-8', extra='ignore')

    host: str = Field(default='0.0.0.0', alias='HOST')
    port: int = Field(default=8000, alias='PORT')
    debug: bool = Field(default=False, alias='DEBUG')

    firebase_project_id: str = Field(default='', alias='FIREBASE_PROJECT_ID')
    firebase_admin_sdk: str = Field(default='', alias='FIREBASE_ADMIN_SDK')

    next_js_origin: str = Field(default='http://localhost:3000', alias='NEXT_JS_ORIGIN')
    flutter_origin: str = Field(default='http://localhost:8080', alias='FLUTTER_ORIGIN')

    huggingface_api_key: str = Field(default='', alias='HUGGINGFACE_API_KEY')

    # LOCKED — TRACK_AI_BACKEND_FINAL_v4_13.md line 17/136 (v4.11 addition).
    # Conditional lock, not yet validated — see that same section's PoC
    # gate (b)-(e), none of which have been run yet as of this writing.
    model_name: str = Field(default='Qwen/Qwen3-4B-Instruct-2507', alias='MODEL_NAME')

    # 🆕 TEST-ONLY escape hatch. NEVER the default. Lets a developer smoke-
    # test the /api/v1/chat plumbing (routing, auth, schema validation)
    # without downloading the real ~4B-parameter checkpoint. If set, this
    # OVERRIDES model_name at load time — inference_service.py logs a loud
    # warning when this is active so it's never mistaken for a real run.
    test_model_override: Optional[str] = Field(default=None, alias='KOI_TEST_MODEL_OVERRIDE')

    # Dev hardware per locked spec: 8GB VRAM (RTX 5060), TRACK_AI_BACKEND_
    # FINAL_v4_13.md line 152 (v4.6 addition). 4-bit via bitsandbytes is
    # the locked memory wrapper for THIS (dev) tier — production g4dn.xlarge
    # (T4) is 8-bit per Blueprint line 279, a different, later target.
    # This flag lets a CPU-only dev machine still boot the service for
    # plumbing work, at the cost of not actually being able to run real
    # inference — that limitation is intentional, not silently hidden.
    force_cpu: bool = Field(default=False, alias='KOI_FORCE_CPU')

    max_new_tokens: int = Field(default=512, alias='MAX_NEW_TOKENS')
    inference_timeout: int = Field(default=30, alias='INFERENCE_TIMEOUT')

    @property
    def allowed_origins(self) -> List[str]:
        return [self.next_js_origin, self.flutter_origin]

    @property
    def effective_model_name(self) -> str:
        return self.test_model_override or self.model_name


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
