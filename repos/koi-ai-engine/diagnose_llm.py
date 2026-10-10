"""
Diagnostics: (1) was the 18.7s outlier a JSON-retry, or just a long reply?
             (2) real VRAM/throughput numbers -- PoC gate criterion (d).

HOW THIS WORKS, so it's not a black box:

  We monkey-patch InferenceService._generate_structured and _generate_raw
  at RUNTIME, in this script's own process memory only. This does NOT
  edit inference_service.py on disk -- your actual source file is
  untouched. We're wrapping the existing methods with instrumented
  versions that call the real ones and record extra info (attempt count,
  token count, per-call timing) before returning the same result.

  This is a legitimate, common technique for adding observability to
  code you don't want to permanently modify -- but it's fragile (it
  depends on the exact method names staying the same), so treat this as
  a one-off diagnostic script, not something to build permanent
  reliance on.

RUN THE SAME WAY as test_urdu_ruab.py:
    python diagnose_llm.py
"""

import time
import torch

from app.models.schemas import SessionTurn
from app.services.inference_service import ModelNotLoadedError, inference_service


# ---------------------------------------------------------------------------
# Instrumentation via monkey-patching
# ---------------------------------------------------------------------------
_call_log = []  # each entry: dict with attempt_count, token_count, gen_seconds

_original_generate_raw = inference_service._generate_raw
_original_generate_structured = inference_service._generate_structured


def _patched_generate_raw(prompt):
    start = time.monotonic()
    raw_text = _original_generate_raw(prompt)
    elapsed = time.monotonic() - start
    # tokenize the output text to count actual generated tokens for tok/s
    n_tokens = len(inference_service._tokenizer(raw_text)["input_ids"])
    _call_log.append({"kind": "raw_call", "seconds": elapsed, "tokens": n_tokens})
    return raw_text


def _patched_generate_structured(prompt):
    attempts_before = sum(1 for c in _call_log if c["kind"] == "raw_call")
    result = _original_generate_structured(prompt)
    attempts_after = sum(1 for c in _call_log if c["kind"] == "raw_call")
    attempt_count = attempts_after - attempts_before
    _call_log.append({"kind": "structured_result", "attempt_count": attempt_count})
    return result


inference_service._generate_raw = _patched_generate_raw
inference_service._generate_structured = _patched_generate_structured


# ---------------------------------------------------------------------------
# Part 1: repeat the suspicious prompt 5x, see if attempt_count > 1 ever
# ---------------------------------------------------------------------------
SUSPECT_PROMPT = (
    "Wo kehti hai agar main usay sach much pasand karta hoon to dosto aur "
    "ghar walo se milna chor doon."
)

print("=" * 70)
print("PART 1: repeating the 18.7s outlier prompt 5x to check for retries")
print("=" * 70)

for i in range(1, 6):
    _call_log.clear()
    start = time.monotonic()
    try:
        result = inference_service.generate_reply(SUSPECT_PROMPT, [])
        elapsed = time.monotonic() - start
        structured_entries = [c for c in _call_log if c["kind"] == "structured_result"]
        attempt_count = structured_entries[-1]["attempt_count"] if structured_entries else "?"
        raw_calls = [c for c in _call_log if c["kind"] == "raw_call"]
        total_tokens = sum(c["tokens"] for c in raw_calls)
        print(f"  run {i}: wall={elapsed:.1f}s  attempts={attempt_count}  "
              f"total_generated_tokens={total_tokens}  reply_len_chars={len(result.reply)}")
    except ModelNotLoadedError as exc:
        print(f"  run {i}: FAILED after retries exhausted: {exc}")

# ---------------------------------------------------------------------------
# Part 2: VRAM + throughput on a small varied set (model already warm)
# ---------------------------------------------------------------------------
print()
print("=" * 70)
print("PART 2: VRAM + throughput measurement")
print("=" * 70)

if not torch.cuda.is_available():
    print("  No CUDA device visible -- skipping VRAM measurement.")
else:
    torch.cuda.reset_peak_memory_stats()

    throughput_prompts = [
        "How was your day?",
        "Neend nahi aati aajkal.",
        "I don't know yaar, kuch samajh nahi aa raha.",
    ]

    tokens_per_sec_samples = []
    for p in throughput_prompts:
        _call_log.clear()
        result = inference_service.generate_reply(p, [])
        raw_calls = [c for c in _call_log if c["kind"] == "raw_call"]
        for c in raw_calls:
            if c["seconds"] > 0:
                tokens_per_sec_samples.append(c["tokens"] / c["seconds"])

    avg_tok_s = sum(tokens_per_sec_samples) / len(tokens_per_sec_samples) if tokens_per_sec_samples else 0

    peak_allocated_gb = torch.cuda.max_memory_allocated() / (1024 ** 3)
    peak_reserved_gb = torch.cuda.max_memory_reserved() / (1024 ** 3)
    current_allocated_gb = torch.cuda.memory_allocated() / (1024 ** 3)

    print(f"  Device: {inference_service.device}")
    print(f"  Peak VRAM allocated (this process, since last reset): {peak_allocated_gb:.2f} GB")
    print(f"  Peak VRAM reserved  (this process, since last reset): {peak_reserved_gb:.2f} GB")
    print(f"  Currently allocated right now: {current_allocated_gb:.2f} GB")
    print(f"  Approx generation throughput: {avg_tok_s:.1f} tokens/sec "
          f"(averaged over {len(tokens_per_sec_samples)} calls)")
    print()
    print("  NOTE: 'peak allocated' includes the ~8GB 4-bit model weights")
    print("  themselves plus activation memory for these specific short")
    print("  generations -- it is NOT purely a 'per-request overhead' number.")
    print("  Compare peak_reserved against your GPU's total VRAM to see real headroom.")

print("\nDone.")
