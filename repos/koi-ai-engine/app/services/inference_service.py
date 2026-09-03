"""
🆕 [PHASE 2 REBUILD] Real model loading and generation — the previous
version of this file returned a hardcoded placeholder dict and never
imported torch/transformers at all despite both being in requirements.txt.
This version actually loads and calls the model.

SCOPE, STATED PLAINLY:

  DONE in this file:
    - Loads the real, locked base model (Qwen/Qwen3-4B-Instruct-2507),
      frozen, no adapter — see "NOT done" below for why.
    - 4-bit loading via bitsandbytes when a CUDA device is available,
      matching the locked DEV hardware spec (TRACK_AI_BACKEND_FINAL_v4_13
      line 152: 8GB RTX 5060, v4.6 addition). Falls back to full-precision
      CPU loading otherwise, with a loud warning — this is for plumbing/
      routing development on a machine with no GPU, NOT a claim that CPU
      inference is fast or production-viable.
    - Generation via `transformers.generate()` (the locked default,
      TRACK_AI_BACKEND_FINAL_v4_13 line 148 — no hand-rolled causal loop).
    - Structured output where `companion_state` precedes `reply` in the
      generated JSON, per the locked field-ordering requirement (Blueprint
      §4.1e / line 358) — enforced via prompt instruction + a validate-
      and-retry loop (see `_generate_structured` below), NOT via a formal
      grammar-constrained decoding library.

  EXPLICITLY NOT done, flagged rather than silently skipped:
    - NO LoRA adapter. Phase 3 (training) hasn't run — there is no
      fine-tuned adapter to load yet. This serves the frozen base model.
      `adapter_path` is left as a wired-but-unused hook (see config
      TODO below) for when Phase 3 produces one.
    - NOT real TTFT. `latency_ms` here is full wall-clock generation
      time, because this endpoint is not yet streaming (Phase 3 /
      Blueprint §4.1e territory, FastAPI StreamingResponse/WebSocket).
      Do not read this number against the locked sub-500ms TTFT gate —
      that gate is specifically about streamed time-to-first-token,
      not full-generation time, and Blueprint line 279 itself says
      full generation on the production target is expected to take
      low-single-digit SECONDS, not sub-500ms.
    - NOT grammar-constrained JSON generation. The retry-on-invalid-JSON
      approach below is a reasonable first pass, but per this project's
      own Coding-Agent Implementability Principle, unreliable structured
      output is exactly a silent-failure-mode risk category — a vetted
      constrained-decoding library (e.g. `outlines`, guided generation
      support in a serving framework) should be evaluated before this is
      trusted for the actual PoC gate (b)/(c) criteria in
      TRACK_AI_BACKEND_FINAL_v4_13 line 137. Flagging as a real follow-up
      task, not deciding it here.
    - Model is loaded LAZILY on first request, not at app startup, to
      keep `uvicorn` boot fast for routing/plumbing iteration. This means
      the FIRST real chat request will be slow (multi-second to
      multi-minute model load) — expected, not a bug.
"""

from email import message
import json
import logging
from pyexpat.errors import messages
import time
from typing import Any, Dict, List, Optional

from app.core.config import settings
from app.models.schemas import ChatResponse, CompanionState, SessionTurn

logger = logging.getLogger(__name__)

_MAX_JSON_RETRY_ATTEMPTS = 3

_SYSTEM_INSTRUCTION = (
    "You are KOI, a supportive companion. Respond ONLY with a single JSON "
    "object, with keys in EXACTLY this order: \"companion_state\" first, "
    "then \"reply\". \"companion_state\" is an object with \"emotion\" "
    "(a short lowercase word describing your emotional tone) and "
    "\"intensity\" (a float between 0.0 and 1.0). \"reply\" is your "
    "conversational response text. Output nothing before or after the "
    "JSON object — no markdown fences, no commentary."
)


class ModelNotLoadedError(RuntimeError):
    pass


