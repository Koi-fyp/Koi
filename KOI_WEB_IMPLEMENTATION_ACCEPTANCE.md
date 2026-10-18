# KOI Web/product implementation acceptance â€” 2026-10-18

## Identity, approvals and preservation

- Branch **`feat/web-product-data`**, created with the user's explicit approval from the actual dirty W1 tree, not a presumed remote checkpoint.
- Initial HEAD **`223e97c489947b98677392f9b8ea383690ab1fe8`**. The user approved W1 and the independent branch. Local baseline checkpoint **`49ad94880bdeb66a071add4cb320d0e148d5cf91`** contains exactly the seven reviewed W1 files; message `fix(web): checkpoint reviewed W1 acceptance baseline`. No remote action.
- Current product batch is uncommitted, tested at **49ad948 + this working-tree batch**. No edits to protected auth/crypto/db/P0/conversation/SSE/contracts, crisis policy, backend, assigned renderer/companion components, assets or Flutter. Verified with an actual repository-root protected-path diff.
- Pre-existing `.idea` (5) and Android local/generated files (21) preserved and excluded. No environment/secret/config reads, dependencies installed, reset/stash/clean/merge/push/deploy or irreversible storage operation. All browsers use fresh synthetic identities/content; no token, UID, private text, recording or storage-state export in reports/artifacts.
- Ownership/inventory: `KOI_WEB_BASELINE_AND_FILE_OWNERSHIP.md`. Decisions: `KOI_WEB_PRODUCT_ADRS.md`. Review-ready typed requests/copy-paste handoff: `KOI_WEB_TO_AHMAD_HANDOFF.md`.

## Executed bounded milestone: read-only product access and independent foundations

Shipped to the local application: **`/history`** and its Chat entry point, read-only draft-backup metadata preview on existing Import page, and Settings companion-picker keyboard/dialog focus handling. No existing data store or session owner was replaced.

Additional independent components/validators are implemented/tested but deliberately **not advertised as completed production workflows**: 25-slot saved-state board presenter, consent/scale validation for voluntary check-ins, and disabled-by-default voice-input adapter controls. They do not mint rewards, save ratings, create a media store or enable shipping mic/video.

## Source â†’ tests â†’ runtime matrix

All Web paths below are relative to `repos/koi-backend/nextjs_app`.

| Capability / state | SOURCE INSPECTED / implemented path | TEST EXECUTED | BROWSER / HOSTED evidence |
| --- | --- | --- | --- |
| Current owned history **implemented**; older sessions **partial/locked** | New `src/lib/history/readHistory.ts`, `src/app/(authenticated)/history/page.tsx`; Chat adds Browse saved history. Group retained owned ciphertext metadata; current content comes only from P0's already unlocked transcript. Other groups stay locked, read-only; no raw-key lookup/generation. | `history.test.ts`, `history-page.test.tsx`: two synthetic conversation groups, foreign/ownerless exclusion, reopen, corrupt/locked/partial/error/empty, abort/late UID, bounded 200 records, in-memory Unicode search and safe text rendering. | **BROWSER OBSERVED:** actual authenticated empty view, retained transcript read, no-match and user-input search, full reload, mobile fit, Continue current, new Firebase owner empty. **HOSTED OBSERVED:** exactly one genuine Modal 200/SSE request completed while history route was open. |
| Multi-conversation creation/switch **blocked** | Existing protected header is keyed by UID; selector does not exist. Historical groups cannot be silently adopted. Current Continue link navigates to current Chat only. | Read model fixture covers two groups; no claim that it creates/reopens two real P0 sessions. | **NOT RUN / DECISION NEEDED:** actual multi-session switch, old-key unlock, linked-key recovery. Joint ADR-HISTORY only approved for design review. |
| Bounded search **implemented for readable current window** | Newest 200 owned retained records; decryptor injection in query, P0 readable-message lookup in app. NFKC/case-normalized local search, 120-char query; unreadable records not searched. No plaintext localStorage/search index/backend. Explicit truncation/unreadable copy. | Bound/dedup ownership/late results; Urdu-script and Roman Urdu query fixtures. | **BROWSER OBSERVED:** real saved neutral user prompt found; unmatched term gives honest empty result. **NOT RUN:** all-history/unlocked-old-session search. |
| Draft portability parsing/metadata preview **implemented, read-only** | `src/lib/data-portability/backupDraft.ts`, `src/components/data-portability/BackupPreview.tsx`, existing `settings/import/page.tsx`. Exact owner UID and public binding, version/compatibility, source/count/date/ciphertext/unknown-field checks, max 2 MiB/200 records; stable-ID duplicate/conflict dry-run. | `backup-draft.test.ts`, `backup-preview.test.tsx`: zero/oversized/type/parse/version/owner/count/duplicate/unknown fields, interrupted reads, no writes, duplicate vs conflict, disabled restore. | **BROWSER OBSERVED:** real Firebase owner, synthetic empty draft yields 0 actual counts, foreign-owner metadata rejected, Restore disabled, mobile fits. Metadata preview is **not decryption or authorization**. |
| Existing-key ciphertext verification **foundation only** | Injected `verifyDraftCiphertexts`; no key lookup/write; owner/cancellation checks; manifest integrity stays NOT VERIFIED and importAllowed false even when ciphertext authentication succeeds. | `backup-existing-key.test.ts`: real existing AES-GCM/PBKDF2 encrypt/decrypt, wrong/missing key, bit-tamper and late owner change fail closed. Not a full restored backup. | **FIXTURE ONLY / NOT RUN:** production nonmutating decryptor, authenticated manifest, export/download and fresh-browser full round-trip/restore. No import writer exists. |
| Settings selector accessibility **implemented** | Web-owned `settings/components/AvatarPicker.tsx`; new `useModalFocus.ts`. Named dialog, pressed state, initial focus, Tab/reverse Tab, Escape, focus restore; existing save/preferences/animation/styles retained. | `avatar-picker-accessibility.test.tsx`; previous saved-avatar/user preference suites preserved. | **BROWSER OBSERVED:** focus boundaries/Escape/restore, Raza save and loaded Male PNG after reload, legacy fox remains fox with no human image, mobile dialog fit. Aisha/current female retained in accepted W1; fresh current batch does not claim full live expression/device acceptance. |
| Recorded 25-piece board **tested presenter, not wired to live issuance** | `src/components/progress/RecordedBoard.tsx`: exactly 25 native buttons, details, owner/slot/completion duplicate validation, explicit unavailable state, separate legacy total, no fabricated unlock conversion. | `recorded-board.test.tsx`: saved fixture slots, locked/unavailable/foreign/duplicate/invalid slot, owner switch. | **FIXTURE ONLY** (React DOM tests). **NOT RUN:** event-backed live board/milestones, approved event store; not mounted as a second fake production board. Product policy is proposed, joint approval pending. |
| Real check-ins **absent persistence; validation foundation implemented** | `src/lib/checkins/validateCheckIn.ts`: user-entered values, owner/consent/date/scale validation, defensive copy, no DB/cloud write. Scale supplied explicitly; test 1â€“5 scale is a fixture, not product policy. | `checkin-validation.test.ts`: consent, owner, invalid/out-of-range/nonfinite/off-step values. | **NOT RUN / BLOCKED:** approved encrypted rating/event schema, scale provenance and durable writer. Existing reminder preference is not a check-in entry. |
| Voice input UI **fixture-ready, shipping disabled** | `src/components/voice/VoiceCaptureControls.tsx`, type-only reuse of existing CaptureSnapshot; adapter owns actual MicrophoneCapture. Explicit Record/Stop/Discard/direct-submit, single flight, abort on identity/companion/urgent generation change, no permission call on mount. Stale foreign capture binding cannot submit. Review-first button unavailable. | `voice-controls.test.tsx`: default disabled/no mount action, exactly one fixture submit, abort/cancel on owner/companion change, stale recording rejection. | **FIXTURE ONLY**. Not mounted in public modes. **NOT RUN / BLOCKED:** real hosted audio/ASR/VoiceOutput adapter, playback/mute/replay/synthesis/lip sync. No new audio store, endpoint, upload or production media call. |
| Safety/exercise behavior **existing, unchanged; fresh live blocked** | Existing ExerciseDirector/CrisisHandoff/contract code read only. No policy wording, threshold or token changes. | Existing `test-exercise-director.cjs` and `test-flow4.cjs` pass synthetic clocks/events, interrupt, resolution queue and unavailable safe-content behavior. | **FIXTURE ONLY**. Ahmad G0b verification and sanitized deployed 18-request receipt still missing; no crisis-provoking live turns submitted. |
| Optional video **planned/gated** | Typed handoff/privacy gate documented. No capture code activated or hidden permission request. Existing mode remains disabled. | Existing media-disabled regression retained. | **NOT RUN / BLOCKED:** live exact input codecs/limits/privacy approval, then optional consented UI. Not removed from roadmap. |

## Browser/live observations and limits

Frontend **http://127.0.0.1:3000**, Next 14.2.35 development, real installed headless Chrome with isolated contexts. One server PID **4604** during current browser runs; no duplicate server. Browser contexts closed before production build; server temporarily stopped for low RAM. Build/runtime identity is not a deployment identity.

History run: genuine anonymous Firebase signup/lookup HTTP 200. **One POST** to existing `https://ahsulem--koi-chat-api-chatserver-web.us-east.modal.run/api/v1/chat`, HTTP **200**, `text/event-stream; charset=utf-8`. Observed named events `latency`, `companion_state`, `delta`, `risk`, `state`, `done`; no order assumption introduced. `/history` observed with **pending true**, then same conversation finalized **two completed messages**, pending false, no error, no duplicate POST. Continue current preserved conversation fingerprint **94cd0b93d51367a9**, message fingerprints **bf87e8f42c2134d6 / 13661027db76de6a**, completed-history fingerprint **e636edef7295ae7e**. Refresh restores saved view; programmatic existing application sign-out followed by genuine new anonymous sign-in gives empty history. This is real account-isolation acceptance, not a newly delivered logout UI.

The run did not verify a live second-session selector, old-session key unlock, returning linked session, actual backup restore or non-neutral expression/speech. New history navigation was observed during pending request; do not equate pending HTTP with a proven between-SSE-frames transition. No backend health/redirect/timeouts experiments or crisis/media requests.

Browser artifacts are ignored `artifacts/product-history/`, `artifacts/product-accessibility/`, `artifacts/product-portability/`: sanitized JSON results, synthetic screenshots and harness scripts, no storage-state/credential/raw-key exports. Metadata preview fixture uses empty synthetic records; it is not a real restored backup. UI does not display raw UID. An early history attempt hit a startup SyntaxError; clean rerun passed with zero page errors. Initial Raza image check ran before load completion and returned false; explicit image-readiness follow-up passed. A duplicate-alert selector interrupted a preview harness and was corrected. A **real new preview mobile overflow** was reproduced in screenshot, fixed by bounding file input/wrapping the new Restore button, then browser fit passed. No failures hidden as successful single-run acceptance.

## Exact verification commands

At HEAD **49ad94880bdeb66a071add4cb320d0e148d5cf91 + current product diff**, in canonical Next.js app:

