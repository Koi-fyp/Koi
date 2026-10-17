# KOI P0 recovery handoff - 2026-10-17

## Scope and identity

P0.0-P0.2 implementation only. No jigsaw, retention, media, Flutter, authentication policy, backend contract, Firestore path/rules, or deployment changes.

- Branch: feat/avatar-webview-host
- HEAD: 40be37e201998c54e5be3f0f9abd6973ec36e616 (unchanged).
- Checkout was dirty before work; all original tracked/untracked work remains. In particular the existing M13 transport, Firebase auth, avatar preference/onboarding edits, .idea/ and koi-mobile/android/ were preserved.
- No Next server was listening on ports 3000-3002 when checked. No server was started. Verified artifact is a Next.js 14.2.35 production build, not an authenticated running application.
- API origin: UNKNOWN from process environment; .env.local was not read or modified. Backend deployed version: UNKNOWN. No network inference, Firebase sign-in, credential inspection or deployment was performed.
- The requested backend contract path and named Blueprint/track/UX documents were not present in this checkout. Current source/tests and WEB_BLITZ_STATUS.md were inspected; no proposed v1.1 behavior was declared deployed.

## Root cause and change

The old route-mounted hooks constructed different random ConversationSession IDs and cancelled them on unmount. The old history lookup therefore searched the new ID instead of the persisted conversation. The new regression test reproduces the identity mismatch; no live baseline click-through is claimed.

The authenticated layout now owns one UID-scoped PersistentConversation. Both route hooks subscribe to its existing ConversationSession; ordinary navigation does not own cancellation. The original service, Firebase boundary, encrypted message writes and SSE parser remain in use.

Dexie v2 adds a conversations table without changing/removing v1 stores. Its per-UID active record holds a stable conversation ID, timestamps, revision and encrypted full session snapshot. There is no expiry policy. Content, safety events and signed exercise state in that snapshot use the existing AES-GCM/PBKDF2 functions. The encrypted envelope also verifies UID ownership. New service message rows have additive ownerUid and replyTo fields. Existing Firestore collection paths remain unchanged and receive the same encrypted content.

Recovery blocks input until unlock/read completes, restores IDs/roles/order/timestamps/companion state, and reconciles owned service rows when a refresh raced the final snapshot. Pending replies become interrupted, preserved user turns; no POST is automatically replayed. Failed storage/decryption blocks new sends. Revision checks reject stale-tab writes; this is conflict detection, not cross-tab live transcript merging.

Account changes unmount the old owner, abort its request, purge its live snapshot and isolate the new UID. Consumed exercise UI actions and resolved safety handoffs are session-owned so a view remount does not replay them. Safety/exercise events are checkpointed during streams; ordinary token deltas are not individually checkpointed.

Back/navigation continues SSE. Cancel reply stops the current reply. Existing End session stops the reply and returns to Chat while preserving the transcript. No New Chat UI, archive browser or retention policy was added.

Legacy ownerless rows are neither adopted nor deleted. Recovery of those historical orphaned threads needs independently proven UID/cryptographic provenance; no automatic migration guesses ownership.

## Acceptance evidence

| Gate | Status | Evidence / limit |
| --- | --- | --- |
| Chat -> Progress -> Chat, repeated | PASS, component fixture | Same session object/ID, four messages after two exchanges, no repeated send |
| Chat -> Avatar -> Chat | PASS, component fixture | Same shared hook/provider session; ordinary Back no longer cancels |
| Navigation during active SSE | PASS, local fixtures | Route subscribers detach/reattach; real parser/transport fixture completes one POST and one assistant bubble |
| Refresh / tab reopen recovery | PASS, local fixtures | Provider remount plus real Dexie close/reopen, original IDs and valid follow-up history |
| Encryption at rest | PASS, real crypto fixture | Actual AES-GCM/PBKDF2 snapshot and message ciphertext; original payload format retained |
| Cross-account isolation | PASS, fixtures | Account switch abort/purge, empty other-user session, owner envelope and wrong-key decryption rejection |
| Interrupted / partial turns | PASS, fixtures | User-only pending turn restored cancelled, no automatic inference replay; committed reply race reconciles once |
| Locked/corrupt/unavailable DB | PASS, fixtures | No send or partially decrypted history exposed |
| Legacy preservation / schema upgrade | PASS, real Dexie fixture | Existing v1 row remains byte-for-byte; no adoption |
| Stale tab protection | PASS, fixture | Revision mismatch rejects checkpoint; newer record remains authoritative |
| Exercise / crisis / avatar regressions | PASS, offline fixtures | Event consumption, signed state, resolved handoffs, existing Flow4/parser/controller tests |
| Real authenticated browser navigation/refresh | NOT RUN | No legitimate runtime test session exercised |
| Real offline launch / Modal / Firestore sync | NOT RUN | Crypto context/auth/fetch/remote sync use fixtures; no deployed success claimed |
| Screenshots | NOT RUN | No authenticated browser session started |

