# MESSAGING REPORT (client-side batch)

START=5d062c85959ec3e674b537527691311ec673598e, branch integrate/web-ahmad, node v20.12.2, tree clean at start.

## PART 0 - VERIFY (code only)

(a) CareConversation [FILE src/components/patient/CareConversation.tsx:10-47]: props `{api, relationshipId, professional?, onError}`. Loads messages+appointments once (no polling), shows `sender_uid` raw, sorts by created_at string compare, "More messages" button for next_cursor, plain POST (`{relationship_id, body}`, textarea maxLength 4000), no optimistic UI, no retry state; generic error text; errors go to `onError`. Fresh-auth is NOT handled in the component: it is done inside `api.request` via `beforeMutation` (RecentAuthentication dialog). Not modified.

(b) Routes: GET `/api/v1/relationships/{id}/messages` -> `communityRoute('messages')` [FILE src/lib/platform/server/community-http.ts:37] -> `conversation()` [FILE src/lib/platform/server/community.ts:183-192]. Allowed query: `limit` (1..100, default 25), `cursor`. POST `/api/v1/messages` body `{relationship_id, body}`; body 1..4000 chars (JSON-schema code points) [FILE contracts/v0.5.2/contracts.schema.json:2311-2321], whitespace-only -> 422 [FILE community.ts:134]. Needs `Idempotency-Key` (schema `Id`); 201 + HumanMessageDTO. `sendMessage` calls `fresh(actor)`: auth_time age > 300 s -> 401 `unauthenticated` [FILE service.ts:23-26].
ORDER: Firestore `orderBy(documentId())` [FILE firestore-store.ts:19]; message id = `message_${hash(idempotency receipt id)}` -> ORDER IS BY HASH, NOT TIME. The first page is therefore NOT the newest. Every poll must load all pages and sort by created_at client-side. List does return all pages only via next_cursor (cursor bound to actor+scope+relationship revision).
Idempotency: `professionalApi` keeps `pendingKeys` keyed by fingerprint JSON([method,path,body]); key is created on first send, KEPT on network error/5xx, DELETED on <500 error and on success [FILE src/lib/platform/client.ts:24-40]. Consequence: a retry reuses the key only if path+body are byte-identical; two in-flight sends of identical text would share a key (server would dedupe the second) -> the UI must send sequentially. `beforeMutation` (re-auth dialog when auth_time >= 240 s) runs for every non-GET/PATCH, including notification mark-read.
DTO [FILE src/lib/platform/community-types.ts:1]: HumanMessage `{id, relationship_id, sender_uid, body, created_at}`. No per-message read state.

(c) CareNotification `{id, event_id, kind: new_message|appointment_change|assignment|application_state, reference:{message_id}|..., created_at, read_at?}` - NO relationship_id in the DTO, so a notice can only be tied to a conversation by matching `reference.message_id` against loaded messages. GET `/api/v1/notifications` ordered by hash id too, limit<=100, cursor; each page re-checks access per item (`noticeAccess`), and the first page also materializes assignment notices [FILE community.ts:193-247]. POST `/api/v1/notifications/{id}/read` body `{}`; idempotent (`read_at ?? now`), does NOT require fresh auth server-side. CareNotifications [FILE src/components/patient/CareNotifications.tsx] shows kind + time + "Mark read" for loaded items only.

(d) Navigation: `platformLinks(caps)` builds links purely from server CapabilitiesDTO [FILE src/lib/platform/navigation.ts:4-17]. A patient "Messages" link ALREADY exists (`/patient?view=messages#care`); no professional one. PlatformNavigation [FILE src/components/platform/PlatformNavigation.tsx] polls capabilities (navPollMs) with its own `professionalApi` (no beforeMutation). It scrolls to `#id` if the element exists. PatientWorkspace reads `?view=` once; 'messages' currently renders the whole page (no dedicated screen) and requires an active relationship. ProfessionalWorkspace: any `view` other than 'questionnaires' sets `showPatients`.

