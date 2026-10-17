# KOI jigsaw audit and first frontend milestone — 2026-10-17

## Scope and baseline

Branch `feat/avatar-webview-host`, HEAD `40be37e201998c54e5be3f0f9abd6973ec36e616`, dirty before and after this work. This is a working-tree milestone, not a commit or deployment. P0's prior genuine browser acceptance remains documented in `KOI_P0_BROWSER_ACCEPTANCE_2026-10-17.md`; this report does not replace that evidence.

Read the P0 recovery/browser reports, integration recovery plan, current source and diffs. No backend, Flutter, API contract, Firebase behavior, transport, timeout, crisis policy, schema or encryption changes. No credentials, tokens, private conversations or `.env.local` contents were inspected. All 23 protected auth/conversation/storage/transport source files matched their pre-milestone SHA-256 hashes after implementation. Existing M11–M14 and other dirty work was preserved.

## Blueprint authority and unresolved policy

The Blueprint is absent from this checkout. Two identical local copies were found in Downloads; audit used `C:\Users\PMYLS\Downloads\KOI_ULTIMATE_MASTER_BLUEPRINT_v4_13.md` (the `(1)` copy has the same hash). Line 130 explicitly lists the jigsaw/gamification data model among items that were **not confirmed locked**, and says not to treat them as decided architecture. The later v4.10 discussion retains this open status. Its referenced `KOI_UX_FLOWS_LOCKED_v1_1.md` was not found in the searched repository/Downloads/Documents/Desktop locations.

No approved numeric reward rates, activity eligibility, caps, streak calendar, milestone thresholds or puzzle-unlock mapping were available. Demo UI amounts are not policy. Section 3.1a requires client-side encryption for mood ratings; this milestone does not create a mood-rating writer or infer mood from chat/crisis state.

## Read-only wiring audit

All source paths below are under `repos/koi-backend/nextjs_app`.

| Area | Verified source and initial state | Safe integration / outstanding dependency |
| --- | --- | --- |
| Stored progress | `src/lib/db.ts:32` defines UID-keyed `JigsawProgressRecord`, total, five source counters, milestone IDs and date; table declaration at line 87. No production progress reader/writer found before this milestone. | Read existing per-user records; preserve values without repair/recalculation. |
| Progress screen | `src/app/(authenticated)/progress/page.tsx` initially hardcoded 247 pieces, 12-day streak, 47 sessions, mood 7.2, sample milestones (+5/+10/+15/+20), two filled puzzle cells, sample mood week and randomized heatmap. | Bind verified persisted metadata; explicitly label remaining visual samples. |
| Chat completion | `src/lib/conversation/conversationService.ts:44,55` persists encrypted user and successful assistant rows with `ownerUid`, `conversationId`, `replyTo`. | Count unique owned completed exchanges without touching P0 or decrypting bodies. A successful reply is not an approved reward unit or a completed therapy session. |
| Breathing | `src/components/companion/ExerciseDirector.tsx:193` emits `playback_done` on actual completion; stop/unmount paths emit `playback_stopped`. | No durable completion ledger/reward policy. Do not reward exercise requests, server completion, interruption or repeated playback by assumption. |
| Check-ins/tasks | Existing stores/types are present, but no completed check-in/task user flow and durable completion writer found in the audited web implementation. Reminders alone are not completed check-ins. | Requires actual activity workflow and approved completion criteria; no fabricated counts. |
| Bonuses/streaks/milestones | Demo declarations exist; no approved policy or production award path found. | Defer new awards pending locked rules. |
| Mood/heatmap/share | Sample visual data and existing inert Download/Share controls. | Retained with preview labels; no mood inference, new export behavior or claims of functional parity. |

## Implemented milestone: live progress reads, not reward issuance

1. New `src/lib/progress/progressReadModel.ts`: read-only Dexie transaction over existing stores; validates recorded counters; counts encrypted owned user/reply pairs in the same conversation. Duplicate assistant IDs for the same user turn count once. User-only, orphaned, foreign-owner, mismatched-conversation and plaintext rows are excluded. Invalid records fail closed; no repair/write/decryption/network operation.
2. New `src/hooks/useProgress.ts`: existing Dexie `liveQuery`, loading/error/retry states, unsubscribe guards and immediate old-owner hiding on UID change/logout.
3. Modified `src/app/(authenticated)/progress/page.tsx`: live saved total/source counters/milestone count and actual completed-exchange/conversation counts. Removes asserted 247/12/47/7.2 statistics. Existing layout retained; puzzle, mood, timeline, heatmap and emotion examples explicitly labelled previews. Heatmap deterministic. No new dependency.
4. New `src/__tests__/progress.test.tsx`: ten focused tests using real Dexie/fake IndexedDB and synthetic encrypted-format metadata.

