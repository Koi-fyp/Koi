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

## Not wired
- No path from the deployed crisis app to the router (hook is a stub in the deployed build).
- Crisis image has no `sentence-transformers`, no `haystack-ai`, no e5 weights, no RAG data.
- (Step 5 of this session adds hook code behind a default-OFF flag; see the section appended below. It is not deployed and not enabled.)

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
- Conflict to resolve first: crisis image pins `transformers==4.46.3`, `torch==2.5.1`, `huggingface_hub==0.26.5`; recent sentence-transformers needs newer transformers/hub.
- Model files: `intfloat/multilingual-e5-small` baked at build or on the `koi-crisis-assets` volume; runtime `HF_HUB_OFFLINE=1`, `TRANSFORMERS_OFFLINE=1`, `HAYSTACK_TELEMETRY_ENABLED=False`.
- Data: `rag_prototype/scripts/`, `data/processed/authoritative_chunks.jsonl`, `mhgap_pk_chunks.jsonl` (+ `annomi_chunks.jsonl`, loaded then excluded from the HIGH pool), `eval/multilingual_queries.py`, `eval/labels/koi_queries_master_draft.csv` (contains holdout rows; code keeps dev rows only — consider stripping them from the shipped copy).
- Latency: `KOI_RAG_TIMEOUT_S` (4 s default) vs the chat risk budget (5 s from request start, P3.4b); measure p95 on a warm T4 first.