class InferenceService:
    """
    Lazy-loading singleton wrapper around the Companion LLM. Instantiated
    once at import time (see routes.py), but does not touch torch/
    transformers or download/load any weights until the first call to
    `generate_reply()` — see module docstring for why.
    """

    def __init__(self) -> None:
        self._model = None
        self._tokenizer = None
        self._device: str = "unloaded"

    # ---- lazy loading ----

    def _ensure_loaded(self) -> None:
        if self._model is not None:
            return

        import torch
        from transformers import AutoModelForCausalLM, AutoTokenizer

        model_name = settings.effective_model_name
        if settings.test_model_override:
            logger.warning(
                "KOI_TEST_MODEL_OVERRIDE is set — loading '%s' instead of the "
                "real locked Companion LLM ('%s'). This is a TEST-ONLY "
                "configuration for smoke-testing plumbing. Do NOT trust "
                "generation quality/latency from this process.",
                model_name,
                settings.model_name,
            )

        cuda_available = torch.cuda.is_available() and not settings.force_cpu

        logger.info("Loading tokenizer for '%s'...", model_name)
        self._tokenizer = AutoTokenizer.from_pretrained(
            model_name,
            token=settings.huggingface_api_key or None,
        )

        if cuda_available:
            logger.info(
                "CUDA available — loading '%s' in 4-bit (bitsandbytes), "
                "per locked dev-hardware spec.",
                model_name,
            )
            from transformers import BitsAndBytesConfig

            quant_config = BitsAndBytesConfig(
                load_in_4bit=True,
                bnb_4bit_compute_dtype=torch.bfloat16,
                bnb_4bit_use_double_quant=True,
                bnb_4bit_quant_type="nf4",
            )
            self._model = AutoModelForCausalLM.from_pretrained(
                model_name,
                quantization_config=quant_config,
                device_map="auto",
                token=settings.huggingface_api_key or None,
            )
            self._device = "cuda (4-bit)"
        else:
            logger.warning(
                "No CUDA device available (or KOI_FORCE_CPU set) — loading "
                "'%s' in full precision on CPU. This will be SLOW. This "
                "path exists for routing/plumbing development only, not "
                "for evaluating real model quality or latency.",
                model_name,
            )
            self._model = AutoModelForCausalLM.from_pretrained(
                model_name,
                token=settings.huggingface_api_key or None,
            )
            self._device = "cpu"

        self._model.eval()
        logger.info("Model loaded on device: %s", self._device)

    @property
    def is_loaded(self) -> bool:
        return self._model is not None

    @property
    def device(self) -> str:
        return self._device

    # ---- generation ----

    def _build_prompt(self, message: str, session_history: List[SessionTurn]) -> str:
        messages: List[Dict[str, str]] = [{"role": "system", "content": _SYSTEM_INSTRUCTION}]
        for turn in session_history:
            messages.append({"role": turn.role, "content": turn.content})
        messages.append({"role": "user", "content": message})

        if getattr(self._tokenizer, "chat_template", None) is None:
        # 🆕 Fallback for tokenizers with no chat template (e.g. bare test
        # models like sshleifer/tiny-gpt2). The REAL locked model
        # (Qwen3-4B-Instruct-2507) has a proper instruct chat template —
        # already confirmed via AutoConfig earlier this session — so this
        # branch should only ever fire during tiny-model smoke testing,
        # never in real use. Flagging rather than silently masking that.
            logger.warning(
                "Tokenizer has no chat_template — using manual prompt "
                "concatenation fallback. This is expected ONLY for test "
                "models without instruction tuning, not for the real "
                "Companion LLM."
            )
            return "\n".join(f"{m['role']}: {m['content']}" for m in messages)

        return self._tokenizer.apply_chat_template(
            messages,
            tokenize=False,
            add_generation_prompt=True,
    )

    def _generate_raw(self, prompt: str) -> str:
        import torch

        inputs = self._tokenizer(prompt, return_tensors="pt").to(self._model.device)

        with torch.no_grad():
            output_ids = self._model.generate(
                **inputs,
                max_new_tokens=settings.max_new_tokens,
                do_sample=True,
                temperature=0.7,
                pad_token_id=self._tokenizer.eos_token_id,
            )

        # Only decode the newly generated continuation, not the echoed prompt.
        new_tokens = output_ids[0][inputs["input_ids"].shape[1]:]
        return self._tokenizer.decode(new_tokens, skip_special_tokens=True)

    def _parse_structured_output(self, raw_text: str) -> Optional[Dict[str, Any]]:
        text = raw_text.strip()
        # Tolerate the model wrapping output in markdown fences despite
        # being told not to — a common instruction-following slip.
        if text.startswith("```"):
            text = text.strip("`")
            if text.lower().startswith("json"):
                text = text[4:]
            text = text.strip()

        try:
            parsed = json.loads(text)
        except json.JSONDecodeError:
            return None

        if not isinstance(parsed, dict):
            return None
        if "companion_state" not in parsed or "reply" not in parsed:
            return None

        # Enforce the LOCKED field-ordering requirement (Blueprint line 358):
        # companion_state must precede reply in the raw generated text, not
        # just be present. json.loads() on a Python 3.7+ dict preserves
        # insertion order, so we can check this directly against the
        # source text's key order rather than the parsed dict's iteration
        # order (which would trivially always "pass" after parsing).
        cs_pos = text.find('"companion_state"')
        reply_pos = text.find('"reply"')
        if cs_pos == -1 or reply_pos == -1 or cs_pos > reply_pos:
            logger.warning(
                "Model output had valid JSON but violated the locked "
                "companion_state-before-reply field ordering. Treating as "
                "invalid, will retry."
            )
            return None

        return parsed

    def _generate_structured(self, prompt: str) -> Dict[str, Any]:
        last_raw: str = ""
        for attempt in range(1, _MAX_JSON_RETRY_ATTEMPTS + 1):
            last_raw = self._generate_raw(prompt)
            parsed = self._parse_structured_output(last_raw)
            if parsed is not None:
                return parsed
            logger.warning(
                "Structured output parse/order failed on attempt %d/%d. "
                "Raw output: %r",
                attempt,
                _MAX_JSON_RETRY_ATTEMPTS,
                last_raw[:500],
            )

        # All retries exhausted. Per this project's "flag rather than
        # silently guess" discipline: do not fabricate a fallback
        # companion_state/reply. Fail loudly so the caller (route handler)
        # can return a real 502/500, not a response that looks successful
        # but contains made-up content.
        raise ModelNotLoadedError(
            f"Failed to obtain validly-ordered structured JSON output after "
            f"{_MAX_JSON_RETRY_ATTEMPTS} attempts. Last raw output: "
            f"{last_raw[:500]!r}"
        )

    def generate_reply(
        self, message: str, session_history: List[SessionTurn]
    ) -> ChatResponse:
        self._ensure_loaded()

        start = time.monotonic()
        prompt = self._build_prompt(message, session_history)
        structured = self._generate_structured(prompt)
        elapsed_ms = int((time.monotonic() - start) * 1000)

        companion_state_raw = structured["companion_state"]
        return ChatResponse(
            reply=structured["reply"],
            companion_state=CompanionState(
                emotion=str(companion_state_raw.get("emotion", "neutral")),
                intensity=float(companion_state_raw.get("intensity", 0.5)),
            ),
            latency_ms=elapsed_ms,
        )


# Module-level singleton — imported once by routes.py. Loading is still
# lazy (see _ensure_loaded); constructing this does not load the model.
inference_service = InferenceService()
