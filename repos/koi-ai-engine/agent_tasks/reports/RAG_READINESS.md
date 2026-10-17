# RAG readiness (report only; nothing implemented, nothing deployed, no flag changed)

Written 2026-10-17 on branch feat/exercise-director-modal.

## Bottom line
**RAG is not wired into the crisis service.** Every HIGH response from `/api/v1/crisis` (and therefore chat `risk.intervention_content`) is the **static built-in fallback**. CRITICAL is always the fallback by design.

- `deploy/modal/koi_rag_hook.py` is a **stub**: `init()` returns None, `build_intervention()` returns None (lines 25-30). `crisis_app._intervention` therefore always falls through to `koi_crisis_core.builtin_fallback` (`koi_crisis_core.py:122-129`, chunk_id `builtin-fallback-v0`, marked "PLACEHOLDER").
- **`KOI_RAG_ENABLED` does not exist in any code.** `git log --all -S KOI_RAG_ENABLED` finds it only in reports/agent checkpoints; no file under `deploy/` reads it.
- **`/health` has no `rag_enabled` or `rag_assets_loaded`.** It reports `rag_hook: true`, which only means the stub module imported (live: `live2/crisis_ready.txt`). It does **not** mean retrieval runs.
- Ledger P2.2 (`af2384c`) and P2.3 (`5f941b6`) are **report-only commits** (each changes only `P2_REPORT.md` + `PROGRESS.md`). The flag, assets and health fields they describe were never implemented. Correction lines are in PROGRESS.md.

## What the flag would do (design intent, MASTER_NIGHT P2.2; not built)
`KOI_RAG_ENABLED=0` (default): byte-identical to today (static fallback at HIGH). `=1` and HIGH: `{source: "grounded", language, items 1-3, helpline}` from the prototype; exception / empty / missing asset / timeout → existing fallback. Below HIGH: field omitted. CRITICAL: fallback only (`koi_crisis_core.intervention` already enforces this and discards a "grounded" result at CRITICAL).

## How HIGH content would change
Today: one English placeholder sentence + helpline (1166, `verified: false`). With RAG: up to 3 extractive passages from the 22-chunk pool (WHO mhGAP, SAMHSA minus four US-only 988 chunks, mhGAP-HIG-PK) when the kNN router's top-chunk vote share >= 0.5709; otherwise `rag_prototype/scripts/fallback_bank.py` text (en / ur / ur-roman, "draft-unreviewed"). Per ADR-001 §5 (canon `E:\Koi\Koi-App\docs\KOI RAG ADR_001.md`): about half of in-scope HIGH messages still get the fallback; holdout false-accept 9% [2-25].

## Prototype that exists (rag_prototype/, not imported by deploy/)
- Entry point: `rag_prototype/scripts/crisis_service.py` `CrisisContentService.load()` / `.intervention_content(message, risk_category, language)`; sets `HF_HUB_OFFLINE=1`, `TRANSFORMERS_OFFLINE=1`, `HAYSTACK_TELEMETRY_ENABLED=False` before imports.
- Pipeline: `haystack_pipeline.py` (TierCheck → KnnRoute → ContentBuilder), `retrieval_pipeline.py` `CrisisRouter` (`CRISIS_GATE = 0.5709`, `CRISIS_MODEL = intfloat/multilingual-e5-small`), `content_safety.filter_indices` (required by the service), `fallback_bank.py`, `language_detector.py`.

