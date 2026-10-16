# P3 Section F report (raw and complete)

## Paths and commits read

* Web: `repos\koi-backend\nextjs_app`, commit `fa223ae 2026-10-11 01:41:34 +0500`.
* Dart: `repos\koi-backend\flutter_lib`, commit `fa223ae 2026-10-11 01:41:34 +0500`.
* Engine/report workspace: `repos\koi-ai-engine`.
* Both expected client paths existed. P1 was PASS-WITH-NOTES before this task.

## Full deliverables


### docs\contracts\firestore\FIRESTORE_ACCESS_INVENTORY.md


# Firestore / Firebase access inventory

Audit scope: `repos\koi-backend\nextjs_app\src` and
`repos\koi-backend\flutter_lib\lib`, read at Web/Dart commit
`fa223ae` (`2026-10-11 01:41:34 +0500`). This is an inventory of code
present in those working copies, not a statement about other branches.
IndexedDB, Hive, localStorage, and Secure Storage operations are included
where they explain a Firestore sync or crypto boundary.

## A. Firestore/Auth touchpoints

| file:line | operation | path pattern | fields written (exact key names) | who calls it | notes |
|---|---|---|---|---|---|
| `nextjs_app/src/app/api/auth/anonymous/route.ts:13-25` | `ADMIN` `get`, conditional `set` | `users/{uid}` | `koiUuid`, `createdAt`, `lastActive`, `profile.avatar`, `profile.language`, `profile.notificationTime`, `classification` (empty map), `settings.notifications_enabled`, `settings.sound_enabled`, `settings.haptic_enabled`, `stats.total_conversations`, `stats.total_check_ins`, `stats.current_streak`, `stats.longest_streak`, `stats.jigsaw_pieces` | `AuthContext.signInAnonymously` â†’ `POST /api/auth/anonymous` | Admin SDK bypasses Firestore rules. `uid` is a newly generated UUID. |
| `nextjs_app/src/app/api/auth/link-email/route.ts:28` | `ADMIN` merge `set` | `users/{uid}` | `email`, `emailVerified` | `AuthContext.linkWithEmail` â†’ `POST /api/auth/link-email` | Admin SDK bypasses rules; caller token is verified first. |
| `nextjs_app/src/lib/onboarding.ts:50-61` | `setDoc(..., merge:true)` | `users/{uid}` | `profile.avatar`, `profile.companion`, `profile.language`, `profile.notificationTime`, `onboarding_complete` | `completeOnboarding` | `notificationsEnabled` is persisted in IndexedDB but is not included in this Firestore write. |
| `nextjs_app/src/lib/crypto.ts:280-282` | `getDoc` | `users/{uid}` | none | `getActiveCryptoContext` | Reads `public_crypto_metadata.salt`. |
| `nextjs_app/src/lib/crypto.ts:310-313`, `lib/firestore/sync.ts:36,57` | queued/attempted `setDoc(..., merge:true)` | `users/{uid}` | `public_crypto_metadata.salt` | `getActiveCryptoContext` â†’ `syncQueue.enqueue` â†’ immediate write or online flush | Resolved queue template: collection `users`, docId `uid`. |
| `nextjs_app/src/lib/conversation/conversationService.ts:85-90`, `lib/firestore/sync.ts:36,57` | queued/attempted `setDoc(..., merge:true)` | `conversations/{conversationId}/messages/{messageId}` | `id`, `conversationId`, `sender`, `content`, `timestamp`, `emotion`, `emotion_confidence`, `synced` | `sendMessage` â†’ `saveMessage` â†’ `syncQueue.enqueue` | `content` is encrypted before the queued write. `conversationId` is supplied by the caller; this code does not prove it equals the authenticated UID. |
| `flutter_lib/lib/services/auth_service.dart:103-107` | `set(..., merge:true)` | `users/{uid}` | `koiUuid`, `email`, `emailVerified` | `AuthService.linkWithEmailAndPassword` | Firebase client SDK; credential is linked first at line 96. |
| `flutter_lib/lib/services/auth_service.dart:133-138` | `get`, conditional `set` | `users/{uid}` | On create: `koiUuid`, `createdAt`, `lastActive`, `profile.avatar`, `profile.language`, `profile.notificationTime`, `classification.primary_profile`, `classification.secondary_profile`, `classification.severity_tier`, `classification.ucla_score`, `settings.notifications_enabled`, `settings.sound_enabled`, `settings.haptic_enabled`, `stats.total_conversations`, `stats.total_check_ins`, `stats.current_streak`, `stats.longest_streak`, `stats.jigsaw_pieces`. Existing doc: `koiUuid`. | `AuthService.signInAnonymously` â†’ `createUserDocument` | `KoiUser.toMap()` is in `models/user_model.dart:30-43`. |
| `flutter_lib/lib/services/auth_service.dart:43-54,101,124`; `storage/hive_manager.dart:51-59` | Auth/local persistence, not Firestore | none | none | `AuthService.signInAnonymously`, `restoreSession`; Hive key and `koi_user_uuid` use `FlutterSecureStorage` | Included to identify device-local state; no additional cloud path. |

