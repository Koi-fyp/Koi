"""
8-bit local precision test -- isolates "does precision change break anything"
from "is the real g4dn.xlarge/T4 instance different" (a separate, later
question). Production is locked to 8-bit on merged LoRA weights
(TRACK_AI_BACKEND_FINAL_v4_13 DevOps profile); tonight's testing was all
4-bit. This checks whether tonight's fixes/findings hold at 8-bit, using
your ALREADY-DOWNLOADED model files -- no new download needed.

APPROACH: monkey-patch ONLY inference_service._ensure_loaded (the loading
method) to request 8-bit instead of 4-bit. _build_prompt, _generate_raw,
_generate_structured, _parse_structured_output are all left completely
untouched -- so any behavior difference we see is attributable to
precision, not to a different code path. inference_service.py on disk is
NOT modified.

RUN THE SAME WAY:
    python test_8bit_local.py

Uses less GPU memory pressure than a fresh full run since this is a
single condition -- should be faster than tonight's earlier scripts.
"""

import time
import torch

from app.services.inference_service import ModelNotLoadedError, inference_service


def _detect_repetition_loop(raw_text: str, min_words: int = 18) -> bool:
    """Same verified detector used earlier tonight."""
    words = raw_text.split()
    if len(words) < min_words:
        return False
    unique_ratio = len(set(words)) / len(words)
    if unique_ratio < 0.55:
        return True
    for n in (3, 4, 5, 6):
        for i in range(len(words) - n):
            phrase = " ".join(words[i:i + n])
            if raw_text.count(phrase) >= 3:
                return True
    return False


def _patched_ensure_loaded_8bit(self) -> None:
    """Identical to the real _ensure_loaded, except load_in_8bit=True
    instead of load_in_4bit=True, and simpler BitsAndBytesConfig (8-bit
    doesn't use compute_dtype/double_quant/quant_type -- those are
    4-bit-specific bitsandbytes options)."""
    if self._model is not None:
        return

    from transformers import AutoModelForCausalLM, AutoTokenizer, BitsAndBytesConfig
    from app.core.config import settings

    model_name = settings.effective_model_name
    cuda_available = torch.cuda.is_available() and not settings.force_cpu
    if not cuda_available:
        raise RuntimeError("No CUDA device -- 8-bit test requires GPU, same as production target.")

    print(f"Loading tokenizer for '{model_name}'...")
    self._tokenizer = AutoTokenizer.from_pretrained(
        model_name, token=settings.huggingface_api_key or None,
    )

    print(f"Loading '{model_name}' in 8-bit (bitsandbytes) -- matches PRODUCTION precision...")
    quant_config = BitsAndBytesConfig(load_in_8bit=True)
    self._model = AutoModelForCausalLM.from_pretrained(
        model_name,
        quantization_config=quant_config,
        device_map="auto",
        token=settings.huggingface_api_key or None,
    )
    self._device = "cuda (8-bit)"
    self._model.eval()
    print(f"Model loaded on device: {self._device}")


# Bind the patched method to the singleton instance
import types
inference_service._ensure_loaded = types.MethodType(_patched_ensure_loaded_8bit, inference_service)


import warnings
warnings.filterwarnings("ignore", message=".*MatMul8bitLt.*")

TEST_PROMPTS = [
    ("Roman Urdu", "Usne kaha agar maine kisi ko ghar ki baat batayi to mera bahut bura hoga."),
]
N_DRAWS = 2


def main():
    if torch.cuda.is_available():
        torch.cuda.reset_peak_memory_stats()

    print("=" * 70)
    print("8-BIT LOCAL TEST (same model files, precision changed only)")
    print("=" * 70)

    results = []
    for lang, prompt in TEST_PROMPTS:
        for draw in range(1, N_DRAWS + 1):
            start = time.monotonic()
            try:
                result = inference_service.generate_reply(prompt, [])
                elapsed = time.monotonic() - start
                looped = _detect_repetition_loop(result.reply)
                status = "LOOPED" if looped else "ok"
                print(f"  [{lang:12s}] draw {draw}: {status:6s}  "
                      f"emotion={result.companion_state.emotion!r} "
                      f"intensity={result.companion_state.intensity} "
                      f"{elapsed:.1f}s")
                print(f"      reply: {result.reply[:150]}...")
                results.append({"lang": lang, "outcome": "repetition_loop" if looped else "ok"})
            except ModelNotLoadedError as exc:
                print(f"  [{lang:12s}] draw {draw}: json_retry_exhausted: {exc}")
                results.append({"lang": lang, "outcome": "json_retry_exhausted"})

    total = len(results)
    ok = sum(1 for r in results if r["outcome"] == "ok")
    loops = sum(1 for r in results if r["outcome"] == "repetition_loop")
    json_fails = sum(1 for r in results if r["outcome"] == "json_retry_exhausted")

    print(f"\n{'=' * 70}\nSUMMARY: 8-bit\n{'=' * 70}")
    print(f"  ok: {ok}/{total}  repetition_loop: {loops}/{total}  json_retry_exhausted: {json_fails}/{total}")

    if torch.cuda.is_available():
        peak_allocated_gb = torch.cuda.max_memory_allocated() / (1024 ** 3)
        peak_reserved_gb = torch.cuda.max_memory_reserved() / (1024 ** 3)
        print(f"\n  Peak VRAM allocated: {peak_allocated_gb:.2f} GB  (4-bit tonight was 2.58 GB)")
        print(f"  Peak VRAM reserved:  {peak_reserved_gb:.2f} GB  (4-bit tonight was 2.74 GB)")

    print(f"\n  Device: {inference_service.device}")


if __name__ == "__main__":
    main()