- `npm test -- --runInBand --silent history`: **PASS 2 suites / 9 tests**.
- Focused backup/board/dialog/voice/check-in tests executed as recorded; final authoritative aggregate below.
- Final `npm test -- --runInBand --silent`: **PASS 25 suites / 137 tests**. Earlier TypeScript narrowing/test-table issues corrected; Jest and TypeScript rerun.
- Final `npx tsc --noEmit --incremental false`: **PASS**.
- `node scripts/test-conversation-recovery.cjs`: **PASS**, real local crypto/Dexie, synthetic auth/fetch; not a hosted test.
- `node scripts/test-avatar-session.cjs`: **PASS**, deterministic controller/session fixtures, not a rendered/live emotion test.
- `node scripts/test-exercise-director.cjs`, `node scripts/test-flow4.cjs`: **PASS**, synthetic safety/exercise fixtures; no changed policy.
- `git diff --check`: **PASS** before build. Protected paths compared at repository root: **no changes**.
- Production build and final preservation result appended below after completion. No concurrent browser/heavy build.

## Changed-file inventory

Three existing Web files: `src/app/(authenticated)/chat/page.tsx` (history link), `src/app/(authenticated)/settings/import/page.tsx` (read-only preview), `src/app/(authenticated)/settings/components/AvatarPicker.tsx` (semantics/focus only).

New implementation files: `src/app/(authenticated)/history/page.tsx`; `src/lib/history/readHistory.ts`; `src/hooks/useModalFocus.ts`; `src/lib/data-portability/backupDraft.ts`; `src/components/data-portability/BackupPreview.tsx`; `src/components/progress/RecordedBoard.tsx`; `src/lib/checkins/validateCheckIn.ts`; `src/components/voice/VoiceCaptureControls.tsx`.

New tests: `history.test.ts`, `history-page.test.tsx`, `avatar-picker-accessibility.test.tsx`, `backup-draft.test.ts`, `backup-existing-key.test.ts`, `backup-preview.test.tsx`, `recorded-board.test.tsx`, `checkin-validation.test.ts`, `voice-controls.test.tsx` under `src/__tests__`.

New root docs: `KOI_WEB_BASELINE_AND_FILE_OWNERSHIP.md`, `KOI_WEB_PRODUCT_ADRS.md`, `KOI_WEB_TO_AHMAD_HANDOFF.md`, this acceptance. Historical reports retained. The initial seven W1 files are in the separately listed approved baseline commit, not overwritten/reimplemented by this product diff.

## Remaining gates and truthful readiness

1. **Joint user + Ahmad approval required:** nonmutating decryptor and multi-session selector/persistence/crypto design. User authorized **design review only**. App never reads/recreates missing raw keys; historical groups stay locked/read-only. Exact signatures/data flow/affected files/test matrix are in ADR-HISTORY.
2. **Rewards PROPOSED â€” AWAITING JOINT APPROVAL:** product owner revised JPV-2 to 1 piece/source/day for explicit conversation completion, saved voluntary check-in, measured â‰¥80% breathing (5 of 6 cycles); Asia/Karachi caps, immutable completion_id, 25 permanent slots and 5/10/15/20/25 milestones. Technical/security provenance/store approval remains missing. No issuance, retroactive conversion, negative rewards or legacy jigsawProgress migration. Board presenter is ready for approved saved events, not an award engine.
3. **Portability scope product-approved, joint security pending:** exact same Firebase UID + existing authorized key; no recovery/key export/rekey/cross-account/legacy adoption/cross-device promise. Metadata parser and injected ciphertext verifier do not authenticate all manifest metadata or approve transactions. No export download, import writer, overwrite or cloud mutation enabled; full round-trip/interruption rollback remains NOT RUN until authority is approved.
4. **Encrypted activity/check-in storage requires approval:** existing mood schema does not authorize sensitive plaintext writes. Candidate scale/type/provenance and encrypted persistence need joint review before real forms save entries. No fabricated mood history.
5. **Ahmad media/G0b evidence missing:** live audio codec/limits/authorization, generation/voice-language binding, VoiceOutput/audio+cues adapter and urgent cancellation. Existing speech internals remain his ownership. Fixture UI is not hosted audio; shipping modes stay disabled. Roman Urdu/code-mixing text is unchanged; no unmeasured speech claim. Video follows voice/privacy/input acceptance.
6. **Deletion, retention, account linking/cloud authority remain joint:** no destructive semantics guessed. Formal policy, linked-key collection, verified email delivery, true cloud receipts and legal publication need owners. No new logout/account linking UI claimed.
7. **Broader acceptance still required:** fresh linked accounts, old-history unlock, two real independent sessions, full export/import round-trip, physical device/native WebView, long GPU/media soak, all-page full keyboard/screen-reader review, new HIGHâ†’resolutionâ†’fresh HIGH and live interrupted exercise after G0b. Existing local tests/historical reports remain separate evidence.

No deadline-driven feature removal. This batch advances usable current history/read-only import preview/accessibility and independently testable foundations; it does **not** declare the full application/rewards/media/restore release complete. Work that remains crosses the explicitly protected joint interfaces, needs approved durable provenance/schema or missing hosted prerequisites. See the local copy-paste handoff for the minimal requested reviews; no external message sent.


## Final build, checkout and continuation point

- **TEST EXECUTED â€” PASS production build:** `npm run build`, Next.js **14.2.35**, **19/19** generation entries including `/history`; build ID **`qpymEdOpAtmGxZqfk-nvU`**. Tested source is 49ad948 + the product batch above. Build/type/lint/trace collection completed with one process-only 1024 MB heap cap, no concurrent browser/server. No deployment or hosted frontend acceptance claimed.
- Final full Jest **137 tests / 25 suites**, explicit TypeScript, local P0/avatar/exercise/Flow 4 scripts and `git diff --check` PASS. Test/source changes made before this build; subsequent edits are documentation only.
- Local application features are integrated, **not deployed**. All test browser contexts closed. One development server restored at **http://127.0.0.1:3000** after checking there was no listener.
- Branch **feat/web-product-data**, HEAD **49ad94880bdeb66a071add4cb320d0e148d5cf91**. Only local commit this run: seven approved W1 baseline files at 49ad948. Current product code/tests/four docs remain uncommitted and unstaged; excluded IDE/Android files unchanged. No auto-commit of another owner's work.
- Continue at the joint reviews in KOI_WEB_PRODUCT_ADRS.md. Proposed interfaces are review artifacts, not API contracts or deployment claims. Existing routes/data/media remain intact; no feature was discarded for time. No additional independent writer/selector/media pipeline can safely be enabled before the listed approvals/provenance/hosted prerequisites.

## 2026-10-18 approved UX decisions — incremental acceptance

**Exact baseline:** feat/web-product-data / b384ce2cef44e83e53db7f50182f3ccfaac32187 plus the uncommitted changes listed below. Previous product foundations are committed; no repeat implementation. Initial exclusions .idea/ and repos/koi-mobile/android/ preserved untouched. No commits or remote operations this batch.

| Requirement | Current result | Evidence / remaining gate |
| --- | --- | --- |
| UX-CHAT-01 visible New Chat | BROWSER OBSERVED PASS for truthful disabled control; actual new-session creation BLOCKED | ConversationProductControls; protected UID-keyed session header cannot safely store/select multiple sessions without joint review. No ID mutation, fake save or completion. |
| Historical selection/resume | SOURCE INSPECTED PARTIAL / BLOCKED | Existing history read model/current-session continuation unchanged. Secure older-session unlock + selector need SESSION-V1 approval. No key generation or legacy adoption. |
| Explicit Complete Conversation | TEST EXECUTED + BROWSER OBSERVED PASS for expandable requirements and disabled save; actual completion BLOCKED | No completion writer, no reward calls; Back/End/New Chat never issue awards in these controls. |
| Aisha/Raza mid-conversation switch | BROWSER OBSERVED PASS for saved selection and unchanged pending session/message IDs | Existing Settings AvatarPicker + saveAvatarPreference reused in both route pages; user-triggered preference only. Pending request had no SSE response. |
| Selection navigation/reload | BROWSER OBSERVED PASS | Separate authenticated no-request context: Aisha PNG -> Raza PNG -> Scene -> Aisha -> Chat -> refresh, same empty-session fingerprint. Female VRM asset HTTP 200; this alone does not certify visible GPU rendering or male VRM loading. |
| Mobile layout | BROWSER OBSERVED PASS | 390x844: no horizontal overflow; textarea bounds inside viewport. Screenshot review caught and corrected excess explanatory height; final mobile-chat.png inspected. |
| Fox/account/error guards | TEST EXECUTED PASS | New tests: fox unchanged until explicit save; correct UID writer; failed save shows error; old-owner picker hidden after account switch. Genuine cross-account populated-history browser acceptance NOT RUN this batch. |
| Verified automatic check-in/breathing eligibility and actual rewards | BLOCKED | Product policy documented; joint durable event/provenance/atomic ledger approval missing. No awards, no migration/retroactive conversion. Existing RecordedBoard/read model preserved. |
| Voice pairing / media | INTENTIONALLY DISABLED | No mic/camera requests; future companion/generation binding requested from Ahmad. |
| P0 completed history / live context regression | NOT RUN for completed live exchange in this batch | Firebase anonymous signUp/lookup HTTP 200. One legitimate Modal POST /api/v1/chat, status not received, no SSE events in observation window. No transport retry/tuning or new endpoint. Historical accepted P0 evidence remains historical. |

### Actual browser evidence and limitations

Frontend **http://127.0.0.1:3000**. Real Chrome isolated synthetic anonymous contexts. Production-mode first attempt timed out before onboarding (no Firebase/Modal observed); development-only sign-in then succeeded without modifying authentication/configuration. One server at a time. Browser scripts/results/screenshots are local ignored `artifacts/ux-decisions/`; `pending-request-result.json` preserves the initial attempt and `browser-result.json` records the final seven-check no-request pass. No raw identity, token, message text or storage state exported by the inspection results; only synthetic screenshots and hashes/counts.

The initial pending request had two unfinished placeholder turns and no SSE events. Switching to Raza retained both IDs and the session. A subsequent full refresh comparison against those unfinished placeholders returned **FAIL**; it is not a completed-history test and must not be reported as a P0 regression or a completed-history PASS. Existing UI said the interrupted message was preserved and not resent. Pending/failed-turn behavior is protected and was not changed. No completed answer or jigsaw award was claimed. Final separate browser pass sent no backend requests and verifies only selection + empty-session identity persistence. Zero page errors observed. No hosted frontend acceptance claimed.

### Executed checks

- `npm test -- --runInBand --silent`: **PASS, 141 tests / 26 suites**, including four new controls tests and existing P0/avatar/progress regressions. Initial run exposed duplicate preference reads from the new child; fixed by consuming the existing route preference state; full final rerun passed.
- `npx tsc --noEmit --incremental false`: **PASS** after final source change.
- `git diff --check`: **PASS** (line-ending notices only).
- Production build: initial build PASS, Next 14.2.35 / 19 entries / MxgJ_tMDO_flL9TWyor2x; final compact-control build recorded below after completion. Browser and server closed for builds; process-only 1024 MB heap cap.

### Changed files / ownership