No Firestore `onSnapshot`, `writeBatch`, `runTransaction`, `addDoc`,
`updateDoc`, `deleteDoc`, or Firebase callable function use was found in the
audited client source. `db.ts` is Dexie/IndexedDB only.

### Distinct paths found

* `users/{uid}`
* `conversations/{conversationId}/messages/{messageId}` (the task's
  `conversations/{id}/messages` collection pattern)

For `users/{uid}`, the distinct top-level field names written are:

`koiUuid`, `createdAt`, `lastActive`, `profile`, `classification`, `settings`,
`stats`, `email`, `emailVerified`, `onboarding_complete`,
`public_crypto_metadata`.

Nested keys observed are:

* `profile`: `avatar`, `companion`, `language`, `notificationTime`
* `classification`: `primary_profile`, `secondary_profile`, `severity_tier`,
  `ucla_score` (the Web Admin create currently writes `{}`)
* `settings`: `notifications_enabled`, `sound_enabled`, `haptic_enabled`
* `stats`: `total_conversations`, `total_check_ins`, `current_streak`,
  `longest_streak`, `jigsaw_pieces`
* `public_crypto_metadata`: `salt`

## D. Auth and request wiring

* `AuthContext.tsx:104-113` calls `POST /api/auth/anonymous`; the returned
  custom token is passed to `signInWithCustomToken` at line 111. Firebase
  `onAuthStateChanged` at lines 79-88 supplies the current user.
* `AuthContext.tsx:119-127` obtains `auth.currentUser?.getIdToken()` and
  sends it as `Authorization: Bearer <ID token>` to
  `POST /api/auth/link-email`. The route verifies it with
  `adminAuth.verifyIdToken` (`app/api/auth/link-email/route.ts:14-17`).
* `app/api/auth/anonymous/route.ts` generates a UUID, creates a Firebase
  custom token with Admin Auth, ensures the `users/{uid}` document exists,
  and returns `{userId, token}`. It has Admin privileges.
* `lib/firebase.ts:6-11` reads these environment variable names only:
  `NEXT_PUBLIC_FIREBASE_API_KEY`, `NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN`,
  `NEXT_PUBLIC_FIREBASE_PROJECT_ID`, `NEXT_PUBLIC_FIREBASE_STORAGE_BUCKET`,
  `NEXT_PUBLIC_FIREBASE_MESSAGING_SENDER_ID`, `NEXT_PUBLIC_FIREBASE_APP_ID`.
* No active Firebase Cloud Function or `geminiClient` call was found in
  `src`; the conversation service explicitly uses the self-hosted HTTP
  endpoint. The API base variable is `NEXT_PUBLIC_KOI_API_BASE`
  (`conversationService.ts:42`), and the chat request at lines 106-111
  sends `Authorization: Bearer <ID token>`.


