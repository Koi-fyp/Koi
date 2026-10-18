# KOI Web final ownership handoff - 2026-10-18

**Transfer status: PREPARED, NOT STAGED, NOT COMMITTED, NOT PUSHED.** Ahmad is the sole Web implementation owner. This session has stopped feature implementation. Review-branch creation, commit and push await explicit owner approval of the staging manifest and inherited credential concern.

## Identity and verification

| Item | Actual state |
|---|---|
| Current local branch | `feat/web-product-data` |
| Current HEAD | `b384ce2cef44e83e53db7f50182f3ccfaac32187` |
| Proposed destination | `handoff/web-product-data-2026-10-18` - not created |
| Pushed handoff SHA | **NONE** - approval pending |
| Ahmad remote inspected | `origin/avatar/vrm-emotion`, `884a278e0370835e98c07ae192cfa2dc8ba73495` |
| Shared merge base | `223e97c489947b98677392f9b8ea383690ab1fe8` |
| Initial tracked modifications / staged paths | 24 / 0 |
| Initial nonignored untracked paths | 69, including 26 unrelated IDE/Android paths |
| Ignored files audited by filename | 51,726 before new handoff outputs; exhaustive local-only index in `artifacts/web-final-handoff/excluded-ignored-files.jsonl` |
| Fresh Jest | `npm test -- --runInBand --silent`: **286 PASS /39 suites**, 28.334s |
| Fresh TypeScript | `npx tsc --noEmit --incremental false`: **PASS**, exit 0 |
| Fresh production build | `npm run build`: **PASS**, Next 14.2.35, 19/19 entries, BUILD_ID `i4JLGTu9EUai8YYGsixEA` |
| Diff whitespace | `git diff --check`: checked before approval; line-ending notices do not constitute errors |
| Fresh browser / Ahmad combined build | **NOT RUN** - no integration, browser user data or live backend requests performed during transfer |

Fresh checks ran sequentially with no duplicate server. The build reads existing configuration normally; no `.env.local` content was read or exported by the audit. Fetch only downloaded Ahmad's branch; no checkout/merge/cherry-pick or source replacement occurred.

All paths below beginning `src/` are relative to **`repos/koi-backend/nextjs_app/`**. The exact full-path, line-numbered inventory of 81 files and 234 function bindings is `KOI_WEB_FINAL_FILE_FUNCTION_INVENTORY_2026-10-18.json`. The staging manifest labels each changed/new file; inherited paths explicitly identified below are already in HEAD, not new staging operations.

## Feature inventory from actual current source

### 1. Activity events / rewards - IMPLEMENTED AND VERIFIED

**Changed/new files:** `src/lib/db.ts` (tracked modification); new `src/lib/activities/{activityTypes,activityLedger,rewardPreview}.ts`; new `src/__tests__/{activity-ledger,reward-preview}.test.ts`.

`createActivityLedger(database).record(candidate,payload)` / `activityLedger.record` validate source, authenticated captured owner, ciphertext and evidence, then use one Dexie `rw` transaction covering `activityEvents`, `rewardReceipts`, `milestoneReceipts`. Duplicate ID returns the original event/receipt, owner/source/day caps apply, next sequential slot is allocated, threshold receipt inserted atomically. Owner-change listener aborts; unexpected write errors roll back. `read(owner)` is owner-filtered and checks consistency. `karachiDay` assembles `Intl.formatToParts` values explicitly. `previewReward` remains an advisory predicate, not a second writer.

**Evidence:** automated races, retry/reopen, source/day boundaries, rollback at write stages, migration preservation, 25/26 cap; historical actual browser first check-in/receipt and two-tab duplicate race. No cloud activity sync, no legacy conversion, no automatic historical awards. Client time is accepted for gamification, not an authoritative security clock. Conversation producer remains unavailable (item 3); ledger existence does not prove that producer's eligibility.

