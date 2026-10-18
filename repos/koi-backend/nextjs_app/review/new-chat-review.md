# New Chat / History: joint review package

Prepared 2026-10-18 from `feat/web-product-data`, HEAD `b384ce2cef44e83e53db7f50182f3ccfaac32187`, including the existing uncommitted Web work. **PROPOSED ONLY. Joint approval remains required.** No protected application changes have been applied.

This package supersedes the illustrative schema/signatures in `new-chat-approval.md`. It reuses the existing `ApprovedSessionTransitionAdapter` and `transitionOwnedConversation`; there is no second transition store or consumer abstraction.

## Package contents

| Artifact | Purpose / status |
|---|---|
| `new-chat-session.proposed.diff` | Exact two-file archive/shared-owner proposal, based on current dirty source, NOT applied |
| `new-chat-consumers.proposed.diff` | Exact four-file New Chat / History consumer proposal, NOT applied |
| `new-chat-tests.proposed.diff` | Ten proposed fixture/migration tests, NOT applied or executed |
| `new-chat-source-baseline.json` | SHA-256 of nine relevant source files before preparation; no user data or credentials |
| `validate-new-chat-proposal.cjs` | Checks source hashes, reconstructs proposals in memory and optionally type-checks them; never applies/writes application source |

## Actual local inventory and ownership

Read current status, recent log, diff stat/name-status, untracked filenames, relevant source and earlier proposal. Existing v3 activity stores, ledger, encrypted check-ins, rewards, progress charts/milestones, preference sync and historical UI fixes are present. They are reused and unchanged. There is **no existing archive store or functional production session-switch adapter** to duplicate. P0's UID-keyed active header and optimistic revision check are present. Current History reads the already unlocked current transcript; older rows stay locked. Conversation completion is separately blocked and not implemented here.

Pre-existing work spans 24 modified tracked files and additional untracked tests/modules/reports. IDE/Android files are unrelated and untouched. The manifest verifies the relevant current source remains byte-identical after proposal preparation, including the already-dirty `db.ts`, History and product controls. No Firebase configuration/rules, authentication contract, crypto implementation, keys, ciphertext, rewards, renderer, speech/camera, backend or Flutter file was edited.

The only independently applied code change during this task is **test coverage** in `src/__tests__/session-transition.test.ts`: eight added cases covering cancelled/missing selection, unchanged/invalid targets, cancellation after a simulated commit, and invalid owner/previous/checkpoint/publication/target receipts. No production seam behavior changed.

## Exact proposed files / changes

| File | Proposed delta |
|---|---|
| `src/lib/db.ts` | Add one `conversationArchives` table property and one v4 store declaration; v1-v3 definitions remain verbatim |
| `src/lib/conversation/PersistentConversation.ts` | Factor existing recovery/observer logic; implement the existing adapter with an exclusive switching lease, owner checks and atomic archive/select; add bounded already-unlocked saved-session read |
| `src/hooks/useChat.ts` | Include manager `switching` in input blocking |
| `src/components/chat/ConversationProductControls.tsx` | Delegate New Chat to existing transition consumer + reviewed manager adapter; truthful pending/failure state; no reward/completion action |
| `src/lib/history/readHistory.ts` | Optional `resumable` field only; legacy reader remains unchanged |
| `src/app/(authenticated)/history/page.tsx` | Merge verified archive snapshots with existing retained/locked rows, list empty sessions, delegate New/Continue, preserve existing design/search/transcript rendering |
| `src/__tests__/new-chat-proposed.test.ts` | Proposed transaction, lifecycle, migration and owner tests using synthetic crypto/inference fixtures |

Existing History/product-controls mocks and assertions also require updates when the approved functionality is actually implemented; the current tests correctly assert the still-disabled baseline. Do not enable consumers by applying only their patch. No changes are proposed to `ConversationSession`, `ConversationContext`, transport, schemas/endpoints, crisis policy, auth, crypto or Ahmad-owned components.

## Smallest additive schema

```ts
conversationArchives!: Table<ConversationRecord, [string, string]>;
this.version(4).stores({
  conversationArchives: '[uid+conversationId], uid, [uid+lastActiveAt]',
});
```

The primary key is `[uid, conversationId]`; the time index permits owner-scoped bounded recent-history reads without scanning other owners. The archive reuses `ConversationRecord`: `uid`, `conversationId`, `createdAt`, `lastActiveAt`, `status`, `revision`, optional existing-format `encryptedState`. `status: 'active'` is the reused record type, **not a completed-conversation claim**; the current active pointer determines the UI badge.

No upgrade callback, existing-row rewrite, deletion, key initialization, activity conversion or sync queue operation. Archives start empty after upgrade; the current legitimate session is archived only when the user explicitly switches. Old versions must not be reopened in the upgraded browser profile; do not implement rollback by downgrading/deleting IndexedDB.