New `src/components/chat/ConversationProductControls.tsx` and `src/__tests__/conversation-product-controls.test.tsx`; route composition only in `src/app/(authenticated)/chat/page.tsx` and `companion-scene/page.tsx`; appended KOI_WEB_PRODUCT_ADRS.md, KOI_WEB_TO_AHMAD_HANDOFF.md, KOI_WEB_BASELINE_AND_FILE_OWNERSHIP.md and this report. No protected storage/crypto/session/auth/SSE/API/renderer/Flutter edits. Prior local work preserved.

### Next integration gates / copy-paste Ahmad review

1. Review SESSION-V1 in ADR: checkpoint then new stable selection, owner/key checks, selected-ID persistence, cross-tab serialization, active-SSE rejection/continuation semantics, locked legacy handling. Enable New Chat/history resume only after joint approval.
2. Review COMPLETION-V1 durable explicit receipt and verified saved check-in/measured breathing provenance, encrypted event storage and atomic dedup/caps/25-slot allocation. Product approved policy is not permission to issue before technical sign-off.
3. Provide deployed chat/G0b network evidence for fresh completed-answer/P0/reward/exercise browser rerun; one unanswered request does not diagnose jigsaw failure. VoiceOutput companion/generation pairing remains an Ahmad-owned future contract; shipping media disabled.

Final compact-control production build: TEST EXECUTED PASS, Next 14.2.35, 19/19 entries, build ID NR6eQfm-MIJDNtoaaXdsS. Exact source: b384ce2 plus this uncommitted batch. No deployment. One development server restored afterward.

## Increment 03 — 2026-10-18 final product / data acceptance update

This dated section supersedes contrary implementation assumptions above without deleting historical evidence. **Branch feat/web-product-data, HEAD b384ce2cef44e83e53db7f50182f3ccfaac32187 plus preserved Increment 02 and new Increment 03 uncommitted changes.** No commit/push/merge/deploy/reset/stash/clean; unrelated IDE/Android files untouched. Browser frontend: **http://127.0.0.1:3000**, actual Next development runtime; tests/build are local, not a hosted frontend release.

### UAT diagnosis and actual shipped local behavior

| Finding | Classification / actual state |
| --- | --- |
| Owner confirms both VRMs and completed P0 navigation/refresh | Owner UAT preserved; fresh browser in this increment also observed both male/female renderer ready. Live completed Modal response not observed in this increment. |
| No direct avatar switch | Prior Increment 02 uncommitted controls are present, not reimplemented. This increment verified Aisha/Raza PNG switching during a pending request, both ready VRMs, local saved selection + empty-session refresh. |
| Account choice sync failure | BUG in generic explanation, underlying access denial remains externally BLOCKED. Existing onboarding local save succeeded and SDK surfaced account permission denial. Local rules source allows own users/{uid}; deployed rules/App Check/project access was not verified. Firestore streaming HTTP 200 is NOT a write receipt. New allowlisted category copy accurately preserves local success; no SDK payload/UID is displayed. Settings/inline picker use local writer only and never claim account sync. |
| New Chat / real multi-session selector | MISSING, INTENTIONALLY GATED at protected joint session/crypto/storage API. Visible disabled New Chat + explanation; pending copy explains streaming guard. Cannot create/select A/B with current UID-keyed recovery header. No parallel session store or key mutation. |
| History UX | Actual retained conversation list now prioritizes titles/timestamps/current/locked metadata; completion status explicitly unavailable; optional search collapsed. Current conversation can continue; older resume visibly unavailable, no false completed badges. Old-session secure unlock NOT VERIFIED. |
| Complete Conversation / saved activities / reward issuance | INTENTIONALLY GATED: requirements + pending/unknown eligibility displayed; no saved completion receipt exists. Check-in consent/rating collection disabled until encrypted writer/approved scale. No new events/awards/migrations. Pure reward preview is advisory and always issuanceAllowed:false. |
| Sample mood/heatmap/milestones/personality-like interpretations | Real exchange/legacy count cards retained. Mood/heatmap/emotional-growth/milestone samples now behind closed Design previews. No generated sample values are added as personal facts. No actual rating chart source is claimed. |
| Puzzle detail | RecordedBoard integrated with 25 accessible slots; source unavailable => no inferred unlocks. Piece/milestone dialogs support focus trap/Escape/return focus. Legacy totals never turn into piece provenance. Threshold detail is not a fabricated persisted milestone receipt. |
| Confusing Import and PDF restoration claims | BUG FIXED: actionable distinct errors and enforced content validation, clear draft-only preview. Removed stale PDF/ordinary-JSON restoration, smart-merge and notification promises while preserving cards/styles/animations. |
| Export / restore / media | INTENTIONALLY GATED. Export gives precise consistency/existing-key/manifest blocker; no PDF/download success. No raw media archived, no invented modality labels or deployed audio claims; actual capture/output/lip-sync acceptance still Ahmad-owned. |

### Required W-01–W-14 acceptance matrix

A BROWSER PASS below applies only to the specifically described observed behavior, never to a blocked feature as a whole. Fixtures/Jest are not hosted evidence.

| ID | Status | Evidence and exact remaining coverage |
| --- | --- | --- |
| W-01 | **BLOCKED** (guard UI BROWSER PASS) | New Chat disabled in Chat/History. No A->B creation, no new reward. Needs joint checkpoint/create/select storage capability; A/B distinct-ID acceptance NOT RUN. |
| W-02 | **BLOCKED** / JEST PASS | Owned retained list, locked/current/status display and secondary search tested; two owned IDs in read-model fixtures only. Actual A/B resume, old unlock and follow-up context not enabled/browser verified. |
| W-03 | **BROWSER PASS, guarded path only** / BLOCKED actual switching | During one pending legitimate POST, New Chat disabled; Aisha->Raza and Chat->History->Chat preserve session/turn IDs; exactly one POST observed. No actual New Chat transition or independent browser proof of key nonrotation. No crypto/session writes added by Web. |
| W-04 | **BROWSER PASS** | Pending request retains identity/messages through Raza PNG change; separate fresh authenticated route observes male VRM ready then female VRM ready (one canvas, expected model URL), Aisha PNG + same empty-session fingerprint after reload. Actual live voice pairing BLOCKED. |
| W-05 | **BROWSER PASS for accurate failure** / BLOCKED cloud success | Actual onboarding local save + denied account sync; UI safe permission-denial category observed, local continuation available. No rules/auth changes. Exact deployment-side cause beyond access denial unverified. |
| W-06 | **JEST PASS / NOT RUN live successful exchange** | Existing read model dedup/ownership/unfinished-turn behavior passes. One neutral Modal POST had no HTTP response/content-type/SSE during bounded observation; no genuine completed exchange to verify increment. Not diagnosed as failed jigsaw. |
| W-07 | **BLOCKED** (guard UI BROWSER PASS / advisory JEST PASS) | Explicit action opens honest requirements; pending cannot complete; save disabled, no completion or reward write. Duplicate/cap/exclusion calculation fixtures pass, not actual ledger issuance. |
| W-08 | **BROWSER PASS for unavailable alternative** | Consent and Save disabled; no ratings collected or chart entry fabricated. Real encrypted save/reload remains BLOCKED on CheckInWriterV1/schema/scale approval. |
| W-09 | **BROWSER PASS for honest unavailable state / JEST PASS for supplied-record renderer** | 25 slots, zero invented recorded unlocks; source unavailable honestly distinct from verified empty ledger; milestone dialog Escape restores focus. Real earned-piece provenance and permanent unlock receipts remain BLOCKED. |
| W-10 | **BROWSER PASS for file/content guards and structure-only dry-run; JEST PASS for crypto fixture** | Real file-input selection rejects txt/csv/pdf, invalid/arbitrary JSON, >2 MiB, wrong UID, unsupported version and malformed ciphertext. Valid empty KOI draft metadata preview keeps Restore disabled. Final before/after counts across messages/conversations/users/moodEntries/jigsawProgress unchanged. Genuine existing-crypto fixture rejects wrong/missing key and authenticated tamper. UI same-key authenticated decrypt/tamper validation BLOCKED; format-valid altered ciphertext is NOT VERIFIED, never restore-ready. |
| W-11 | **BROWSER PASS for explicitly disabled alternative** | No generation/download enabled; owner-bound consistent full backup, authenticated manifest + exact supported metadata/decrypt capability and same-key round-trip are absent. Real export/round-trip NOT RUN. |
| W-12 | **BROWSER PASS partial / JEST PASS; completed live path NOT RUN** | Pending Chat->History->Chat keeps ID/one POST; separate empty-session Scene->Chat/reload retains ID; existing application signOut then second real anonymous account yields separate empty ID, no previous turns. Existing auth/encryption/P0 suites pass; fresh completed live context/crisis/exercise and populated old-owner unlock not run. Owner completed P0 UAT remains separate evidence. |
| W-13 | **SOURCE ONLY / JEST PASS** | Existing shipping media mode guards and standalone fixture controls preserved; schema has no verified modality field, none invented. Strict draft parser admits no extra raw-media fields, but cannot attest encrypted plaintext content without reviewed decrypt/payload validator. No actual microphone/camera or media persistence added. |
| W-14 | **BLOCKED** | No hosted ASR/TTS/cue/voice-pairing adapter evidence. Both VRMs ready is not synthesized speech acceptance. Future voice/video remain desired and gated. |

### Exact Import acceptance format matrix (actual parser, not picker attributes)

Source `src/lib/data-portability/backupDraft.ts`, UI `src/components/data-portability/BackupPreview.tsx`.

| Property | Enforced now / capability limit |
| --- | --- |
| Extension | Case-insensitive .json required; .txt/.csv/.pdf/.docx and other extensions rejected before file text read. Renaming unrelated content to .json does not bypass JSON/envelope validation. |
| Declared MIME | Empty, application/json, text/json only. Other MIME rejected even for .json. MIME is only a gate, never content proof. Picker accept is advisory; actual reader enforces checks. |
| File bounds | Positive safe-integer size, max 2,097,152 bytes (2 MiB), plus UTF-8 text length recheck; interrupted read fails safely. Max 200 records. |
| Envelope / version | Exact keys kind,schemaVersion,ownerUid,ownerBinding,createdAt,compatibility,sources,counts,records. kind=koi-backup-draft; schemaVersion=1 only; compatibility=same-owner-existing-key-only. Unknown fields/arbitrary JSON rejected. |
| Owner | Exact current UID (1..128 length) + expected 64-lowercase-hex public SHA256 binding of koi-owner:v1: + UID. Public hash is not authentication, key possession or integrity proof. |
| Source/count constraints | Unique sources only messages/conversations; exact counts.messages/counts.conversations equal actual parsed records. Preferences, check-ins, rewards, personality scores and raw media are unsupported. |
| Record fields | Exact source,id,timestamp,ciphertext; nonblank ID <=160 chars, no controls; duplicate(source,id) inside file rejected. Date fields exact finite UTC ISO .sssZ. |
| Cipher shape | <=100,000-char v1:PBKDF2:salt:nonce:ciphertext, canonical Base64; salt16 bytes, nonce12 bytes, encrypted payload >=16 bytes. Plaintext/malformed records rejected. Structure does not authenticate ciphertext or manifest. |
| Duplicate/conflict preview | Existing identical source/ID/ciphertext/timestamp => duplicate; differing existing record => conflict; neither overwrites. Bounded local comparison errors shown; no restore writes. |
| Crypto / absent keys | verifyDraftCiphertexts accepts injected nonmutating existing-key capability; fixtures exercise real encrypt/decrypt, missing/wrong key, tampering and UID changes. Browser UI has no approved capability, reports decryption and manifest integrity NOT VERIFIED. It never looks up/generates/replaces keys. |
| Export/restore reality | No download, restore transaction or key recovery. Current draft omits required message/session relationship metadata and authenticated envelope. Same UID is insufficient; no cross-device/browser-reset recovery claim. |

