# KOI Web — source-based page audit, API-independent backlog, and Ahmad/Web parallel plan

**Audit date:** 2026-10-17. **Source baseline:** GitHub `Koi-fyp/Koi`, `feat/avatar-webview-host` at published `40be37e201998c54e5be3f0f9abd6973ec36e616`. **Local source caveat:** P0, new jigsaw read-model, M13 and possible avatar work are **uncommitted on the user's computer and are not represented by the published source**. Codex must inspect the actual worktree and handoffs, and never revert working local changes simply because GitHub appears older.

**Documentation read:** `KOI_ULTIMATE_MASTER_BLUEPRINT_v4_13(1).md` (particularly §§1–4 and 6–7); `TRACK_WEB_AVATAR_PATCHED_v4_9.md`; `TRACK_AI_BACKEND_FINAL_v4_13(1).md`; `SESSION_HANDOFF(3).md`; `KOI_P0_P4_INTEGRATION_RECOVERY_CODEX_2026-10-17.md`; prior M11 and full Web handoff documents. Historical passages have supersession notes; **current live behavior and accepted local testing supersede old deployment forecasts**.

## Immediate policy

- **Keep UI visually unchanged:** retain DOM composition and accessible labels where possible, layout, palettes, fonts, spacing, cards, animations, image assets, breakpoints and navigation. Update data sources, callbacks, feedback and honest empty/error states, not the design system.
- **No invented personal data.** A fixed heading, FAQ answer, brand color or design illustration is valid static content. Numbers, achievements, activity times, storage amounts, wellness insights, messages, completion states and purported facts about this user's data must be derived from real records or shown as an honest unavailable/empty state. Decorative **preview** may remain only when conspicuously labeled and not conflated with real progress.
- **Do not send everything to FastAPI.** Blueprint §3.1a requires local CSE-at-rest and makes `session_history` client-authoritative. Read user-specific Web state from UID-scoped Dexie and documented local preferences. Encrypt sensitive data before Firestore sync. FastAPI should not become an invented persistence service.
- **Freeze Ahmad's API:** do not modify endpoint routes, event schemas, tokens, SSE, risk policy, crisis intervention, redirect semantics or deployment. `/api/v1/chat` and `/health` are the current integration boundary; no new endpoints assumed. The source chat contract is explicitly partly PROPOSED and has supersession notes. Live version remains to be identified before audio/video enabling.
- **No false action confirmations:** never claim deletion, sync, account deletion, reminder scheduling, import/export accuracy or crisis evaluation without evidence.
- **Retain protected baseline:** P0 browser acceptance (genuine Firebase Auth, six successful SSE POSTs) and first jigsaw read model (50 tests) were reported as successful on the *uncommitted local worktree*. Revalidate these after each change. Backend returned no observable reply in the most recent jigsaw browser attempt; don't imply this path was accepted.

## Route-by-route audit

