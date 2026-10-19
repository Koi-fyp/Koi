# Authentication and local ownership evidence

Source inspected on 2026-10-19 at main worktree HEAD
`1390f1b3da96270ad47d8edfa06510ed838add77`. No private IndexedDB, browser session,
Firestore documents, Auth users, tokens or credential contents were inspected.
Findings below describe code paths and possible failures, not observed user-data leaks.

## Actual authentication lifecycle

| Stage | Default web path | Development test path |
| --- | --- | --- |
| Entry | `AuthContext.signInAnonymously` POSTs `/api/auth/anonymous` | Only `NODE_ENV=development` AND `NEXT_PUBLIC_KOI_LOCAL_TEST_ANON=true` |
| Identity creation | Server generates a new UUID and calls Admin `createCustomToken(uid)`; initializes `users/{uid}` | SDK `signInAnonymously(auth)` after hardcoded project check `koi-companion-fyp` |
| Session establishment | Browser exchanges the custom token using `signInWithCustomToken` | Firebase creates/restores an anonymous-provider identity |
| Meaning | Authenticated custom-auth **guest**, not proven registered General | Firebase Anonymous Auth guest |
| UI identity | `isAnonymous` directly mirrors SDK user flag; `isLinked` also requires password provider | Anonymous SDK flag is available, but remains a guest regardless |
| Persistence | Firebase SDK persistence and `onAuthStateChanged`, not custom session encryption | Same Firebase persistence/listener |
| API calls | Browser obtains Firebase **ID token** with `getIdToken`; custom token itself is not the API token | Same ID-token path |
| Upgrade | Current `/api/auth/link-email` verifies ID token, Admin-updates current UID with email/password and returns a generated email verification link | Same web linking endpoint; not the SDK linking path |
| Logout | SDK sign-out plus React user reset; no general queue/local ciphertext purge in AuthContext | Same |

Evidence: `src/contexts/AuthContext.tsx:95,115,121,158,188`,
`src/lib/auth/anonymousSignInMode.ts`,
`src/app/api/auth/anonymous/route.ts:5`,
`src/app/api/auth/link-email/route.ts:20`.

Important reconciliation points:

- A successful custom-token exchange does not establish account registration. Do not
  assume the anonymous flag will identify this default guest. Current runtime provider
  flags/claims were not inspected; exact client behavior still needs a synthetic auth test.
- The anonymous server endpoint has no rate-limit or registration ledger in inspected
  code; each new call mints a fresh UUID. Firebase-persisted reload is distinct from
  creating another guest after logout. Never claim/import the old guest automatically.
- Web Admin `updateUser` preserves UID but is not web `linkWithCredential`. It receives
  the password in the application server and returns generic failure for collisions.
  It does not reload the SDK user/force-refresh claims or invoke encryption migration.
  `verifyIdToken(idToken)` here does not request revocation checking.
- Returning the generated verification link to its caller is not inbox-possession
  verification. Therefore the new registration authority requires its own hashed,
  server-delivered challenge; legacy `users.emailVerified` or Firebase email flag alone
  cannot satisfy that requirement. No legacy route was modified.
- AuthContext observes auth-state changes, not explicit token refresh/revocation events.
  New privileged handlers must validate current server authority on every request;
  token claims can be hints, not the membership database.
- Encryption uses UID salt caches but one browser-global `koi_anon_secret`. Linked
  encryption expects the session password; no returning-user unlock input is wired in
  the inspected provider. `reencryptOnLinking` only transforms supplied payloads: no
  migration manifest, upload verification or automatic call from linking exists.
- `../flutter_lib/lib/services/auth_service.dart` uses genuine SDK anonymous auth and
  `linkWithCredential`, but its secure-storage `koi_user_uuid` is separate from Firebase
  UID. `isAuthenticated` can return true from that stored UUID even without a Firebase
  session. This is not a valid backend authentication authority.

## Dexie and other cache ownership