## What real wiring needs (do not implement without Ahmad's go)
1. **Hook:** `koi_rag_hook.init()` builds `CrisisContentService.load()` once; `build_intervention(text, risk_category, language)` returns `svc.intervention_content(...)` only when `KOI_RAG_ENABLED == "1"`, else None. Map/validate the tier strings (crisis_service raises ValueError on unknown enum; the open HIGH_CRISIS vs HIGH question). Import order: the hook must import `crisis_service` before anything imports haystack.
2. **Image packages (crisis_app `KOI_RAG_PIP`):** `haystack-ai==3.3.0`, `sentence-transformers` (local koivenv has 6.1.0). **Conflict to check first:** the crisis image pins `transformers==4.46.3`, `torch==2.5.1`, `huggingface_hub==0.26.5`; recent sentence-transformers needs newer transformers/hub. Resolve pins in a scratch build before any deploy.
3. **Assets:** `KOI_RAG_DIR` → `/root/rag` with `scripts/`, `data/processed/authoritative_chunks.jsonl` (19), `mhgap_pk_chunks.jsonl` (7) (`load_corpus` also reads `annomi_chunks.jsonl`, 6,826 rows, filtered out of the HIGH pool), `eval/multilingual_queries.py` (kNN example store) and `eval/labels/koi_queries_master_draft.csv` (scenario ids; this CSV also contains holdout rows, which the loader skips: shipping it ships holdout labels in the image, decide whether to strip them). e5-small weights baked at build (`run_function` download) or put on the `koi-crisis-assets` volume; runtime `HF_HUB_OFFLINE=1`, `HAYSTACK_TELEMETRY_ENABLED=False` in the image env.
4. **Health:** add `rag_enabled` (flag) and `rag_assets_loaded` (service loaded, pool size 22, store size).
5. **Timeout/latency:** existing `KOI_RAG_TIMEOUT_S` (default 4 s) in `crisis_app._intervention`. Chat waits for risk 1 s (3 s in exercises/audio) before the reply and at most 5 s after it (P3.4b). A HIGH turn that spends up to 4 s in RAG will usually arrive after the reply or as `unavailable`. Measure p95 on a warm T4 before enabling. e5 load adds to cold start.
6. **Content review status (blocking for a user-facing claim):** 22 passages are mostly provider/clinician-directed, audience split unassessed (state file v4.27 §8 item 7); 4 bilingual chunks `pending-native-review`; `fallback_bank.py` is "DRAFT ... Not reviewed by a clinician; Urdu/Roman Urdu NOT checked"; helpline 1166 unverified; labels LLM-adjudicated, not human/clinician-verified; VERA-MH not run.
7. **Tests to add:** hook flag off == current output; flag on + HIGH in-scope → grounded; below gate → fallback; exception/timeout → fallback; CRITICAL → fallback; socket patched → no network; then a real-encoder egress audit in the built image.

## What is tested (run 2026-10-17, koivenv, HF_HUB_OFFLINE=1, HAYSTACK_TELEMETRY_ENABLED=False)
All with a **stand-in/stub encoder** (logic and plumbing only):
```
test_prefilter          rc=0 32 PASS  ALL PASSED (logic only; stand-in dense model)
test_load_labels        rc=0 13 PASS  ALL PASSED
test_ablation           rc=0 24 PASS  ALL PASSED (plumbing only; stand-in encoder)
test_diagnose           rc=0  6 PASS  ALL PASSED
test_embedder_comparison rc=0 22 PASS ALL PASSED (plumbing only; stand-in encoder)
test_super_run          rc=0 33 PASS  ALL PASSED
test_m2_m3              rc=0 51 PASS  ALL PASSED
test_crisis_router      rc=0 26 PASS  ALL PASSED
test_haystack_pipeline  rc=0 36 PASS  ALL PASSED
```
## What is NOT tested
- Any hook → prototype integration (does not exist); the crisis image with RAG packages; `/health` RAG fields (do not exist).
- Real-encoder runs this session: `egress_audit.py`, `dev_zero_vote_check.py`, router/haystack tests with real e5 (model is cached at `E:\huggingface_cache\...multilingual-e5-small`, but not run: report-only step).
- `test_holdout_once.py`: not run (holdout off-limits; rule E spent).
- Latency on GPU/CPU in Modal; content quality with users; Urdu content review.

## Exact steps to flip (after the wiring above exists and is reviewed)
1. Ahmad writes "RAG ON" in PROGRESS.md (MASTER P5.2 gate) after reviewing items 1-7.
2. Local: hook tests + `egress_audit.py` with the real encoder pass.
3. `set KOI_RAG_ENABLED=1`, `set KOI_RAG_PIP=haystack-ai==3.3.0,sentence-transformers==<pinned>`, `set KOI_RAG_DIR=<path to rag bundle>` in the crisis section of `run_live.bat`; deploy crisis via `run_live.bat` only.
4. Check crisis `/health`: `rag_enabled: true`, `rag_assets_loaded: true`; run `smoke_crisis.py` (low-mood text → HIGH, expect `source: grounded` or `fallback`, never grounded at CRITICAL); then `smoke_only.bat`.
5. Rollback: redeploy with `KOI_RAG_ENABLED=0` (static fallback).
