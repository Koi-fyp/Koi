# KOI Web final report — 2026-10-19

Branch `integrate/web-2026-10-19` (worktree `E:\Koi\web-integrate`), starting at `071c397`. All work is committed locally, one commit per phase. Nothing was pushed or deployed. No `modal` or `firebase deploy` command was run. No `.env*` file was opened or printed. Keys, salts, encryption algorithms, the ciphertext format, crisis thresholds and the backend contract are unchanged.

## Commits per phase

| Phase | Commit | Summary |
|---|---|---|
| 0 | `bd1e5f0` | Crypto test-realm shim, CompanionScene notice `<div>`, per-UID onboarding, `.env.local.test` untracked |
| 1 | `ef842fa` | Durable `handoff_open` / `done_seen`, persisted-pair evidence, explicit conversation completion |
| 2 | `c19296b` | Dexie v4 `conversationArchive`, New Chat, History resume, read-only decryptor |
| 3 | `bba46d3` | Message sync to `users/{uid}/conversations/{cid}/messages/{mid}` with the exact 8-field payload |
| 4 | `6624d9e` | Dashboard and printable wellness report from real local data |
| 5 | `48a5abd` | Verification; two smoke findings fixed (History unreadable count, table header alignment); this report |
| Follow-up | `f0ba08f` | Block New Chat during an open handoff (typed `crisis-open`) |

## Verification

| Check | Result |
|---|---|
| `npm test -- --runInBand` | **537/537 pass, 59 suites** (current full suite, at `f0ba08f`) (baseline at start: 472/474, 51 suites, 2 known crypto-realm failures) |
| Test count after each phase | P0 478 · P1 493 · P2 512 · P3 519 · P4 530 · P5 531 · follow-up 537, all green |
| `npx tsc --noEmit --incremental false` | PASS after every phase |
| `git diff --check` outside `review/` | clean after every phase |
| `npm run build` | PASS, Next 14.2.35, 20/20 static pages, new route `/settings/report`. Final **BUILD_ID `fcHZZ7CKkoqUJJ36-eXHD`** (after the phase 5 fixes; the first phase 5 build was `a4RcBqubv9UP2St8_FB1t`) |
| `node scripts/test-avatar-emotion-matrix.cjs` | PASS (`passed: true`) |
| `node scripts/test-avatar-controller.cjs` | PASS (`passed: true`) |
| `node scripts/test-avatar-session.cjs` | PASS (`passed: true`) |
| `node scripts/test-avatar-host.cjs` | PASS (`passed: true`) |
| Headless browser smoke | **PASS, all 16 steps across two runs** against this worktree's dev server on port 3001, using the live chat backend. See the section below. |

## What changed, by phase

### Phase 0 — cleanup
- **Crypto tests (0a).** Root cause: Node 20's WebIDL `BufferSource` check accepts views from any realm but checks a raw `ArrayBuffer` against Node's own prototype. `copyToArrayBuffer` builds that buffer in the jsdom realm, so it was rejected. `jest.setup.ts` now wraps Node's `webcrypto.subtle` once and copies raw jsdom-realm `ArrayBuffer`s into Node's realm. `src/lib/crypto.ts` was not changed in this phase. `checkin-service` and `backup-existing-key` pass.
- **Notice wrapper (0b).** `CompanionScene` notice is a `<div className={styles.notice}>`. A regression test fails on the old `<p>` with a nesting warning and passes now.
- **Per-UID onboarding (0c).**
  - The flag is `koi_onboarding_complete_<uid>`.
  - The legacy global key is read only by `resolveOnboardingComplete`, and only for the signed-in UID whose local `users` row has `onboardingComplete: true`. It is then migrated, and the legacy key is left in place.
  - The flag is set as soon as the local save succeeds, so a cloud failure cannot loop the user back.
  - `/onboarding` sends an onboarded UID to `/chat` unless it was opened by Settings → **Redo setup** (`?redo=1`). Redo updates the existing row and keeps `id`, `createdAt` and any unrelated fields.
- **`.env.local.test` (0d).** `git rm --cached` plus a `.gitignore` entry. The file is still on disk and was not opened by this work. It remains in git history: Ahmad verified and handled the credential on 2026-10-19 00:06, recorded the key disposition himself and chose no history rewrite.

### Phase 1 — handoff state, persisted pairs, completion
- **AI rows.** `conversationService` writes an AI row only after it has seen a terminal `done`. It adds unindexed `handoff_open` and `done_seen: true` to the **local** row only.
  - `handoff_open` is true if `done.handoff != null` **or** a standalone `handoff` event arrived in that turn. Including the standalone event is a conservative superset of the requested rule.
  - Both fields are stripped from the sync payload.