| Route / component | Source evidence in published branch | Actual condition / risk | API-independent action | Needs Ahmad / joint approval |
|---|---|---|---|---|
| `/` landing | `src/app/page.tsx` FEATURES, FAQ and hero | Claims `Zero accounts, zero data storage`, `no waiting, ever`, `2,400+ people talking`; these are unsupported and conflict with auth/local data and Modal cold starts. | Replace unsupported numbers/claims with factual capability descriptions; preserve marketing layout and CTAs. | Confirm externally asserted production support, service hours and validated helplines before claiming them. |
| `/about` | `src/app/about/page.tsx` TIMELINE, values, statistic | Hardcoded claimed timeline (`50 users in Lahore`, `thousands of conversations`, `50,000+`), unsupported unless evidence exists. | Keep timeline/cards; replace unsupported history/metrics with verified team milestones or nonnumerical text. | Only if team wants centrally verified deployment-wide metrics. |
| `/how-it-works` | `src/app/how-it-works/page.tsx` | Static informational content is appropriate, but some feature promises (crisis detection/privacy/languages) need evidence. | Align copy with actual deployed/locally tested scope; keep visuals. | Confirm backend capability and reviewed public safety copy. |
| `/onboarding` | `src/app/onboarding/page.tsx`, `src/lib/onboarding.ts` | Published `AIDisclosureStep` jumps to step 5, skipping avatar step 4; `avatar || 'fox'` fallback conflicts with companion selection. IndexedDB writes best effort; Firestore writes may fail without surfacing. | Reconcile with uncommitted avatar fixes; save one UID-scoped canonical choice, language, consent and notification preference; verify reopening; explicit persistence status. | Firestore rules and cross-device sync; canonical male/female/legacy fox product choice, if not locally resolved. |
| `/chat` | `src/app/(authenticated)/chat/page.tsx` | Published `/Male.png` hardcoded; narrow screens hide avatar after messages. P0 session continuity reportedly fixed locally. | Use shared preference, preserve chat and P0; load correct image and real preference; show intentional media availability. | Only backend emotion/live-chat acceptance; do not alter protocol. |
| `/companion-scene` | `src/app/(authenticated)/companion-scene/page.tsx`, `src/components/companion/*` | Published VRM uses separate IndexedDB avatar lookup and may text-fallback on WebGL. Mic/camera deliberately disabled; event-to-emotion wiring present but authenticated visual verification not demonstrated. | Same UID resolver as `/chat`; verify VRM actual render, fallback, expression mapping with fixtures; preserve P0 and Flow 4. | Live `companion_state` verification and later deployed media payload/response. |
| `/progress` | `src/app/(authenticated)/progress/page.tsx` | Published stats `12/47/7.2`, `247` pieces, fixed sample achievements, fixed mood chart, `Math.random()` heatmap. User reports a newer local UID-scoped completed-exchange/jigsaw read model with remaining previews labeled. | **Merge, don't overwrite**, the new read model; compute legitimate totals; for absent mood/check-in/task sources show empty/unavailable states; enforce event dedup and user scoping. No invented gamification awards. | Signed-off reward rules, scheduled AI check-in content, task service if future scope. |
| `/settings` | `src/app/(authenticated)/settings/page.tsx` | React-only currentAvatar/name/language/reminder state; `Clear History` only displays success toast; storage `1%`, `42 KB of 5 MB`; time picker placeholder; fixed 8 PM; current AvatarPicker state initialized from props. | Use UID-owned persistence and a shared preference store; honest save/restore errors. Replace fake quota with `navigator.storage.estimate()` clearly labeled browser estimate, or KOI-local computed approximate size. Acknowledge permission and reminder limitations. Do NOT falsely clear history. | Complete cross-device prefs, scheduled reminders, true cloud deletion via agreed rules. |
| `/settings/privacy` | `src/app/(authenticated)/settings/privacy/page.tsx` | Hardcoded recent activity array and overly broad privacy claims; Delete Account button lacks a working action; claims server-side deletion. | Replace fabricated recent activity with real optional local audit ledger or empty state. Distinguish local CSE, plaintext inference, attempted/confirmed sync and lack of deletion. Disable destructive path with accurate wording until implemented. | Reviewed retention/deletion policy; cloud deletion transaction/admin authorization; safety/help copy approval. |
| `/settings/export` | `src/app/(authenticated)/settings/export/page.tsx` | PDF uses invented mood, loneliness, counts, conversations, crisis incidents and “insights”; timed fake progress. **High-priority trust issue**. | Change to export only actual authorized, decrypted user records with consent, verified metrics and explicit unavailable sections. Keep existing PDF design. Escape/sanitize rendered text; never invent mental-health trends or crisis resolution. Support cancellation/errors. | Cloud-inclusive export and cross-device records require sync contract/rules; not necessary for truthful local export. |
| `/settings/import` | `src/app/(authenticated)/settings/import/page.tsx` | Static preview and disabled “Coming Soon” import (honest but incomplete). | Keep disabled and explicitly unavailable, or implement local-only JSON validator + preview/dedup in a **separate** safe milestone. Do not claim PDF parsing/backups work. | Data portability/cloud reconciliation only if requirements agreed. |
| `/avatar-host` | `src/app/avatar-host/page.tsx` & WebView bridge | Intentional display-only route; no Firebase/API needed. Isolated verification previously succeeded for male and female models and `AVATAR_READY`. | Leave stable; regression test both models, bridge readiness and no auth/network. | Flutter/Web joint Gate 2-J on real Android only. |
| Navigation and mode picker | `src/components/layout/BottomNav.tsx`, `ModeSelector.tsx` | Chat/Progress/Settings are real routes; ModeSelector has Text only enabled, other modes disabled. | Preserve navigation and P0 shared session; mark true unavailable modes instead of activating an empty shell. Remove development console log. | Media capability and privacy gates before enabling voice/video. |
| Auth routes | `src/app/api/auth/anonymous/route.ts`, `link-email/route.ts` | Admin-backed production flow distinct from development-only Firebase client anonymous sign-in; current testing can work without Admin. | Preserve established auth; make any profile/account-link actions accurately communicate missing Admin config and not falsely succeed. | Firebase Admin, Firestore rules, ownership, account linking and Cloud support. |