### docs\contracts\firestore\firestore.rules.proposed


rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    function isOwner(uid) {
      return request.auth != null && request.auth.uid == uid;
    }

    function userShape(data) {
      return data.keys().hasOnly([
        'koiUuid', 'createdAt', 'lastActive', 'profile', 'classification',
        'settings', 'stats', 'email', 'emailVerified', 'onboarding_complete',
        'public_crypto_metadata'
      ])
      && (!data.keys().hasAny(['profile']) ||
          data.profile.keys().hasOnly(['avatar', 'companion', 'language', 'notificationTime']))
      && (!data.keys().hasAny(['classification']) ||
          data.classification.keys().hasOnly([
            'primary_profile', 'secondary_profile', 'severity_tier', 'ucla_score'
          ]))
      && (!data.keys().hasAny(['settings']) ||
          data.settings.keys().hasOnly([
            'notifications_enabled', 'sound_enabled', 'haptic_enabled'
          ]))
      && (!data.keys().hasAny(['stats']) ||
          data.stats.keys().hasOnly([
            'total_conversations', 'total_check_ins', 'current_streak',
            'longest_streak', 'jigsaw_pieces'
          ]))
      && (!data.keys().hasAny(['public_crypto_metadata']) ||
          data.public_crypto_metadata.keys().hasOnly(['salt']));
    }

    // Inventory: FIRESTORE_ACCESS_INVENTORY.md rows for users/{uid}.
    match /users/{uid} {
      // Separate create rule: all observed client/Admin-created keys are allowed,
      // while unknown top-level and nested keys are rejected.
      allow create: if isOwner(uid) && userShape(request.resource.data);

      // Inventory rows for onboarding, crypto salt, email linking, and
      // AuthService's merge writes.
      allow update: if isOwner(uid)
        && request.resource.data.diff(resource.data).affectedKeys().hasOnly([
          'koiUuid', 'createdAt', 'lastActive', 'profile', 'classification',
          'settings', 'stats', 'email', 'emailVerified', 'onboarding_complete',
          'public_crypto_metadata'
        ])
        && userShape(request.resource.data);

      // No client row reads a user document except the owner.
      allow read: if isOwner(uid);
    }

    // Inventory row: conversationService.ts:85-90.
    // The message document has no owner field, and the code does not establish
    // that conversationId equals request.auth.uid. Safely owner-checkable
    // access is therefore intentionally denied pending the decision in
    // RULES_NOTES.md.
    match /conversations/{conversationId}/messages/{messageId} {
      allow read, write: if false;
    }

    // Default deny is last.
    match /{document=**} {
      allow read, write: if false;
    }
  }
}


### docs\contracts\firestore\RULES_NOTES.md


# Proposed Firestore rules notes

## Basis

The proposal is derived only from
`docs\contracts\firestore\FIRESTORE_ACCESS_INVENTORY.md`. It permits the
observed `users/{uid}` top-level and nested keys, with owner checks and a
separate create rule. Unknown fields are rejected. The message write is
observed, but is denied until ownership can be verified.

## Existing configuration comparison

The backend already contains `repos\koi-backend\firestore.rules`,
`firebase.json`, and `.firebaserc`. The existing rules allow owner reads and
writes for:

* `users/{userId}`
* `conversations/{userId}/messages/{messageId}`
* `mood_entries/{userId}/entries/{entryId}`
* `wellness_progress/{userId}`
* `tasks/{userId}/items/{taskId}`

The proposal is **stricter** for `users`: it rejects unknown top-level and
nested keys, separates create from update, and checks the authenticated UID.
It is **stricter** for messages: existing rules allow access when the
conversation path segment equals the UID; the audited client only supplies an
arbitrary `conversationId` and the message has no owner field. The proposal
therefore denies access rather than asserting an unverified relationship.
The proposal is **stricter** for the other three existing paths because it
does not include them: no audited client code writes those paths. It is not
looser than the existing rules for any path.

