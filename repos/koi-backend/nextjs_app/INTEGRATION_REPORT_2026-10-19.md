# Web integration report — 2026-10-19

Branch `integrate/web-2026-10-19` (worktree `E:\Koi\web-integrate`), local merge only. Nothing pushed, deployed or sent to live services. No dev server started. No `.env*` file opened.

## Base SHAs

| Side | Ref | SHA |
|---|---|---|
| Ours (Ahmad: avatar, voice, camera, speech) | `integrate/web-2026-10-19` (from `origin/avatar/vrm-emotion`) | `884a278e0370835e98c07ae192cfa2dc8ba73495` |
| Theirs (Irsa: product data, history, activities) | `origin/review/web-product-data-wip` | `a13e69df32ad2377d1fbd5ce8e8350c59362614f` |
| Merge base | | `223e97c489947b98677392f9b8ea383690ab1fe8` |

The merge ran as `git merge --no-ff --no-commit origin/review/web-product-data-wip`. It would have stopped on the conflicts anyway. It was then committed as a single `--no-ff` merge commit.

## Conflicts and resolutions

Only two files conflicted. Every other file merged automatically, because neither side changed a file the other side changed.

### 1. `src/app/(authenticated)/chat/page.tsx` (2 hunks)

- **Imports (hunk at old :10):** ours (`InputModeContext`, `MicButton`, `CameraPip`) vs hers (`ConversationProductControls`). **Resolution: both kept.**
  - `chat/page.tsx:10-13`: `import { modeUsesCamera, modeUsesMic, useInputMode } …` / `import MicButton …` / `import CameraPip …` / `import ConversationProductControls from '@/components/chat/ConversationProductControls';`
- **Header row (hunk at old :87):** ours is a styled `neo-btn-secondary` "Open avatar conversation" button with an icon. Hers is a plain link, plus `ConversationProductControls` and a History link. **Resolution: our button is kept. Her controls and History link are each inserted once.**
  - `chat/page.tsx:84`: `<ConversationProductControls preferenceState={avatarPreference} pending={isTyping} />`
  - `chat/page.tsx:85-91`: our `<Link href="/companion-scene" className="neo-btn-secondary" …>` "Open avatar conversation"
  - `chat/page.tsx:92`: `<Link href="/history" style={{ padding: '8px 16px' }}>Browse saved history</Link>` (sits inside our button row)
  - Her unstyled duplicate "Open avatar conversation" link was dropped.
  - Our mic `InputBar extra` and camera PiP are unchanged.

### 2. `src/app/(authenticated)/companion-scene/page.tsx` (3 hunks)

- **Imports (hunk at old :11):** **Both kept.** `companion-scene/page.tsx:20-21`: `import BreathingActivityBridge …` / `import ConversationProductControls …`. Our voice, mic, camera and `crisisActive` code is kept as is.
- **`end` + opening JSX (hunk at old :49):** ours `const end = () => { voice.stop(); chat.cancel(); … }` plus our `noticeText`/`inputHint`. Hers `const end = () => { chat.cancel(); … }` and the wrapper. **Resolution: our `end` is kept, so voice still stops on End, and her bridge wraps the scene.**
  - `companion-scene/page.tsx:46`: `const end = () => { voice.stop(); chat.cancel(); router.push('/chat'); };`
  - `companion-scene/page.tsx:56`: `return <BreathingActivityBridge><CompanionScene …`
- **notice/composer (hunk at old :76):** **Ours kept:** our `noticeText`, `micControl`, `cameraControl`, `cameraOverlay`, the voice-aware composer and `idleHint`. Her `ConversationProductControls` is inserted once at the front of the notice.
  - `companion-scene/page.tsx:68`: `notice={<><ConversationProductControls preferenceState={avatarPreference} pending={chat.pending} />{noticeText}`
  - `companion-scene/page.tsx:77`: `… idleHint={inputHint} />} /></BreathingActivityBridge>;`
  - **Dropped, not reintroduced:** her `'Text is the only available input mode. Audio and video modes are not enabled yet; avatar speaking movements do not play audio.'`. Our media works, and our `noticeText` already covers loading, unavailable, legacy-fox, text-only fallback and the camera privacy line.
  - **Side effect:** the notice is now always rendered, because the controls are always present. Before, ours was `undefined` when `noticeText` was empty.