### File and data-model recommendations

**Reuse first:** `AuthContext` UID, `db.users`, `db.messages`, `db.moodEntries`, `db.jigsawProgress`, existing accepted local `ConversationContext`/`PersistentConversation`, `conversationService`/CSE routines, `syncQueue`, new local jigsaw read-model, avatar preference resolver if present. Avoid parallel singleton stores or a second client chat API.

**New lightweight local abstractions only if absent:**

1. `useUserPreferences(uid)` + validated update; reflects avatar, preferred language, notification toggle/time, name only if disclosed/consented. Sync best effort but display real outcome.
2. `useWellnessReport(uid)` returns a typed, data-provenance-aware report based on **real** completed messages, check-ins and rewards; has loading, unavailable, empty, partial and error states. Never derive diagnosis or “crisis resolved” from message content.
3. `useLocalStorageEstimate()` returns a clearly labeled origin/browser estimate or an approximate local KOI byte count, never a fixed quota.
4. Optional UID-keyed activity audit ledger for *actual events only*, no fabricated samples and no raw message text; only write after persistence succeeds. Do not treat attempted Firestore sync as completed.
5. `FeatureAvailability` capabilities sourced from what is actually implemented and verified, not a new invented API. Disabled features remain disabled.

**Destructive operations:** Clear History and Delete Account are intentionally **blocked** until a documented policy defines what is removed from local Dexie, pending sync queues, Firestore, backups, ongoing sessions, offline tabs and re-login state. Never show success for a noop. A reversible, local-only *New Chat* is not a replacement for deletion. A 24-hour temporary-chat policy is likewise **not locked** in the blueprint and must not be guessed.

**Mood & daily check-in:** `moodEntries` schema exists, but published Web routes do not contain a completed check-in form/writer. Display no mood score before real entries exist; a minimal check-in screen may be developed locally if approved, but encrypt sensitive ratings before cloud sync. Blueprint §4.1g explicitly specifies **Web in-app check-in-due indicator**, not Web Push. LLM-generated check-in delivery needs Ahmad's hosted service and approved trigger design.

**Jigsaw:** The user reports the first local milestone counts completed exchanges and excludes duplicates/other users. Keep it; do not invent streak rules, points, milestone thresholds, other source awards or engagement metrics until signed off. Exposing pieces earned from crisis severity or encouraging alarming disclosures is inappropriate.

**Export:** PDF is a generated document, not a guarantee of clinical measurement. Date ranges, exact user totals and mood averages require source records. If there are no check-ins or crisis data, print “No recorded entries” or omit that section; NEVER fill it with demo crisis events. Beware decrypted data inside HTML strings: use sanitized DOM/text nodes or a safe renderer.

**Privacy review:** Cloud storage is CSE-at-rest, not E2EE; inference FastAPI necessarily receives plaintext prompts/history over TLS. Do not promise “not even we can read” without clarifying the inference trust boundary. No undocumented server telemetry, universal deletion, clinical certification or active emergency-service validation claims.

## Implementation release train — do in strict order

| Batch | Web owner task | API touched? | Gate |
|---|---|---|---|
| W0 — freeze and inventory | Read current dirty files, enumerate all routes and user-dependent hardcoded values; snapshot rendered UI screens; record SHA and test build. Compare existing P0/jigsaw/avatar local deltas. | None | Baseline and screenshots/DOM snapshots; no uncommitted work lost |
| W1 — stop misleading UI | Remove invented public usage counts, progress values not already fixed, fabricated privacy activity; disable noop destructive actions with real notice. Preserve layout. | None | No invented personal values, warnings correct, P0 still passes |
| W2 — persist preferences | Settings avatar/name/language/check-in preference and times use UID-scoped local store; onboarding and 2D/3D chat share preference; test reload/account-switch. | None | Aisha/Raza consistency, no cross-user carryover, honest save errors |
| W3 — truthful progress and storage | Reuse existing jigsaw read model; actual browser-estimated storage; real completed chats; mood/check-in empty states. | None | Idempotent counts and privacy boundaries; no static counts |
| W4 — real PDF export | Replace sample wellness data and fake progress with real UID-scoped authorized records. Empty/partial cases, safe rendering and error handling. | None | PDF contains real verified values only; no fabricated crisis/clinical claims |
| W5 — privacy and consistency | Honest privacy screen, actual local activity when available, sync pending/success states; do not fake deletion. Review intro/about/features against delivered functionality. | None | Privacy copy matches code, cloud status accurate |
| W6 — browser regression | Route screenshot comparison desktop/mobile; manual Firebase authenticated smoke and local DB isolation; preserve P0 SSE and actual avatar rendering verification. | No API changes | PASS/FAIL/NOT RUN evidence for each route and responsive layout |