`firebase.json` configures Functions and emulators but does not configure a
Firestore rules file. `.firebaserc` contains project/hosting/function target
metadata only. The proposal does not overwrite either file or the existing
`firestore.rules`.

Firebase CLI is installed (`firebase`/`firebase.cmd` found), but the proposal
is a standalone file and is not wired into `firebase.json`; it was **NOT
syntax-checked** to avoid changing or deploying the backend configuration.

## UNDECIDED â€” needs field list from mobile

* Mobile onboarding answers and settings fields not written by the audited
  client code must not be added to rules. The requested future onboarding
  answers/settings contract is UNDECIDED.
* Whether `conversationId` is guaranteed to equal the authenticated UID, or
  whether messages should carry a server/client-written owner field, is
  UNDECIDED. Options: use UID as the conversation path segment, add a
  protected owner field with create-time validation, or introduce a parent
  conversation document whose owner is checked.
* Whether Admin-created user documents should be exempt from client create
  constraints is UNDECIDED; Admin SDK bypasses rules in any case.

## What rules cannot protect

* An owner can write arbitrary ciphertext and any permitted scalar/map values;
  rules do not attest plaintext meaning or cryptographic correctness.
* Admin SDK writes in the two API routes bypass Firestore rules.
* Rules cannot recover an anonymous secret, re-encrypt ciphertext, or make
  local storage/device state durable.
* Without an owner-bearing message document or a contract tying the path ID to
  the UID, rules cannot safely prove message ownership.


### docs\contracts\firestore\CRYPTO_AUDIT.md


# Client crypto audit

Audited at Web/Dart commit `fa223ae` (`2026-10-11 01:41:34 +0500`).

## Spec comparison

| Spec line | Result | Evidence |
|---|---|---|
| AES-GCM 256-bit | MATCH (Web and Dart) | Web `lib/crypto.ts:102-108` derives `{name:"AES-GCM", length:256}` and encrypts with AES-GCM. Dart `services/crypto_service.dart:31,90` uses `AesGcm.with256bits()`. |
| PBKDF2-HMAC-SHA256, 600,000 iterations | MATCH (Web and Dart) | Web `crypto.ts:37,101-106`: `PBKDF2_ITERATIONS = 600_000`, `hash:"SHA-256"`. Dart `crypto_service.dart:25,78-84`: `iterations: 600000`, `Hmac.sha256()`. |
| `v1:PBKDF2:base64(salt):base64(nonce):base64(ciphertext_with_mac)` | MATCH (implementation shape) | Web `crypto.ts:118-125`; Dart `crypto_service.dart:90-112` explicitly joins the five parts and appends the separate Dart MAC. Dart notes that byte-for-byte Gate 1-J verification is still pending. |
| Salt stored at `users/{uid}.public_crypto_metadata.salt` | PARTIAL / MISMATCH in Dart wiring | Web reads at `crypto.ts:280-282` and queues the write at `307-313`. Dart generates a salt at `crypto_service.dart:39-44` but contains no Firestore write or `uid` parameter in the crypto service. |
| Anonymous secret is random, device-local, not synced | MATCH (storage differs) | Web `crypto.ts:75-80` uses `localStorage`; Dart `crypto_service.dart:55-70` uses `FlutterSecureStorage`. Neither queues the secret. |
| Linked secret is per-session password, never stored | PARTIAL | Web documents the intended source at `crypto.ts:18-29` and requires `linkedSecret` at `crypto.ts:238-260`; `AuthContext.tsx:119-137` receives the password only for the link request and does not retain it. Dart passes the password to `linkWithCredential` (`auth_service.dart:96`) and does not persist it. |
| Anonymous ciphertext re-encrypted at linking | MISMATCH in active wiring | Web has a pure helper `reencryptOnLinking` at `crypto.ts:173-181`, but no caller was found. Dart has `clearAnonymousSecret` (`crypto_service.dart:67-71`) but no ciphertext migration or call from `AuthService.linkWithEmailAndPassword`. |