Portability consequence verified from current `ciphertextExport.ts`: the existing data export explicitly selects owner message rows and the one active snapshot, not arbitrary database tables. This proposal does not add archives to its format. Consequently that export must not be advertised as a complete restorable multi-session backup; archive export/restoration remains a separate approved compatibility change. No portability code is changed here.

## Proposed interfaces and data flow

```ts
// Existing interface, now proposed to be implemented by PersistentConversation:
transition(input: SessionTransition & {
  ownerUid: string;
  expectedConversationId: string;
  signal: AbortSignal;
}): Promise<SessionTransitionReceipt>;

// Scoped read using only this existing unlocked manager; no raw key/decryptor export:
readSavedConversations(signal: AbortSignal): Promise<{
  conversations: SavedConversationView[];
  truncated: boolean;
}>;
```

1. Capture owner and expected session; reject restoring, switching, storage error, wrong owner/ID or active SSE. Acquire a synchronous lease so double-clicks cannot race. Disable sends and detach the old checkpoint observer.
2. Flush P0's encrypted checkpoint queue. On failure retain the current selection and fail closed. This successful checkpoint may increment the active revision even if a later switch fails; rollback means **no partial identity/archive transition**, not undoing a legitimate history save.
3. New: create a UUID and empty independent session. Resume: read only `[uid, targetId]`, decrypt with the existing unlocked secret, verify embedded owner/message conversation IDs, reconcile only owner-matching service rows using the existing recovery path. No network or key retrieval. Corrupt/foreign targets cannot replace the current selection.
4. Encrypt target state **before** the transaction using the current format and key. In one Dexie `rw` transaction over active headers and archives, compare current ID/revision, archive the current header, persist target archive and replace active header. Owner-change and abort listeners abort in-flight transactions. Errors roll back archive/header operations together.
5. Use a monotonically increasing active-header revision even on A -> B -> A, preventing a stale A tab from overwriting the returned A. Only after commit publish the new session and clear old in-memory plaintext via the existing disposal path.
6. History reads at most 100 recent archive records plus the current header, displays at most 200 messages/session, creates first-user-input excerpts in memory and marks truncation. Failed decryption stays locked and read-only. Empty saved sessions remain listed. Legacy rows without a verified archive are not silently adopted or made resumable.

No calls to completion, activity/reward, Firebase sync or import/export services. New Chat is not Complete Conversation. Created time stays stable; last-activity time is not fabricated by merely opening an archive. The old transcript and its session recovery state remain encrypted and attached to the old ID.

## SSE, failed turns and cancellation

- **Active stream:** New Chat/Continue wait; do not cancel, repost, detach the shared provider or assign an active response to a new ID. Route navigation continues using P0.
- **Failed/cancelled stream:** preserve the user turn and its failure/cancelled status in the old snapshot. New Chat never retries it. Completed-only context filtering stays in existing `ConversationSession.send`.
- **Refresh during stream:** existing P0 recovery drops partial assistant placeholders and keeps interrupted user turns without resending. The proposal reuses this behavior.
- **Switch crash:** before transaction commit, old selection remains authoritative; after commit, refresh reads the new active header and old archive. No intermediate partially selected state is durable.
- **Abort before commit:** abort the transaction and keep old selection. **Abort after commit:** cannot undo the completed transaction; publish the committed selection for a still-valid owner. The current consumer reports cancellation conservatively, not a rollback guarantee. Re-read the manager before retrying.
- **Account change:** SDK UID checks plus owner-change listener prohibit cross-owner publication/writes. Archive lookup is owner-scoped. No identities, key material, tokens or plaintext get logged or stored in a second cache.

## Mandatory joint-review decisions before implementation/enablement

1. Approve the v4 additive archive and transition transaction; review all two-store failure/commit boundaries and cancellation-after-commit behavior.
2. **Safety continuity:** P0 currently has no authoritative durable unresolved-handoff accessor; queued resolution is not acknowledged resolution. Merely saving old safety state does not prove it is safe to dismiss an active handoff by starting another session. Ahmad must define/review the minimal transition guard or cross-session handoff presentation before consumers are enabled. The draft does not claim to solve this or change classifier/policy. Never infer clearance from a score, missing latest event or `done.handoff: null`.
3. Verify signed exercise/consumed-UI state restoration cannot restart a stale interrupted activity, and that leaving an actual running exercise reports interruption without reward. No edits to Ahmad's ExerciseDirector/Scene/speech ownership are part of this package.
4. Verify current linked-account key lifecycle/ownership on resume. The proposal uses only already-unlocked manager material and provides no cross-device/key-loss guarantee, legacy adoption or `withOwnedDecryptor` implementation.
5. Review archive ciphertext compatibility. Existing encrypted snapshots are not rewritten at upgrade. Saving a session normally produces a new existing-format ciphertext with the same authorized key/salt; no key rotation or algorithm change. Existing empty snapshots bind owner but not an explicit encrypted conversation-ID field; do not claim stronger historical ID binding than the current envelope provides.

These are narrow review questions, not permission to apply the patch. The draft is **not release/enablement-ready** until they and the proposed tests/browser matrix are satisfied.