`grep` confirms each page has exactly one `<ConversationProductControls`, chat has one `/history` link, and companion-scene has one `BreathingActivityBridge` pair.

## Files merged automatically: required checks

### Conversation, transport and session files: OURS kept, byte for byte

`git diff --cached HEAD` over `src/lib/conversation/`, `src/contexts/`, `src/hooks/useChat.ts`, `src/lib/speech/`, `src/components/voice/MicButton.tsx` and `src/components/companion/` is **empty except for `ExerciseDirector.tsx`**. That covers `ConversationSession`, `ConversationContext`, `useChat`, `conversationService`, `jsonChatTransport`, `chatContract` and `PersistentConversation`. Irsa's branch never modified them.

### `review/`: nothing applied

The merge adds the files under `review/` (proposals, evidence and harness copies) as tracked documents. None of `new-chat-session.proposed.diff`, `new-chat-consumers.proposed.diff`, `new-chat-tests.proposed.diff`, `firestore.user-preferences.proposed.rules` or `firebase-preferences.rules.cjs` was applied. The session and consumer sources are identical to ours (see above). `increment04-db-migration.diff` and `increment04-exercise-callback.diff` are review copies of changes that already exist as source on her branch (`db.ts` and `ExerciseDirector.tsx`); they were not applied a second time.

Note: `src/lib/preferences/accountPreferenceSync.proposed.ts` is a source file on her branch and has a test (`account-preference-sync-proposal.test.ts`). It came in with the merge; it is not under `review/`.

### `src/lib/db.ts`: her v3 taken, verified

- Versions 1 and 2 are unchanged. The only diff from ours adds a type import, three `Table` fields and the v3 block.
  - `db.ts:94`: `this.version(2).stores({ conversations: 'uid, conversationId, lastActiveAt' });`
- Unique indexes are exactly the required set:
  - `db.ts:96`: `activityEvents: 'id, owner_uid, &[owner_uid+source_type+completion_id], [owner_uid+source_type+day_key], completed_at'`
  - `db.ts:97`: `rewardReceipts: 'id, owner_uid, &[owner_uid+source_type+day_key], &[owner_uid+slot_index]'`
  - `db.ts:98`: `milestoneReceipts: 'id, owner_uid, &[owner_uid+milestone]'`
- No `version(4)` exists.

### `src/components/companion/ExerciseDirector.tsx`: her `onBreathingResult` taken

- The observer is wrapped and cannot throw into the exercise flow:
  - `ExerciseDirector.tsx:123`: `try { resultCallback.current?.({ ... }); } catch { /* No reward confirmed; keep normal exercise cleanup. */ }`
- Our voice cancel-on-exercise still fires, and her change does not touch it:
  - `useSpokenReplies.ts:26,35`: cancellation is driven by `chat.serverEvents` (`ui_action` in `EXERCISE_ACTIONS`). `ExerciseDirector` never changes those events.
  - `companion-scene/page.tsx:61`: `onExerciseRequest={(event) => { voice.stop(); void chat.session.sendClientEvent(event); }}` (kept)
  - `scene-voice.test.tsx` passes after the merge, including the exercise start, `stop_breathing` and `pause_breathing` cancel cases.
- **Not fully confirmed: "changes nothing sent to the server" holds only in the common path.** Her change adds a new handoff branch:
  - `ExerciseDirector.tsx:162-163`: `if (item.event.event === 'handoff') { if (activeBreathing.current) { report('handoff'); … queueRef.current('playback_stopped'); } continue; }`
  - Common path: the first handoff also changes `interruptKey` (`CompanionScene.tsx:99`, `interruptKey={handoffEventId ?? 0}`). That effect runs first (`ExerciseDirector.tsx:146-156`), queues `playback_stopped` and clears `activeBreathing`, so the new branch is a no-op. Nothing extra is queued.
  - Edge case: `activeCrisisRef` in `CompanionScene.tsx:62-72` stays set until `serverEvents` empties. If a **later** `handoff` event arrives while a **new** breathing run is active, or a handoff follows a HIGH or CRITICAL `risk` event that already set the crisis, `interruptKey` does not change. In that case the new branch queues a `playback_stopped` client event that our pre-merge code would not have queued. That event goes to the server on the next turn.
  - **Needs a decision from Ahmad and Irsa.** Either accept it (stopping breathing on any handoff is arguably the safer behavior) or remove the `queueRef` call from that branch. It was left exactly as Irsa wrote it.