## Direct answers

1. The Web anonymous secret is in browser `localStorage` under
   `koi_anon_secret` (`crypto.ts:75-80`). The Dart equivalent is in platform
   `FlutterSecureStorage` under `koi_anon_secret` (`crypto_service.dart:55-70`).
2. Clearing that storage removes the secret. Existing ciphertext cannot be
   decrypted by the affected browser/device. A different browser/device has a
   different anonymous secret and cannot decrypt it. The Web salt cache is
   also local, although Web can fetch the salt from Firestore; the secret is
   not synced.
3. No recovery path for a lost anonymous secret was found. Linked sessions
   have no implemented password re-entry/unlock path in `AuthContext.tsx`;
   `getActiveCryptoContext` instead requires a caller-supplied `linkedSecret`.
4. The Web helper can re-encrypt payloads, but account-linking code never
   invokes it. Dart linking performs Firebase credential linking and writes
   metadata, but does not re-encrypt existing ciphertext. Therefore active
   code does **not** perform the required migration.
5. Web generates a 16-byte random salt in `crypto.ts:68-70` when an
   anonymous user's Firestore document has no salt (`crypto.ts:303-313`),
   caches it locally, and queues `users/{uid}.public_crypto_metadata.salt`.
   Web reads an existing salt at `280-282`. Dart has a generator at
   `crypto_service.dart:39-44`, but no observed call that writes that salt
   to Firestore.

No `.env*`, key file, service-account file, or secret value was read or
printed during this audit.


## UNDECIDED items

* Mobile onboarding answers/settings field list is not present in audited code.
* Message ownership is undecided: `conversationId` is not proven to equal UID and message data has no owner field. Options are UID path, validated owner field, or an owner-checked parent document.
* Whether Admin-created user documents are exempt from client create constraints is undecided (Admin bypasses rules).
* No anonymous-secret recovery path, linked-session password re-entry path, or Dart salt persistence wiring was found.

## Commands run and raw output

### `git log -1 --format='%h %ci'` (Web/Dart/Engine)

```
WEB
fa223ae 2026-10-11 01:41:34 +0500
DART
fa223ae 2026-10-11 01:41:34 +0500
ENGINE
fa223ae 2026-10-11 01:41:34 +0500
```

### Path/config/tool probe

```
E:\Koi\Koi-App\repos\koi-backend\.firebaserc
E:\Koi\Koi-App\repos\koi-backend\firebase.json
E:\Koi\Koi-App\repos\koi-backend\firestore.rules
NODE_MODULES
True
FIREBASE_CLI
C:\nvm4w\nodejs\firebase
C:\nvm4w\nodejs\firebase.cmd
C:\Users\ahmad\AppData\Roaming\npm\firebase
C:\Users\ahmad\AppData\Roaming\npm\firebase.cmd
```

### Protected hash verification (SHA-256 prefixes after CRLF normalization)

```
FC2D52A9E1D7 director.py
1A318EDFB932 policy.py
39BE0F36A002 intents.py
CA135C692C52 compose.py
9C56B1366F88 journeys.json
EBEEE43DB081 catalogue.py
2CB6BD501EB4 state_token.py
```

### Web test command

Command: `npm test -- --runInBand` (from repository root)

```
npm ERR! Missing script: "test"
npm ERR!
npm ERR! To see a list of scripts, run:
npm ERR!   npm run
npm ERR!
npm ERR! A complete log of this run can be found in: C:\Users\ahmad\AppData\Local\npm-cache\_logs\2026-10-15T23_17_23_850Z-debug-0.log
```

Command: `npm --prefix E:\Koi\Koi-App\repos\koi-backend\nextjs_app test -- --runInBand`

```
> koi-nextjs-app@0.0.1 test
> jest --runInBand

● Validation Error:

  Module <rootDir>/jest.setup.ts in the setupFilesAfterEnv option was not found.
         <rootDir> is: E:\Koi\Koi-App\repos\koi-backend\nextjs_app

  Configuration Documentation:
  https://jestjs.io/docs/configuration
```

