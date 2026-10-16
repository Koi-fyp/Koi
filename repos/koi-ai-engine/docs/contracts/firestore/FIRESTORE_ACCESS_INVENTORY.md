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
| `nextjs_app/src/app/api/auth/anonymous/route.ts:13-25` | `ADMIN` `get`, conditional `set` | `users/{uid}` | `koiUuid`, `createdAt`, `lastActive`, `profile.avatar`, `profile.language`, `profile.notificationTime`, `classification` (empty map), `settings.notifications_enabled`, `settings.sound_enabled`, `settings.haptic_enabled`, `stats.total_conversations`, `stats.total_check_ins`, `stats.current_streak`, `stats.longest_streak`, `stats.jigsaw_pieces` | `AuthContext.signInAnonymously` → `POST /api/auth/anonymous` | Admin SDK bypasses Firestore rules. `uid` is a newly generated UUID. |
| `nextjs_app/src/app/api/auth/link-email/route.ts:28` | `ADMIN` merge `set` | `users/{uid}` | `email`, `emailVerified` | `AuthContext.linkWithEmail` → `POST /api/auth/link-email` | Admin SDK bypasses rules; caller token is verified first. |
| `nextjs_app/src/lib/onboarding.ts:50-61` | `setDoc(..., merge:true)` | `users/{uid}` | `profile.avatar`, `profile.companion`, `profile.language`, `profile.notificationTime`, `onboarding_complete` | `completeOnboarding` | `notificationsEnabled` is persisted in IndexedDB but is not included in this Firestore write. |
| `nextjs_app/src/lib/crypto.ts:280-282` | `getDoc` | `users/{uid}` | none | `getActiveCryptoContext` | Reads `public_crypto_metadata.salt`. |
| `nextjs_app/src/lib/crypto.ts:310-313`, `lib/firestore/sync.ts:36,57` | queued/attempted `setDoc(..., merge:true)` | `users/{uid}` | `public_crypto_metadata.salt` | `getActiveCryptoContext` → `syncQueue.enqueue` → immediate write or online flush | Resolved queue template: collection `users`, docId `uid`. |
| `nextjs_app/src/lib/conversation/conversationService.ts:85-90`, `lib/firestore/sync.ts:36,57` | queued/attempted `setDoc(..., merge:true)` | `conversations/{conversationId}/messages/{messageId}` | `id`, `conversationId`, `sender`, `content`, `timestamp`, `emotion`, `emotion_confidence`, `synced` | `sendMessage` → `saveMessage` → `syncQueue.enqueue` | `content` is encrypted before the queued write. `conversationId` is supplied by the caller; this code does not prove it equals the authenticated UID. |
| `flutter_lib/lib/services/auth_service.dart:103-107` | `set(..., merge:true)` | `users/{uid}` | `koiUuid`, `email`, `emailVerified` | `AuthService.linkWithEmailAndPassword` | Firebase client SDK; credential is linked first at line 96. |
| `flutter_lib/lib/services/auth_service.dart:133-138` | `get`, conditional `set` | `users/{uid}` | On create: `koiUuid`, `createdAt`, `lastActive`, `profile.avatar`, `profile.language`, `profile.notificationTime`, `classification.primary_profile`, `classification.secondary_profile`, `classification.severity_tier`, `classification.ucla_score`, `settings.notifications_enabled`, `settings.sound_enabled`, `settings.haptic_enabled`, `stats.total_conversations`, `stats.total_check_ins`, `stats.current_streak`, `stats.longest_streak`, `stats.jigsaw_pieces`. Existing doc: `koiUuid`. | `AuthService.signInAnonymously` → `createUserDocument` | `KoiUser.toMap()` is in `models/user_model.dart:30-43`. |
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