(e) Titles: caps give only `psychologist_uid` per patient relationship; professional roster (`GET /api/v1/professional/patient-relationships?organization_id=`) gives `patient_uid`. No display names anywhere -> titles "Your psychologist" / "Patient" + short id (last 4 of uid) when more than one conversation.

(f) Firestore reads per call (READ-ONLY count from code, estimates):
 - list messages (patient): participant = 1 (relationship) + patientRelation 6 (account, relationship, + authority: account, verification, org, membership) = 7, plus the query returns min(N, limit+1) docs -> ~7+N per page (psychologist: 5+N).
 - list notifications (patient): ~2+2A (assignment sweep, A assignments) + 1 account + M returned + per-item access check ~7M -> ~3+2A+8M; (psychologist ~3+6M).
 - mark read: ~1 account + 1 notice + access (5-7) + 1 write.

(g) Tests asserting menu items: [FILE src/__tests__/platform/navigation.test.tsx:12-27] (arrayContaining Messages; link 'Messages' by name). No expected-list needs changing as far as I can tell.

(h) [FILE src/lib/platform/poll-config.ts] exists (`parsePollMs`, accessPollMs, navPollMs). Reused; not modified.

## RESULTS

| Part | Result | Notes |
|---|---|---|
| 0 Verify | PASS | above |
| 1 Menu | PASS (code+tests, no live run) | patient "Messages" existed, href changed to `#messages`; professional "Messages" added; badge on the item; screens mounted at `?view=messages` |
| 2 Screen | PASS (RTL tests, no live run) | list (cap 10), chat pane, optimistic send, same-key retry, separators, scroll/jump, composer rules, a11y live log |
| 3 Notifications | PASS (RTL tests, no live run) | badge 9+, `(n) KOI`, toast without text, per-conversation unread via message ids, sequential mark-read (cap 20), opt-in generic desktop notice |
| 4 Polling | PASS | `src/lib/platform/messaging/poll-config.ts`, `poller.ts`; fake-timer tests |
| 5 Tests | PASS | `npx tsc --noEmit --incremental false` clean; 4 new suites = 43 tests; FULL `npm test -- --runInBand`: **93 suites, 778 tests, all passed** (one full run) |
| 6 Docs+commit | PASS | see MESSAGING_README.md; NOTE `.local/` is gitignored, so README/REPORT/PROGRESS are on disk but NOT in git |

START=5d062c85959ec3e674b537527691311ec673598e. Commits (explicit paths): PART 4, PART 2, PART 3, PART 1, PART 5 (see `git log --oneline START..HEAD`). Order differs from numbering because Parts 2/3 import Part 4.

## Edited EXISTING files (and why)
- `src/lib/platform/navigation.ts` - patient Messages href `#care` -> `#messages`; new professional Messages link (only when `professional_workspace`).
- `src/components/platform/PlatformNavigation.tsx` - calls `useUnreadMessages`, renders badge on the Messages link and the "New message" toast.
- `src/components/patient/PatientWorkspace.tsx` - `view=messages` renders `MessagesScreen` (after the existing active-relationship guard).
- `src/components/professional/ProfessionalWorkspace.tsx` - `view=messages` mounts `MessagesScreen`; `view=messages` no longer auto-opens the patients panel.
- NO existing test was edited. CareConversation.tsx untouched. No forbidden path touched.

## New files
`src/components/messaging/{MessagesScreen,ChatPane,useUnreadMessages}.tsx|ts`, `src/lib/platform/messaging/{poll-config,poller,model,thread,unread-store,desktop}.ts`, 4 test files under `src/__tests__/platform/messaging-*.test.ts(x)`.