- **Other risk:** `ExerciseDirector.tsx:177` calls `crypto.randomUUID()` outside the try/catch on `start_breathing`. Browsers expose that only in secure contexts (https or localhost). On an insecure LAN origin, breathing start would throw. Hosted is https, and our mic and camera already need a secure context.

### Tests asserting media is disabled

**No test needed updating.** No merged test asserts that media is disabled on `/chat` or `/companion-scene`, and no test asserts her dropped notice text. Tests checked:
- `voice-controls.test.tsx`: asserts that `VoiceCaptureControls` "ships disabled by default". That is her unwired development adapter component, not our media path, so the assertion is still correct. **Left unchanged.**
- `web-honesty.test.tsx`: her additions cover only the export page and a `ConversationContext` mock. No media assertions. **Unchanged; passes.**

## Verification

| Check | Ours `884a278` before | Theirs `a13e69d` before | Combined after |
|---|---|---|---|
| `npm test -- --runInBand` | **272/272** pass, 27 suites | **284/286** pass, 39 suites (2 fail) | **472/474** pass, 51 suites (same 2 fail) |
| `npx tsc --noEmit --incremental false` | not run separately | not run separately | **PASS** (exit 0) |
| `npm run build` | not run separately | not run separately | **PASS** (exit 0, 25 routes incl. `/chat`, `/companion-scene`, `/history`) |
| `node scripts/test-avatar-emotion-matrix.cjs` | — | — | **PASS**, 10 checks |
| `node scripts/test-avatar-controller.cjs` | — | — | **PASS**, 7 checks |
| `node scripts/test-avatar-session.cjs` | — | — | **PASS**, 6 checks |
| `node scripts/test-avatar-host.cjs` | — | — | **PASS**, 6 checks |
| `git diff --check HEAD` | — | — | **9 trailing-whitespace hits, all in `review/`** (see below). Outside `review/`: **clean** (exit 0) |

Irsa's baseline was run from a `git archive` snapshot of `a13e69d` in the session scratchpad, with `node_modules` junctioned. No branch, worktree or checkout was created. Node `v20.12.2`.

### The 2 failing tests: failing on her branch before the merge, not caused by the merge

- `checkin-service.test.ts` › "saves genuine AES-GCM ratings, decrypts with the existing key…": `TypeError: Failed to execute 'decrypt' on 'SubtleCrypto': 3rd argument is not instance of ArrayBuffer…` at `src/lib/crypto.ts:169`.
- `backup-existing-key.test.ts` › "verifies genuine existing-crypto ciphertext…": expected `status: 'ciphertexts-verified'`, received `'blocked'`. Same root cause: decrypt throws.
- Both tests swap `globalThis.crypto` for Node's `webcrypto` under jsdom. `copyToArrayBuffer` (`crypto.ts:62-66`) builds the `ArrayBuffer` in the jsdom realm, so Node 20.12's cross-realm `instanceof ArrayBuffer` check rejects it.
- Irsa's `review/handoff-evidence/current-verification.json` records 286/286 PASS at `b384ce2` from a dirty worktree. The difference is likely her Node version or uncommitted state.
- **Not fixed.** The fix touches either `crypto.ts`, a core file, or the tests' crypto shim. That is a decision for the owner, not integration breakage.

### `git diff --check` hits (left as is)

The hits are in `review/handoff-evidence/browser-harness/pre-defense/browser-{controls,followup}.cjs:26`, `review/increment04-exercise-callback.diff` (lines 12, 15, 28, 41, 121), `review/new-chat-consumers.proposed.diff:26` and `review/new-chat-session.proposed.diff:32`. They are verbatim evidence copies or blank context lines inside diff files, where the space is significant. Irsa's own record already lists them. They were not modified, because `review/` is not touched.

## Per-feature status (combined tree)