### Tests, exact runtime and artifacts

- `npm test -- --runInBand --silent`: **JEST PASS, 172 tests / 29 suites**. New suites backup-errors, reward-preview, preference-sync-failure; earlier controls suite preserved. Initial focused run found two JSDOM details visibility assumptions; corrected assertions to check native closed state and verified actual browser hiding. Type-only query-option fix then `npm test -- --runInBand --silent history-page`: **4/4 PASS**.
- `npx tsc --noEmit --incremental false`: **PASS** after correcting unsupported test query option. No tsconfig changes.
- `git diff --check`: **PASS**, line-ending notices only. Full final production build recorded below when complete, one process-only 1024 MB heap cap; no concurrent server/browser/build.
- Runtime script `artifacts/increment03/browser.cjs`: 22 scoped checks PASS, 1 live completion check NOT RUN; Firebase signUp/lookup 200; actual syncDenied=true/localFallback=true; exactly one Modal POST and no received status/SSE; zero page errors.
- Final script `artifacts/increment03/final-review.cjs`: **11/11 scoped checks PASS**, fresh Firebase anonymous identity, no Modal calls; both model URLs 200 plus explicit renderer ready/controller snapshot + canvas, unchanged table counts on preview, final import copy, completion gates, empty-session selection refresh. Initial harness reload raced route navigation; first result preserved in final-review-first-result.json, corrected by awaiting /chat + composer before reload; not a product fix.
- Sanitized results: browser-result.json, final-review-result.json. Synthetic screenshots inspected: progress-mobile.png, import-final-mobile.png; model ready screenshots male-ready.png/female-ready.png. All under local ignored artifacts/increment03, no tokens/UIDs/private transcripts/raw media/keys or browser storage dumps. No HOSTED PASS claimed for Modal or media.

### Complete local project file inventory versus HEAD

Pre-existing Increment 02 work preserved: four reports below, Chat/Scene page composition, ConversationProductControls and its spec. Increment 03 modifies the same controls/pages only to explain pending eligibility, plus these independently owned files. Entire project diff (unrelated exclusions omitted):

- KOI_WEB_BASELINE_AND_FILE_OWNERSHIP.md
- KOI_WEB_IMPLEMENTATION_ACCEPTANCE.md
- KOI_WEB_PRODUCT_ADRS.md
- KOI_WEB_TO_AHMAD_HANDOFF.md
- src/app/(authenticated)/chat/page.tsx
- src/app/(authenticated)/companion-scene/page.tsx
- src/app/(authenticated)/history/page.tsx
- src/app/(authenticated)/progress/page.tsx
- src/app/(authenticated)/settings/import/page.tsx
- src/app/(authenticated)/settings/export/page.tsx
- src/components/chat/ConversationProductControls.tsx (new from Increment 02, updated)
- src/components/data-portability/BackupPreview.tsx
- src/components/progress/RecordedBoard.tsx
- src/components/progress/ActivityAvailability.tsx (new)
- src/lib/data-portability/backupDraft.ts
- src/lib/activities/rewardPreview.ts (new; advisory only)
- src/lib/preferences/syncFailure.ts (new)
- src/lib/onboarding.ts (safe error copy only, no auth/sync behavior changes)
- src/__tests__/conversation-product-controls.test.tsx (preserved new Increment 02 spec)
- src/__tests__/history-page.test.tsx
- src/__tests__/progress.test.tsx
- src/__tests__/recorded-board.test.tsx
- src/__tests__/backup-errors.test.ts (new)
- src/__tests__/preference-sync-failure.test.ts (new)
- src/__tests__/reward-preview.test.ts (new)

Source paths above are relative to repos/koi-backend/nextjs_app unless root reports. No protected db/crypto/conversation/AuthContext/ConversationContext/useChat/useConversationSession, Firebase config/rules, API/SSE/crisis, backend, Ahmad renderer/controller/CompanionScene internals, Flutter or local asset edits. IDE/Android untracked files remain untouched. No commit this increment.

### Product-owner manual retest (synthetic account/content)

1. Open local app, sign in and complete onboarding with Aisha. If account sync is denied, verify explicit local-success/access-denial message and Continue with saved companion. Do not treat it as cloud success.
2. In Chat, Change companion -> Raza -> Save; verify male PNG. Open Avatar conversation and wait for male VRM. Change to Aisha; wait for female VRM. Back to Chat, then refresh: Aisha remains and current ID/history remain. For populated chat acceptance, wait for a genuinely completed response first.
3. Open History: actual retained list/current/locked statuses, optional search, current continuation. New Chat and old-session resume remain unavailable; do not count A/B creation as passed.
4. Complete Conversation displays requirements and unavailable Save. While a reply is pending it explains why completion cannot happen. No piece or completed-conversation counter should increment.
5. Progress: recorded exchanges/legacy counters remain separate; Save check-in disabled, no fake mood/calendar entries; 25 slots show unavailable provenance, not inferred earned pieces. Open slot/milestone details by keyboard and Escape back. Sample charts are collapsed under Design previews.
6. Import: choose PDF/TXT/CSV, malformed JSON, unrelated JSON, wrong-owner/unsupported-version KOI drafts; verify distinct errors. A valid current-owner draft yields metadata only, no restore. Export remains disabled with exact reason. No file download or cloud-success toast should occur.
7. Switch/logout to another synthetic account: previous transcript/preferences do not appear. Real A/B creation/reward issuance/restore/audio tests await joint adapters; use the Ahmad handoff rather than bypassing safeguards.

**Increment 03 final production build: PASS** — npm run build, Next.js 14.2.35, 19/19 generation entries, build ID xtkHpq7tAG6ernnlexuLk. Exact source b384ce2 plus preserved/local Increment 02–03 changes. Server/browser were stopped before build; one local development server restored afterward. No deployment.

## Manual UAT follow-up — History / Export — 2026-10-18 (latest acceptance)

**Current baseline:** feat/web-product-data, b384ce2cef44e83e53db7f50182f3ccfaac32187 + all preserved Increment 02/03 uncommitted work and this follow-up. Owner UAT: current encrypted conversation appears in History with **12 retained/readable messages**, Continue Current Conversation available. This was supplied by owner, not extracted from private user records. This follow-up does not label New Chat, A/B resume or restoration complete.

### Separate requested results

| Item | Evidence / result |
| --- | --- |
| Working data export | **SOURCE + TEST + BROWSER PASS**: consented ciphertext-only JSON copy is downloadable. Real Firebase anonymous browser identity; downloaded file matches stored encrypted snapshot byte-for-byte; metadata/keys warning visible; no keys or readable fixture text in file. Browser fixture had 0 service message rows / 1 genuine encrypted snapshot containing synthetic turns; tests separately exercise owner-tagged message rows, reply relationships, foreign/ownerless exclusions, bounds and no writes. Not a private 12-message export or Modal-backed test. |
| Actual restorable backup | **BLOCKED**: restorationSupported=false, decryptionVerified=false, manifestAuthenticated=false. Data copy is not accepted as a restorable Import backup. No import writes/key recovery/full recovery round-trip. |
| Wellness Report empty state | **BROWSER + TEST PASS**: separate section states no report generated, verified source unavailable, generation disabled. Old dormant PDF generator, simulated analytics/progress, unconditional generated-locally/no-personal-information-shared/keep-forever claims removed. No invented content/report produced. |
| Create Conversations A and B | **BLOCKED**: no production transition adapter or approved archive table. New Web consumer seam only; no new decorative control. Existing current conversation is not replaced. |
| Refresh and resume A/B | **BLOCKED / NOT RUN browser**: fixture coordinator A->B->A receipt tests are TEST evidence only, not multi-chat persistence/continuity. Needs narrow joint two-file patch described in ADR. |
| Current session preservation | **BROWSER PASS (synthetic fixture) + owner UAT**: current synthetic ID and message IDs survive History/Export navigation, download and refresh; stored ciphertext copied unchanged. Owner's 12-message current History confirmation is retained as UAT evidence. No new live Modal/P0 acceptance claimed. |
| Firebase UID isolation | **BROWSER + TEST PASS for tested paths**: actual anonymous signUp/lookup HTTP 200; second account cannot see prepared previous-account export or retain consent; unit guards before/after read reject foreign/late UID, foreign and ownerless rows not exported. Fresh linked/account-lock paths NOT RUN. |
| Key-unavailable / locked history | **TEST + SOURCE; UI BLOCKED**: ciphertext reader has no key lookup/decrypt dependency and can copy encrypted rows without a key; absent key never becomes available through export. Existing ConversationProvider hides all authenticated route children when unlock fails, so key-unavailable Export UI is not claimed functional. Older historical unlock/resume remains blocked/read-only. No replacement/generated key or adoption/migration. |

### Why data export can proceed independently, and its exact limits

`src/lib/data-portability/ciphertextExport.ts` calls existing db tables in a single **r** transaction. It reads only rows tagged ownerUid=current Firebase UID and the UID-keyed current conversation header. Read scope is bounded to detect overflow and fail, not silently truncate. It validates IDs, dates, revision, sender, optional replyTo and supported ciphertext shape, builds allowlisted objects, then checks UTF-8 file size. UI obtains owner from existing AuthContext and compares actual auth.currentUser before/after await and again before download. It does not use getActiveCryptoContext, secret/salt storage, cryptographic derivation, decrypt/encrypt, checkpoint, writes, sync, tokens or cloud queries. Owner tag is local ownership metadata, not cryptographic ownership proof.

Atomic database capture is a committed point-in-time local view, not a logical session checkpoint or cloud backup. Current message and recovery snapshots may be written in separate P0 transactions; export does not claim all in-memory work is included/reconciled. UI refuses preparation if currently pending. A completed preparation remains an explicit point-in-time copy. No conversation state is mutated to make an export.

| Format property | Implemented value |
| --- | --- |
| Download | JSON MIME application/json; filename koi-ciphertext-export-YYYY-MM-DD.json (no UID in filename) |
| Identifier/version | kind=koi-ciphertext-data-export, formatVersion=1; distinct from draft backup parser |
| Top metadata | ownerUid, exportedAt, scope=owner-tagged-device-local-records, consistency=single-readonly-database-transaction, exact record counts |
| Capability flags | restorationSupported=false, decryptionVerified=false, manifestAuthenticated=false, originalKeyRequiredToDecrypt=true |
| Messages | id, ownerUid, conversationId, sender(user/ai), UTC timestamp, optional replyTo, copied ciphertext |
| Available current snapshot | ownerUid, conversationId, createdAt, lastActiveAt, revision, copied encryptedState as ciphertext |
| Bounds | <=200 combined message/snapshot records; <=2 MiB serialized UTF-8; IDs <=160 chars/no controls; current UID <=128; ciphertext <=100,000 chars, existing v1:PBKDF2 Base64 salt16/nonce12/payload>=16 bytes |
| Excluded | Foreign/ownerless rows, unencrypted emotion/risk scores, user profiles/preferences, mood/reward tables, raw media fields, tokens/credentials/keys. Unknown properties are not spread into output. |
| Missing/invalid/large data | Empty/missing snapshot/unsupported owned record/size overflow => clear error, no partial file; no data repaired or deleted |

