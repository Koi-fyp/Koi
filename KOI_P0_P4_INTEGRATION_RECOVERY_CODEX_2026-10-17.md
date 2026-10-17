# KOI — Chat Continuity and Integration Recovery Plan (17 October 2026)

## Status and evidence hierarchy

**First objective (P0):** Do not lose the current chat when navigating `/chat` → Progress/Profile → `/chat`, or `/chat` ↔ `/companion-scene`. Preserve one conversation across page changes and browser refresh, within the intended retention rules. P0 completion is required before jigsaw, retention, or voice/video wiring.

**Inspect the *local* repo first:** `C:\Users\PMYLS\Koi`, branch `feat/avatar-webview-host`. The currently published Web branch inspected for this plan is `40be37e`; M13 Firebase and transport changes and possibly M14 changes remain local/uncommitted, so published code is NOT necessarily the exact running build. Do not silently reset/merge to match it. The developer ran Next.js `14.2.35` on `http://localhost:3000` with a temporary 1024 MB Node heap and ~0.52 GB physical memory free after compiling routes. Three HTTP 200 route checks are NOT proof of live authenticated chat.

**Sources to read, in order:**
1. Local code and tests (observed present behavior supersedes old implementation-status prose).
2. Current live/backend authoritative contract `repos/koi-ai-engine/docs/contracts/KOI_CLIENT_CONTRACT_v1.md` and Ahmad's deployment notes: distinguish deployed v1 from planned v1.1; only deploy-confirmed behavior may be called live.
3. `KOI_ULTIMATE_MASTER_BLUEPRINT_v4_13.md` (file may have `(1)` suffix outside repo): §3.1 and §3.1a (client-side encryption, salt, trust boundary), §3.2 (avatar bridge), §4.1 and §4.1f (client-authoritative stateless session history, sliding-window design), §4.1g (check-in), and §7 gates.
4. `TRACK_WEB_AVATAR_PATCHED_v4_9.md`, `TRACK_FLUTTER_MOBILE_PATCHED_v4_8.md`.
5. `KOI_UX_FLOWS_LOCKED_v1_1.md` if actually present; do not invent missing details.
6. `KOI_CODEX_MASTER_BLITZ_2026-10-17.md`, `KOI_M11_CONTRACT_INTEGRATION_BLITZ.md`, `WEB_BLITZ_STATUS.md`, and current local change history.

**Source conflicts:** Source-of-truth is not one document saying everything is implemented. The Blueprint often specifies target requirements and contains superseded historical statements; actual code shows implemented state. The 24-hour ephemeral UX and exact jigsaw award rules are *not confirmed as locked* by the provided Blueprint excerpt; identify further authoritative UX/product decisions, then report unresolved choices rather than invent policy.

## Known code issues to verify locally

- `src/hooks/useConversationSession.ts`: a new `ConversationSession(adapter)` is created within the route-mounted hook. Its effect deactivates/cancels on unmount.
- `src/lib/conversation/ConversationSession.ts`: defaults `conversationId = crypto.randomUUID()`; constructor snapshot starts with empty messages. `send()` uses only last five completed messages for `session_history`. The session's in-memory status and exercise state can be lost upon remount.
- `src/hooks/useChat.ts`: creates its own per-hook session; history rehydration filters `db.messages` by **the newly created session ID**, so existing persisted rows with the previous ID aren't restored.
- Both `/chat` and `/companion-scene` mount `useChat()` independently; merely switching modes causes a new thread. In-flight streaming can be aborted when the former screen unmounts.
- `src/lib/conversation/conversationService.ts`: saves encrypted user and assistant messages to Dexie, then queues the same encrypted data for Firestore. Current queue path is `conversations/{cid}/messages/{mid}` whereas an owner-scoped `users/{uid}/conversations/{cid}/messages/{mid}` path was agreed **in principle**, not yet deployed. Do not unilaterally change paths/rules or claim Firestore storage success.
- `src/lib/db.ts`: existing `messages` indexed by `conversationId`, with no conversation-header record or owner UID on each legacy message. Separate jigsaw table exists but UI is not wired to it.
- `src/app/(authenticated)/progress/page.tsx`: placeholder statistics/milestones/pieces (e.g. 247 pieces, fake heatmap) exist. Do not call those real user progress.
- `src/app/(authenticated)/chat/page.tsx`: published source hardcodes `/Male.png`; `/companion-scene` resolves a saved choice independently. There may be additional uncommitted M14 fixes; do not overwrite them.
- `src/components/companion/ConversationControls.tsx`: microphone and camera deliberately disabled in main flow. Separate `/voice-lab` and `/speech-lab` are local experiments, not verified deployed media paths.