Each batch should create its own local report. **Do not run all batches in a single Codex change**. Stop at genuinely destructive decisions (history/account deletion), unapproved product rules (jigsaw/rewards) or missing authority. Keep one dev server; limited RAM; run expensive build once per cohesive batch.

## Independent parallel division of labour

### You — Web/UI and privacy-consistent client persistence (exclusive edit ownership)
- `repos/koi-backend/nextjs_app/src/app/**` except `api/auth/**` (shared review only), `src/components/**`, Web hooks, renderer and local read models, public truthful copy, browser screenshot/acceptance tests.
- UI-preserving W0–W6 batches, real history/progress/settings/export/privacy; rendering emotion states from existing event types; media controls, browser permission UX, optional locally verified speech/TTS lab.
- Never change Ahmad's `deploy/modal/**`, crisis weights/models or chat wire format. If a real required capability is absent, create a blocked integration ticket with payload/examples, not a guessed endpoint.

### Ahmad — inference/backend and verified deployment contract (exclusive edit ownership)
- `repos/koi-ai-engine/deploy/**` and model/runtime/tests, risk scorer/RAG and crisis fallback; Firebase token validation, `/health`, chat SSE guarantees, deployment release SHA, error codes, memory/latency/cold starts and backend smoke tests.
- Publish sanitized contract fixtures for `latency`, `companion_state`, `delta`, `risk`, `state`, `done`, exercise and crisis handoff; supply realistic size limits & performance under approved modality support. Verify TTS/ASR/multimodal only when deployed, never imply “supported” because a parser accepts a schema.
- For later cloud sync, review/own agreed Firestore rule deploy and Admin workflows, **without requiring you to exchange Admin keys**. Backend does not gain ownership of the client's encrypted history UI or Web state.

### Joint gates / no concurrent edits
1. **Contract handshake:** Ahmad reports deployed SHA, exact authoritative contract version, supported modalities, `/health` status and redacted SSE fixtures. You perform a real Firebase-auth browser test and record HTTP/status/event ordering. API remains frozen until explicit decision to change it.
2. **Storage/sync review:** agree UID namespace, encrypted payload shape, Firestore rules, retention, offline queue, multi-device merge, user data export/delete behavior. Ahmad owns server/rules; you own client encryption and honest sync feedback. Sign off via an interface document before implementation.
3. **Avatar/Flutter Gate 2-J:** Web supplies stable `/avatar-host` and `KoiBridge` commands; Flutter collaborator owns Flutter WebView and on-device permissions. Test real Android jointly.
4. **Multimodal Gate 4-J:** Ahmad demonstrates live approved audio/video endpoint contract, safety/risk behavior and media deletion; you build optional explicit-consent capture/render/stop/fallback. Co-run real-device checks, especially modality dropout; no raw media persisted by default.

**Branch discipline:** you stay on `feat/avatar-webview-host` or a *new Web-only integration branch from its reviewed baseline*; Ahmad stays on `feat/exercise-director-modal`. Avoid concurrent changes to `conversationService.ts`, `jsonChatTransport.ts`, `chatContract.ts`, auth or encryption; jointly approve any necessary patch through a single integration coordinator. A source-only PR is not a deployment guarantee. Codex never automatically commits/pushes/merges/deploys unless explicitly authorized. Leave `.idea/`, mobile Android files, `.env.local`, credentials, tokens and local message content alone.

## When the *complete* AI stack is hosted (the text service was already exercised)

**Current evidence:** Previous accepted P0 report recorded six real 200/SSE calls through Firebase Auth, but the deployed revision/version and multimodal readiness are not established. Treat 'AI gets hosted' as **Ahmad's later complete/versioned deployment**, not the first text endpoint ever becoming available.

**Independent work before the release:** You complete W0–W6, avatar VRM/PNG fallbacks, emotion fixture tests, placeholders-to-empty-state conversion, Web ASR/TTS permission and playback prototypes *in labs*, privacy/read-model tests. Ahmad completes model + crisis/fallback evaluation, service deployment and SSE+auth contract/regressions, clear media/retention limits. Neither modifies the other's files.