Copying encrypted bytes needs no original key. Decrypting later needs the correct original key context for each record; public salt/nonce do not replace a secret. Lost anonymous device secret or unavailable linked-session secret is not recoverable from the export or Firebase UID. No single-key compatibility/manifest authentication/tamper-proof metadata/cross-device restoration is asserted. Restorable backup needs approved nonmutating decryption, authenticated complete format and transactional restore/rollback + verified same-key round-trip.

### Actual browser and test evidence

Frontend **http://127.0.0.1:3000**, actual local development runtime, fresh isolated Chrome synthetic accounts. `artifacts/history-export/browser.cjs` uses the existing runtime **fixture** chat adapter to produce synthetic turns; no Modal POST occurred. Existing P0 encrypts the snapshot; download is real. Browser saved/parsed the JSON and compared its ciphertext to read-only IndexedDB; synthetic export file removed after comparison so no UID-containing export is retained in artifacts. Sanitized hashes/counts/status results in browser-result.json; screenshot export-mobile.png. **10/10 browser checks PASS**, zero page errors. Firebase authentication HTTP 200 is genuine; chat completion is simulated. This is not hosted backend verification.

Full `npm test -- --runInBand --silent`: **PASS 186 tests / 32 suites**. New ciphertext-export (7), ciphertext-export-ui (4), session-transition (3) tests; existing suites preserved. Focused final `web-honesty`: **6/6 PASS** after report button wrap fix. `npx tsc --noEmit --incremental false`: **PASS**. `git diff --check`: **PASS**, line-ending notices only. Production build result recorded below when complete; server and browser stopped before the sequential build.

### Narrow New Chat approval request (not implementation)

The existing UID-keyed active header cannot preserve two independent encrypted recovery states. Proposal keeps it intact as active pointer and adds an owner+conversation archive table only after schema approval. PersistentConversation then owns serialized checkpoint/archive/create-or-select, revision/cross-tab guards, already-authorized key use and session publication. Existing useChat already subscribes to manager changes; no auth, crypto primitive, transport or broad Context replacement is presumed necessary. Safety/exercise active-state transition rules must be confirmed with Ahmad; New Chat cannot reset handoff/signed-state safeguards.

`src/lib/history/sessionTransition.ts` is consumer scaffolding only: one adapter call with ownerUid/expectedConversationId/action/signal; refusal while SSE pending; owner/receipt/selection checks; generic failure never shown as success. No DB, crypto, completion, award or network dependency, no new persistent session store. Tests simulate A/B receipts and failures. Actual storage/adapter implementation, A/B refresh, secure unlock and context isolation remain BLOCKED until joint technical approval. Full signatures, two protected-file candidate and regression matrix in latest ADR/Handoff sections.

### Files changed in this follow-up (all older edits preserved)

- Replaced owned Export page's inactive generator/template with separated data-copy and Wellness empty sections: src/app/(authenticated)/settings/export/page.tsx.
- Existing parser only exposes its unchanged supported-ciphertext predicate for reuse: src/lib/data-portability/backupDraft.ts.
- New src/lib/data-portability/ciphertextExport.ts and src/components/data-portability/CiphertextExport.tsx.
- New src/lib/history/sessionTransition.ts (unwired consumer seam, no actual session changes).
- New tests ciphertext-export.test.ts, ciphertext-export-ui.test.tsx, session-transition.test.ts; updated existing web-honesty.test.tsx for truthfulness/context dependency.
- Appended KOI_WEB_PRODUCT_ADRS.md, KOI_WEB_TO_AHMAD_HANDOFF.md, KOI_WEB_IMPLEMENTATION_ACCEPTANCE.md and ownership note. No protected db/crypto/conversation/auth/transport/controller/backend/Flutter files changed. No commit/push/merge/deploy, no updated Desktop ZIP (its older packet remains untouched).

### Owner retest

1. With the existing readable current chat, open Settings -> Export: no generated-report or forever/no-sharing claims. Wellness Report is empty/disabled.
2. Read metadata/key limitations, consent, Prepare data export -> Download ciphertext data JSON. Confirm actual JSON download; it says restorationSupported=false. Counts come from actual local records; keep the file private. Do not upload private exports into chat or expect Import to restore this file.
3. Return to Chat/History and refresh: current ID/messages remain. New Chat/A-B resume remains unaccepted pending reviewed shared patch; do not count scaffold fixture results as production functionality.

**History/Export follow-up final build: PASS** — npm run build, Next.js 14.2.35, 19/19 generation entries, build ID tCG_244fjW_jdSS9laXjU. Tested b384ce2 plus preserved working-tree changes. Server/browser stopped for build; one development server restored afterward. No deployment.

## Firebase preference-sync investigation acceptance — 2026-10-18 (latest)

Baseline remains feat/web-product-data / b384ce2cef44e83e53db7f50182f3ccfaac32187 with all previous uncommitted product/export work intact. New files: KOI_FIREBASE_PREFERENCE_SYNC_AUDIT_2026-10-18.md; src/lib/preferences/accountPreferenceSync.proposed.ts; src/__tests__/account-preference-sync-proposal.test.ts; review/firebase-preferences.rules.cjs. Existing ADR/handoff/this report appended. No production app imports the proposal. Firebase config/rules/auth/env, P0/crypto/session/API/SSE, renderer/backend/Flutter unchanged. No commit/deploy/new package/emulator.

| Investigation requirement | Evidence/result |
| --- | --- |
| Actual authentication / owner match | BROWSER + HOSTED: anonymous Firebase signUp/lookup 200; raw UID compared in memory with outgoing document UID, identical fingerprint; no UID/token/key export |
| Client configuration alignment | SOURCE + BROWSER: same [DEFAULT] Auth/Firestore app, configured koi-companion-fyp, (default), firestore.googleapis.com; auth domain matches. Config/issuer fully matching intended Console Web registration NOT VERIFIED without Console evidence; no API keys read |
| Exact operations | BROWSER: setDoc users/{current UID} merge mask onboarding_complete/profile.avatar/profile.companion/profile.language/profile.notificationTime; may create/update. Independent own getDocFromServer also permission-denied; user unchanged. No private doc data read |
| Account-sync denial | BROWSER/HOSTED reproduced; local save succeeds, remote write denied. This is not a fake sync-success receipt and not evidence of failed local avatar persistence |
| Deployed Rules / App Check | BLOCKED on Console text/status; no authenticated Console/CLI available. Local rules allow owner; no rule weakening/deployment justified. User requested deployed Rules/project/database/enforcement via pending clarification |
| Client wiring | SOURCE: Settings and inline avatar/language local saves and hook reads never sync/hydrate account; external permission fix alone insufficient |
| Proposed client patch | TEST PASS: 15 tests for owned merge/get, proper SDK receipt, UID/abort/path guards, no false success, allowed profile leaves, fox legacy, missing/invalid remote doc. Unwired candidate, NOT live sync acceptance |
| Actual Rules engine tests | NOT RUN: review/firebase-preferences.rules.cjs refuses absent/non-local emulator; CLI/emulator/rules-testing SDK not installed. Java21 available. No JavaScript mock is labelled Rules PASS |
| P0 regression | TEST PASS via full existing suites; no new Modal call, hosted P0 rerun NOT RUN. Local storage/transport/auth files unchanged |

Commands: full npm test -- --runInBand --silent PASS **201 tests / 33 suites**; final proposal targeted suite **15/15 PASS** after safe error-copy refinement; npx tsc --noEmit --incremental false PASS; git diff --check PASS (line-ending notices only). Sequential production build identity appended below. Real browser artifacts/firebase-preferences/browser-result.json reports 3/3 diagnostics PASS, own-read permission-denied, zero page errors/Modal calls. Published rules and App Check were not invented or scraped through unavailable Console access.

Additional SOURCE finding: protected message cloud path uses conversation UUID in a segment authorized as owner UID by local rules. This is separate from the correctly targeted preferences denial. No message path/rule/queued-data patch or destructive migration applied. Audit/Handoff request narrow owner-scoped review. Local multi-chat/check-in/ledger implementation does not require new Firebase infrastructure, only the existing joint local interfaces; cross-device recovery/global caps need their own security authority.

**Firebase investigation build PASS** — Next.js 14.2.35, 19/19 entries, build ID sk09LrQTPMs1558FzPTB7. Candidate remains unreferenced by production routes. Browser/server closed during build; one development server restored afterward. No deployment.

## Owner-provided Console update — 2026-10-18 (supersedes unresolved-rule statements above)

Owner confirms Anonymous and Email/Password sign-in providers enabled and supplies the published test-mode rule `allow read, write: if request.time < timestamp.date(2026, 6, 5);`. That condition is false on 18 October 2026. It is a sufficient cause for both observed own-document read/write denials when published on the runtime koi-companion-fyp/(default) target. Do not extend its expiry or replace it with a public/all-authenticated wildcard. The selected project/database was not explicitly restated; confirmation and App Check enforcement status were requested. No direct Console access, token inspection or deployment claimed.

Review candidate now exists at nextjs_app/review/firestore.user-preferences.proposed.rules: users/{uid} exact-owner get/create/update only; root changes scoped to profile/onboarding_complete/public_crypto_metadata, profile changes scoped to four existing preference leaves, metadata changes scoped to salt; list/delete/foreign/guest/all other collections denied. It preserves existing unrelated server fields rather than granting users authority over them. No Clinical/chat cloud write enabled. Actual firestore.rules and firebase.json unchanged, no publishing. This candidate must pass Rules engine/Console Playground review and approval; application/client tests do not compile or validate it.

Rules review test adds --proposal switch and cases for owner salt merge, privileged root/profile denial, owner document deletion denial and unrelated collection denial. JS syntax check PASS; actual Rules engine NOT RUN because emulator/tooling absent. App Check must remain separately verified/enforced. Runtime Next build/tests above apply to the client proposal; subsequent edits are review Rules/test specification and documentation, not production code or deployment. Full details/runbook updated in KOI_FIREBASE_PREFERENCE_SYNC_AUDIT_2026-10-18.md.


## 2026-10-18 ? Owner-authorized Settings/inline account preference integration

Supersedes earlier statements that the preference adapter is unwired or that expired Rules still deny the owner document. Owner reports publishing authenticated UID-owner-only users/{uid} Rules and explicitly authorizes client integration. No Rules, Firebase configuration, authentication, encryption, session, renderer, or backend edits were made in this increment. Anonymous end-user Firestore operations now succeed; Rules source/Console/App Check administration was not independently accessed.

Implementation: existing accountPreferenceSync.proposed.ts is now used by preferenceSync.ts (historical filename retained). SDK auth.currentUser.uid must equal the requested owner before/after network operations and before local application; Auth and Firestore must share the same Firebase app. Existing users/{uid}.profile merge writes contain only supplied allowlisted preference leaves. Crypto metadata and unrelated fields are never supplied to this writer. Settings and both inline companion pickers reuse saveUserPreferences/saveAvatarPreference, with no second preference store.