## Stage P0.0 — Evidence, build identity, protection (read-only)

1. Run `git branch --show-current`, `git rev-parse HEAD`, `git status --short`, `git diff --stat`, and enumerate ignored/untracked changes **without exposing secrets**. Do not run `git clean`, `git reset`, `git stash` or modify `.env.local`.
2. Identify which exact local files, routes, and tests are in use. Capture frontend build type (Next dev), branch, SHA, dirty-status indicator, API origin **without exposing credentials**, and backend deployment label **only if the backend proves it** (e.g. response header/version endpoint). Do not infer live version from git branch.
3. Inspect current Web and Flutter responsibilities; don't change Flutter. Inspect any open local Codex changes before creating new ones.
4. Reproduce: anonymous sign-in as an authorized developer, send ordinary non-sensitive English messages, visit Progress, return, note whether messages disappear, whether sending uses prior history, then switch to `/companion-scene`, browser-refresh and return. Use mocked SSE for deterministic tests; real Modal only when approved and auth configured. Do not log bearer ID tokens, message bodies, salts, private keys or `done.trace`.

**Gate:** baseline failure reproduced and owner/lifecycle/persistence root cause documented. Report actual live verification separately from mocks.

## Stage P0.1 — One conversation across route navigation (implement first)

Design a shared conversation lifecycle **above** `/chat` and `/companion-scene` (for example an authenticated layout-level provider or an equivalent owner-scoped session manager). Reuse existing `ConversationSession`, `useChat`, `conversationService`, and `useConversationSession`; do not create a second transport/service/database. Ensure:

- The same UID + conversation ID and same session object serve both text and 3D views. Switching routes must not mean New Chat.
- Display components subscribe/unsubscribe without deactivating/canceling the underlying session on ordinary navigation. `End session`, `Cancel reply`, `New Chat`, logout/account change, actual expiry and explicit termination maintain distinct, tested semantics.
- In-flight SSE should continue safely when navigating within the authenticated app, unless there is an explicit cancellation. UI reattaches with no duplicate provisional bubble and no resubmitted POST. If continuing SSE without a mounted UI is not feasible, preserve the user turn, mark interruption clearly and offer safe retry; NEVER silently lose text or duplicate inference requests.
- Keep existing assistant `companion_state`, signed exercise-state, events, and crisis-handoff safety. Do not accidentally replay UI actions or a handoff across navigation. Never treat absent risk as LOW.
- Ownership follows Firebase UID; switching accounts purges live in-memory state and prevents access to the previous user's ciphertext/plaintext. Avoid cross-tab race conditions where feasible.
- Do not alter the deployed v1 JSON text request contract or enable audio/video.

**Acceptance:** sign in → send two messages → navigate to Progress/Profile and back repeatedly → same conversation ID, exact same two turns, no new request, no duplicate bubbles; switch `/chat`↔`/companion-scene` and repeat. Exercise/risk UI stays safe through navigation.

## Stage P0.2 — Durable encrypted recovery after refresh (implement second)

Inspect existing Dexie schema, encrypted message records, crypto, Firestore sync and auth boundaries. Introduce the smallest additive, backward-compatible conversation metadata/indexing solution (e.g. a Dexie v2 `conversations` table keyed by UID+conversation ID, with `lastActiveAt`, `createdAt`, `status`, and expiry metadata **only after the policy is defined**). Avoid plaintext history in localStorage/sessionStorage. A non-secret per-user active conversation pointer may be stored in a suitable owner-scoped indexed record.