### 2. Encrypted check-ins - IMPLEMENTED AND VERIFIED for existing unlocked anonymous users; linked-key path PARTIALLY IMPLEMENTED / locked

**New files:** `src/lib/checkins/checkInService.ts`, `src/components/progress/ActivityAvailability.tsx`, `src/hooks/useActivityData.ts`, `src/__tests__/checkin-{service,form}.test.ts[x]`. Inherited validation: `src/lib/checkins/validateCheckIn.ts` / `validateCheckIn`, `checkin-validation.test.ts`.

`checkInAvailable`, private `existingContext`, `saveCheckIn`, `readCheckIns`; `OwnedActivities.save`; `useActivityData` Dexie `liveQuery`. Mood/Connection/Energy are integers 1-5 with explicit consent and no free text. A form-open UUID persists through retries, another UUID is created only for another deliberate entry. Existing AES-GCM encrypts `{scale_version,mood,connection,energy}` before the ledger transaction. Ratings are not stored in metadata/localStorage/logs. Completion date is actual client save time after encryption; duplicate ID keeps its original event. Success feedback follows committed persistence, not a button click.

**Evidence:** fresh tests and historical 14/14 actual browser flow: event+one receipt+slot 1; refresh retained saved ratings/chart/piece; second same-day event with no second check-in piece; cross-tab race; missing-key fail-closed; second anonymous UID isolation. **Blocker:** current shared auth context does not supply an already-unlocked linked secret; linked users remain locked rather than generating/replacing keys. No cross-device recovery claim.

### 3. Explicit conversation completion - SCAFFOLDED / DISABLED

**New files:** `src/lib/activities/conversationCompletion.ts`, `src/components/chat/ConversationProductControls.tsx`, `src/__tests__/conversation-completion-evidence.test.ts`, `conversation-product-controls.test.tsx`. Call sites in modified Chat and Companion Scene pages.

`conversationCompletionEligible` is fail-closed over explicit intent, owner, no pending turn, `done-persisted` evidence and `resolved-or-absent` handoff state. `conversationCompletionId` implements the exact UID/conversation/last-persisted-message SHA-256. Complete Conversation opens truthful requirements; Save completion stays disabled. **There is no runtime conversation-completion writer or receipt.**

`conversationService.sendMessage` persists an assistant only after terminal SSE done resolves, but current `ConversationSession` drops earlier turn events and has no durable authoritative unresolved/acknowledged-handoff accessor/lease. `queueCrisisPath` marks a resolution when queued, not when acknowledged. No score or later `done.handoff:null` workaround. Ahmad must supply consistent persisted-pair/safety evidence and commit lease; resolve this on his new voice-aware session version, not by overwriting it with our old file.

### 4. Breathing rewards - IMPLEMENTED BUT UNVERIFIED against hosted exercise production

**Tracked modification:** `src/components/companion/ExerciseDirector.tsx`; **new:** `src/lib/activities/breathingActivity.ts`, `src/components/progress/BreathingActivityBridge.tsx`, `src/__tests__/breathing-activity.test.tsx`; modified Scene route wraps the bridge. Exact existing change also in `review/increment04-exercise-callback.diff`.

`PacedBreathingPanel` / `registerMeasurement` use existing `BreathingClock` and `performance.now()` excluding pauses. `ExerciseDirector.report` invokes optional `onBreathingResult` or bridge callback with session UUID, timestamps, planned/completed cycles, end reason and additive `durationMs`. Completed >=80% and >=48s only; stop/handoff/navigation never qualify. `breathingEligible`, `completionHash`, `saveBreathingResult` use SHA-256 of UID/session, provenance **client-measured**, then the same ledger. Rotating signed exercise tokens are not identities or completion proof.

