# New Chat: exact protected patch for approval

2026-10-18. Branch `feat/web-product-data`, HEAD `b384ce2cef44e83e53db7f50182f3ccfaac32187` plus existing dirty worktree.

Status: NOT IMPLEMENTED. Automatic approval review rejected applying the protected session/storage changes under the general request to unblock New Chat. No rejected source edits were applied. This document is a review artifact, not an executable migration or a claim of approval.

## Why the current button cannot safely just be enabled

`PersistentConversation.initialize()` selects `db.conversations.get(uid)`. That table has one primary-key row per UID. `checkpoint()` checks the current conversation ID and revision before replacing that row. Replacing its identity without retaining its encrypted session state would lose safety/exercise recovery state even if message rows survived. Current History intentionally cannot resume older sessions.

## Explicit approval requested

Authorize this additive archive store plus narrowly scoped shared-session switching. Confirm Ahmad's joint review covers these changes. Existing database stores, encryption/key derivation, Firebase identity/config/rules, backend/SSE transport and reward issuance remain untouched.

Proposed `db.ts` additions only:

```diff
 export class KoiDatabase extends Dexie {
+  conversationArchives!: Table<ConversationRecord, [string, string]>;
   conversations!: Table<ConversationRecord, string>;
@@
     this.version(3).stores({
       // Existing activity/reward/milestone definitions stay unchanged.
     });
+    this.version(4).stores({
+      conversationArchives: '[uid+conversationId], uid, lastActiveAt',
+    });
```

Archive values reuse `ConversationRecord`: owner `uid`, stable `conversationId`, creation/activity dates, revision, existing AES-GCM `encryptedState`. Compound primary key binds owner and conversation. No plaintext titles/transcripts or additional key material are stored. Titles quote decrypted first user input in memory only. Existing v1-v3 records are neither rewritten nor adopted.

## Minimal session interfaces

```ts
// Methods on the already authenticated/unlocked PersistentConversation owner.
newChat(): Promise<string>;
resumeConversation(conversationId: string): Promise<string>;
readHistory(signal?: AbortSignal): Promise<HistoryResult>;
// Existing manager snapshot gains switching: boolean.
// HistoryConversation gains resumable?: boolean.
```

No generic decryptor/key-export API is needed. Reads use only this manager's existing unlocked secret; missing keys fail closed. Unverified legacy sessions remain locked/read-only. No crypto initialization occurs during archive reads/switches.

## Transition invariants

1. Capture the current owner/session. Reject if restoring, storage-blocked, already switching, or SSE pending. Concurrent clicks cannot create two new conversations.
2. Block sends on the old session and detach its checkpoint observer. Flush the existing encrypted checkpoint queue. A failed checkpoint leaves the old session selected and no new conversation visible.
3. For New Chat create a UUID and empty session. For resume load `[uid, conversationId]` only, authenticate/decrypt its snapshot with the existing key, validate embedded owner/session IDs and reconcile only owner-matching service rows. A corrupt/foreign/legacy target cannot replace the active session.
4. Encrypt the next session before opening IndexedDB's transaction. No crypto/network async work inside the transaction.
5. In one transaction over `conversations` and `conversationArchives`, compare current active ID/revision, archive its entire encrypted record, persist the next archive and replace the active header. Unexpected errors roll back all three operations. Use a monotonic active-header revision even when returning to an older session, preventing stale-tab ABA writes.
6. Only after commit publish the next session, dispose old plaintext state, attach its observer and enable sends. Restore the old session on failure. Account disposal invalidates outstanding work; assertions around asynchronous stages and inside the transaction prevent cross-owner publication/writes.
7. An active SSE is never cancelled merely by New Chat: switching is disabled with a wait explanation. Ordinary route changes keep P0's existing shared owner/stream.
8. New Chat/switching creates no completion event, reward, crisis-policy decision, import/export record or cloud sync. Saved safety/exercise recovery state stays attached to its original conversation.

## Source files affected after approval

- `src/lib/db.ts`: additive archive table/version only.
- `src/lib/conversation/PersistentConversation.ts`: owner-scoped archive reads, guarded atomic transition and reuse of existing recovery logic.
- `src/hooks/useChat.ts`: prevent input while switching.
- `src/lib/history/readHistory.ts`: optional resumability metadata only.
- `src/components/chat/ConversationProductControls.tsx`: connect New Chat with actual pending/error states.
- `src/app/(authenticated)/history/page.tsx`: actual current/saved/locked list and Continue handlers.
- Focused continuity, migration, controls and History tests; acceptance/handoff reports.

No edits needed to Ahmad's renderer, Companion Scene route, voice/camera controls, conversation transport, Firebase or crypto implementation.

## Required verification before claiming usable multi-chat

| Case | Required result |
|---|---|
| Existing v3 database upgrade | Old messages, active header, user preferences, activity/reward/milestone/legacy stores preserved; archive starts empty |
| A -> New Chat -> B | Distinct UUIDs, A encrypted state retained, B empty context, zero reward/completion writes |
| Refresh / resume A / resume B | Both listed including empty sessions; correct isolated text/context/safety state; selected ID survives refresh |
| Double click / failed archive/header write | One transition or atomic rollback; no partial selection or lost transcript |
| Pending SSE / route hopping | New Chat waits; stream not cancelled, no duplicate POST or misattributed reply |
| Stale second tab / return-to-A ABA | Revision compare rejects stale writes, no archive overwrite |
| Foreign UID / account switch | Owner-filtered reads; no foreign decryption/publication/writes, disposed plaintext cleared |
| Missing key / corrupt archive / legacy rows | Explicit locked/unavailable; current session unchanged; no regeneration/adoption |
| Real browser, synthetic identity | Genuine authenticated A/B creation, refresh, resume and follow-up context; fixture results labelled separately |

Tests and browser acceptance for these new interfaces are NOT RUN because application of the patch was blocked. Existing Increment 04 acceptance is unaffected.


## 2026-10-18 review-package update

The owner retained joint approval and authorized an unapplied proposal only. See new-chat-review.md and the three new-chat-*.proposed.diff files for the current exact schema, reused consumer interface, outstanding safety decisions and validation limits. Earlier illustrative signatures/schema in this note are superseded; no protected change is applied.