- **`hasUnresolvedHandoff`** is computed from saved rows: it is true when the newest AI row has `handoff_open`. `PersistentConversation` and `useChat` expose it.
  - Tested: it stays open through dialog close, remount/navigation, a benign turn that still returns a handoff, and an aborted `crisis_resolved` request.
  - It clears only after a later completed turn returns a null handoff.
- **Failed, interrupted and cancelled turns** write no AI row. Tested: transport failure, a stream with no `done`, a resolved adapter without `done` (guarded), and a cancel. Recovery after reload does not adopt a row.
- **`getQualifyingPair(uid, conversationId)`** (`lib/conversation/persistedEvidence.ts`) takes the newest owned user row plus a `done_seen` reply with `replyTo` pointing to it. `lastPersistedMessageId` is the newest row.
- **`saveConversationCompletion`** runs under a completion lease that blocks sends while it reads evidence and commits.
  - `completion_id = sha256("koi:conv:v1:"+uid+":"+conversationId+":"+lastPersistedMessageId)`.
  - It goes through the existing ledger: one piece per source per Karachi day, a 25-slot cap and milestones.
  - "Save completion" is enabled only when eligible. New Chat, navigation, Back and End never call it.
  - ADR-REWARDS matrix tests: double click; two tabs; same-day second completion is event-only; the next Karachi day earns a piece; unresolved handoff is ineligible; a handoff resolved earlier is eligible; no pair is rejected; a pending reply is rejected; an owner change is rejected.

### Phase 2 — New Chat and History resume (Dexie v4)
- **Schema.** `version(4)` adds `conversationArchive: '&[uid+conversationId], uid, archivedAt'`, holding the same header and ciphertext blob, moved verbatim. There is no upgrade callback, no existing store changes, and it is not in `syncQueue`. Migration tests open real v1, v2 and v3 databases and assert every row survives.
- **Switching.** `archiveAndStartNew(uid)` and `activateArchived(uid, targetId)` do the following:
  - Take a synchronous lease and refuse while a turn is pending (`busy`).
  - Flush the encrypted checkpoint.
  - Decrypt the target only *before* the transaction, to refuse a locked target.
  - Run **one** rw transaction over `conversations` and `conversationArchive` that compares the expected id/revision, so a stale tab fails closed with `conflict`.
  - Use a monotonic revision, so A→B→A cannot be matched by a stale tab.
  - Never archive an empty current conversation.
  - Watch for owner changes and abort the transaction.
  - Never let a stale checkpoint from a swapped-out session write.
  - Return typed errors: `busy | owner-changed | conflict | storage-unavailable | not-found`, plus `locked` for an undecryptable target. `locked` is an addition to the requested list.
- **Read-only crypto.** `peekActiveCryptoContext(uid)` was added to `crypto.ts`. It returns an existing local secret and salt or `null`, and never generates, writes, syncs or fetches. `withOwnedDecryptor` returns `ready | locked | unavailable` and checks the owner around every await. Linked accounts stay locked.
- **Context.** `ConversationContext` exposes `useOwnedConversationActions()` (`createOwned` / `openOwned`). It keys the route children by `conversationId`, so a committed swap remounts route state. That cancels speech playback, mic capture and exercise UI. A late exercise callback from the old route lands on the disposed old session, which ignores it (tested).
- **UI.**
  - New Chat is enabled. While a reply is pending it shows "(reply in progress)" and is disabled.
  - History lists the active conversation, archived ones (title from the first user message, dates, message count) and legacy retained row groups as read-only.
  - "Open conversation" calls `openOwned` and routes to `/chat`. Locked rows show as locked.

### Phase 3 — cloud message path
- **Path and payload.** Messages queue to `users/{uid}/conversations/{cid}/messages/{mid}` with exactly `id, conversationId, sender, content (ciphertext), timestamp (Date), emotion, emotion_confidence (0..1, default 0), synced`. A test checks real AES output against the phase-1 rule's `isCiphertext` regex.
- **Never sent:** `handoff_open`, `done_seen`, `ownerUid`, `replyTo`, `companion_state` and audio.
- **Legacy queue items.** Items on the old root path that are owned by the signed-in uid are re-pathed once, with the exact payload. Items owned by another uid, or with no owner, are never adopted or sent.
- **Queue fixes:**
  - Timestamps are revived after the localStorage JSON round-trip, as the rule requires `timestamp is timestamp`.
  - Flush is single-flight and keeps items enqueued during a flush.
  - Retries run on `online` **and** on app start/sign-in (`ConversationProvider`).