**Evidence:** automated threshold, duration, interruption/idempotence tests; historical **LOCAL FIXTURE browser 4/4**, real 60s timer, callback/receipt/piece/refresh and user-stop checks. Separate genuine Modal HTTP200/done supplied no `start_breathing`; therefore **hosted exercise completion NOT RUN**, not PASS or inferred failure. The optional `durationMs` extension still needs Ahmad's exact callback review before integration. No independent speech stop/lip-sync implementation is claimed; integrate those interruptions with Ahmad's real voice owner.

### 5. Jigsaw / milestones - IMPLEMENTED AND VERIFIED (first earned piece and refresh); full board TEST ONLY

**Modified:** `src/components/progress/RecordedBoard.tsx`, `src/__tests__/recorded-board.test.tsx`; new ledger/types and `ActivityAvailability` above.

`RecordedBoard` validates owner/slot/completion identities; displays 25 slots from reward receipts (storage 1-25, UI internal 0-24). Earned detail is keyboard/touch accessible with existing `useModalFocus`; genuine source/time/provenance is displayed. Milestones unlock only from `milestoneReceipts`, not count alone. Existing styled timeline now uses thresholds 5/10/15/20/25; fabricated 7-day and 50-piece achievements were removed. Legacy `jigsawProgress` remains separate and unchanged.

**Evidence:** actual browser slot 1, provenance dialog, refresh, daily cap and locked milestone keyboard detail; tests cover exactly 25, final milestone and 26th event-only. No artificial backdated real-user activities were created to simulate 25 earned browser pieces.

### 6. Progress / dashboard / charts - IMPLEMENTED AND VERIFIED for saved activity; remaining previews explicitly separate

**Modified:** `src/app/(authenticated)/progress/page.tsx`, `progress.test.tsx`; new `useActivityData` / `ActivityAvailability`; inherited `src/lib/progress/progressReadModel.ts`, `src/hooks/useProgress.ts`.

`summarizeCompletedExchanges` counts UID-owned encrypted user/replyTo assistant pairs once; `readProgress` reads legacy totals without issuing rewards. Actual saved check-ins are decrypted for current-owner rating chart/table; actual ledger events feed recorded activity days and piece/milestone UI. Loading, locked, corrupt and unavailable states do not fabricate zeros. Existing labelled Design previews remain samples, not personal history; preview bar zero-height bug fixed. No separate `/dashboard` route exists in this local tree. No clinical improvement, inferred moods, personality score, streak or reward from exchange count.

**Remaining:** future dashboard/localization/heatmap design should consume this existing data, not add another store or writer. English/Urdu preference persistence does not mean full Urdu interface localization is implemented.

### 7. Data export / import / wellness report - mixed status

**Changed/new files:** `src/app/(authenticated)/settings/{export,import}/page.tsx`; new `src/components/data-portability/CiphertextExport.tsx`, `src/lib/data-portability/ciphertextExport.ts`, `ciphertext-export{,-ui}.test.ts[x]`, `backup-errors.test.ts`; modified `BackupPreview.tsx`, `backupDraft.ts`; inherited draft/existing-key/preview tests.

- **Ciphertext data export IMPLEMENTED AND VERIFIED:** `readCiphertextExport`, `serializeCiphertextExport`, `assertExportOwner`; `CiphertextExport.prepare/download`. One read-only snapshot transaction over owner-tagged messages and the active conversation header; max 200 records /2MiB. `kind:'koi-ciphertext-data-export'`, formatVersion 1. Allowlisted ciphertext and owner/session/sender/time metadata, no raw keys, tokens, metrics or ratings. Real browser download with synthetic content matched stored ciphertext; account changes clear prepared data. Download request wording does not pretend the user saved a file.
- **Restorable backup NOT IMPLEMENTED:** export explicitly says restorationSupported=false, decryptionVerified=false, manifestAuthenticated=false, originalKeyRequiredToDecrypt=true. It is not the draft-import format. No original-key loss/cross-device restore guarantee.
- **Import PARTIALLY IMPLEMENTED:** `readBackupDraft`, `parseBackupDraft`, `previewDraftConflicts` enforce draft JSON envelope/type/size/version/owner binding/ciphertext shape/record limits and metadata-only duplicate/conflict preview. `kind:'koi-backup-draft'`, schemaVersion 1, same-owner-existing-key-only. `verifyDraftCiphertexts` is a tested dependency-injected foundation but the page has no authorized existing-key verifier. UID hash is public binding, not integrity proof. **No import mutation or transactional restoration path enabled.**
- **Wellness report SCAFFOLDED / DISABLED:** current Export page separates the products and shows no generated report. Old synthetic PDF implementation was removed from the active page. No invented mood/loneliness/insight/crisis content. A real report requires an approved source/consent design, not setting an old export flag true.