| Store/key | Actual keys and ownership | Risk / proposed boundary |
| --- | --- | --- |
| Dexie `users` | Auto-increment ID; **nonunique** UID index | `.first()` hides duplicates. Onboarding read/add is outside a wrapping transaction and concurrent calls can create duplicates. Do not silently delete/merge; inventory by UID and preserve conflicting rows. |
| `messages` | Global primary key `id`; `ownerUid` optional and not indexed | Current history/session readers filter exact owner and reject ownerless legacy rows. A future reused imported ID could overwrite another owner's row via `put`; migration must verify destination identity/owner before writing. |
| `conversations` | Primary key UID; one active encrypted header per UID | Snapshot validates owner; existing switch uses transaction/revision guards. Reuse this owner model, no duplicate companion store. |
| `conversationArchive` | Unique composite `[uid,conversationId]` | Explicit ownership and local-only archive; keep partitioned, never professional data. |
| `moodEntries` | Global `id`, indexed `userId` | Legacy table; inspect owner on any future import/read. Current check-in writer uses encrypted activity events instead. |
| `jigsawProgress` | UID primary key | Current progress model validates selected UID. Not a clinical score or questionnaire analytics source. |
| `activityEvents` | Global event ID plus unique `[owner_uid,source_type,completion_id]` | Ledger validates current owner and aborts on auth change. Global ID conflict is rejected; do not reinterpret it as ownership or auto-merge. |
| `rewardReceipts` | Owner/source/day and owner/slot unique constraints | UID-filtered ledger; no new reward/sync behavior proposed. |
| `milestoneReceipts` | Owner/milestone unique constraint | UID-filtered; leave untouched. |
| Dexie `syncQueue` | Auto-increment ID; no explicit owner field | Declared store; active production queue imports resolve to **localStorage implementation**, not this table. Do not mistake it for the queue in use. |
| localStorage `koi_sync_queue` | Single global JSON array; collection/doc/data/priority/timestamp | No owner field, revision precondition, schema allowlist or per-item UID guard in replay. Owner-targeted rules are a critical backstop, not a local ownership guarantee. |
| `koi_anon_secret` / `koi_salt_cache_{uid}` | Global anonymous secret / UID-specific salt | Never migrate/export secret as account data. Global secret retention is an isolation risk if another reader omits ownership; existing history safeguards reduce exposure but do not prove every path. |
| `koi_onboarding_complete_{uid}` | Per-UID flags with guarded legacy migration | **Corrects older report:** current source already avoids reading another UID's global completion flag. |
| Input mode preference | Browser-global UI preference | Nonclinical device setting; do not infer account authorization from it. |
| Preference sync maps/listeners | UID-keyed status/task maps, owner checks around awaits | Current hook hides prior-owner profile during UID change. New protected caches must clear/partition and invalidate independently. |

Evidence: `src/lib/db.ts:95`, `src/lib/firestore/sync.ts:13,53,80`,
`src/lib/firestore/messageSync.ts`, `src/lib/history/readHistory.ts`,
`src/lib/history/ownedDecryptor.ts`, `src/lib/conversation/PersistentConversation.ts`,
`src/lib/preferences/{userPreferences,preferenceSync}.ts`,
`src/lib/onboarding.ts:55`, `src/lib/activities/activityLedger.ts`.

### Queue findings in detail

Legacy root-message repathing explicitly requires `data.ownerUid === current uid`
and matching IDs. Existing tests cover that useful safeguard. However, already
repathed `users/A/...` items and generic `users/A` writes pass `flushOnce`'s filter
when B signs in: replay checks **legacy path shape**, not ownership of every item.
Correct rules should deny foreign writes; wrong published rules would remove that
backstop. This is a source-confirmed attempted-write isolation gap, not proof of a
successful cross-account write.

`enqueue` attempts immediate SDK writes without a current-UID guard. Replay uses
merge writes without CAS/revision checking; an older pending write can overwrite a
newer field. Read/modify/write of a shared localStorage array is not transactional
across tabs. Dedupe keys use path + millisecond timestamp rather than a durable
operation ID. These are reasons **not to reuse this queue for platform data**.

New platform autosave is server-only with optimistic revisions. Future companion
queue hardening requires its owner's review and dedicated A/B/offline tests; this
task makes no change to queue, auth, encryption, database schema or companion transport.

### Migration policy to implement later

Use the frozen `MigrationManifestRecord`, explicit source ownership/claim consent,
stable destination IDs, content hashes, source/destination schema versions, encrypted
verification and server acknowledgements. Preserve both on conflict; ownerless records
remain blocked until authorized claim. UID-preserving linking still requires deliberate
key migration. No data/keys are removed before acknowledged verification. Neither
duplicate-row counts nor actual device migration success was measured in this audit.
