"""
Regression test: eligibility is applied BEFORE ranking.

Needs NO model download. The dense leg is replaced by a TF-IDF stand-in injected
as `sentence_transformers` (HuggingFace is blocked in the Claude sandbox). So this
tests the PRE-FILTER LOGIC, not retrieval quality, and says nothing about real
MiniLM results. The real dev-set rerun must happen on Ahmad's machine.

Run:  python test_prefilter.py        (needs rank_bm25, scikit-learn, numpy)
"""
import importlib.util
import sys
import types
from pathlib import Path

import numpy as np
from sklearn.feature_extraction.text import TfidfVectorizer

ROOT = Path(__file__).resolve().parent.parent


class _TfidfStandIn:
    def __init__(self, *_a, **_k):
        self.v = TfidfVectorizer()
        self.fitted = False

    def encode(self, texts, convert_to_numpy=True, show_progress_bar=False):
        if not self.fitted:
            self.fitted = True
            return self.v.fit_transform(texts).toarray()
        return self.v.transform(texts).toarray()


_fake = types.ModuleType("sentence_transformers")
_fake.SentenceTransformer = _TfidfStandIn
sys.modules["sentence_transformers"] = _fake


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


fixed = load(ROOT / "scripts" / "retrieval_pipeline.py", "fixed")
ref = load(ROOT / "reference" / "retrieval_pipeline_REFERENCE_v0.py", "ref")

chunks = fixed.load_corpus()
fails = []


def check(name, cond, detail=""):
    print(("PASS " if cond else "FAIL ") + name + (f"  [{detail}]" if detail else ""))
    if not cond:
        fails.append(name)


# 1. corpus size (as stated in KOI_RAG_SEGMENT_STATE_v1 §4)
check("corpus is 6,852 chunks", len(chunks) == 6852, str(len(chunks)))

# 2. mask correctness on the real corpus
high = fixed.eligibility_mask(chunks, "HIGH")
crit = fixed.eligibility_mask(chunks, "CRITICAL")
low = fixed.eligibility_mask(chunks, "MODERATE")
n_neg = sum(c["evidence_role"] == "NEGATIVE_EXAMPLE" for c in chunks)
check("HIGH mask excludes exactly the NEGATIVE_EXAMPLE chunks",
      sum(high) == len(chunks) - n_neg, f"{sum(high)} eligible, {n_neg} excluded")
check("HIGH mask has no NEGATIVE_EXAMPLE",
      all(not m or c["evidence_role"] != "NEGATIVE_EXAMPLE" for m, c in zip(high, chunks)))
check("CRITICAL mask only AUTHORITATIVE_*",
      all(not m or c["evidence_role"].startswith("AUTHORITATIVE_") for m, c in zip(crit, chunks)))
check("CRITICAL mask excludes pending-native-review (Urdu review gate)",
      all(not m or c.get("review_status") != "pending-native-review" for m, c in zip(crit, chunks)))
check("CRITICAL pool is non-empty", sum(crit) > 0, f"{sum(crit)} eligible")
check("below HIGH: nothing eligible", sum(low) == 0)

# 3. crowd-out property: pre-filter keeps k eligible results; reference does not.
fixed_r = fixed.HybridRetriever(chunks)
ref_r = ref.HybridRetriever(chunks)
queries = ["suicidal thoughts safety plan", "ask about means access",
           "client ambivalence about change", "hopeless and want to give up",
           "how to assess risk of self-harm", "motivational interviewing reflection"]
for tier in ("HIGH", "CRITICAL"):
    crowded = 0
    for q in queries:
        new = fixed_r.retrieve(q, k=10, eligible_mask=fixed.eligibility_mask(chunks, tier))
        old = ref_r.retrieve(q, k=10, eligible_mask=ref.eligibility_mask(chunks, tier))
        old_elig = ref.answer_stage_filter(old, tier)
        new_elig = fixed.answer_stage_filter(new, tier)
        check(f"{tier} '{q[:28]}': pre-filter returns only eligible", len(new) == len(new_elig))
        check(f"{tier} '{q[:28]}': pre-filter never worse than reference",
              len(new_elig) >= len(old_elig), f"new={len(new_elig)} ref={len(old_elig)}")
        crowded += len(new_elig) > len(old_elig)
    print(f"INFO {tier}: reference lost eligible slots on {crowded}/{len(queries)} queries (stand-in dense model)")

print("\nFAILED: " + ", ".join(fails) if fails else "\nALL PASSED (logic only; stand-in dense model)")
sys.exit(1 if fails else 0)