### 8. History / selection - PARTIALLY IMPLEMENTED

**Modified:** `src/app/(authenticated)/history/page.tsx`, `history-page.test.tsx`; inherited `src/lib/history/readHistory.ts`, `history.test.ts`.

`HistoryPage` reuses only the current shared session's already-unlocked messages; `readOwnedHistory` reads at most 200 newest owner-tagged service rows, actual quoted titles, times, counts and locked metadata; `searchHistory` searches current in-memory readable content. Transcript display and Continue current conversation work. Older sessions stay locked/read-only and cannot be resumed. No generic `withOwnedDecryptor` implemented.

**Evidence:** current history browser observation/manual UAT and test coverage; independent older-session unlock/resume remains NOT RUN/not enabled. Active snapshot can contain messages not yet represented in service rows; do not imply current row-based list is a complete archive.

### 9. New Chat - SCAFFOLDED / DISABLED; production multi-session management NOT IMPLEMENTED

**New files:** `src/lib/history/sessionTransition.ts`, `session-transition.test.ts`, product controls above; `review/new-chat-*` and `validate-new-chat-proposal.cjs`.

`transitionOwnedConversation` validates consumer selection/receipts and refuses streaming transitions without invoking an adapter. It has **no production adapter**. Current New Chat buttons remain disabled. Earlier attempt was rejected by automatic approval review; no protected source changed. Product owner explicitly retained joint approval and requested review-only diffs. Source hash manifest confirms protected files unchanged.

`new-chat-session.proposed.diff` proposes only an additive v4 archive + narrow existing-manager adapter; `new-chat-consumers.proposed.diff` shows UI wiring; `new-chat-tests.proposed.diff` holds 10 fixture/migration cases. `git apply --check`, syntax and in-memory candidate TypeScript passed locally; candidate tests were NOT RUN. New Chat has never been browser verified. **Do not apply these old-baseline drafts wholesale over Ahmad's voice-aware session.**

### 10. Firebase account preferences - IMPLEMENTED AND VERIFIED

**Modified:** `src/lib/preferences/userPreferences.ts`, `src/hooks/useUserPreferences.ts`, Settings and Chat/Scene call sites, `src/lib/onboarding.ts`; **new:** `accountPreferenceSync.proposed.ts` (despite its name, now runtime-used), `preferenceSync.ts`, `syncFailure.ts`, `AccountPreferenceStatus.tsx`, preference-sync/account adapter tests, `KOI_FIREBASE_PREFERENCE_SYNC_AUDIT_2026-10-18.md`.

`readOwnedAccountPreferences` / `writeOwnedAccountPreferences`: current Firebase UID and same app validation, exact `users/{uid}` document, `getDocFromServer` and merge-only `{profile: allowlistedFields}` writes; no overwrite of crypto salt or unrelated fields. `syncAccountPreferences` single-flights, hydrates appropriate missing fields, keeps pending local changes/revisions, clears only acknowledged revisions and exposes truthful status/retry. `saveUserPreferences` local receipt precedes best-effort sync. `useUserPreferences` initializes and refreshes on focus/online. Avatar/language persist; local offline fallback is preserved.