## Estimated Firestore reads per tab-hour at defaults (ESTIMATE from code, not measured)
Defaults: chat 8 s -> 450 polls/h, badge 30 s -> 120 polls/h, hidden tab 0.
- Open chat, patient, N messages (<=100, one page): (7 + N) reads/poll -> N=20: ~12,150/h; N=100: ~48,000/h. Psychologist: (5 + N) -> N=20: ~11,250/h. Over 100 messages each extra page repeats the 6-7 fixed reads.
- Badge poll (always on while any Messages-capable page is visible): patient ~(3 + 2A + 8M) per poll (A assignments, M notifications returned, <=100 per page, <=3 pages); A=2, M=10 -> 87 -> ~10,400/h. Psychologist ~(2 + 6M): M=10 -> 62 -> ~7,400/h.
- Mark read ~10 reads/notice, one-off. Opening the list: ~(7+N) per conversation once (<=10 conversations).
- One patient tab with an open 20-message chat + badge: ~22,600 reads/h => the 50,000/day Spark read quota lasts about 2 h of one visible tab (two users: about 1 h). Env knobs `NEXT_PUBLIC_KOI_PLATFORM_MESSAGE_POLL_MS` / `..._UNREAD_POLL_MS` (e.g. 20000 / 90000) cut this ~2.5x.

## Deviations / honest limits
1. "Showing latest 300": message ids are hashes so the server's first 300 are NOT the latest 300. The UI says "Showing 300 messages. This view is limited to 300, so some messages may not appear." instead of claiming "latest".
2. Notification DTO has no relationship id, so per-conversation unread is only known for conversations whose messages were loaded (list loads each of <=10 conversations once on open; a notice matching no loaded message triggers one preview refresh, then is ignored).
3. Desktop notifications cannot fire while the tab is hidden (hidden = no polling, per spec). They fire only for a visible-but-unfocused window. True background alerts need push (FCM + service worker) - [GUESS: out of scope here].
4. Tab hidden/offline/capabilities error clears `caps` in PlatformNavigation (existing behaviour), which releases the unread poller; on return it restarts and the first poll never toasts (badge still updates).
5. Switching conversations remounts the chat pane: unsent/failed bubbles and the draft of the previous conversation are dropped. In-flight sends still complete.
6. Identical text sent twice shares an Idempotency-Key (client derives key from method+path+body) so sends are serialised; a *failed* bubble plus a new identical text is effectively a retry.
7. A server 401 on send (stale auth_time despite the client's 240 s hint) shows "Not sent. Tap to retry"; the retry goes through the existing re-auth dialog. 401/403/404 on polling stops polling and clears data (404 added to the spec's 401/403).
8. Both nav instances on the home page share one poller (module store, first mounted leads).
9. Nothing was run live: no server, no browser. Layout (two panes >= md, one pane + back button below) is [GUESS] from Tailwind classes, not seen.

## BLOCKED-BY-PERMISSION
None.

## Proposals needing forbidden files (not implemented)
1. Cheaper polling (server): `GET /api/v1/relationships/{id}/messages?since=<iso>` or `order=desc&limit=N`, and `GET /api/v1/notifications?unread=true` plus `relationship_id` in NotificationDTO. Would cut most reads and make "latest 300" and per-conversation unread exact.
2. Read state, additive contract 0.5.3: `PUT /api/v1/relationships/{id}/read-cursor` body `{ last_read_message_id }` (monotonic, idempotent, participant only, no fresh-auth); record `conversation_reads/{relationship_id}__{reader_uid}` `{relationship_id, organization_id, reader_uid, last_read_message_id, last_read_at}`; `HumanMessageListDTO` gains optional `peer_last_read_message_id`; Firestore rules: client read/write denied (Admin SDK only), same as `messages`. UI would then add Seen ticks.
3. Push for background alerts: FCM token registration endpoint + service worker (new routes under `src/app/api/**`, `public/**`).

## Decisions for Ahmad
- Raise default poll intervals before a shared demo on Spark (see read estimate)?
- Accept honest "300 messages" wording instead of "latest 300"?
- Want the server-side proposals (1)/(2) in the next contract slice?
- Commit `.local/ahmad/*` (currently gitignored)?