- **Unchanged:** preference sync and the `users/{uid}` salt write.
- **Needs deployment.** Cloud message writes will be denied until Ahmad deploys `firestore.rules.phase1`. Writes stay queued and retry.

### Phase 4 — dashboard and report
- **Progress.**
  - Real counts: completed exchanges, conversations, completed conversations, check-ins, breathing sessions, pieces and milestones.
  - Check-in chart over 7, 30 or 90 days or all time, with a series filter, legend, direct labels, hover tooltip and table view. Palette: validated reference slots 1–3 with distinct markers.
  - A Monday-first Karachi-day activity calendar from `activityEvents`.
  - The 25-slot board from receipts (unchanged component).
  - Sample previews stay collapsed. Empty states say "No data yet". There are no streaks and no inferred mood.
- **`/settings/report`** (linked from Export) covers a chosen date range:
  - Check-in summary (lowest/average/highest of the self-reported 1–5 ratings) and chart.
  - Activity and piece counts, all-time milestones, and a count of conversations with messages.
  - Message titles only when the user ticks the box.
  - The fixed disclaimer, and "Print / Save as PDF" (`window.print`, print CSS).
  - No crisis content and no risk scores.

## Decided and implemented after Phase 5

**New Chat during an open handoff is blocked** (commit `f0ba08f`).
- **Typed error.** `archiveAndStartNew` and `activateArchived` refuse with `'crisis-open'` while the current conversation has an unresolved handoff.
- **Re-read after the checkpoint.** Besides the in-memory flag checked up front, the saved message rows are re-read after the encrypted checkpoint flush, so an out-of-date flag cannot let a switch through. A read failure fails closed (`storage-unavailable`).
- **Same conversation allowed.** Reopening the current conversation is still a no-op that is allowed. Nothing is archived and the header is unchanged.
- **Disabled buttons.** New Chat in the chat controls and on the History page, and "Open conversation" for other conversations on History, are disabled with "Please finish the safety check first." The same text appears if the manager refuses with `crisis-open`. "Continue current conversation" stays available.
- **When it clears.** The block lifts after a later completed turn returns no handoff, for example the reply to a `crisis_resolved` request.
- **Tests:** blocked while open (both actions); blocked with an out-of-date flag; same-conversation reopen allowed; allowed again after a resolving turn; both UIs' disabled states.

## Per-feature status

S source · U unit-tested here · B browser-verified in this session's smoke · H hosted · — not run

| Feature | S | U | B | H |
|---|---|---|---|---|
| Crypto test-realm fix (all suites green) | ✔ | ✔ | n/a | n/a |
| CompanionScene notice `<div>` (no nesting warning) | ✔ | ✔ | B (0 hydration/nesting console errors) | — |
| Per-UID onboarding, legacy migration, Redo setup | ✔ | ✔ | B (fresh anonymous account; first visit sees onboarding) | — |
| `.env.local.test` untracked/ignored | ✔ | n/a | n/a | n/a |
| New Chat blocked during open handoff (`crisis-open`) | ✔ | ✔ | — (no handoff triggered by neutral messages) | — |
| Local `handoff_open` / `done_seen`, no AI row without done | ✔ | ✔ | — (no handoff triggered by neutral messages) | — |
| Explicit Save completion (ledger, Karachi cap, 25 slots) | ✔ | ✔ | B ("One piece was added") | — |
| Dexie v4 archive + migration | ✔ | ✔ | B | — |
| New Chat / History list / resume | ✔ | ✔ | B (2 listed, A reopened with messages) | — |
| Read-only decryptor (`peekActiveCryptoContext`, `withOwnedDecryptor`) | ✔ | ✔ | B (2 listed, A reopened with messages) | — |
| Cloud message path + exact payload + re-path + retry | ✔ | ✔ | — | — (rules phase 1 not deployed) |
| Progress dashboard (counts, chart, calendar, board) | ✔ | ✔ | B (run 2) | — |
| Wellness report `/settings/report` + print | ✔ | ✔ | B (run 2) | — |
| Voice / speech / camera / avatar (preserved) | ✔ | ✔ (suites + 4 node scripts) | — (no mic/camera in smoke) | — |

## Open items

1. **Crisis `/health`.** The web app has no separate crisis endpoint configured: risk runs inside the chat backend, per the integration docs. Only chat `/health` was warmed. If a separate crisis service exists, warm it manually.
2. **Ciphertext export** still covers message rows and the active header only, not `conversationArchive`. It is still labelled non-restorable.
3. **Linked accounts** remain locked for History titles, archives and report titles: no stored secret on the device, unchanged by design.
4. **ExerciseDirector handoff edge case** (integration report item 3) was not changed.
5. **Port 3000** was serving a different worktree (`E:\Koi\web-avatar`), so it was not reused and not stopped. This session used its own dev server on port 3001 and stopped it afterwards.
6. **Browser smoke findings:** both were fixed in Phase 5; see the smoke section. No crisis or handoff turn was exercised live, because the messages were neutral by design.