**Evidence:** historical actual Firebase/Firestore browser **10/10**: Settings language, Settings Raza, inline Aisha/Raza including rendered Scene, refresh, offline/reconnect, server hydration and foreign read denied. Fresh adapter/integration/failure tests pass. No Console/rules deployment was performed by this handoff. Review rules files are proposals only; do not mistake them for deployed rules. Notification preference is not a delivered notification or saved check-in. Display-name edits remain local-only unless explicitly added to approved sync scope.

### 11. Authentication / account linking - PARTIALLY IMPLEMENTED

**Inherited, not dirty:** `src/contexts/AuthContext.tsx`, `src/components/providers/{AppAuthBoundary,AuthenticatedApplication}.tsx`, `src/lib/auth/anonymousSignInMode.ts`, `src/app/api/auth/{anonymous,link-email}/route.ts`, `auth.test.tsx`, `public-signin-retry.test.tsx`. Modified Settings still has no working email-link form.

`AuthProvider.signInAnonymously`, SDK `onAuthStateChanged`, `signOut` and genuine local-development anonymous path work; server path/custom-token contract remains unchanged locally. `linkWithEmail` helper and server `POST` verify identity/update credentials/return verification link, but **complete user-facing linking + email delivery + crypto transition/returning linked unlock is not implemented/verified**. AuthContext does not supply `linkedSecret`; existing caller re-encryption responsibility is not a complete flow. No auth rewrite or plaintext key fallback should be inferred from the helper's existence. Account deletion and Clear History remain intentionally disabled pending scoped deletion policy.

### 12. Onboarding / local persistence - PARTIALLY IMPLEMENTED (core saved selection verified)

**Modified:** `src/lib/onboarding.ts`, `src/lib/preferences/userPreferences.ts`, `useUserPreferences.ts`; inherited local-commit fixes in `src/components/onboarding/WelcomeStep.tsx`, `src/app/page.tsx`, Settings AvatarPicker/accessibility tests; shared avatar resolver/hooks inherited.

`completeOnboarding` persists matching avatar/companion/language/reminder fields to the current UID's existing local user row, preserves unrelated data, notifies consumers and merge-writes the existing Firestore profile. Local-save and sync-failure messages are distinct. Aisha=female, Raza=male, fox preserved; same preference used by PNG/VRM. Language setting is a saved preference, not complete translation. Local reminder is due-time copy, not notification delivery or activity completion.

**Known remaining gap from source:** `isOnboardingComplete` reads global `koi_onboarding_complete` rather than a UID-specific flag, even though the persisted user record has `onboardingComplete`; this can skip onboarding for another identity in the same browser. No fix made during transfer. Local callback fires before cloud write; cloud failure leaves actual local profile intact. Settings/inline sync uses the newer adapter while onboarding retains its direct merge-write path; consolidate only under Ahmad's review, preserving pending-choice rules.

## Current storage, crypto and session contracts

**Live Dexie version 3**, not version 4. Exact already-implemented v3 diff: `review/increment04-db-migration.diff`.

| Version | Stores / indexes |
|---|---|
| 1 | Existing `users`, `messages`, `moodEntries`, `jigsawProgress`, `syncQueue` unchanged |
| 2 | `conversations: 'uid, conversationId, lastActiveAt'` - one active header per UID |
| 3 | `activityEvents: 'id, owner_uid, &[owner_uid+source_type+completion_id], [owner_uid+source_type+day_key], completed_at'` |
| 3 | `rewardReceipts: 'id, owner_uid, &[owner_uid+source_type+day_key], &[owner_uid+slot_index]'` |
| 3 | `milestoneReceipts: 'id, owner_uid, &[owner_uid+milestone]'` |

Event `id === completion_id`; receipts use `JSON.stringify([owner_uid,source_type,day_key])`, milestone keys `JSON.stringify([owner_uid,milestone])`. New source fields/interfaces are in `activityTypes.ts`. Activity metadata is plaintext allowlisted provenance; ratings are ciphertext. No activity records in `syncQueue` or portability. The proposed archive v4 is **only a diff**, not a live migration.