Local saves commit immediately to the existing users table; additive accountSync pending fields/revision metadata is in that same UID row, without a Dexie schema/version/index migration. Network failure does not roll back local selection or block picker dismissal. Missing/denied server reads and rejected writes do not clear pending edits. Retries use the authenticated owner only. Initialization, refresh, focus and online restoration perform guarded server reads; a single-flight coordinator coalesces consumers. Newer pending edits take precedence over server snapshots; only the exact acknowledged revision is cleared. Concurrent edits during a write are sent in the next iteration, and stale reads cannot replace a changed local revision. Existing legacy local choices are preserved and synchronized once; fox remains fox/koi. Cloud legacy avatar-only/companion-only metadata is canonicalized locally without an unsolicited server rewrite.

A shared account status/Retry control is shown in Settings and inline controls. Local-save toasts remain explicitly local. Server success requires a real getDocFromServer response and, for pending changes, resolved setDoc acknowledgement. Permission-denied is explicit; other errors use safe unavailable copy. The status subscription uses useSyncExternalStore to avoid missed completion notifications across navigation/mounts. No raw Firebase error text is rendered.

Scope: Aisha/Raza avatar/companion and en/ur language preference synchronize. Nickname and reminder-enabled state remain local; interface translation and reminder delivery are not claimed. No generic global syncQueue is used for this feature.

Current increment source/test files (relative to nextjs_app):
- src/lib/preferences/userPreferences.ts
- src/lib/preferences/preferenceSync.ts (new)
- src/lib/preferences/accountPreferenceSync.proposed.ts (existing candidate now wired; comment updated)
- src/hooks/useUserPreferences.ts
- src/components/chat/AccountPreferenceStatus.tsx (new)
- src/components/chat/ConversationProductControls.tsx (preserved prior work, added status)
- src/app/(authenticated)/settings/page.tsx
- src/__tests__/preference-sync-integration.test.ts (new, 8 tests)

TEST EXECUTED: npm test -- --runInBand --silent: **209 PASS / 34 suites**, 12.296s; npx tsc --noEmit --incremental false: PASS. Existing P0/session tests remain passing. Production npm run build PASS, Next.js 14.2.35, 19/19 entries, BUILD_ID **PayaHUPYLgqqrRX6UvgKO**. Exact HEAD **b384ce2cef44e83e53db7f50182f3ccfaac32187**, branch **feat/web-product-data**, dirty worktree including preserved prior work; no commit. Build ran with browser and the existing dev server stopped, process-local 1024MB Node heap, then one dev server was restored at http://127.0.0.1:3000. Browser evidence is against the development runtime at this SHA plus uncommitted changes; this is not a hosted Next deployment or a Modal acceptance run.

New tests cover hydration/field preservation, persisted offline pending patches/reconnect, permission denial, late UID change, an edit during acknowledgement, legacy fox, stale cross-tab read, and legacy account fox hydration. Adapter's existing 15 tests cover exact UID/path checks, merge masks, allowlists, cancellation, and safe error mapping. Rules emulator tests remain NOT RUN; application unit tests do not validate deployed Rules.

Browser procedure uses fresh isolated Chrome and synthetic anonymous accounts; only UID fingerprints, approved preference values, field names, equality checks, model URLs/status and safe session metadata are retained. No token, key, salt value or message content is logged/exported. A read-only account hydration test removes only the disposable synthetic user's local preference row; it leaves conversation/key storage untouched, then reloads. Foreign-owner read probe uses only the other synthetic account and records denied status, never document content. Anonymous browser identity/key recovery across devices and Email/Password sign-in are NOT RUN; preference hydration does not demonstrate encrypted history recovery. No Modal request is needed or made for preference testing.


### Final genuine browser results ? 2026-10-18

**10/10 BROWSER PASS against real hosted Firebase**, URL http://127.0.0.1:3000, isolated desktop Chrome, current development runtime at b384ce2cef44e83e53db7f50182f3ccfaac32187 plus the uncommitted changes listed above. Auth anonymous sign-up/lookup HTTP 200; exact SDK owner UID compared in memory and only a fingerprint recorded. Actual server reads verified approved profile values after resolved writes. No Modal calls, no private existing account/messages used. Zero page errors or recorded network failures.

| Acceptance | Evidence/result |
| --- | --- |
| Owner Firebase identity/document access | BROWSER/HOSTED PASS: anonymous owner sign-in and server read/write succeed |
| Settings language | BROWSER/HOSTED PASS: English ? Urdu saved as profile.language=ur; return to English during offline/reconnect test |
| Settings Raza | BROWSER/HOSTED PASS: profile.companion=raza, profile.avatar=male_human; existing unrelated fields including public_crypto_metadata unchanged |
| Chat inline Aisha | BROWSER/HOSTED PASS: female_human/aisha server acknowledged, language remains ur |
| Refresh | BROWSER/HOSTED PASS: selected avatar and language retained |
| Companion Scene inline Aisha ? Raza | BROWSER/HOSTED PASS: female and male model HTTP 200 and renderer ready; current conversation fingerprint unchanged; model URLs /models/koi-female.vrm then /models/koi-male.vrm |
| Offline local preference / reconnect | BROWSER PASS local English selection with explicit offline status; HOSTED PASS pending language flushed to owner document after reconnect |
| Account preference hydration | BROWSER/HOSTED PASS: after removing only disposable synthetic user's local preference row, refresh restores actual saved Raza + English from server |
| Account change/isolation | BROWSER/HOSTED PASS: distinct fresh anonymous owner has no prior account profile; foreign synthetic owner's server document read is permission-denied |
| Truthful denied-write fallback | TEST PASS: denial keeps local data/pending changes and explicit denied status; actual owner's new Rules permit writes, so forcing own-account denial in browser NOT RUN |

Final artifacts: artifacts/preference-sync-live-final/browser-result.json, chat-account-synced.png, scene-raza-synced.png. Earlier attempts exposed harness timing/stale-expectation issues (immediate server read before acknowledgement, Aisha expectation after deliberately choosing Raza); bounded server acknowledgement checks and the correct saved choice are used in final run. A status mount notification timeout led to the useSyncExternalStore fix. These earlier runs are not being counted as production backend tests.

Limits: browser conversation was empty synthetic data, so session identity continuity was observed but a live Modal reply/navigation-during-SSE regression was NOT RUN in this increment; existing P0 automated suites PASS. No linked Email/Password account or second physical device was tested. Real preference sync is functioning for the tested anonymous Firebase identity and published owner-only policy. This is not an encrypted backup/recovery, media, multi-chat or reward issuance acceptance.

Final checks: 209 Jest tests /34 suites PASS, TypeScript PASS, production build PASS (19/19, PayaHUPYLgqqrRX6UvgKO); git diff --check PASS with existing line-ending notices only. No commit, push, deployment, security rule/config/auth/crypto/session/renderer/backend edits. All earlier uncommitted project/IDE/Android work preserved; one development server remains running.


## Increment 04 ? 2026-10-18 ? Approved activities, check-ins and rewards

### Baseline and ownership

Branch feat/web-product-data; HEAD b384ce2cef44e83e53db7f50182f3ccfaac32187 plus preserved uncommitted product/preference work. Reverified original 209 tests /34 suites PASS before new tests. New owner-provided October 18 Ahmad approval supersedes blanket reward-disabled gates; only specifically unapproved P0/session/unlock interfaces remain blocked. No commits, push, merge, deploy, reset, clean or unrelated work edits. .idea and Android remain untouched. Backend, auth/Firebase configuration/rules, crypto.ts, conversation internals/contracts/transport, avatar/CompanionScene/Crisis dialog remain unchanged. ExerciseDirector receives only the specifically authorized additive result observation/interruption wiring. New Chat remains separately blocked.

### Implemented source/files for this increment

- src/lib/db.ts: additive version 3 only; three stores and their table types. Exact review patch: review/increment04-db-migration.diff.
- src/lib/activities/activityTypes.ts: event, reward and milestone interfaces.
- src/lib/activities/activityLedger.ts: one three-store rw transaction, exact UID guards/account-change abort, event idempotence, daily/source caps, slots 1?25, permanent receipt-only milestones, deterministic PKs, consistent owner-filtered reads.
- src/lib/activities/rewardPreview.ts: explicit YYYY-MM-DD construction and additive typed duration/reason/client-measurement evidence; advisory helper still does not issue.
- src/lib/checkins/checkInService.ts: validated encrypted current-owner save and decrypt-on-display, existing-key/cache-hit-only precondition, no key creation when missing, no cloud queue.
- src/hooks/useActivityData.ts: owner-scoped Dexie live data; decrypted ratings exist only in current-owner component memory.
- src/components/progress/ActivityAvailability.tsx: working voluntary 1?5 Mood/Connection/Energy form with explicit consent, stable UUID and first-attempt time through retries, actual success/error state, saved history, actual chart/table/activity days and earned/completed counts.
- src/components/progress/RecordedBoard.tsx: actual slots from reward receipts, earned details with completion/provenance, explicit saved milestone receipts. Legacy totals remain separate.
- src/app/(authenticated)/progress/page.tsx: connects real activity dashboard and board; retains labelled design previews separately.
- src/lib/activities/breathingActivity.ts: exact owner/session SHA256 completion ID and completed-only >=80%, >=48,000 active monotonic milliseconds eligibility, client-measured provenance.
- src/components/progress/BreathingActivityBridge.tsx and src/app/(authenticated)/companion-scene/page.tsx: callback via local context composition, no CompanionScene/renderer/speech edit.
- src/components/companion/ExerciseDirector.tsx: optional onBreathingResult; new session UUID on genuine start; current clock measurement excludes pause, reports completion/handoff/stop/navigation once; observer failure cannot suppress existing playback_done/cleanup. Exact review patch: review/increment04-exercise-callback.diff.
- src/lib/activities/conversationCompletion.ts: TEST-ONLY eligibility boundary and exact deterministic SHA256, no unapproved session producer/runtime completion writer.
- src/components/chat/ConversationProductControls.tsx: replaces blanket old reward-gate explanation with the specific session evidence integration blocker and tells users check-in/breathing rewards are now available.
- New tests: activity-ledger.test.ts, checkin-service.test.ts, checkin-form.test.tsx, breathing-activity.test.tsx, conversation-completion-evidence.test.ts. recorded-board tests gain genuine receipt-driven milestone test; jest.setup.ts adds JSDOM's missing secure randomUUID shim from Node WebCrypto.

### Contract/schema

Policy version koi-pakistan-25-v1-product-approved. One piece/source/Karachi day, 25 slots maximum, milestones 5/10/15/20/25, no penalties/reset/retroactive conversion. Client clock is explicitly not an authoritative security clock. activityEvents.id === completion_id (explicit indexed alias); reward id=JSON.stringify([owner_uid,source_type,day_key]); milestone id=JSON.stringify([owner_uid,milestone]). Exact indexes/types are in the review diff and activityTypes.ts. Existing users/messages/conversations/moodEntries/jigsawProgress/syncQueue schemas/records untouched. The encrypted check-in payload is exactly {scale_version,mood,connection,energy}. provenance contains only allowlisted scalar evidence, no plaintext rating values. Breathing measurement='client-measured', not a backend proof. No new records are added to syncQueue, import or export.

