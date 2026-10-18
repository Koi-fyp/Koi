# KOI Web baseline and file ownership â€” 2026-10-18

Initial HEAD `223e97c489947b98677392f9b8ea383690ab1fe8`, initially on `feat/avatar-webview-host`. User explicitly approved the local W1 baseline and a separate feature branch through the pending baseline question. New branch: `feat/web-product-data`. No fetch/merge/reset/stash/clean, secret inspection or remote action.

## Reviewed local baseline

Five modified tracked paths: `src/__tests__/progress.test.tsx`, `src/app/(authenticated)/progress/page.tsx`, `src/app/how-it-works/page.tsx`, `src/app/page.tsx`, `src/components/onboarding/WelcomeStep.tsx`. Two intentional new files: `src/__tests__/public-signin-retry.test.tsx` and root `KOI_W1_FINAL_ACCEPTANCE.md`. All Web paths are relative to `repos/koi-backend/nextjs_app`.

These are the preceding Web owner's reviewed W1 work, not newly introduced implementation. Approved baseline checkpoint includes exactly these seven files. Excluded, preserved untracked work: five `.idea` metadata files and 21 Android local/generated files (16 Gradle caches, plugin registrant, wrapper JAR/scripts, local.properties). Ignored secrets/configuration, dependencies, .next and artifacts remain excluded.

Baseline TEST EXECUTED this run: full Jest 16 suites / 91 tests PASS. Previous W1 TEST EXECUTED/report: TypeScript PASS; production Next 14.2.35 build `gPMvOacVG8ULlQA_MtRTQ`, 18/18 generation entries. That build is historical evidence, not a new build invocation. Previous W1 BROWSER OBSERVED/HOSTED OBSERVED: one genuine Firebase-authenticated Modal 200/SSE exchange, counted once in Progress, encrypted refresh/session continuity; exact evidence/limitations in preserved W1 report.

## Ownership boundaries

Web owner may edit authenticated history/presentation, settings import/export/privacy, progress/check-in/activity UI and new isolated modules/tests. Existing local P0, jigsaw, canonical avatar choices, user preferences and legacy fox fallback must be reused. No database duplication or new reward policy.

Protected joint-review files: `src/lib/db.ts`, `src/lib/crypto.ts`, `src/lib/conversation/**`, `src/contexts/AuthContext.tsx`, `ConversationContext.tsx`, `src/hooks/useChat.ts`, `useConversationSession.ts`, Firebase linking/sync/security and Web transport/contracts. Read/reuse only without reviewed interface approval.

Ahmad-owned: `src/components/avatar/**`, `src/components/companion/{CompanionScene,ExerciseDirector,CrisisHandoffDialog}.tsx`, backend `deploy/modal/**`, `koi_policy/**`, media contracts/generation/lip-sync internals. Flutter belongs to mobile owner. No edits authorized here.

## Source-inspected active feature inventory

| Feature/routes | Current state | Evidence / prerequisite |
| --- | --- | --- |
| `/`, `/about`, `/how-it-works` | Implemented informational pages and sign-in | Honest copy; W1 retry/keyboard fixes; existing rendered/browser evidence. Static nonpersonal content remains static. |
| `/onboarding`, Settings avatar/language/time | Implemented local UID preferences | Existing `db.users`, preference resolver/hooks; Aisha/female, Raza/male, legacy fox unavailable. No verified cloud receipt or scheduled message. |
| `/chat`, `/companion-scene` | Implemented P0 shared encrypted conversation | PersistentConversation, ConversationContext; accepted live W1. Preserve ownership/streaming. |
| `/avatar-host` | Implemented presentation-only host | Existing native bridge/model allowlist. Physical native device NOT RUN. |
| `/progress` | Real read model plus explicit previews | Owned encrypted successful reply pairs counted/deduped. Recorded jigsaw counters read, no award writer. Puzzle/mood/milestones/heatmap previews; no genuine ratings writer. |
| History list/search/reopen | Absent user-facing flow | One active header per UID, not per conversation. Can derive owned retained conversation groups from message rows; session switching requires ADR-HISTORY. |
| `/settings/privacy` | Truthful information, empty ledger | CSE not E2EE; inference readable; plaintext preferences; no manufactured activity. |
| `/settings/export`, `/settings/import` | Intentionally disabled / placeholder | Guarded historical PDF code must not be enabled. ADR-PORTABILITY and review required before writes/recovery/rekey. |
| Clear History/Delete Account/retention | Disabled, policy blocked | No local/queued/cloud deletion semantics approved. |
| Voice controls | Shipping modes disabled; sandbox implemented | Existing MicrophoneCapture/SpeechPlayback; no accepted deployed audio/VoiceOutput contract. |
| Video | Planned and gated | No live codec/limits/privacy acceptance; no permission requests or shipping enablement. |
| Safety/exercises | Existing integration, acceptance incomplete | Ahmad's 18-request report is reported, not independently supplied. G0b readiness/fixtures required for new safety runs. |