**Release event (short joint checkpoint):** Ahmad supplies release SHA/endpoint/health, contract and fixture pack and a sanitized supported-capabilities declaration; you verify real authenticated English chat, delta and done, signed exercise state, risk/handoff handling, avatar emotion, one long cold start and failures. Never print Bearer tokens or `done.trace`.

**After that checkpoint:** You can enable **only actually supported** frontend pathways, in stages: text/avatar first; separately local text-to-audio TTS + lipsync (without modifying API); then microphone ASR with reviewed transcript and an approved audio endpoint; finally optional camera/video with permission and raw-media cleanup. Ahmad owns back-end ASR/TSD/media invocation and accepts one agreed client fixture set. A passed fixture alone is not live acceptance.

## Acceptance definition

- Pixel/layout snapshots stable at mobile/desktop, aside from content and legitimate empty/error/help messaging.
- No personalized values or achievements render without a source; public metrics and historical claims verified or removed.
- UID ownership confirmed across logout, new anonymous identity and two tabs.
- P0 (navigation, refresh, SSE no duplicate requests) remains green.
- Jigsaw never counts duplicate/incomplete/foreign messages; raw clinical ratings aren't leaked into logs/analytics.
- All destructive controls either work end-to-end with audited consequences or clearly say unavailable; never fake a success.
- Settings persist across reload, reflect saved state on every route, and handle offline/Firestore-denied behavior honestly.
- PDF export has real user-owned data or a transparent no-data state; no synthetic crisis cases or fabricated wellness improvement.
- No backend contract or modality changed under the API freeze; disabled media is not silently enabled.
- Git SHA, local dirty state, actual build, browser/device version, endpoint/version and evidence are included in handoffs; differentiate automated fixtures, genuine local browser and live Modal.

## Evidence links for source review

- Web route tree: `https://github.com/Koi-fyp/Koi/tree/40be37e/repos/koi-backend/nextjs_app/src/app`
- Settings: `https://github.com/Koi-fyp/Koi/blob/40be37e/repos/koi-backend/nextjs_app/src/app/(authenticated)/settings/page.tsx`
- Privacy: `https://github.com/Koi-fyp/Koi/blob/40be37e/repos/koi-backend/nextjs_app/src/app/(authenticated)/settings/privacy/page.tsx`
- Export: `https://github.com/Koi-fyp/Koi/blob/40be37e/repos/koi-backend/nextjs_app/src/app/(authenticated)/settings/export/page.tsx`
- Import: `https://github.com/Koi-fyp/Koi/blob/40be37e/repos/koi-backend/nextjs_app/src/app/(authenticated)/settings/import/page.tsx`
- Progress: `https://github.com/Koi-fyp/Koi/blob/40be37e/repos/koi-backend/nextjs_app/src/app/(authenticated)/progress/page.tsx`
- Onboarding: `https://github.com/Koi-fyp/Koi/blob/40be37e/repos/koi-backend/nextjs_app/src/app/onboarding/page.tsx`
- Chat: `https://github.com/Koi-fyp/Koi/blob/40be37e/repos/koi-backend/nextjs_app/src/app/(authenticated)/chat/page.tsx`
- Companion: `https://github.com/Koi-fyp/Koi/blob/40be37e/repos/koi-backend/nextjs_app/src/app/(authenticated)/companion-scene/page.tsx`
- Mode selector: `https://github.com/Koi-fyp/Koi/blob/40be37e/repos/koi-backend/nextjs_app/src/components/layout/ModeSelector.tsx`
- Auth and storage: `src/contexts/AuthContext.tsx`, `src/lib/onboarding.ts`, `src/lib/db.ts`, `src/lib/firestore/sync.ts`, `src/lib/conversation/*`
- Backend source: `https://github.com/Koi-fyp/Koi/tree/feat/exercise-director-modal/repos/koi-ai-engine/deploy/modal`
- Proposed/extended v1.1 contract: `https://github.com/Koi-fyp/Koi/blob/feat/exercise-director-modal/repos/koi-ai-engine/docs/contracts/KOI_CLIENT_CONTRACT_v1.md`

**Note:** This is a detailed **published-source audit and local execution plan**. It is *not* a claim to have run or modified the current local uncommitted worktree, and it is not a live acceptance report of every page.
