"""
Modality Dropout Sampler — TSD PoC Phase 1

Spec source: KOI_TSD_POC_PLAN_v1.md, Phase 1 (lines 79-94).
Locked design source: KOI_ULTIMATE_MASTER_BLUEPRINT_v4_13.md §4.2 (v4.7 addition).

Goal: verify the training-time modality dropout restriction is correctly
implemented before any training code consumes its output. This is a pure
code-correctness check, not a design question — the four valid combos are
already locked.

Weighting: uniform (25% each) — simplest default, per project-owner direction.
No inputs beyond the locked spec are required.
"""

import random
from enum import Enum


class ModalityCombo(str, Enum):
    """The four — and only four — valid training-time modality combos."""
    TEXT_ONLY = "text_only"
    AUDIO_ONLY = "audio_only"
    TEXT_VIDEO = "text_video"
    AUDIO_VIDEO = "audio_video"


_VALID_COMBOS: tuple[ModalityCombo, ...] = (
    ModalityCombo.TEXT_ONLY,
    ModalityCombo.AUDIO_ONLY,
    ModalityCombo.TEXT_VIDEO,
    ModalityCombo.AUDIO_VIDEO,
)


def sample_modality_combo(rng: random.Random | None = None) -> ModalityCombo:
    """
    Draw one modality combo for a single training batch.

    Uniform weighting (25% each) across the four locked combos.
    Never returns Video-only, Text+Audio, all-three, or zero-modality —
    those are not valid combos and must never be producible by this
    function, regardless of implementation changes downstream.

    Args:
        rng: optional Random instance for reproducible/seeded draws
             (e.g. in tests). Defaults to the module-level random state.

    Returns:
        One ModalityCombo member.
    """
    picker = rng or random
    return picker.choice(_VALID_COMBOS)


if __name__ == "__main__":
    # Phase 1 pass/fail check: 10,000+ draws, 100% must fall within
    # the four-combo set. Any violation is a code bug, not a design
    # ambiguity — the design question was already resolved upstream.
    N_DRAWS = 10_000
    draws = [sample_modality_combo() for _ in range(N_DRAWS)]

    invalid = [d for d in draws if d not in _VALID_COMBOS]
    assert not invalid, (
        f"Phase 1 FAIL: {len(invalid)} draw(s) outside the locked four-combo "
        f"set: {invalid[:5]}..."
    )

    # Sanity check on distribution — not part of the formal pass/fail
    # criteria (uniformity wasn't mandated), but useful to eyeball.
    counts = {combo: draws.count(combo) for combo in _VALID_COMBOS}
    print(f"Phase 1 PASS: {N_DRAWS} draws, all within the locked combo set.")
    print("Distribution:")
    for combo, count in counts.items():
        print(f"  {combo.value:<12} {count:>6}  ({count / N_DRAWS:.1%})")