Legend: **S** source implemented · **U** unit tested (passing here) · **B** browser verified · **H** hosted verified · **—** not run in this integration.
"B (prior)" means browser evidence from before this merge on that branch alone. It was not re-run on the combined tree.

| Feature | Owner | S | U | B | H |
|---|---|---|---|---|---|
| VRM avatar, emotion and lifecycle | Ahmad | ✔ | ✔ (jest + 4 node scripts) | B (prior: `verify-avatar-emotion-screens`/`lifecycle` per AVATAR_ACCEPTANCE doc) | — |
| Voice input (mic → `/api/v1` transcription) | Ahmad | ✔ | ✔ | B (prior: "works in live test" per `884a278` message, unreviewed WIP) | — |
| Spoken replies (speech client, chunker, turn controller, cancel rules) | Ahmad | ✔ | ✔ | B (prior, same as above) | — |
| Camera self-view (local only, crisis suspend) | Ahmad | ✔ | ✔ | B (prior, same as above) | — |
| Input modes, layout, header identity | Ahmad | ✔ | ✔ | B (prior, same as above) | — |
| Conversation product controls (New Chat disabled, Complete info, Change companion) | Irsa | ✔ | ✔ | B (prior, her harness) | — |
| History browsing (`/history`) | Irsa | ✔ | ✔ | B (prior, her harness) | — |
| Activity ledger (Dexie v3), rewards, milestones | Irsa | ✔ | ✔ | B (prior, her harness) | — |
| Breathing result → activity (`BreathingActivityBridge` + `onBreathingResult`) | Irsa | ✔ | ✔ | B (prior, her harness) | — |
| Check-ins (encrypted) | Irsa | ✔ | ✘ 1 test fails (crypto realm, see above) | B (prior, her harness) | — |
| Backup draft / ciphertext export / preview | Irsa | ✔ | partial: 1 test fails (crypto realm) | B (prior, her harness) | — |
| Account preference sync status | Irsa | ✔ (status UI; proposed rules not deployed) | ✔ | B (prior, her harness) | — |
| Progress board (recorded) | Irsa | ✔ | ✔ | B (prior, her harness) | — |
| Sign-in retry / onboarding keyboard access | Irsa | ✔ | ✔ | B (prior, her harness) | — |
| Combined `/chat` + `/companion-scene` UI | both | ✔ | ✔ (page tests pass) | **— not run** | **— not run** |

## Remaining work

1. **Combined browser pass.** No browser verification was run on the merged tree. Check on `/chat` and `/companion-scene`: product controls next to mic and camera, History link placement, and the always-present notice region.
2. **`<div>` inside `<p>`.** `ConversationProductControls` renders `<div>` content inside CompanionScene's notice `<p className={styles.notice}>` (`CompanionScene.tsx:101`). Her branch already placed it this way. Browsers will re-nest it, so expect a hydration warning in dev. A layout decision is needed: move it to its own slot, or change the notice wrapper.
3. **ExerciseDirector handoff edge case** (see above): decide whether a later handoff during breathing should queue `playback_stopped`.
4. **Crypto test realm failures:** fix the shim or `copyToArrayBuffer`, owner's call. Then confirm 474/474.
5. **New Chat (Dexie v4 / session switch).** Proposals under `review/new-chat-*` are still unapplied, and v4 is deliberately absent. Needs the joint review in `review/new-chat-approval.md`.
6. **`handoff_open`.** Durable unresolved-handoff status exposed by the shared session, a precondition for conversation completion.
7. **Conversation completion producer.** Persisted SSE completion evidence plus an explicit, saved completion. `lib/activities/conversationCompletion.ts` exists only as a consumer and evidence check; there is no producer. The "Save completion" button is disabled.
8. **Per-UID onboarding flag.** Onboarding completion is still not scoped per UID. It uses one global key: `onboarding.ts:50` `localStorage.setItem('koi_onboarding_complete', 'true')` and `onboarding.ts:56` reads the same key.
9. **Dashboard / report.** The wellness report stays disabled (`web-honesty.test.tsx`). Dashboard and report are not implemented.
10. **Protected-file review.** `884a278` edits protected conversation and transport files. Its commit message flags that it needs Irsa's review. This merge kept those edits unchanged, so that review is still outstanding.