### Existing Firebase configuration read (not modified)

`firestore.rules` currently allows owner-only writes for users, conversations/messages,
mood entries, wellness progress, and tasks. `firebase.json` configures Functions and
emulators; `.firebaserc` contains project/hosting/function metadata. The proposal was
not wired into this configuration. Firebase CLI was present, but the proposal was NOT
syntax-checked because it is not the configured rules file and no deploy/config change
was permitted.

### `git status --short` at audit time

```
 M repos/koi-ai-engine/app/api/routes.py
 M repos/koi-ai-engine/app/models/schemas.py
 M repos/koi-ai-engine/app/services/inference_service.py
 M repos/koi-ai-engine/rag_prototype/data/processed/annomi_chunks.jsonl
 M repos/koi-ai-engine/rag_prototype/data/processed/authoritative_chunks.jsonl
 M repos/koi-ai-engine/rag_prototype/data/raw/AnnoMI-full.csv
 M repos/koi-ai-engine/rag_prototype/data/raw/samhsa_2025_guidelines.txt
 M repos/koi-ai-engine/rag_prototype/data/raw/who_mhgap_sui.txt
 M repos/koi-ai-engine/rag_prototype/eval/dev_set.py
 M repos/koi-ai-engine/rag_prototype/eval/phase2b_smoke_test.py
 M repos/koi-ai-engine/rag_prototype/eval/run_dev_eval.py
 M repos/koi-ai-engine/rag_prototype/scripts/retier_annomi.py
 M repos/koi-ai-engine/rag_prototype/scripts/retier_authoritative.py
 M repos/koi-ai-engine/rag_prototype/scripts/retrieval_pipeline.py
?? docs/
?? koi-ai-enginekoi_policyadapter_qwen.py
?? repos/koi-ai-engine/AGENTS.md
?? repos/koi-ai-engine/agent_tasks/
?? repos/koi-ai-engine/app/services/risk_provider.py
?? repos/koi-ai-engine/deploy/
?? repos/koi-ai-engine/docs/
?? repos/koi-ai-engine/koi_policy/
?? repos/koi-ai-engine/rag_prototype/data/processed/mhgap_pk_chunks.jsonl
?? repos/koi-ai-engine/rag_prototype/data/raw/mhgap_hig_pk_bilingual.txt
?? repos/koi-ai-engine/rag_prototype/eval/.emb_cache/
?? repos/koi-ai-engine/rag_prototype/eval/ablation.py
?? repos/koi-ai-engine/rag_prototype/eval/after_prefilter.txt
?? repos/koi-ai-engine/rag_prototype/eval/aliases.py
?? repos/koi-ai-engine/rag_prototype/eval/before_prefilter.txt
?? repos/koi-ai-engine/rag_prototype/eval/before_true.txt
?? repos/koi-ai-engine/rag_prototype/eval/calibrate_gate.py
?? repos/koi-ai-engine/rag_prototype/eval/compare_prefilter_real.py
?? repos/koi-ai-engine/rag_prototype/eval/compare_prefilter_real.txt
?? repos/koi-ai-engine/rag_prototype/eval/content_review.py
?? repos/koi-ai-engine/rag_prototype/eval/dev_holdout.py
?? repos/koi-ai-engine/rag_prototype/eval/dev_zero_vote_check.py
?? repos/koi-ai-engine/rag_prototype/eval/diagnose_handlabelled.py
?? repos/koi-ai-engine/rag_prototype/eval/egress_audit.py
?? repos/koi-ai-engine/rag_prototype/eval/embedder_comparison.py
?? repos/koi-ai-engine/rag_prototype/eval/holdout_once.py
?? repos/koi-ai-engine/rag_prototype/eval/labels/
?? repos/koi-ai-engine/rag_prototype/eval/load_labels.py
?? repos/koi-ai-engine/rag_prototype/eval/multilingual_queries.py
?? repos/koi-ai-engine/rag_prototype/eval/results/
?? repos/koi-ai-engine/rag_prototype/eval/review_blind.py
?? repos/koi-ai-engine/rag_prototype/eval/review_packet/
?? repos/koi-ai-engine/rag_prototype/eval/service_check.py
?? repos/koi-ai-engine/rag_prototype/eval/super_run.py
?? repos/koi-ai-engine/rag_prototype/eval/test_ablation.py
?? repos/koi-ai-engine/rag_prototype/eval/test_crisis_router.py
?? repos/koi-ai-engine/rag_prototype/eval/test_diagnose.py
?? repos/koi-ai-engine/rag_prototype/eval/test_embedder_comparison.py
?? repos/koi-ai-engine/rag_prototype/eval/test_haystack_pipeline.py
?? repos/koi-ai-engine/rag_prototype/eval/test_holdout_once.py
?? repos/koi-ai-engine/rag_prototype/eval/test_load_labels.py
?? repos/koi-ai-engine/rag_prototype/eval/test_m2_m3.py
?? repos/koi-ai-engine/rag_prototype/eval/test_prefilter.py
?? repos/koi-ai-engine/rag_prototype/eval/test_super_run.py
?? repos/koi-ai-engine/rag_prototype/reference/
?? repos/koi-ai-engine/rag_prototype/scripts/content_safety.py
?? repos/koi-ai-engine/rag_prototype/scripts/crisis_service.py
?? repos/koi-ai-engine/rag_prototype/scripts/fallback_bank.py
?? repos/koi-ai-engine/rag_prototype/scripts/haystack_pipeline.py
?? repos/koi-ai-engine/rag_prototype/scripts/language_detector.py
?? repos/koi-ai-engine/rag_prototype/scripts/retier_mhgap_pk.py
?? repos/koi-ai-engine/real_run_task2c.py
?? repos/koi-ai-engine/real_run_task2e.py
?? repos/koi-ai-engine/test_task2.py
```