## Test and acceptance matrix

| ID | Case / required assertion | Evidence now |
|---|---|---|
| M1 | v3 -> v4 preserves exact old users/messages/current header/mood/jigsaw/sync/activity/reward/milestone rows; empty archives | Proposed fixture test, NOT RUN |
| M2 | Migration failure aborts without deleting or adopting records; old schema/source rollback never destroys upgraded data | Required, NOT RUN |
| S1 | A -> New -> B: distinct IDs, A retained, B empty context, no completion/reward | Proposed fixture test, NOT RUN |
| S2 | Empty B still listed; refresh restores selection; A/B resume independently with correct follow-up context | Proposed fixture test + required real browser/Modal, NOT RUN |
| S3 | Pending SSE prevents switch without abort/duplicate request; route hopping still works | Proposed fixture + existing P0 tests; new browser case NOT RUN |
| S4 | Failed/cancelled/interrupted turns remain in A, never resent by switching; no partial assistant adopted | Failed-turn proposed fixture; interrupted/cancelled matrix still required |
| S5 | Double click/retry creates at most one switch; expected-ID mismatch returns error | Proposed fixture + existing seam tests |
| T1 | Inject failure after each archive put and active-header put: no partial identity transition | Header failure proposed fixture; every-stage cases still required |
| T2 | Two independent tabs race; winner only; losing/stale tabs cannot overwrite; A->B->A ABA rejected | Stale-manager proposed fixture; actual two-tab race NOT RUN |
| T3 | Refresh/crash before/after commit selects the corresponding durable header, both transcripts retained | Required browser/integration, NOT RUN |
| U1 | Wrong UID/owner change/disposal during decrypt/write/read returns no foreign transcript/new-owner writes | Proposed owner fixture + current receipt tests; new browser NOT RUN |
| U2 | Wrong key/corrupt archive/foreign target: locked, current unchanged; no generated replacement key | Corrupt/foreign/no-key-lookup proposed fixture; actual missing-key crypto test still required |
| U3 | Legacy ownerless/orphaned rows remain unchanged/locked, never resumed | Existing P0 behavior; new archive integration NOT RUN |
| C1 | Cancellation before start/while adapter pending; malformed owner/ID/checkpoint/target receipts | Current consumer tests EXECUTED, fixture only |
| C2 | Abort at commit boundary: no false rollback claim, refresh reconciles actual selection | Consumer fixture executed; producer/real browser NOT RUN |
| H1 | Titles escape user text, locked/empty/error/loading states, keyboard New/Continue, layout unchanged | Existing UI baseline tests only; proposed UI tests need updating after approval |
| X1 | No safety-handoff escape, no stale exercise replay, no reward on New/Back/navigation | Mandatory joint-review decision + future regression/browser tests |

## Executed validation and limits

- Current source `npm test -- --runInBand --silent`: **286 PASS /39 suites**, 50.139 seconds. Includes 11 existing-seam tests (8 newly added). Does **not** execute the proposed archive code/tests.
- Current source `npx tsc --noEmit --incremental false`: PASS.
- `git apply --check` on all three proposals: PASS, against current dirty files. **Only `--check` was used.**
- Validator `--semantic`: candidate syntax and TypeScript checked entirely in memory, zero diagnostics, zero emitted files; protected-source hashes unchanged. This is not transaction execution, browser acceptance or approval.
- Initial semantic-validator run had harness root/type-resolution/casing errors; fixed the review tool's compiler host/current-directory/path deduplication and reran. No application changes made to silence those errors.
- Production build NOT RUN for this review/test-only change; last application build remains the separately recorded Increment 04 result, not a new acceptance result.
- Browser/hosted A/B acceptance NOT RUN: feature is unapplied and unapproved. No dev listener on port 3000 was found during inspection; no server/build was started for this review task.

Reproduce safe review checks from repository root:

```powershell
git apply --check -- repos/koi-backend/nextjs_app/review/new-chat-session.proposed.diff repos/koi-backend/nextjs_app/review/new-chat-consumers.proposed.diff repos/koi-backend/nextjs_app/review/new-chat-tests.proposed.diff
node repos/koi-backend/nextjs_app/review/validate-new-chat-proposal.cjs --semantic
```

## Copy-paste handoff to Ahmad

Please review the unapplied New Chat package in `nextjs_app/review/new-chat-*`. It reuses our existing transition consumer, adds only v4 `conversationArchives` keyed `[uid+conversationId]`, and proposes a single owner-bound archive/select transaction while retaining P0's active-header/revision contract. No auth/crypto/transport/reward or renderer changes are applied. Please decide the unresolved-handoff transition guard and exercise-state restoration boundary, review same-key archive recovery and commit/cancellation/multi-tab behavior, then approve a narrow implementation patch. Syntax/in-memory TS and patch applicability pass; actual archive tests, migration execution and authenticated A/B browser acceptance are NOT RUN. Current unchanged runtime plus independent consumer tests passes 286/39. No joint approval is assumed.