- Persist a stable active conversation ID with UID ownership; never choose a fresh ID when an eligible active one exists.
- Rehydrate the exact same encrypted messages by that ID before allowing a subsequent send; decryption uses `getActiveCryptoContext`, retaining salt/key policy. Show loading/locked/error state rather than accepting a new message with empty history.
- Preserve original message IDs, roles, order, timestamp, emotion/companion metadata, and previously completed turn context. Handle user row saved but assistant missing due to error/abort, pending bubbles, duplicate SSE done, failed decrypt, IndexedDB unavailable, unavailable Firestore, and page refresh while sending.
- Existing v1 message rows have no UID association. **Do not automatically attach old orphaned `conversationId` rows to another user** or delete them. Document safe recovery options, only recover when ownership/cryptographic provenance is proved. No blanket database clear, no schema reset.
- Keep privacy: CSE at rest, no plaintext Firestore writes, no fabricated E2EE claims. Keep current sync path until Ahmad/Irsa authorize coordinated schema + rules migration. Any remote sync remains best-effort with honest UI status.
- Preserve `session_history` semantics from the Blueprint (§4.1f): current recent raw-turn handling is not full long-term memory; don't introduce unreviewed summary/embedding jobs in this hotfix.

**Acceptance:** send messages → navigate → refresh → close/reopen tab → restore same active conversation; send follow-up and verify valid prior user/assistant turns are sent within the backend contract's history window; no cross-account leak. Offline storage, failed crypto, and partial turns are tested.

**Do NOT proceed to P1–P4 if P0 gates fail.**

## Stage P1 — Avatar consistency and emotion

Reconcile current (possibly uncommitted) M14 fixes before editing. Onboarding Aisha/Raza selection -> UID-scoped saved preference -> `/Female.png` or `/Male.png` and female/male VRM. Legacy fox must not silently become male (current Blueprint v4.10 scope favors two MVP avatars). Test navigation, reload, mobile widths, missing assets. Connect verified `companion_state` SSE to `VRMAvatarRenderer` with valid emotion mapping `neutral|joy|angry|sorrow|fun` and idle/listening/thinking/speaking state. Distinguish **animated facial emotions** from **speaking lip-sync**, which requires real speech audio and cue alignment. Use fixtures and real authenticated English chat where available; no claim of end-to-end success without live proof.

## Stage P2 — Jigsaw wiring and real progress

Audit `/progress`, `db.jigsawProgress`, check-in, exercises, task completion, chat completion and any canonical UX flows. The provided master blueprint explicitly noted the **jigsaw/gamification model was open**; don't silently select award rates, streak logic, milestones or eligibility criteria. Produce proposed award rules and request product approval if needed. Implement only decisions that can be grounded in approved UX flow / code tests. Use a deterministic idempotent domain-event ledger (`eventId`, UID, event type, source ID, completedAt, reward version), with derived aggregate `pieces_by_source` and `jigsaw_pieces`; prevent double-credit on navigation/reload/retry. Scope to UID and use reviewed persistence and encrypted storage for sensitive check-in values. Do not award points for crisis severity or for revealing traumatic/suicidal content. Replace fake `totalPieces=247`, hardcoded milestones and random heatmap with real data or explicitly labelled demo state. Test one genuine completion increments once, repeated actions/reloads don't, another UID doesn't inherit it, and offline progress reconciles without duplicates.

## Stage P3 — 24-hour temporary chats vs backend storage

Treat "disappear after 24 hours but remain stored in backend" as a **product requirement to confirm**, not evidence of an implemented backend. Decide: TTL from creation or last activity? Is expiration only removal from the visible active list, an encrypted archive, or deletion from all devices/cloud backups? What consent/retention disclosure applies? Existing FastAPI is designed for stateless inference with client-supplied `session_history`; encrypted Firestore sync is a separate path and **not confirmed deployed**. Do not falsely imply Modal permanently stores chats, and do not label chats "deleted" if encrypted archives remain.