`encrypt(plaintext,secret,saltB64)` / `decrypt(payload,secret)` keep existing `v1:PBKDF2:salt:nonce:ciphertext+MAC`, PBKDF2-SHA256 600,000 rounds and AES-GCM. `getActiveCryptoContext(uid,{isLinked,linkedSecret?})` may initialize missing anonymous context; check-in reads first require existing local anonymous secret+UID salt to stay on the cache-hit path. It is **not** a general nonmutating historical decryptor. `PersistentConversation.initialize/checkpoint/dispose` owns unlocked key material and one stable session; `ConversationProvider` survives route changes; `ConversationSession.recoveryState/restore` persist encrypted session state and never replay interrupted POSTs. Do not replace these with another session store.

Provenance must distinguish submitted/partial/done/persisted pair/explicit completion/eligible event/receipt. Real saved check-in ciphertext + atomic event commit proves its source. Breathing is client measured only. Conversation's persisted pair plus durable unresolved-handoff lease is still missing. New Chat/navigation/message volume is not completion or eligibility.

## Conflict and security decisions

Read `KOI_WEB_FINAL_CONFLICT_REPORT_2026-10-18.md` before integration. Only two direct implementation paths are edited on both sides, but session/voice/Scene integration has additional semantic and proposed-patch overlaps. No merge simulation or conflict resolution was applied.

**Security gate:** current changes have no high-confidence secret-pattern hits in the audit. The inherited tracked baseline contains `repos/koi-backend/nextjs_app/.env.local.test` with service-account-shaped/private-key material. Local non-disclosing parsing did not establish a usable PEM/DER key; its identity fields did not clearly identify a synthetic fixture. Treat as credential material needing Ahmad/security-owner assessment before any push. It is not proposed for staging, but unchanged tracked contents/history remain inherited by a review branch. Other tracked environment templates/test fixtures contain placeholder key markers. No key value is printed, copied into these reports, changed or rotated. See security summary and manifest for exact names/limits. A pattern scan is not a proof of absence.

## Answers to Ahmad's three questions

**1. What was implemented that was previously unavailable on GitHub?**

Relative to Ahmad's pushed commit/shared base, our local commits already contain W1 truthfulness/accessibility, current-history browsing, draft import validation, existing modal-focus/voice-control foundations and source-derived progress UI. The **uncommitted snapshot** adds the live v3 atomic activity/reward ledger, real encrypted anonymous check-ins and ratings/history/chart, receipt-backed 25-slot puzzle and milestone timeline, measured breathing result/bridge, local-first acknowledged Firestore preference synchronization, actual non-restorable ciphertext data download, truthful Wellness Report empty state, validation/error tests, and all handoff/review documents. Exact committed-vs-uncommitted paths are in the manifest/function inventory; not all of these are new since local HEAD. No live conversation reward, full backup restoration or multi-chat implementation is hidden in the snapshot.

**2. What New Chat/History changes were actually planned or started?**

Production work stops at readable current History, locked older metadata, disabled New Chat/Continue-old controls and a pure tested consumer interface. Exact unapplied source/UI/test drafts propose additive owner+conversation archives, save-before-select transaction, stable IDs, existing-key-only recovery and streaming guards. No v4, archive writer, production switching adapter, independent A/B browser pass or generic decryptor was applied. Joint review remains required, including safety continuity; the proposed code must be adapted to Ahmad's latest voice input changes.

**3. What increments follow without duplication?**