This prevents duplicate completion counts and issues **no rewards**, so repeated reads/remounts cannot duplicate rewards. It does not implement an award ledger or claim new activity-to-piece allocation. Existing per-user totals remain intact. Legacy ownerless ciphertext is neither adopted nor deleted. Counts are local completed exchanges, not a measure of disclosure, clinical improvement or risk.

## Acceptance and validation

| Check | Result | Evidence / limits |
| --- | --- | --- |
| Deduplication and completion eligibility | PASS, local tests | Same-turn duplicate replies count once; incomplete/foreign/orphan/plaintext/mismatched rows excluded. |
| Per-user stored totals and no mutation | PASS, local tests | Distinct users' 7/22-piece records remain separate; repeated reads leave messages/progress unchanged. |
| Live updates, account changes and failures | PASS, local tests | Reply persistence updates live summary; switch/logout/remount hides old values; DB failure offers retry instead of invented balance. |
| UI actual values vs previews | PASS, component tests | Real counts/totals rendered, preview labels present, old asserted statistics absent. |
| Full Jest suite | PASS | `node node_modules/jest/bin/jest.js --runInBand`: 9 suites, 50 tests. Existing styled-jsx warning in preserved chat-avatar test. |
| TypeScript | PASS | Installed compiler, `--noEmit --incremental false`. |
| P0 local regression | PASS, fixtures | `node scripts/test-conversation-recovery.cjs`: real Dexie upgrade/encryption/recovery, SSE parser and isolation; synthetic auth/fetch, not live Modal. |
| Protected source regression | PASS | All 23 recorded source hashes unchanged. |
| Browser fresh/authenticated Progress | PASS | Real Chrome, existing Next dev server `http://127.0.0.1:3000`; Firebase anonymous sign-up/lookup HTTP 200; actual counters all zero; no page errors. |
| Browser navigation with pending request | PASS, limited | Chat → Progress → Chat preserved same conversation/message identities and pending state. Progress remained zero for incomplete exchange; exactly one chat POST observed. No claim that this was active SSE: no events arrived. |
| Browser encrypted interrupted recovery/logout | PASS | Full navigation to Progress restored owned encrypted snapshot with cancelled user turn, zero completed counts and no second POST; logout cleared live session and returned to landing. |
| Browser successful-reply progress update | NOT RUN to completion | One legitimate authenticated POST to existing Modal `/api/v1/chat` remained pending with no observable HTTP response/content type/SSE events until document navigation. No fabricated status or success; no retries, timeout changes or API experimentation. Live completed-reply update and nonzero browser account isolation remain unverified this milestone. |

Browser inspection recorded only counts, ownership/encryption booleans and hashed identities. Prior P0 acceptance had genuine HTTP 200/SSE evidence; this pending attempt does not supersede it or prove a backend defect. No backend changes are recommended from this observation alone.

Production build: **PASS**, `npm run build`, Next.js **14.2.35**, on the dirty working tree at HEAD `40be37e201998c54e5be3f0f9abd6973ec36e616` with the four source/test changes listed above. Compilation, lint/type validation, all **18/18** static-generation entries and final optimization completed; `/progress` is 9.9 kB / 228 kB first-load JS. Process-only Node heap limit 1024 MB; no dependency install or concurrent browser/server during build. This was a local build, not a deployed artifact. Build ID was not captured before dev restart replaced generated build state.

The original dev server was stopped only after the isolated browser was closed, then one dev server was restored at `http://127.0.0.1:3000` (Next 14.2.35; ready). No duplicate server started. `git diff --check` passed; existing CRLF normalization warnings are unrelated. This report is the fifth changed/added file for this milestone; all other dirty paths predate it.

## Next milestone dependencies

Provide/confirm locked gamification UX and policy: eligible activity unit and completion evidence, piece amounts/caps, replay/dedup identity, cross-device authority, milestone thresholds, puzzle mapping, streak timezone and treatment of legacy records. Then implement one atomic, UID-scoped idempotent award path through existing frontend storage, with replay/reload/account-isolation tests. Any genuinely required API/schema-contract change must be documented for approval, never implemented under this freeze.

Avatar, wider UI fixes, voice, ASR/TTS, lip-sync, video and retention were not started. No new backend capability is implied.

Automatic review rejected an initial wholesale progress-page overwrite because it could discard existing UI/work. It was not applied; the accepted narrower data-binding/state/preview-label patch preserves the page. No approval remains pending for that rejected approach.