After the product decision, implement server-time-resistant expiry checks, user-visible notices, account-specific cleanup, retention metadata and Firestore behavior with Ahmad's ownership and Irsa's parity. Decide what happens to current `session_history`, summaries, crisis safety, jigsaw evidence, open tabs, offline devices, and overdue sync queues. Design migration and purge tests before deletion code. Do not expire chats after ordinary route navigation; ensure 24-hour expiry is separate from UI lifecycle. Never erase user content by interpreting an unset timestamp as expired.

## Stage P4 — Media, avatar speech, and Flutter handoff

Preserve text-only production until confirmed deployed schema, privacy, permissions, and real-device tests. Inventory local `/speech-lab`, `/voice-lab`, Piper, Rhubarb, ASR, existing VRM viseme mapping and speech timeline. Stage A: TTS of confirmed assistant text with audible playback and time-aligned cues to VRM (test voice quality and language). Stage B: explicit-permission microphone capture -> local ASR/transcript review or documented backend audio path -> correct turn submission without duplicate text+audio modes. Stage C: video/face optional with consent, size/duration budget, denial and modality dropout. Follow the **current** backend v1.1 contract only when Ahmad confirms deployment and smoke-tests it; never infer multipart behavior from a proposed contract. Restrict to allowed combinations Text-only, Audio-only, Text+Video, Audio+Video for crisis modality integration, as specified in Blueprint §4.1a; don't invent unsupported video-only or text+audio. Raw media shouldn't be stored beyond processing; make retention auditable. Preserve hardcoded crisis fallback/Flow4 and don't send media into WebView bridge or leak Firebase tokens. Flutter WebView renderer is display-only and must use `KoiBridge` without calling the API or receiving auth tokens; physical Android Gate 2-J belongs jointly to Web and Flutter owners.

## Verification matrix (each gate records PASS/FAIL/NOT RUN)

- Local build identity: exact branch, SHA, dirty state, dev/prod, host/port; backend deployed version independently attested or UNKNOWN.
- Baseline chat persistence: route navigation, mode switch, browser refresh, tab close/open, offline/locked/unavailable DB, logout and account switch, 24-hour boundary once defined.
- API: legitimate Firebase JWT, `/health` result, real SSE `companion_state`, incremental deltas, `done`, empty reply, errors, abort, safe retry, 303/cold-start tests with no blind POST replay. No tokens or debug `trace` logged.
- Crypto: salt sourcing, AES-GCM roundtrip, ciphertext at rest, regression, retained legacy encrypted rows, no Firestore plaintext.
- Avatar: preference 2D and 3D, neutral/joy/angry/sorrow/fun states, error fallback, screen sizes, VRM resources cleanup, no duplicate WebGL loops.
- Jigsaw: source event completion, idempotency, person isolation, offline reconciliation, real statistics vs demo.
- Media: separate mock vs local lab vs real device vs production integration evidence; permission, stop/cleanup, cancellation and raw-media retention.
- Performance: memory budget on 7.73 GB RAM; only one Next dev server; serial tests where possible; avoid all tests/build/dev server concurrently.

## Non-negotiable restrictions

Do not commit, push, merge, deploy, reset, clean, or remove files. Leave `.idea/` and `repos/koi-mobile/android/` untouched. Do not read/print/diff `.env.local`, any Firebase credentials, service account keys, private conversation bodies, raw Bearer tokens or `done.trace`. No unauthorized Firebase rules/Firestore path migration, no forced DB schema wipe, no cloud inference substitutions, no crisis policy weakening. Run cheapest relevant tests after each stage, then `npx tsc --noEmit --incremental false`, relevant Jest and smoke scripts, `git diff --check`; only run full Next build with memory availability and one-server discipline.

## First implementation instruction

**Execute P0.0 → P0.1 → P0.2 only.** Do not begin P1, P2, P3 or P4 in the same Codex run. Keep progress in a concise local handoff report with precise statuses and screenshots/test results where feasible. Include manual reproduction steps and the *first* unresolved blocker. Finish with current git status and file change list. Stop only on a truly destructive/security decision or an authoritative contract ambiguity that would cause data loss; otherwise choose the smallest safe solution and implement it.
