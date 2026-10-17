# RAG readiness (report; nothing deployed, no env default changed)

Branch feat/exercise-director-modal. Retrieval is **not live** anywhere.

## Served today (deployed crisis service)
- HIGH-risk `intervention_content` = **static DRAFT fallback**, no clinician review: `koi_crisis_core.builtin_fallback` (`deploy/modal/koi_crisis_core.py:122-129`, chunk_id `builtin-fallback-v0`, marked PLACEHOLDER) + helpline.
- Helpline 1166: `verified: false` (live `reports/live2/smoke_crisis.txt`).
- CRITICAL is never emitted: `KOI_MAX_CATEGORY` defaults to `HIGH` (`crisis_app.py:81,151`; live `/health` `max_category: 'HIGH'`). If it were raised, CRITICAL still never uses retrieval (`koi_crisis_core.intervention` discards non-fallback content at CRITICAL).
- Deployed `koi_rag_hook.py` is a stub returning None. Live `/health` `rag_hook: true` only means that stub imported.
- Ledger P2.2 (`af2384c`) and P2.3 (`5f941b6`) were report-only commits; `KOI_RAG_ENABLED`, `rag_enabled`, `rag_assets_loaded` were not implemented then (CORRECTION lines in PROGRESS.md).

## Built (offline, in `rag_prototype/`, not in the deployed image)
- Router: `scripts/retrieval_pipeline.py` `CrisisRouter` — 22-chunk pool (AUTH_noUS), kNN routing over labelled example queries, multilingual-e5-small, gate = top-chunk vote share >= 0.5709, <= 3 items, zero-vote chunks never served.
- Haystack 3.3.0 wrapper: `scripts/haystack_pipeline.py` (TierCheck → KnnRoute → ContentBuilder; telemetry forced off), entry `run_crisis`.
- `scripts/crisis_service.py` (`CrisisContentService`), `content_safety.py` (user-facing filter), `fallback_bank.py` (DRAFT, unreviewed en/ur/ur-roman), `language_detector.py`.
- Offline tests (stand-in encoder; run 2026-10-17 with HF_HUB_OFFLINE=1, HAYSTACK_TELEMETRY_ENABLED=False), all rc=0: prefilter 32, load_labels 13, ablation 24, diagnose 6, embedder_comparison 22, super_run 33, m2_m3 51, crisis_router 26, haystack_pipeline 36 PASS.

## Not wired in the deployed service
- The deployed crisis app runs the stub hook; nothing reaches the router.
- Crisis image has no `sentence-transformers`, no `haystack-ai`, no e5 weights, no RAG data.

## Hook code behind a flag (step 5; committed, NOT deployed, NOT enabled)
- `deploy/modal/koi_rag_hook.py`: `KOI_RAG_ENABLED` must be exactly `"1"`; default/unset = OFF → `init()` imports nothing, `build_intervention()` returns None (static fallback, identical to today).
- ON: lazy-imports `rag_prototype/scripts` (`KOI_RAG_SCRIPTS_DIR`, else `/root/rag/scripts`, else repo path), builds `CrisisRouter` (content filter ON) + `haystack_pipeline.build_crisis_pipeline` once; calls `haystack_pipeline.run_crisis` for **HIGH only**. CRITICAL and every other tier → None (no retrieval).
- Returns only `source: "grounded"` results (helpline stripped so the endpoint adds its configured one). Below-gate prototype fallback (`fallback_bank` DRAFT), any exception, ImportError, missing asset, or a run over `KOI_RAG_TIMEOUT_S` (default 4 s, own thread pool) → None → static fallback.
- Example store: `load_example_store()` rows kept only if the master CSV `split == "dev"` (filtered in code; only `id`/`split` columns read). `eval/results`, `.lock` files and holdout rows are not opened by the hook or by me.
- `/health` gains `rag_enabled` and `rag_assets_loaded` from `koi_rag_hook.status()` (false/false when the hook can't say).
- `crisis_app.py` forwards `KOI_RAG_ENABLED` into the container like `KOI_HELPLINE_*`, default `"0"`. `run_live.bat` and all env defaults unchanged.
- Tests `deploy/modal/test_rag_hook.py`: 18 passed (stand-in encoder, sockets blocked, no download, no pip): flag-off subprocess imports nothing; only `"1"` enables; missing assets / ImportError → None + `rag_assets_loaded: false`; store ⊂ dev rows; CRITICAL/MODERATE/LOW/unknown never call retrieval; grounded/fallback/exception/non-dict mapping; timeout returns in < 1 s; `koi_crisis_core.intervention` keeps grounded at HIGH and forces fallback at CRITICAL; health fields.
- **Not verified:** the grounded path end-to-end. With the stand-in encoder the real pipeline runs but stays below the gate (returns the draft fallback → hook None); grounded results were only exercised with a mocked `run_crisis`. Real e5 encoder, GPU/Modal latency and the image build: not run.
- Known: `crisis_app._intervention` wraps the hook in `with ThreadPoolExecutor(1)`, whose exit waits for the worker, so its own timeout does not bound latency; the hook's internal timeout does.

## Pending (not done, not verified)
- Haystack tests with the **real** encoder (only stand-in encoder runs this session).
- Real-encoder **egress audit** (`eval/egress_audit.py`) — not run.
- `eval/dev_zero_vote_check.py` — not run.
- **VERA-MH** evaluation — not run.
- **Audience review**: most of the 22 passages are written for clinicians/service designers; user-fitness unassessed.
- **Native Urdu review**: bilingual chunks `pending-native-review`; `fallback_bank.py` Urdu/Roman Urdu unchecked.
- Clinician review of any served text; helpline 1166 verification; risk enum strings (HIGH_CRISIS vs HIGH) open.
- `test_holdout_once.py`: not run (holdout off-limits; rule E spent).

## Image dependencies needed before any enablement (listed, NOT added)
- `sentence-transformers` (koivenv has 6.1.0; pin to a version compatible with the crisis image) and `haystack-ai==3.3.0`.
- Also imported at module level by `retrieval_pipeline.py`: `rank_bm25`, `scikit-learn` (numpy already present).
- Image env: `KOI_RAG_SCRIPTS_DIR` (or keep the `rag_prototype` layout at `/root/rag`: `scripts/`, `data/processed/`, `eval/`), since the prototype resolves data paths relative to its own files.
- Conflict to resolve first: crisis image pins `transformers==4.46.3`, `torch==2.5.1`, `huggingface_hub==0.26.5`; recent sentence-transformers needs newer transformers/hub.
- Model files: `intfloat/multilingual-e5-small` baked at build or on the `koi-crisis-assets` volume; runtime `HF_HUB_OFFLINE=1`, `TRANSFORMERS_OFFLINE=1`, `HAYSTACK_TELEMETRY_ENABLED=False`.
- Data: `rag_prototype/scripts/`, `data/processed/authoritative_chunks.jsonl`, `mhgap_pk_chunks.jsonl` (+ `annomi_chunks.jsonl`, loaded then excluded from the HIGH pool), `eval/multilingual_queries.py`, `eval/labels/koi_queries_master_draft.csv` (contains holdout rows; code keeps dev rows only — consider stripping them from the shipped copy).
- Latency: `KOI_RAG_TIMEOUT_S` (4 s default) vs the chat risk budget (5 s from request start, P3.4b); measure p95 on a warm T4 first.
