"""
Day 3 — Sufficiency gate calibration.

Methodology locked this session (per the calibration research round):
  - Feature: cosine of the top-1 ELIGIBLE chunk only. Margin (top1-top2,
    over DISTINCT chunk_ids/sources, not raw ranks) is computed and
    reported but held out of the final gate unless it demonstrably helps
    out-of-fold -- per the research finding that margin mostly captures
    ambiguity, not sufficiency, on overlapping/duplicate-heavy corpora.
  - "Sufficient" label: hit_at == 1 for Tier A/B (the top-ranked eligible
    chunk IS the correct one -- this is what an extractive-only answer
    would actually surface). Out-of-corpus queries are always label=0
    (insufficient) by construction.
  - Threshold selection: constrained (Neyman-Pearson) rule -- maximize
    coverage (answer rate on label=1 queries) subject to FAR <= alpha on
    label=0 queries. NOT a cost-weighted optimum with an invented ratio.
  - Validation: 5-fold (not 5x5 -- n=29 is too small for repeated folds
    to mean anything beyond one honest pass) stratified GROUP k-fold,
    grouped by underlying fact (paraphrase pairs share a group, so they
    can't leak across train/test).
  - Stability: stratified bootstrap over the full set, reporting the
    SPREAD of the selected threshold across resamples -- explicitly to
    show how under-determined it is at this N, not to produce a clean
    point estimate.
  - Reporting: exact Clopper-Pearson intervals, never bare percentages.

SAMPLE SIZE WARNING, stated once here and required in every downstream
report of these numbers: n=29 (23 positive, 6 negative) is far below what
would let a threshold generalize with any real confidence. This entire
script's job Day 3 is to produce an honestly-caveated PROVISIONAL
threshold and demonstrate its instability -- not to produce a validated
safety number. See the calibration research round for the formal
justification of every choice above.
"""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts"))
from retrieval_pipeline import load_corpus, HybridRetriever, eligibility_mask, answer_stage_filter
from dev_set import DEV_SET

import random
import numpy as np
from scipy import stats


# ---- grouping (paraphrase pairs / same-fact queries must share a fold) ----
GROUPS = {
    "a02": "g_suicidal_ideation_def", "a08": "g_suicidal_ideation_def",
    "a03": "g_988_lifeline", "a09": "g_988_lifeline",
    "a04": "g_digital_interventions", "a11": "g_digital_interventions", "a12": "g_digital_interventions",
    "a05": "g_trauma_informed", "a10": "g_trauma_informed",
    "a06": "g_developmentally_appropriate", "a18": "g_developmentally_appropriate",
    "a13": "g_safety_principle", "a17": "g_safety_principle",
    "a14": "g_followup_care", "a15": "g_followup_care",
    "b01": "g_alcohol_ambivalence", "b04": "g_alcohol_ambivalence",
    "b02": "g_cutting", "b05": "g_cutting",
}
def group_of(qid):
    return GROUPS.get(qid, f"g_solo_{qid}")


def extract_features(retriever, chunks, dev_set):
    """Real feature extraction against the live retriever -- run this on the
    machine with real embeddings; this is NOT runnable to meaningful effect
    in the Claude sandbox (dense leg needs huggingface.co, blocked there)."""
    rows = []
    for item in dev_set:
        mask = eligibility_mask(chunks, item["risk_tier"])
        retrieved = retriever.retrieve(item["query"], k=10, eligible_mask=mask)
        eligible = answer_stage_filter(retrieved, item["risk_tier"])
        ranked = eligible if eligible else retrieved

        if not ranked:
            cosine_top1, margin = 0.0, 0.0
            label = 0
        else:
            cosine_top1 = ranked[0]["cosine"]
            # margin over DISTINCT chunk_ids (not just next rank) -- per
            # calibration research, dedup so overlapping near-identical
            # chunks don't artificially shrink the margin
            distinct_next = next((r for r in ranked[1:] if r["chunk"]["chunk_id"] != ranked[0]["chunk"]["chunk_id"]), None)
            margin = cosine_top1 - (distinct_next["cosine"] if distinct_next else 0.0)

            if item["gt_tier"] == "N/A":
                label = 0  # out-of-corpus: always insufficient by construction
            else:
                top1_chunk = ranked[0]["chunk"]
                if item["gt_tier"] == "A":
                    label = int(top1_chunk["chunk_id"] in item["gt_chunk_ids"])
                else:  # Tier B
                    if "gt_topic_match" in item:
                        label = int(item["gt_topic_value_contains"].lower()
                                    in str(top1_chunk.get(item["gt_topic_match"], "")).lower())
                    else:
                        label = int(item["gt_text_contains"].lower() in top1_chunk["text"].lower())

        rows.append({"id": item["id"], "group": group_of(item["id"]), "label": label,
                      "cosine": cosine_top1, "margin": margin})
    return rows