1. Ahmad reviews security gate and approved WIP branch, resolves the two shared pages manually, keeps his media/session implementation, and ports only our product controls/bridge. Re-run both branches' tests; do not claim current 286 tests verify the combination.
2. Reuse the existing v3 ledger/check-in/board and validate in his integrated app. Supply already-unlocked linked-key access; keep anonymous flow and existing legacy totals.
3. Implement the jointly reviewed shared transition adapter/archive and safety gate on his current session, using our consumer seam/draft tests; then real A/B refresh/resume/context/SSE/account-isolation browser acceptance. No second history store or independent media client.
4. Add authoritative persisted-SSE pair + acknowledged unresolved-handoff completion lease, connect explicit completion to the existing ledger, preserving one conversation award/day and no reward for New Chat.
5. Verify hosted breathing directives plus real interruption/audio cancellation through his controller, reusing existing monotonic callback/ledger. Do not reward a token or unverified done event.
6. Finish UID-scoped onboarding completion, actual Urdu localization and remaining dashboard workflows from current data; avoid personality/mood/streak invention. Approve security boundaries for restore/linking/deletion/reporting before enabling those paths. Keep ciphertext export distinct from backup/PDF.

## Evidence transfer and remaining verification limits

`review/handoff-evidence/browser-evidence-summary.json` contains sanitized assertion/status summaries derived from historical actual artifacts: anonymous check-in 14/14, Firebase/Firestore preference 10/10, export/history 10/10 (synthetic adapter content, not hosted inference), breathing LOCAL FIXTURE 4/4. Each source artifact hash is recorded. No raw UID, private message, ciphertext, token, header, key or browser profile is copied into that summary.

22 authored browser harness scripts are copied verbatim under `review/handoff-evidence/browser-harness/`, with origin/hash mapping. They are review/reference tools, not automatically runnable production tests: some use dev webpack/React inspection, Windows Chrome path, artifact output paths, synthetic fixture adapters or disposable preference/key probes. **Run only in a fresh isolated synthetic context after reviewing them**, never a personal browser database. They were not rerun during handoff. Local screenshots/logs/downloads/profiles remain excluded; no raw runtime artifacts silently staged.

No current automated failures. Proposed archive tests are unapplied/NOT RUN. Ahmad branch and combined app tests/build/browser are NOT RUN. Historical hosted text HTTP200/SSE acceptance does not verify hosted breathing, multi-chat, speech, camera or restoration. Earlier failed harness assertions remain documented in previous reports; do not reinterpret them as successful backend acceptance.

Whitespace preflight limitation: current tracked `git diff --check` passes, but it does not inspect untracked files. A separate proposed-file scan found one inherited trailing-space line each in the verbatim `pre-defense/browser-controls.cjs` and `browser-followup.cjs` copies, plus space-only context lines in three proposed `.diff` files. The latter are valid patch context, not source defects. These were preserved rather than silently modifying reviewed source copies; final staged whitespace review must distinguish patch context and inherited cosmetic notices from application failures.

## Requirements Ahmad must preserve

- Genuine Firebase UID isolation, encrypted P0 history, shared Chat/Scene continuity, refresh recovery, active-stream navigation, no duplicate requests/AI rows.
- Existing encryption format/key material and safe locked history; no silent legacy adoption/rekey or promise of key-loss recovery.
- One piece/source/Karachi day, 25 cap, 5/10/15/20/25 milestones, idempotent atomic writes, event-only after cap, no legacy conversion or retroactive award.
- Explicit eligible conversation completion; saved consented encrypted 1-5 check-in; breathing completed >=80% plus >=48s monotonic, no reward for stop/handoff/navigation.
- Crisis decisions unchanged; no score-based reward or falsely acknowledged resolution; no audio/camera work duplicated from Ahmad.
- Same Aisha/Raza choice across PNG/VRM, saved fox remains honest unavailable fallback, truthful local/cloud/error receipts and real empty states.
- Nonclinical privacy language: CSE at rest, plaintext inference boundary; no invented outcomes, fake PDF, deletion, cloud sync or notifications.

After manifest/security approval, create/push **only** the named WIP branch and append its actual SHA here. Until then the pushed branch/SHA remain NONE. No parallel implementation resumes in this Codex session.