The working tree already contained unrelated P1/RAG/app/policy changes and untracked
files. This task added only these audit deliverables plus this report and the required
PROGRESS line:

* `repos\koi-ai-engine\docs\contracts\firestore\FIRESTORE_ACCESS_INVENTORY.md`
* `repos\koi-ai-engine\docs\contracts\firestore\firestore.rules.proposed`
* `repos\koi-ai-engine\docs\contracts\firestore\RULES_NOTES.md`
* `repos\koi-ai-engine\docs\contracts\firestore\CRYPTO_AUDIT.md`
* `repos\koi-ai-engine\agent_tasks\reports\P3_REPORT.md`
* `repos\koi-ai-engine\agent_tasks\reports\PROGRESS.md` (appended only)

## Status, skips, and halt reason

**HALT.** The required Web test command reached Jest but failed before tests
because `nextjs_app\jest.setup.ts` is missing while Jest configuration requires it.
Per P3 hard rules, test failure halts. No dependencies were installed, no Firebase
deploy/emulator was run, no client/backend source or canon/protected file was modified,
and no secrets/key files were read or printed. Dart tests were not run (the Web test
failure halted the task); rule syntax was not checked for the standalone proposal.
No guesses were made about undecided ownership or future mobile fields.


P3.1: chat_core currently accepts JSON only; multipart not implemented.

P3.2: crisis_client.py absent; no internal async lookup wired.

P3.3: risk wait/fail-closed not implemented.

P3.4: risk event and post-reply cap not implemented.

P3.5: audio transcript path not implemented.

P3.6: existing ChatRequest accepts deprecated risk field.

P3.7: done contract has handoff/exercise fields but transcript/risk additive schema absent.

P3.8: language/script instruction absent.

P3.9: trace checker added, smoke scripts not fully risk-aware.

P3.10: not deployed; P3 contract prerequisites incomplete.
