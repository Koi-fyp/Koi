"""
Isolated test: repetition_penalty ALONE (no no_repeat_ngram_size, which we
now know collides with the system prompt's own required JSON key names and
causes JSON-retry-exhaustion regardless of language -- see prior run).

CORRECTNESS FIX vs the previous script: that version's run_condition()
labeled BOTH a real repetition-loop AND a JSON-retry-exhaustion as
"looped": True in the results dict -- conflating two different failure
modes under one word. This version tracks three distinct outcomes per
draw: "ok", "repetition_loop" (via the verified text-based detector), and
"json_retry_exhausted" (via ModelNotLoadedError) -- so the summary can't
blur genuinely different problems together again.

Compares against the ALREADY-ESTABLISHED baseline numbers from the earlier
real run (not re-run here, to save GPU time): 1/18 looped, 0/18
json_retry_exhausted, EN=0% UR=11% loop rate.

RUN:
    python test_repetition_penalty_only.py
"""

import time
import torch

from app.services.inference_service import ModelNotLoadedError, inference_service

TEST_PROMPTS = [
    ("EN", "She says if I really loved her I'd stop talking to my friends and family."),
    ("EN", "I can't sleep, I can't focus, everything feels heavy and pointless right now."),
    ("EN", "He told me if I ever tell anyone what happens at home, things will get much worse for me."),
    ("Roman Urdu", "Wo kehti hai agar main usay sach much pasand karta hoon to dosto aur ghar walo se milna chor doon."),
    ("Roman Urdu", "Neend nahi aati, dil kisi kaam mein nahi lagta, sab kuch bojh lagta hai aajkal."),
    ("Roman Urdu", "Usne kaha agar maine kisi ko ghar ki baat batayi to mera bahut bura hoga."),
]
N_DRAWS_PER_PROMPT = 3

_original_generate_raw = inference_service._generate_raw
_call_log = []


def _detect_repetition_loop(raw_text: str, min_words: int = 18) -> bool:
    """Verified against real transcript data earlier this session -- see
    ab_test_repetition_fix.py for the validation this was checked against."""
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


def _patched_generate_raw(prompt):
    from app.core.config import settings as _settings

    inputs = inference_service._tokenizer(prompt, return_tensors="pt").to(
        inference_service._model.device
    )
    start = time.monotonic()
    with torch.no_grad():
        output_ids = inference_service._model.generate(
            **inputs,
            max_new_tokens=_settings.max_new_tokens,
            do_sample=True,
            temperature=0.7,
            pad_token_id=inference_service._tokenizer.eos_token_id,
            repetition_penalty=1.15,  # the ONLY change vs baseline
        )
    elapsed = time.monotonic() - start
    new_tokens = output_ids[0][inputs["input_ids"].shape[1]:]
    raw_text = inference_service._tokenizer.decode(new_tokens, skip_special_tokens=True)
    _call_log.append({
        "seconds": elapsed, "tokens": len(new_tokens),
        "looped": _detect_repetition_loop(raw_text), "raw_text": raw_text,
    })
    return raw_text


def main():
    inference_service._generate_raw = _patched_generate_raw

    outcomes = []  # each: {"lang":.., "outcome": "ok"|"repetition_loop"|"json_retry_exhausted"}

    print("=" * 70)
    print("CONDITION: repetition_penalty=1.15 ALONE (no no_repeat_ngram_size)")
    print("=" * 70)

    for lang, prompt in TEST_PROMPTS:
        for draw in range(1, N_DRAWS_PER_PROMPT + 1):
            _call_log.clear()
            try:
                result = inference_service.generate_reply(prompt, [])
                info = _call_log[-1] if _call_log else {}
                looped = info.get("looped", False)
                outcome = "repetition_loop" if looped else "ok"
                preview = (info.get("raw_text", "") or "")[:120].replace("\n", " ")
                print(f"  [{lang:12s}] draw {draw}: {outcome:20s} "
                      f"tokens={info.get('tokens', '?')} {info.get('seconds', 0):.1f}s")
                if looped:
                    print(f"      preview: {preview}...")
                outcomes.append({"lang": lang, "outcome": outcome})
            except ModelNotLoadedError:
                print(f"  [{lang:12s}] draw {draw}: json_retry_exhausted")
                outcomes.append({"lang": lang, "outcome": "json_retry_exhausted"})

    inference_service._generate_raw = _original_generate_raw

    total = len(outcomes)
    ok = sum(1 for o in outcomes if o["outcome"] == "ok")
    loops = sum(1 for o in outcomes if o["outcome"] == "repetition_loop")
    json_fails = sum(1 for o in outcomes if o["outcome"] == "json_retry_exhausted")

    en = [o for o in outcomes if o["lang"] == "EN"]
    ur = [o for o in outcomes if o["lang"] == "Roman Urdu"]
    en_loop_rate = sum(1 for o in en if o["outcome"] == "repetition_loop") / len(en) if en else 0
    ur_loop_rate = sum(1 for o in ur if o["outcome"] == "repetition_loop") / len(ur) if ur else 0
    en_json_rate = sum(1 for o in en if o["outcome"] == "json_retry_exhausted") / len(en) if en else 0
    ur_json_rate = sum(1 for o in ur if o["outcome"] == "json_retry_exhausted") / len(ur) if ur else 0

    print(f"\n{'=' * 70}\nSUMMARY: repetition_penalty=1.15 alone\n{'=' * 70}")
    print(f"  ok: {ok}/{total}   repetition_loop: {loops}/{total}   "
          f"json_retry_exhausted: {json_fails}/{total}")
    print(f"  EN:  loop_rate={en_loop_rate*100:.0f}%  json_fail_rate={en_json_rate*100:.0f}%")
    print(f"  UR:  loop_rate={ur_loop_rate*100:.0f}%  json_fail_rate={ur_json_rate*100:.0f}%")

    print(f"\n{'=' * 70}\nCOMPARE AGAINST ESTABLISHED BASELINE (from earlier real run)\n{'=' * 70}")
    print(f"  Baseline : loop_rate=1/18 (6%)  json_fail_rate=0/18 (0%)  "
          f"EN_loop=0%  UR_loop=11%")
    print(f"  Pen=1.15 : loop_rate={loops}/{total} ({loops/total*100:.0f}%)  "
          f"json_fail_rate={json_fails}/{total} ({json_fails/total*100:.0f}%)  "
          f"EN_loop={en_loop_rate*100:.0f}%  UR_loop={ur_loop_rate*100:.0f}%")


if __name__ == "__main__":
    main()