## Ahmad's manual steps

1. **Deploy Firestore rules phase 1** by following `E:\Koi\Koi-App\rules_draft\DEPLOY_STEPS.txt`: back up the live rules, run the emulator tests, then `firebase deploy --only firestore:rules --config firebase.deploy.json --project koi-companion-fyp`. Until then, cloud message writes stay queued. The local app works fully.
2. **`.env.local.test`.** Done: Ahmad verified and handled the credential on 2026-10-19 00:06 and recorded the key disposition himself. No history rewrite. The file is untracked and ignored but remains in git history.
3. **Review and push.** Review the phase commits and the follow-up `f0ba08f`, then push `integrate/web-2026-10-19` yourself. Nothing was pushed.
4. **Video checklist** for the recording:
   - Onboarding with a fresh account; a second account in the same browser sees onboarding.
   - Two messages, then Complete Conversation → Save completion → "One piece was added".
   - New Chat; send one message.
   - History shows two conversations → Open the first → messages restored.
   - Progress: save a check-in; the chart, calendar and board show it (2 of 25).
   - Range filter 7/30/90/all.
   - Settings → Export → Open Wellness Report → pick a range → Print / Save as PDF.
   - Settings → Redo setup keeps history.
   - Avatar scene with voice reply on, then New Chat: speech stops.
   - Optional: a crisis-path turn showing Save completion disabled until resolved.

## Browser smoke (Phase 5b)

Headless Chromium (Playwright). Each run used a fresh synthetic anonymous account created through the app's own **Get Started** sign-in. No mic or camera permission was granted. Port 3000 was serving a different worktree (`E:\Koi\web-avatar`), so this worktree's dev server ran on **port 3001** and was stopped afterwards; the port 3000 server was left running. Chat `GET /health`: HTTP 200 on attempt 2, after a cold-start timeout on attempt 1.

**Run 1** (chat flow; 3 neutral English messages; every chat POST returned HTTP 200):
- PASS: sign-in → onboarding (Aisha) → `/chat`. Local and cloud save succeeded directly.
- PASS: "Hello, how are you today?" and "I went for a short walk this morning." both got live replies.
- PASS: Complete Conversation → Save completion → "Conversation completion saved. One piece was added to your board."
- PASS: New Chat → empty conversation → "What is a simple way to relax in the evening?" got a live reply.
- PASS: History lists 2 conversations, with titles quoting the first messages, the current one first, and one "Open conversation".
- PASS: Open conversation → `/chat` with conversation A's messages restored.
- The run then stopped on a **script selector error**, not an app error: `getByLabel('Mood')` also matched the chart's "Mood" series checkbox. The session was lost with the browser.

**Run 2** (fresh account, **0 messages sent**, covering the remaining steps):
- PASS: onboarding → `/chat`.
- PASS: saved one check-in → "Check-in saved encrypted. One puzzle piece earned."
- PASS: Progress shows the real chart, the activity calendar and the board at "1 of 25".
- PASS: `/settings/report` renders the disclaimer and "1 saved check-in".

Run 2 shows 1 of 25 rather than 2 of 25 because it is a different account; the conversation piece was verified in run 1. Both runs logged **0 console errors**, including 0 hydration or nesting warnings.

**Findings fixed in Phase 5:**
1. History showed "Some retained records could not be unlocked…" for the archived conversation's own message rows. Those rows are listed from the archive, so they are no longer counted as unreadable. A test was added.
2. Table headers in the report and the chart table were centred; they are now left-aligned.

Screenshots in `artifacts/final/`: `01-chat-empty`, `02-chat-conversation-a`, `03-completion-saved`, `04-chat-conversation-b`, `05-history`, `06-chat-resumed-a`, `99-failure` (the run 1 selector stop), `part2-01-chat-empty`, `part2-07-progress`, `part2-08-report`. Results are in `smoke-results.json` and `smoke-results-part2.json`. The History, Progress and report screenshots were taken before the two fixes above.

## Evidence

Screenshots and `smoke-results.json` are in `nextjs_app/artifacts/final/`, which is gitignored by the root `.gitignore` (`artifacts/`). The smoke script is in the session scratchpad. It prints statuses only: no env values, tokens or message bodies.
