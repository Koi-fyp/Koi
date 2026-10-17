# Handoff for redeploy (written 2026-10-17, branch feat/exercise-director-modal, not pushed)

## Commits to deploy
| Step | Commit | What |
| --- | --- | --- |
| P3.4b | `31b5b5a` | Deterministic risk budget (5 s from request start, never more than 5 s after the reply) → `risk {"status":"unavailable"}`; every stream ends with `state`, `done` (`exercise_state: null` when no exercise). |
| P3.11 | `aca640c` | Extractor re-parses vLLM cumulative text (fixes Urdu reply loss when text is not prefix-stable), tolerates misspelled keys (`cocompaniion_state`), unwraps/drops JSON-looking replies, salvages truncated/plain-text replies, neutral 0.4 `companion_state` before text, new `error` event when no usable reply. Contract "v1.1 ADDITIONS" appended. |
| P3.2b | `8b4995f` | `Crisis.score` is now a real `@modal.method()` sharing the `/api/v1/crisis` code path (`_score_bytes`); chat calls `modal.Cls.from_name("koi-crisis", "Crisis")().score.remote(...)` (local modal 1.5.5); all failures → `{"status":"unavailable"}`. |

Other commits this session: `6bdd469` (prior-agent reports + P3.10 DONE), `37e8123` (smoke_only.bat `:run` fix), `cacc073` (docs).

## Test results (exact, run at resume end)
```
pytest deploy\modal\test_chat_contract.py deploy\modal\test_chat_v11.py deploy\modal\test_crisis_core.py -q
46 passed in 11.17s
pytest deploy\modal\test_crisis_score_surface.py -q
8 passed in 0.80s
koi_policy\test_director.py  exit=0 PASS=71 FAIL=0 ALL PASSED
koi_policy\test_policy.py    exit=0 PASS=44 FAIL=0 ALL PASSED
koi_policy\test_catalogue.py exit=0 PASS=34 FAIL=0 ALL PASSED
hashes: director.py fc2d52a9e1d7 policy.py 1a318edfb932 intents.py 39be0f36a002 compose.py ca135c692c52
        journeys.json 9c56b1366f88 catalogue.py ebeee43db081 state_token.py 2cb6bd501eb4  (unchanged)
```
No failures. At resume, before P3.4b, `test_normal_event_contract` FAILED (stream had no `state` without the director); fixed in `31b5b5a`.

## Notes
- Deployed build showed `risk {"status":"unavailable"}` on every chat turn (`live2/smoke_chat.txt`): P3.2b is the fix. Not live-verified.
- P3.11 is verified with a local harness only; Urdu/Roman Urdu stay "unreliable" in the docs until smoke after redeploy.
- `score()` writes media to a `TemporaryDirectory` deleted after decoding (same as the web endpoint; ffmpeg needs a seekable mp4). MASTER P2.4 said "memory only": contradiction recorded, behaviour kept identical to `/api/v1/crisis`.
- Crisis web JSON gains `language` when ASR ran (additive).
- Strays (not deleted): `E:\Koi\Koi-App\koi-ai-enginekoi_policyadapter_qwen.py`, untracked `E:\Koi\Koi-App\docs\` (canon). `agent_tasks\run_live.bat` is untracked. rag_prototype CRLF-only modifications left uncommitted.

## Prep steps added after the handoff (no deploy, no flag change, nothing run live)
### RAG readiness — `bd8e819`, report `agent_tasks/reports/RAG_READINESS.md`
- **RAG is not wired.** `deploy/modal/koi_rag_hook.py` is a stub (returns None); `KOI_RAG_ENABLED`, `/health` `rag_enabled` and `rag_assets_loaded` do not exist in code. HIGH/CRITICAL content = static built-in fallback only. `rag_hook: true` on `/health` only means the stub imported.
- Ledger corrections appended: P2.2 (`af2384c`) and P2.3 (`5f941b6`) were report-only commits.
- DEMO_RUNBOOK.md / UX_FLOWS_STATUS.md now say HIGH content is the static fallback and RAG is not wired.
- Offline RAG tests (stub encoder only), all rc=0: prefilter 32, load_labels 13, ablation 24, diagnose 6, embedder_comparison 22, super_run 33, m2_m3 51, crisis_router 26, haystack_pipeline 36 PASS. Not run: real-encoder egress audit, `test_holdout_once.py` (holdout off-limits).
- The report lists what real wiring needs (hook → `rag_prototype/scripts/crisis_service.py`, image pins incl. a transformers/sentence-transformers conflict, assets, timeout vs the chat 5 s risk budget, content review status). Not implemented.

### Multipart live-smoke prep — `9540b7e`
- `agent_tasks\multipart_smoke.py <CHAT_URL>` (KOI_TOKEN from env): audio; text+video; audio+video. 2 s silent WAV generated in memory; mp4 via ffmpeg if on PATH, else both video cases print `SKIPPED` (ffmpeg is NOT on PATH on this machine). Prints event names and `transcript` / `risk` / `error` events, checks v1.1 ordering. Silent audio → HTTP 422 (no speech) is reported as expected, not a failure.
- Offline test `deploy/modal/test_multipart_smoke.py`: 6 passed (local uvicorn app with fake engine/scorer, never the live service). Full chat/crisis suites still 54 passed; koi_policy hashes unchanged.
- Finding (not changed): on audio turns the server sends `transcript` **before** `latency`; contract v1 table lists `latency` first, v1.1 additions only require `transcript` before `companion_state`. Clients that assume `latency` is first should not.

## Instruction
Ahmad: run agent_tasks\run_live.bat once, then smoke_only.bat with both URLs