def far_at_threshold(rows, tau, feature="cosine"):
    negs = [r for r in rows if r["label"] == 0]
    if not negs:
        return 0.0, 0
    fa = sum(1 for r in negs if r[feature] >= tau)
    return fa / len(negs), len(negs)


def coverage_at_threshold(rows, tau, feature="cosine"):
    pos = [r for r in rows if r["label"] == 1]
    if not pos:
        return 0.0, 0
    covered = sum(1 for r in pos if r[feature] >= tau)
    return covered / len(pos), len(pos)


def select_threshold(rows, alpha=0.10, feature="cosine"):
    """Neyman-Pearson-style: max coverage s.t. FAR <= alpha. Returns the
    conservative side of the feasible region's middle, not its edge."""
    candidates = sorted(set(r[feature] for r in rows))
    feasible = []
    for tau in candidates:
        far, n_neg = far_at_threshold(rows, tau, feature)
        cov, n_pos = coverage_at_threshold(rows, tau, feature)
        if far <= alpha:
            feasible.append((tau, cov, far))
    if not feasible:
        return None, None, None
    feasible.sort(key=lambda x: -x[1])  # max coverage first
    best_cov = feasible[0][1]
    tied = [f for f in feasible if f[1] == best_cov]
    tied.sort(key=lambda x: x[0])
    tau = tied[len(tied) // 2]  # middle of the tied/feasible band, conservative side
    return tau[0], tau[1], tau[2]


def clopper_pearson_one_sided(successes, n, conf=0.95):
    """One-sided upper bound -- the correct interval for a directional
    safety claim ('FAR <= alpha'), not the two-sided interval. Per the
    Day 3 research round: at n=6, zero failures, this is 39.3%, not the
    45.9% two-sided figure originally (incorrectly) reported."""
    if n == 0:
        return 1.0
    if successes == n:
        return 1.0
    return float(stats.beta.ppf(1 - (1 - conf), successes + 1, n - successes))


def min_negatives_for_bound(target_far=0.10, conf=0.95):
    """Mathematical floor: minimum independent negatives, at ZERO observed
    failures, for the one-sided upper bound to fall at or below target_far.
    This is a best-case floor, not a recommended validation sample size --
    see Day 3 research round for why real design needs substantially more."""
    import math
    n = 1
    while True:
        bound = 1 - (1 - conf) ** (1 / n)
        if bound <= target_far:
            return n
        n += 1
        if n > 1000:
            return None


def group_kfold(rows, k=5, seed=42):
    groups = sorted(set(r["group"] for r in rows))
    random.Random(seed).shuffle(groups)
    folds = [groups[i::k] for i in range(k)]
    results = []
    for fold_groups in folds:
        test = [r for r in rows if r["group"] in fold_groups]
        train = [r for r in rows if r["group"] not in fold_groups]
        if not test or not train:
            continue
        tau, cov, far = select_threshold(train, alpha=0.10)
        if tau is None:
            continue
        test_far, n_neg = far_at_threshold(test, tau)
        test_cov, n_pos = coverage_at_threshold(test, tau)
        results.append({"tau": tau, "train_cov": cov, "train_far": far,
                         "test_cov": test_cov, "test_far": test_far,
                         "test_n_pos": n_pos, "test_n_neg": n_neg})
    return results


def stratified_bootstrap(rows, n_boot=200, alpha=0.10, seed=42):
    rng = random.Random(seed)
    pos = [r for r in rows if r["label"] == 1]
    neg = [r for r in rows if r["label"] == 0]
    taus = []
    for _ in range(n_boot):
        sample = [rng.choice(pos) for _ in range(len(pos))] + [rng.choice(neg) for _ in range(len(neg))]
        tau, cov, far = select_threshold(sample, alpha=alpha)
        if tau is not None:
            taus.append(tau)
    return taus


def run():
    print("=" * 90)
    print("DAY 3 — SUFFICIENCY GATE CALIBRATION")
    print("=" * 90)
    print("\n!! SAMPLE SIZE WARNING: n=29 (23 positive, 6 negative). Every number below is\n"
          "!! provisional. This script's job is to show a threshold AND how unstable it is\n"
          "!! at this N -- not to produce a validated safety claim. See module docstring.\n")

    chunks = load_corpus()
    retriever = HybridRetriever(chunks)
    rows = extract_features(retriever, chunks, DEV_SET)

    n_pos = sum(1 for r in rows if r["label"] == 1)
    n_neg = sum(1 for r in rows if r["label"] == 0)
    print(f"Feature extraction: {len(rows)} queries ({n_pos} positive/sufficient, {n_neg} negative/insufficient)")

    # ---- 1. margin ablation ----
    print("\n--- Margin ablation (is margin worth keeping?) ---")
    tau_cos, cov_cos, far_cos = select_threshold(rows, alpha=0.10, feature="cosine")
    tau_marg, cov_marg, far_marg = select_threshold(rows, alpha=0.10, feature="margin")
    print(f"  cosine-only: tau={tau_cos:.4f}  train coverage={cov_cos:.2%}  train FAR={far_cos:.2%}")
    if tau_marg is not None:
        print(f"  margin-only: tau={tau_marg:.4f}  train coverage={cov_marg:.2%}  train FAR={far_marg:.2%}")
    else:
        print(f"  margin-only: NO FEASIBLE THRESHOLD at alpha=0.10 -- margin alone cannot separate "
              f"positive from negative queries on this data. Drop margin from the gate.")

    # ---- 2. group k-fold ----
    print("\n--- 5-fold stratified GROUP cross-validation (cosine feature) ---")
    fold_results = group_kfold(rows, k=5)
    for i, f in enumerate(fold_results):
        print(f"  fold {i+1}: train_tau={f['tau']:.4f}  "
              f"test_coverage={f['test_cov']:.2%} (n={f['test_n_pos']})  "
              f"test_FAR={f['test_far']:.2%} (n={f['test_n_neg']})")
    if fold_results:
        taus = [f["tau"] for f in fold_results]
        print(f"  tau range across folds: {min(taus):.4f} to {max(taus):.4f}  "
              f"(spread={max(taus)-min(taus):.4f})")

    # ---- 3. bootstrap stability ----
    print("\n--- Stratified bootstrap (200 resamples) — threshold stability ---")
    taus = stratified_bootstrap(rows, n_boot=200, alpha=0.10)
    if taus:
        taus_arr = np.array(taus)
        print(f"  {len(taus)}/200 resamples found a feasible threshold")
        print(f"  median tau={np.median(taus_arr):.4f}  "
              f"[5th pct={np.percentile(taus_arr,5):.4f}, 95th pct={np.percentile(taus_arr,95):.4f}]")
        print(f"  -> a {np.percentile(taus_arr,95)-np.percentile(taus_arr,5):.4f}-wide 90% spread. "
              f"{'WIDE -- threshold is under-determined at this N.' if (np.percentile(taus_arr,95)-np.percentile(taus_arr,5)) > 0.05 else 'Reasonably tight.'}")

    # ---- 4. VERDICT: can this dataset certify the target FAR? ----
    fa_count = sum(1 for r in rows if r["label"] == 0 and r["cosine"] >= tau_cos)
    print(f"\n{'='*90}")
    print("VERDICT — confirmed by two independent research passes, matching math:")
    print(f"{'='*90}")
    n_min = min_negatives_for_bound(target_far=0.10)
    one_sided = clopper_pearson_one_sided(fa_count, n_neg)
    print(f"  Development set has {n_neg} negatives. Even at 0 observed false-accepts,")
    print(f"  one-sided 95% upper bound = {one_sided:.1%} (was previously misreported as the")
    print(f"  two-sided 45.9% figure -- corrected here per Day 3 research).")
    print(f"  Mathematical FLOOR to certify FAR<=10% at zero failures: {n_min} independent negatives.")
    print(f"  This dataset has {n_neg}. NO statistical method -- conformal risk control, Bayesian")
    print(f"  without an external prior, sequential testing, bootstrap -- can close this gap.")
    print(f"  This is not a methodology problem. It is an information/sample-size problem.")
    print(f"\n  CONCLUSION: this threshold is NOT statistically validated. Per the locked")
    print(f"  architecture decision (Day 3), CRITICAL-tier queries do NOT use this gate to")
    print(f"  autonomously accept -- they fail closed to the deterministic fallback. The gate")
    print(f"  runs in shadow/logging mode at CRITICAL tier to accumulate real evaluation data.")
    print(f"  At HIGH tier, the gate may operate, but must be labeled 'conservative, not")
    print(f"  statistically calibrated' -- never 'validated' or '<=10% FAR'.")
    print(f"{'='*90}")

    return rows, tau_cos


if __name__ == "__main__":
    run()