Encryption/hashing precedes the write transaction. Only IndexedDB awaits occur inside it. A duplicate add collision is caught inside the transaction, owner/source/source-ID checked, original event/receipt returned; no retroactive award for replay. Overlapping IDB scopes serialize tabs, unique indexes enforce source/day and slot ownership. Unexpected failures abort all event/reward/milestone rows. Eligible capped/full-board activities still persist without another receipt. No arbitrary record adoption, migration or key recovery.

### Genuine browser and hosted evidence

Environment: one locally running Next dev server http://127.0.0.1:3000, fresh isolated Chrome desktop 1100x850 and mobile width 390, synthetic anonymous Firebase accounts. Raw artifacts/increment04/browser-result.json and screenshots retained. Normalized browser-acceptance.json explicitly marks unavailable hosted exercise opportunity NOT RUN; raw conditional assertion remains false for transparency.

| Case | Result and precise evidence |
| --- | --- |
| Genuine Firebase identity | BROWSER/HOSTED PASS: anonymous sign-up/lookup HTTP 200, SDK owner used for store writes; only fingerprint logged |
| No implicit issuance | BROWSER PASS: initialization/navigation had zero activity events/receipts |
| Real check-in -> event -> receipt -> slot | BROWSER PASS: consented UI save with genuine AES-GCM ciphertext produced one event, one receipt, slot 1; synchronous double-click produced no duplicates |
| Refresh/history/chart | BROWSER PASS: encrypted event and reward remain, saved ratings decrypt and genuine chart/table and slot return |
| Second daily check-in | BROWSER PASS: second actual save produced a second event, receipt count remains one |
| Two browser tabs same completion | BROWSER INTEGRATION PASS: authenticated real crypto/save service in both tabs returns daily-cap and duplicate; only one new event, no duplicate slot. This race used an explicit synthetic service draft, not two normal UI UUIDs |
| Missing key | BROWSER PASS: check-in capability rejected locked; no replacement anonymous key generated; test restored existing key only in disposable synthetic browser |
| Piece keyboard/detail | BROWSER PASS: keyboard Enter opened earned detail, Escape closed; source/provenance shown |
| Mobile | BROWSER PASS: actual form/chart/puzzle fit width 390 without overflow |
| UID isolation | BROWSER PASS: second identity had zero old events/receipts; foreign read throws owner-changed |
| Live Modal text/SSE | HOSTED OBSERVED: exactly one existing POST /api/v1/chat HTTP 200 text/event-stream; latency, companion_state, delta, risk, state, done; normal end, no parser read failure. No private response text retained |
| Hosted breathing start/completion | NOT RUN: no start_breathing ui_action supplied, no paced panel ran, no breathing reward. HTTP 200 is not an exercise acceptance pass. Original conditional assertion was false; it is not evidence of a frontend ledger defect |
| Local fixture breathing pipeline | FIXTURE-ONLY BROWSER PASS 4/4, separate isolated account/artifacts/increment04-breathing-fixture: supplied local start event, waited 60 real monotonic seconds, one client-measured event/receipt/slot; refresh retained it; user stop created nothing additional; zero Modal calls |
| 25 pieces/all milestone thresholds | TEST ONLY: controlled eligible synthetic days/sources fill exactly 25; 26th activity adds no piece; all 5 permanent milestone receipts exist |
| P0 | Existing automated continuity suites PASS. Real live request completed, but full P0 active-SSE route-hopping suite NOT RUN in this increment; no transport/session edit |
| Voice/media | Deliberately disabled; no speech/lip-sync or camera capability claim |

### Narrow blocked integrations, not blanket reward gates

1. **Runtime explicit conversation completion BLOCKED:** current shared session clears earlier events on next send and has no durable authoritative unresolved-handoff getter. Resolved-handoff keys are exposed but cannot prove absence of older unresolved handoffs. Do not infer from numeric risk or later done.handoff:null. Existing assistant persistence follows successful SSE done, but a consistent shared completion/safety lease still needs a narrow joint patch. Exact get/lease proposal in latest Ahmad handoff; deterministic hash and fail-closed proof validator tested, not a completed workflow. No conversation reward enabled. Current visible completion control explains this exact missing integration.
2. **Linked-key check-ins BLOCKED when no existing unlock capability is supplied:** existing AuthContext does not provide linkedSecret; no new prompt/key generation or auth/crypto change made. Anonymous already-unlocked path is browser verified. Request owner-scoped active activity encrypt/decrypt capability using already unlocked material; do not repurpose still-blocked withOwnedDecryptor for legacy history.
3. **Hosted breathing action not observed:** Ahmad should inspect the ordinary start_breathing client request/director output. No endpoint/schema/transport/safety workaround applied. Callback/ledger path is tested and browser-fixture verified, not claimed as deployed exercise acceptance.
4. New Chat/multi-conversation, restore writes, cloud activity/global award authority and live media remain separately gated/out of scope. No import/export activity expansion.

### Test/build evidence

Intermediate full suite 270/39 PASS, TypeScript PASS, build 19/19 IwsJIj-YjnNiAobKuTC37. Final source hardening adds callback-observer error containment, accurate unavailable copy and receipt-consistency checks; final regression counts/build appended after actual execution. Migration tests seed and preserve v2 messages, conversations, mood entries, jigsaw, users and queue. Real crypto tests decrypt correct-key payload and reject corrupt data; rollback tests fail event, reward and milestone stages; races use independent Dexie connections and real browser tabs. Unit/fixture results do not verify Modal.


### Increment 04 resumed finalization ? 2026-10-18

The usage-limit interruption did not lose or replace implementation work. On resume, branch remains feat/web-product-data at b384ce2cef44e83e53db7f50182f3ccfaac32187 with the previous dirty worktree intact. No application source was rewritten during finalization. The final browser smoke had actually completed before interruption; its persisted artifact was inspected rather than repeating those scenarios.

**Final source evidence:** saveCheckIn assigns completed_at from the current client clock after encryption, so a previously failed form retried on a new Karachi day does not backdate a new event to its first attempt. The form UUID remains stable; a retry of an already persisted ID returns the original event/time without a new reward. Duplicate lookup now queries the explicit [owner_uid+source_type+completion_id] index, so every ledger read filters by owner at query time; it does not fetch another owner's row and then merely hide it. These statements supersede the earlier draft description of primary-key duplicate lookup and form-time event dating.

**TEST EXECUTED after resume:** npm test -- --runInBand --silent: **274 PASS /39 suites**, 71.042s. npx tsc --noEmit --incremental false: **PASS**, exit 0. git diff --check: **PASS** (existing CRLF notices only). Production build run and identity recorded below only after it finishes. No dependencies installed.

**BROWSER VERIFIED final source:** artifacts/increment04-final-smoke/browser-result.json: **10/10 PASS**, no failures/page errors, genuine Firebase anonymous HTTP 200. At http://127.0.0.1:3000 the actual consented UI check-in creates one encrypted event, one unique reward receipt, and one visible slot; refresh restores genuine saved ratings/chart and piece; second same-day save creates an event only; two browser tabs racing one completion ID create one event/no duplicate reward; missing-key operation remains locked with no replacement; current actual save-day keys are verified; mobile width 390 has no overflow. This smoke intentionally makes zero Modal requests. Synthetic screenshots first-earned-piece.png and final-checkins-mobile.png in that artifact directory are available; no private account or message capture.

**TEST ONLY / LOCAL FIXTURE BROWSER:** artifacts/increment04-breathing-fixture/browser-result.json: **4/4 PASS**. A supplied local start event led to 60 actual monotonic browser seconds, one client-measured breathing event/reward, refresh recovery, and no new reward after user stop. Zero Modal requests. This does not verify a deployed exercise directive or backend-issued completion proof. Automated tests cover all 25 slots/milestones, 26th event without award, unique-index races, transaction rollback, source/day caps, Karachi midnight/year/leap boundaries, ownership and old-store migration preservation.

**HOSTED OBSERVED / NOT RUN:** the separate genuine Modal call in artifacts/increment04/browser-result.json returned HTTP 200 SSE with latency,companion_state,delta,risk,state,done, but no start_breathing ui_action. No paced exercise ran or breathing reward was issued, so hosted breathing completion remains NOT RUN. The raw harness retains its false conditional assertion; browser-acceptance.json explicitly classifies the unavailable opportunity rather than claiming success or inferring a ledger defect.

**BLOCKED, precisely:** runtime Complete Conversation still needs the shared owner's authoritative completion/safety lease; current queueCrisisPath marks resolution when queued, which must not be mistaken for a verified acknowledged resolution, and latest-turn events cannot prove older unresolved handoff absence. No numeric risk score or done.handoff:null workaround is used. The exact completion hash and defensive evidence predicate are TEST ONLY; no runtime conversation completion receipt has been created. Linked check-ins also need an already-unlocked activity crypto capability that current AuthContext does not expose. New Chat remains separately blocked. These are specific shared-interface boundaries, not an approval gate on the now-working check-in/reward ledger.

Exact review diffs are current: review/increment04-db-migration.diff and review/increment04-exercise-callback.diff. Existing database schemas/records and legacy progress are preserved; no activity data sync/export expansion. No authentication, crypto implementation, conversation/SSE/API, Firebase config/rules, core CompanionScene/VRM/speech or Flutter edits. No commit, push, merge, deploy, reset, clean or destructive migration.

Manual retest: open Progress with an already-unlocked anonymous identity; choose Mood/Connection/Energy 1?5, consent and Save; verify a yellow slot and saved row, then refresh. Save another check-in: two recorded entries but still one check-in piece that day. Open an earned slot by keyboard and close with Escape. Switch accounts: old entries/pieces must disappear. Real breathing requires an actual start directive; do not treat a normal text reply or local fixture as that directive. Complete Conversation and New Chat remain visibly unavailable for the distinct shared-session integration reasons above.


**Resumed final production build PASS** ? npm run build, Next.js 14.2.35, 19/19 entries, BUILD_ID `IBmeusgjUb1IU7TVShA4T`; branch `feat/web-product-data`, HEAD `b384ce2cef44e83e53db7f50182f3ccfaac32187` plus preserved uncommitted Increment 04 work. Jest 274/39 and TypeScript PASS executed sequentially before build; no browser/server ran alongside it. Build ID captured before restoring development mode (next dev may remove production BUILD_ID). Browser acceptance is the actual development-runtime smoke at this same unchanged source, not a deployed production frontend. No commit, push, merge, deployment or source rewrite during resumed finalization.


## Increment 04 gap-only continuation - 2026-10-18

Environment: feat/web-product-data, HEAD b384ce2cef44e83e53db7f50182f3ccfaac32187 plus preserved dirty worktree. Actual browser URL http://127.0.0.1:3000. No commits, merges, deployments, resets or secret reads.

### Inventory before editing