First unresolved blocker: complete legitimate authenticated browser acceptance against a verified runtime configuration and approved backend. Local automated results are not a substitute for this live gate. P1-P4 were not started.

## Commands and results

- PASS: TypeScript compiler --noEmit --incremental false (installed compiler directly; no package download).
- PASS: Jest --runInBand: 8 suites, 40 tests. One existing styled-jsx DOM warning appears in the preserved chat-avatar test.
- PASS: scripts/test-conversation-recovery.cjs (real Dexie, encryption and service/SSE with synthetic auth/fetch only).
- PASS: scripts/test-chat-contract.cjs, test-crypto-roundtrip.cjs, test-exercise-director.cjs, test-flow4.cjs, test-v11-fixture.cjs, test-avatar-controller.cjs, test-avatar-host.cjs.
- PASS: final npm run build, Next.js 14.2.35; all 18 static-generation entries completed, including Chat/companion-scene routes. Used a temporary process-only 1024 MB Node heap, no concurrent server/tests.
- PASS: git diff --check before handoff; final check also run after creating this report.

## Files changed by P0

All paths below are relative to repos/koi-backend/nextjs_app, except this report.

Modified:
- src/app/(authenticated)/layout.tsx
- src/app/(authenticated)/companion-scene/page.tsx (small changes on top of pre-existing local edits)
- src/components/companion/CompanionScene.tsx
- src/components/companion/ExerciseDirector.tsx
- src/hooks/useChat.ts
- src/hooks/useConversationSession.ts
- src/lib/conversation/ConversationSession.ts
- src/lib/conversation/conversationService.ts
- src/lib/db.ts

Added:
- src/contexts/ConversationContext.tsx
- src/lib/conversation/PersistentConversation.ts
- src/__tests__/conversation-continuity.test.tsx
- scripts/test-conversation-recovery.cjs
- KOI_P0_RECOVERY_HANDOFF_2026-10-17.md (repository root)

Generated .next artifacts are ignored. No dependency or lockfile changed. Other modified/untracked files in final git status predate P0.

## Manual live acceptance still required

1. Start one local server with approved runtime configuration. Sign in through genuine Firebase anonymous auth; do not inject a fake token.
2. Send two ordinary non-sensitive messages and wait for each reply. Navigate Chat -> Progress -> Chat repeatedly, then Chat -> Avatar -> Chat. Verify the same IDs/turns and no additional chat POSTs.
3. Start a reply and navigate away before done. Return during streaming and after completion; verify one request, one provisional bubble and one completed reply.
4. Refresh, close/reopen the tab and send a follow-up. Verify correct prior user/assistant roles within the existing five-completed-message window.
5. Refresh during an unfinished reply. Confirm preserved interrupted user input with no automatic POST. If the reply committed before refresh, confirm exactly one recovered reply and no false interruption warning.
6. Switch to a second legitimate Firebase UID and confirm no old messages. Return to the original UID and verify only its own record restores. Test logout separately.
7. Test cached offline reload, blocked local storage and linked-account unlock without logging tokens, plaintext history, salts or trace. Verify remote encrypted sync separately; do not assume inference persists history.
8. Resolve a synthetic safety handoff only in the approved fixture environment; navigate away/back and verify it does not replay. Do not generate real crisis content for testing.

Final state: dirty working tree retained, nothing staged/committed/pushed/merged/reset/cleaned/deployed. No P1-P4 implementation.