## Roadmap and evidence hierarchy

Read local review draft `C:\Users\PMYLS\Downloads\KOI_GRAND_IMPLEMENTATION_PLAN_REVIEW_v1_1_AHMAD_REVIEW_2026-10-18.md`; it is a roadmap, not security/policy approval. Reviewed P0/P1/pre-defense/W1 source/reports and actual protected data interfaces. Historical divergent branch SHAs and reported backend test commit are references; no branch merging or deployed-version assumption.

New milestone outputs/results and exact checkpoint identities are appended to `KOI_WEB_IMPLEMENTATION_ACCEPTANCE.md`. SOURCE INSPECTED, TEST EXECUTED, BROWSER OBSERVED, HOSTED OBSERVED, NOT RUN, BLOCKED and DECISION NEEDED remain distinct.


Approved baseline checkpoint: **49ad94880bdeb66a071add4cb320d0e148d5cf91**, local `feat/web-product-data`, exactly seven reviewed W1 files. Fresh baseline Jest 91/16 and explicit TypeScript passed before checkpoint. Current additive product-batch execution and build identity are in KOI_WEB_IMPLEMENTATION_ACCEPTANCE.md. Reported backend commit 8dac2b6 was not available as a local Git object; no fetch, merge or deployment/version assumption made.

## 2026-10-18 approved UX implementation update

Baseline inspected: feat/web-product-data, b384ce2cef44e83e53db7f50182f3ccfaac32187 (prior product batch is committed). Initial worktree had only excluded .idea/ and repos/koi-mobile/android/. No baseline edits discarded. This update owns ConversationProductControls, its focused spec, route composition in chat/page and companion-scene/page, and appended ADR/handoff/acceptance documentation. Protected auth/crypto/db/session/SSE, Ahmad renderer/controller, backend and Flutter remain untouched. No new persistence store or reward issuance. No commit/push/merge/deploy performed.

## Increment 03 ownership update — 2026-10-18

Initial status matched the preserved Increment 02 dirty worktree at b384ce2 on feat/web-product-data; .idea/ and repos/koi-mobile/android/ were already untracked. No other-owner edits overwritten. New work owns history/list presentation, activity availability, recorded-board dialogs, advisory reward preview, bounded backup error explanations, Import/Export copy and onboarding sync-failure categorization. Full 25-project-file working diff inventory and exact evidence are appended to KOI_WEB_IMPLEMENTATION_ACCEPTANCE.md. Protected storage/session/crypto/auth/transport, Ahmad renderer/backend and Flutter remain untouched. No commit/push/merge/deploy performed.

## History / Export follow-up ownership — 2026-10-18

Preserved the existing dirty feat/web-product-data baseline at b384ce2. New owned modules: read-only ciphertextExport, CiphertextExport UI, unwired sessionTransition consumer scaffold, three test suites; Export page intentionally replaces its dormant report generator/false-claim template. Existing parser predicate is exported unchanged; web-honesty adds context mock/truthfulness assertions. Four root reports updated. No protected DB/session/crypto/auth/API/SSE/renderer/backend/Flutter edit or migration; no commit/deployment. Latest acceptance section has separate data-copy vs restoration vs A/B results. Desktop review packet was not regenerated.