| Subsystem | Initial classification | Current evidence |
|---|---|---|
| Additive Dexie v3 / three approved stores | ALREADY IMPLEMENTED | Existing approved unique indexes preserved; no further schema/version change. Migration preservation test executed. |
| Atomic activity/reward/milestone ledger | ALREADY IMPLEMENTED | Single three-store readwrite transaction, owner guards, unique indexes, duplicate return, daily source caps, 25-slot cap and rollback tests; real two-tab race observed. |
| Consented encrypted check-in / UUID retries | ALREADY IMPLEMENTED | Genuine UI save, encrypted event and receipt, correct-key read, refresh and second-day-cap checks rerun. No new store/helper created. |
| Saved ratings/chart/activity days | ALREADY IMPLEMENTED | Current-owner encrypted records decrypted for display; actual saved ratings/chart observed after refresh. |
| 25-slot board / receipt detail / milestone receipts | ALREADY IMPLEMENTED | Fresh UI check-in filled slot 1 and retained it after refresh. All milestone thresholds and 25/26 cap TEST ONLY. |
| Old styled milestone timeline | IMPLEMENTED BUT NOT CONNECTED | Fixed now: removed fabricated 7-Day Streak/50 Pieces/done flags; reused timeline styles, actual receipts and existing accessible detail dialog. |
| Progress loading/error copy and preview chart | PARTIALLY IMPLEMENTED | Fixed stale reward-unavailable claim, clarified separate legacy totals; failed ledger counters now Unavailable. Labelled preview bars have concrete heights and browser-visible nonzero size. |
| Breathing callback + monotonic eligibility | ALREADY IMPLEMENTED | Existing integration preserved; local fixture 4/4 historical browser evidence, current automated tests pass. Hosted completed exercise NOT RUN in this continuation. |
| Conversation completion / New Chat / legacy decryptor | BLOCKED BY SHARED ARCHITECTURE | No protected changes made. Existing completion evidence/acknowledged-handoff/session interface still required. |
| Linked-account check-in unlock | BLOCKED BY SHARED ARCHITECTURE | Existing active linked-key capability is not exposed; remains locked, never regenerates keys. Anonymous already-unlocked path genuinely browser verified. |

### IMPLEMENTED NOW / exact files changed in this continuation

1. src/app/(authenticated)/progress/page.tsx - truthful active reward/legacy copy; removed fake milestone dataset and relocated existing styled timeline to recorded board; clearly labelled preview bars with nonzero pixel heights.
2. src/components/progress/RecordedBoard.tsx - reused styled timeline, five policy thresholds, saved-receipt unlocked state, keyboard detail activation and existing focus-managed modal.
3. src/components/progress/ActivityAvailability.tsx - failed reads show unavailable counters, loading text corrected.
4. src/__tests__/progress.test.tsx - truthful copy and no obsolete achievement claims.
5. src/__tests__/recorded-board.test.tsx - receipt-driven timeline, Enter/Escape/focus and exact thresholds.
6. src/__tests__/checkin-form.test.tsx - locked key/read failures do not imply success or invented zeroes.
7. src/__tests__/checkin-service.test.ts - account switch during encryption/save leaves no activity/reward rows.
8. KOI_WEB_IMPLEMENTATION_ACCEPTANCE.md and KOI_WEB_TO_AHMAD_HANDOFF.md - appended current evidence, preserving historical reports.

No new db.ts or ExerciseDirector changes in this continuation; existing earlier Increment 04 edits remain intact. Exact additive db diff remains review/increment04-db-migration.diff (verified matches current git diff). No second version bump; no modifications to old schemas, syncQueue, encryption, Firebase settings/rules, SSE/API/P0, Flutter or Ahmad-reserved files. Ahmad's four reported commit objects are unavailable in this checkout, so no three-way comparison or integration claimed.

### TEST EXECUTED

- npm test -- --runInBand --silent: **278 tests PASS /39 suites**, 15.939 seconds, exit 0.
- npx tsc --noEmit --incremental false: **PASS**, exit 0.
- git diff --check: **PASS**, existing line-ending warnings only.
- Ledger tests cover duplicates, separate-connection concurrency, three independent source/day caps, midnight/year boundaries, 25 slots/26th event, permanent milestones, atomic rollback at each write stage, owner changes and v2 old-store preservation. Check-in tests cover invalid/consent/key/crypto/plaintext metadata/retry/account-switch behavior. Breathing tests cover threshold/time/reason/duplicate eligibility. These are TEST ONLY where not independently browser exercised.

### BROWSER VERIFIED - fresh synthetic identities, no mocks

artifacts/increment04-followup/browser-result.json: **14/14 PASS**, no exceptions, page errors or failed network requests. Real Firebase anonymous signup and lookup HTTP 200 for two distinct fingerprinted UIDs; no raw UID/token/key/private message artifacts. Actual running Next development application, no Modal requests.

| Check | Result |
|---|---|
| New identity starts with zero events/receipts on existing v3 | BROWSER VERIFIED |
| Valid consented UI save/double-click creates one AES-GCM activity and one receipt | BROWSER VERIFIED |
| Slot 1 opens genuine check-in provenance using keyboard | BROWSER VERIFIED |
| Refresh retains saved ratings, actual chart and earned piece | BROWSER VERIFIED |
| Second check-in same Karachi day saves event but no second piece | BROWSER VERIFIED |
| Two real tabs race same completion: one additional event, duplicate safely returned, no duplicate slot | BROWSER VERIFIED |
| Missing existing key fails locked without generating replacement | BROWSER VERIFIED |
| Stored day keys match actual Karachi save time | BROWSER VERIFIED |
| Mobile 390px viewport has no horizontal overflow | BROWSER VERIFIED |
| Five real timeline milestones stay locked without receipts; keyboard opens truthful detail | BROWSER VERIFIED |
| Explicit sample-only preview bars have nonzero size | BROWSER VERIFIED (preview rendering only, not personal data) |
| Second genuine anonymous UID sees zero former-owner entries/receipts | BROWSER VERIFIED |
| All 25 pieces and milestone unlocks | TEST ONLY; no fabricated backdated browser rewards |
| Deployed breathing completion / full live P0 SSE navigation | NOT RUN this continuation; no new live Modal claim |

An initial harness assertion expected the word "locked" inside the milestone dialog, while the actual truthful UI said "No saved milestone receipt for this threshold." That assertion failed; initial-browser-result.json is retained. Corrected the assertion to verify the actual required no-receipt state, reran the complete fresh-identity browser flow and obtained 14/14. No application workaround was made to force a test pass.

Screenshots: artifacts/increment04-followup/first-earned-piece.png, final-checkins-mobile.png, desktop-progress.png, isolated-owner-empty.png. These show synthetic accounts only. Browser source/results are local artifacts, not hosted production evidence.

### Ledger / review summary

Existing transaction inserts the valid encrypted activity, returns original on duplicate, checks source/day receipt and owner piece count, then inserts next slot and threshold receipt atomically. Any unexpected write failure aborts all rows. Encryption finishes before opening the transaction. Account-change guards/abort keep the original owner stable. Receipt primary keys are JSON.stringify([owner_uid,source_type,day_key]); milestone keys JSON.stringify([owner_uid,milestone]); event id equals completion_id with explicit indexed completion_id alias. Client Asia/Karachi dates are not a security clock. No legacy conversion, retroactive award, Firebase sync or export expansion.

Remaining handoff: db v3 diff review before merge; already-unlocked linked-account crypto capability; durable completed-SSE persisted-pair/safety lease and separate multi-session approval; hosted start_breathing evidence. Existing optional durationMs extension preserves monotonic timing and 48-second requirement; no new speech/camera/renderer edits.

Manual retest: open Progress as an already-unlocked anonymous user, select all three ratings 1-5 and consent, Save; inspect earned slot and saved row, refresh; save a second genuine entry and confirm piece count unchanged that day. Existing users may already have their daily check-in piece: that is a legitimate cap, not a failure. Switch to a separate synthetic identity for zero-data isolation testing. Missing/linked unavailable keys stay locked. New Chat and explicit conversation reward remain separately blocked.


**Current continuation production build PASS:** npm run build, Next.js 14.2.35, 19/19 entries, BUILD_ID `I5KedjnwMYlP6z_npRRgJ`; HEAD b384ce2cef44e83e53db7f50182f3ccfaac32187 plus preserved dirty worktree. Build executed after browser closed and existing dev server was stopped; one dev server restored afterward. No deployed production acceptance implied.


### New Chat review preparation, not implementation - 2026-10-18

feat/web-product-data at b384ce2cef44e83e53db7f50182f3ccfaac32187, existing dirty work preserved. Owner explicitly retained Ahmad joint approval. No archive/session/crypto/auth/Firebase/reward changes were applied. Review-only exact diffs, source hashes, validator and full test matrix are in repos/koi-backend/nextjs_app/review/new-chat-review.md. git apply --check passed; reconstructed candidates passed syntax and in-memory TypeScript with zero emitted files. Relevant source hashes remained unchanged. Proposed archive/migration/session tests are NOT RUN and the feature is still BLOCKED from enablement pending joint decisions (including unresolved handoff/exercise recovery).

Independent safe work: expanded existing src/__tests__/session-transition.test.ts by 8 cases for cancelled/missing/current selection and invalid owner/previous/checkpoint/publication/target receipts, including cancellation-after-simulated-commit semantics. Focused 11/11 PASS; full npm test -- --runInBand --silent 286/39 PASS (50.139s), npx tsc --noEmit --incremental false PASS. No application behavior changed; these are consumer fixtures, not a working multi-chat claim. Build and browser/hosted multi-chat acceptance NOT RUN for this review-only task. Existing Increment 04 build/browser evidence remains historical and unchanged.


### Final ownership transfer prepared - 2026-10-18

Ahmad is now sole KOI Web implementation owner. No new feature implementation in this transfer. See KOI_WEB_FINAL_HANDOFF_2026-10-18.md, KOI_WEB_FINAL_CONFLICT_REPORT_2026-10-18.md, KOI_WEB_FINAL_FILE_FUNCTION_INVENTORY_2026-10-18.json and KOI_WEB_WIP_STAGING_MANIFEST_2026-10-18.md for the authoritative actual-source inventory, exact proposed snapshot and blockers. Proposed handoff/web-product-data-2026-10-18 has NOT been created/committed/pushed; explicit manifest and push approval pending. Current source feat/web-product-data at b384ce2cef44e83e53db7f50182f3ccfaac32187 plus preserved dirty work. Ahmad remote fetched and verified at 884a278e0370835e98c07ae192cfa2dc8ba73495; no merge/cherry-pick.

Fresh tests: 286/39 Jest PASS (28.334s), TypeScript PASS, production build PASS 19/19, Next14.2.35 BUILD_ID i4JLGTu9EUai8YYGsixEA. No combined-branch or fresh browser acceptance. New Chat remains review-only/unapplied. Sole remaining transfer actions after approval are selective snapshot/branch push and actual SHA handoff; no parallel coding. 22 authored browser harnesses preserved as review copies with sanitized historical evidence summaries under nextjs_app/review/handoff-evidence. Raw runtime artifacts/environment/IDE/Android files excluded and untouched.

Security decision before push: existing tracked nextjs_app/.env.local.test contains service-account-shaped/private-key material. Non-disclosing local scan did not establish a parseable key or clearly synthetic identity. It is excluded from new staging, but unchanged tracked content remains inherited in branch/history. Ahmad/security owner must assess fixture status/credential disposition; no automatic deletion, rekey, rule edit or history rewrite. No secret value included in these reports.
