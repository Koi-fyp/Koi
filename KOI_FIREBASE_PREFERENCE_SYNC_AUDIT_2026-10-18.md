# Firebase preference sync investigation — 2026-10-18

Branch: feat/web-product-data. HEAD: b384ce2cef44e83e53db7f50182f3ccfaac32187 plus preserved uncommitted product work. This investigation does not change live rules, Firebase configuration/authentication, protected P0 storage/session/transport, or backend services. No credentials/environment files/tokens were read or exported. No existing private browser profile or private messages were accessed.

## Conclusion and evidence boundary

There are **two separate problems**:

1. **BROWSER/HOSTED OBSERVATION:** onboarding's correctly owner-targeted Firestore write is denied; a server read of that same owner document is also denied. The anonymous Firebase sign-in itself succeeds.
2. **SOURCE:** Settings and in-chat avatar/language changes are local-only. They never call Firestore, and the preference reader never hydrates an account profile. A rules correction alone cannot make those paths sync.

The owner subsequently supplied the published test-mode rule: `allow read, write: if request.time < timestamp.date(2026, 6, 5);`. It expired on **5 June 2026**; on 18 October it denies every client request, including authenticated owners. This is a sufficient explanation for the observed denial if published on the runtime project/database. The reply also confirms Anonymous and Email/Password providers enabled. Project/database selection and App Check enforcement were not explicitly supplied and must still be checked. No rule was deployed; a narrowly scoped review candidate is now provided below.

## Actual browser comparison (synthetic account)

Frontend: http://127.0.0.1:3000, local development mode, isolated Chrome. Sanitized evidence: artifacts/firebase-preferences/browser-result.json. Three diagnostic checks passed; zero page errors; no Modal calls.

| Check | Observed |
| --- | --- |
| Firebase authentication | signUp and lookup HTTP 200; user.isAnonymous=true; providerData empty as expected for this anonymous account; development anonymous path from AuthContext |
| Actual UID vs write owner | Compared exact UID in memory; equality confirmed. Only SHA-256 prefix 57c7aa3c6ef71f0b recorded, no raw UID/token |
| Firebase app | Auth and Firestore reference the same [DEFAULT] app |
| Configured project | koi-companion-fyp for both app options and Firestore database ID |
| Database/host | (default), firestore.googleapis.com; no emulator configured in this runtime |
| Auth domain | Matches configured project's firebaseapp.com domain |
| Write target | projects/koi-companion-fyp/databases/(default)/documents/users/{the same signed-in UID} |
| Write operation | setDoc(..., {merge:true}); no exists precondition, so it may create or update |
| Actual update mask | onboarding_complete, profile.avatar, profile.companion, profile.language, profile.notificationTime |
| Local result | Companion saved successfully to the existing UID-filtered Dexie user record |
| Remote result | SDK permission-denied surfaced as account access denial; not a sync-success receipt |
| Same-owner server read | getDocFromServer(users/{same UID}) also rejected with permission-denied; same user remained signed in |

No API key, ID token, Authorization header, token claims or document contents were inspected. Matching client app options does **not** prove the Auth token issuer or API key belongs to the intended Console project. Confirm the synthetic anonymous user appears in that project's Authentication user list and compare Web app registration/configuration privately. No credential change should be inferred merely from SDK sign-in success.

## Source-level operations and ownership

| Source | Actual behavior |
| --- | --- |
| src/lib/firebase.ts:6–11,43–46 | Config supplied through existing NEXT_PUBLIC_FIREBASE_* names; same default app passed to getAuth/getFirestore. No named database argument. Environment values not read by this audit. |
| src/contexts/AuthContext.tsx:130 onward; src/lib/auth/anonymousSignInMode.ts | Existing development-only anonymous SDK sign-in when enabled; production custom-token path remains distinct and was not altered/tested here. |
| src/lib/onboarding.ts:14,17–45 | Capture current UID, save local selection first, then merge nested profile + onboarding_complete at users/{uid}. UID checked again after successful cloud operation. No cloud profile read/hydration. |
| src/lib/preferences/userPreferences.ts:11–48 | Load/save IndexedDB users by UID, notify local listeners. No Firestore call. |
| src/hooks/useUserPreferences.ts | Re-read that local record on preference event/focus; never reads account profile. |
| src/lib/avatar/avatarPreference.ts | Canonical local companion/avatar resolver and writer. Does not sync account. |
| repos/koi-backend/firestore.rules:5–12 | request.auth non-null and request.auth.uid == users path ID allows owner read/write, including anonymous users; no linked-only/time/field constraint in this local rule. |
| repos/koi-backend/firebase.json | Functions/emulator config present, but **no firestore.rules mapping**. The rules file existing in Git is not evidence it was published or will be selected by CLI. |
| App Check source | No initializeAppCheck/production provider setup found in the active Web source. Enforcement in Console unknown. |

Expected invariant: a signed-in user accesses only users/{their UID}; no users collection listing, cross-owner read/write, broad authenticated-user grant or Admin bypass. Existing local owner rule is ownership-based but not a field-level schema validator; client validation does not make it field-restricted server policy.

### Separate cloud-message path mismatch (SOURCE, not the preference-denial cause)

Protected src/lib/conversation/conversationService.ts:25 enqueues messages under conversations/{record.conversationId}/messages/{id}. P0 uses a new UUID conversation ID. The repository rule instead authorizes conversations/{userId}/messages/{id} by comparing that middle segment with request.auth.uid. These differ in current P0 and future multi-chat.

Do **not** fix this by widening rules to all signed-in users. A minimal joint-reviewed candidate is owner-UID-scoped cloud placement, keeping actual conversationId as existing record metadata. This touches a protected file and queued-path compatibility; no patch/replay/migration was applied. Existing private/queued rows were not inspected. This mismatch does not explain onboarding denial, which already uses users/{correct UID}.

The old generic syncQueue is global localStorage, with no per-owner lease/receipt at its flush boundary. Do not reuse it for new preference synchronization or call a queued operation synced. Keep its review separate from accepted P0 transport.

## Precise Firebase Console checks — inspect first, do not publish

1. Select **koi-companion-fyp** by project ID, not display name. Project settings → General → Your apps: compare the intended Web registration's project ID/auth domain/app ID and key association **privately** with your own local settings. Do not paste SDK keys, service-account files or tokens here.
2. Authentication → Users: confirm the current synthetic/browser identity belongs to this project and its provider is Anonymous. Sign-in method → Anonymous: inspect enabled status; this runtime already signed in successfully, so enabling it again is not a proposed fix. Keep raw UIDs local; use them only in the Console/your own local comparison.
3. Firestore → select **(default)**. Confirm it exists and is the intended Native-mode database. If data lives in a different named database, do not create another database or change rules on the wrong database; approve the intended database/client selection first. The SDK defaults to (default): https://firebase.google.com/docs/firestore/manage-databases
4. Firestore → Rules: confirm the owner-supplied expired test rule is the **published** rule for koi-companion-fyp/(default), not another database or an unsaved editor draft. Save its publication/version details privately. Review the candidate below in the Rules editor/Playground without publishing. **Do not extend the test expiry** or replace it with public/authenticated-wide access. Do not publish the broader repository rules wholesale. Firestore ownership checks: https://firebase.google.com/docs/firestore/security/rules-conditions
5. Use **Rules Playground** with synthetic IDs/data and the exact request shape below. This simulates Rules, not App Check, deployment identity or real end-to-end syncing. For update tests, request.resource.data is the final merged document: preserve unrelated existing public crypto metadata. Simulator guidance: https://firebase.google.com/docs/rules/simulator
6. App Check → APIs → Cloud Firestore: inspect enforcement and valid/invalid/unverified request metrics for this Web app. If enforcement is on but the Web provider is absent/mismatched, the correction is reviewed Web App Check registration/provider integration, not disabling enforcement or weakening Rules. Any development debug registration/token stays private; no token should be logged or shared here. https://firebase.google.com/docs/app-check/enable-enforcement
7. If Rules allow own operations, the correct project/database/user is confirmed and App Check is not rejecting this Web app, investigate the exact sanitized service error/API availability and deployed app registration next. Do not grant end-users IAM Editor/Admin, relax key restrictions or bypass Rules to hide permission-denied.

### Playground / emulator request matrix

| Identity and operation | Intended outcome |
| --- | --- |
| Signed out: get/create/update users/synthetic-a | DENY |
| Anonymous synthetic-a: get users/synthetic-a | ALLOW under current repository ownership rule |
| synthetic-a: create own missing document with exact onboarding profile below | ALLOW if client-owned profile creation is approved policy |
| synthetic-a: merge own profile.language=ur, other fields preserved | ALLOW |
| synthetic-b: get/create/update users/synthetic-a | DENY |
| synthetic-a: list users collection | DENY |

```json
{
  "profile": {
    "avatar": "female_human",
    "companion": "aisha",
    "language": "ur",
    "notificationTime": "20:00"
  },
  "onboarding_complete": true
}
```

If published policy deliberately requires linked identities or server-created profiles, reconcile that product/security decision explicitly rather than bypassing it. A successful Console-admin write is not a test of end-user Security Rules; do not use Admin SDK credentials for this acceptance.

## Concrete proposed changes for approval — not wired/deployed

### P-FB-01: one owned account-preference client module

Candidate src/lib/preferences/accountPreferenceSync.proposed.ts, imported only by tests. Provides readOwnedAccountPreferences(ownerUid,signal) and writeOwnedAccountPreferences(ownerUid,patch,signal). Exact existing users/{uid}/profile shape; no new collection, endpoint, service, key or SDK dependency. Server read only; SDK merge acknowledgement only; current UID before/after every await; same Auth/Firestore app; explicit allowed fields and avatar pairing; legacy fox preserved; language-only patches supported; no local writes, generic queue, token access or remote plaintext echo.

Tests cover missing/foreign/changed owner, cancel, invalid path segment, wrong pair/extra fields, legacy fox, server read/missing record, safe error categories and no false acknowledgement. A cancellation after a dispatched SDK write cannot guarantee server rollback; no current-account success is returned after identity change. No automatic retry/replay or deployment was enabled.

After approval: connect existing local-success paths in onboarding/settings/inline switch to this adapter; show account success only after SDK acknowledgement; give explicit failure/retry under current UID. Add account-profile read/hydration with explicit conflict handling so stale cloud data never silently overwrites unsynced local selection. The candidate does not itself choose an automatic conflict/adoption policy. displayName/notificationsEnabled are not added to cloud schema in this first proposal. An entire cloud sync workflow is NOT claimed implemented from unit tests alone.

### P-FB-02: rules/config correction only after Console evidence

**The supplied expired test rule needs replacement, not a later expiry.** Review-only file `review/firestore.user-preferences.proposed.rules` grants authenticated exact-owner `get/create/update` at users/{uid}; create/update are restricted to profile, onboarding_complete and public_crypto_metadata, with profile leaf changes limited to avatar/companion/language/notificationTime and crypto metadata changes limited to salt. Existing unrelated server-owned fields are preserved, not client-writable. Owner delete, user listing, guest/foreign access and all other collections remain denied. This is a minimal preference/crypto-metadata correction, not a new general cloud-data permission grant or verified crypto migration. It is not connected to firebase.json or deployed.

This changes expired deny-all behavior to necessary owner-only operations and therefore still needs approval and Rules-engine tests. It does not extend the old public grant, introduce account deletion or change encryption keys. The candidate checks field scope/basic maps, not all possible application enums or cryptographic provenance; the tested client separately validates allowed preference values. App Check remains independently enforced. No backend/SSE/auth-provider/clinical collection access is changed. Existing repository firestore.rules remains untouched.

Config-only candidate, after approval and promotion of the exact reviewed rules to their final canonical path: add an explicit Firestore rules mapping inside repos/koi-backend/firebase.json while preserving Functions configuration. If that path is firestore.rules, the mapping is `"firestore": { "rules": "firestore.rules" }`; do not point at and publish the current broader file without review. Console-only publication does not require a CLI/config change. Named-database deployment needs its own explicit reviewed target. No config file modified.

### P-FB-03: executable real Rules tests, not a JavaScript imitation

review/firebase-preferences.rules.cjs uses Firebase's rules-unit-testing + Firestore SDK against **127.0.0.1 only**, demo-koi-preference-review project. Default tests load the actual repository rules; `--proposal` loads the review candidate. It refuses live targets and does not deploy. Specs: anonymous own create/get/merge, guest/foreign deny, collection-list deny; proposal adds salt merge success, privileged root/profile changes denied, owner delete denied and unrelated clinical collection write denied.

**NOT RUN:** no local Firestore emulator/CLI or rules-unit-testing package is installed/configured. Java 21.0.2 exists. No packages or emulator were installed/started. Tooling/dependency version compatible with existing Firebase 10 SDK needs approval; do not upgrade Firebase just to run tests. Once prerequisites are approved and local emulator is running, use `node review/firebase-preferences.rules.cjs --proposal` from nextjs_app with FIRESTORE_EMULATOR_HOST=127.0.0.1:<port>. This tests the proposed file, not a deployed policy. Until then, validate the exact candidate in Console Rules Playground without Publish; its results must be recorded rather than assumed. https://firebase.google.com/docs/rules/unit-tests

## Local implementation vs genuine Firebase dependencies

| Goal | Can use existing local infrastructure? | Real approval/infrastructure requirement |
| --- | --- | --- |
| Saved avatar/language, PNG/VRM switching | Already works using existing UID-scoped users table; those preference fields are readable metadata, not encrypted chat content | Account sync needs existing Firestore access + guarded client wiring/read/conflict behavior, not a new backend/database |
| Independent A/B conversations, local history/resume | Yes: existing Dexie + authorized P0 encryption; no Firestore needed for same-device multi-chat | Joint additive archive/active-selection + session adapter review, not a cloud infrastructure blocker |
| Encrypted user check-ins and local mood chart | Yes: approved existing-key encryption + owner-scoped local records | New encrypted activity schema/writer + rating scale/provenance approval; existing moodEntries numeric plaintext schema is not sufficient |
| Completed exchanges | Already computed from real owner-tagged encrypted message relationships | No new Firebase service |
| Explicit completion, local pieces/milestones/calendar | Can be persisted atomically/idempotently in approved local event ledger | Joint completion evidence/reward storage/provenance; no rule change needed just to render genuine local records |
| Global per-account caps/awards across devices | Local-only ledger cannot enforce account-global concurrency/trusted issuance | Shared transactional authority/provenance/rules design needed; existing Firestore may suffice for coordination, verified issuance may need trusted producer review. No automatic new service promised |
| Cross-device encrypted history/check-ins/recovery | Not solved by Firestore access or UID alone | Approved key/unlock/recovery semantics and sync ownership; message cloud path mismatch reviewed separately; no raw media migration |
| Ciphertext data export | Already implemented using owner-filtered read-only local storage, not a recovery guarantee | Verified restore still requires approved manifest/crypto/transaction path; no new Firebase required for local data copy |
| Local reminders/media | Preference storage local; actual scheduler/voice/video not fabricated | Notifications/media services remain separately approved capabilities; preference-sync access does not enable them |

No additional disabled controls were introduced. The next concrete implementation after Console comparison/approval is wiring the tested preference adapter into the existing controls, and separately approving local session/check-in/ledger adapters. Deployed Rules uncertainty is not a reason to treat all local product work as Firebase-dependent.

## Verification

- SOURCE: current client/config/rules/preferences/P0 read-only inspection, exact Firestore path mismatch identified.
- BROWSER/HOSTED: fresh actual Firebase anonymous sign-in; same configured app/project/default database; exact UID/path match; own write + server read permission-denied. No Modal request or production key inspection.
- TEST: full Jest PASS **201 tests / 33 suites**; final proposal suite **15/15 PASS**; TypeScript PASS; diff check PASS. Candidate module unreferenced by production app.
- RULES: owner-provided published test expiry identified; direct Console project/database confirmation and App Check status still pending. Real emulator/candidate compilation/Playground tests NOT RUN. Unit mocks are not permission/rules acceptance. Proposed rules remain unapplied.
- Production build identity appended to the main implementation acceptance report on completion. No commit, push, merge, deploy, environment/rule/auth change or protected migration.


## 2026-10-18 ? Owner-authorized Settings/inline account preference integration

Supersedes earlier statements that the preference adapter is unwired or that expired Rules still deny the owner document. Owner reports publishing authenticated UID-owner-only users/{uid} Rules and explicitly authorizes client integration. No Rules, Firebase configuration, authentication, encryption, session, renderer, or backend edits were made in this increment. Anonymous end-user Firestore operations now succeed; Rules source/Console/App Check administration was not independently accessed.

Implementation: existing accountPreferenceSync.proposed.ts is now used by preferenceSync.ts (historical filename retained). SDK auth.currentUser.uid must equal the requested owner before/after network operations and before local application; Auth and Firestore must share the same Firebase app. Existing users/{uid}.profile merge writes contain only supplied allowlisted preference leaves. Crypto metadata and unrelated fields are never supplied to this writer. Settings and both inline companion pickers reuse saveUserPreferences/saveAvatarPreference, with no second preference store.

Local saves commit immediately to the existing users table; additive accountSync pending fields/revision metadata is in that same UID row, without a Dexie schema/version/index migration. Network failure does not roll back local selection or block picker dismissal. Missing/denied server reads and rejected writes do not clear pending edits. Retries use the authenticated owner only. Initialization, refresh, focus and online restoration perform guarded server reads; a single-flight coordinator coalesces consumers. Newer pending edits take precedence over server snapshots; only the exact acknowledged revision is cleared. Concurrent edits during a write are sent in the next iteration, and stale reads cannot replace a changed local revision. Existing legacy local choices are preserved and synchronized once; fox remains fox/koi. Cloud legacy avatar-only/companion-only metadata is canonicalized locally without an unsolicited server rewrite.

A shared account status/Retry control is shown in Settings and inline controls. Local-save toasts remain explicitly local. Server success requires a real getDocFromServer response and, for pending changes, resolved setDoc acknowledgement. Permission-denied is explicit; other errors use safe unavailable copy. The status subscription uses useSyncExternalStore to avoid missed completion notifications across navigation/mounts. No raw Firebase error text is rendered.

Scope: Aisha/Raza avatar/companion and en/ur language preference synchronize. Nickname and reminder-enabled state remain local; interface translation and reminder delivery are not claimed. No generic global syncQueue is used for this feature.

Current increment source/test files (relative to nextjs_app):
- src/lib/preferences/userPreferences.ts
- src/lib/preferences/preferenceSync.ts (new)
- src/lib/preferences/accountPreferenceSync.proposed.ts (existing candidate now wired; comment updated)
- src/hooks/useUserPreferences.ts
- src/components/chat/AccountPreferenceStatus.tsx (new)
- src/components/chat/ConversationProductControls.tsx (preserved prior work, added status)
- src/app/(authenticated)/settings/page.tsx
- src/__tests__/preference-sync-integration.test.ts (new, 8 tests)

TEST EXECUTED: npm test -- --runInBand --silent: **209 PASS / 34 suites**, 12.296s; npx tsc --noEmit --incremental false: PASS. Existing P0/session tests remain passing. Production npm run build PASS, Next.js 14.2.35, 19/19 entries, BUILD_ID **PayaHUPYLgqqrRX6UvgKO**. Exact HEAD **b384ce2cef44e83e53db7f50182f3ccfaac32187**, branch **feat/web-product-data**, dirty worktree including preserved prior work; no commit. Build ran with browser and the existing dev server stopped, process-local 1024MB Node heap, then one dev server was restored at http://127.0.0.1:3000. Browser evidence is against the development runtime at this SHA plus uncommitted changes; this is not a hosted Next deployment or a Modal acceptance run.

New tests cover hydration/field preservation, persisted offline pending patches/reconnect, permission denial, late UID change, an edit during acknowledgement, legacy fox, stale cross-tab read, and legacy account fox hydration. Adapter's existing 15 tests cover exact UID/path checks, merge masks, allowlists, cancellation, and safe error mapping. Rules emulator tests remain NOT RUN; application unit tests do not validate deployed Rules.

Browser procedure uses fresh isolated Chrome and synthetic anonymous accounts; only UID fingerprints, approved preference values, field names, equality checks, model URLs/status and safe session metadata are retained. No token, key, salt value or message content is logged/exported. A read-only account hydration test removes only the disposable synthetic user's local preference row; it leaves conversation/key storage untouched, then reloads. Foreign-owner read probe uses only the other synthetic account and records denied status, never document content. Anonymous browser identity/key recovery across devices and Email/Password sign-in are NOT RUN; preference hydration does not demonstrate encrypted history recovery. No Modal request is needed or made for preference testing.


### Final genuine browser results ? 2026-10-18

**10/10 BROWSER PASS against real hosted Firebase**, URL http://127.0.0.1:3000, isolated desktop Chrome, current development runtime at b384ce2cef44e83e53db7f50182f3ccfaac32187 plus the uncommitted changes listed above. Auth anonymous sign-up/lookup HTTP 200; exact SDK owner UID compared in memory and only a fingerprint recorded. Actual server reads verified approved profile values after resolved writes. No Modal calls, no private existing account/messages used. Zero page errors or recorded network failures.

| Acceptance | Evidence/result |
| --- | --- |
| Owner Firebase identity/document access | BROWSER/HOSTED PASS: anonymous owner sign-in and server read/write succeed |
| Settings language | BROWSER/HOSTED PASS: English ? Urdu saved as profile.language=ur; return to English during offline/reconnect test |
| Settings Raza | BROWSER/HOSTED PASS: profile.companion=raza, profile.avatar=male_human; existing unrelated fields including public_crypto_metadata unchanged |
| Chat inline Aisha | BROWSER/HOSTED PASS: female_human/aisha server acknowledged, language remains ur |
| Refresh | BROWSER/HOSTED PASS: selected avatar and language retained |
| Companion Scene inline Aisha ? Raza | BROWSER/HOSTED PASS: female and male model HTTP 200 and renderer ready; current conversation fingerprint unchanged; model URLs /models/koi-female.vrm then /models/koi-male.vrm |
| Offline local preference / reconnect | BROWSER PASS local English selection with explicit offline status; HOSTED PASS pending language flushed to owner document after reconnect |
| Account preference hydration | BROWSER/HOSTED PASS: after removing only disposable synthetic user's local preference row, refresh restores actual saved Raza + English from server |
| Account change/isolation | BROWSER/HOSTED PASS: distinct fresh anonymous owner has no prior account profile; foreign synthetic owner's server document read is permission-denied |
| Truthful denied-write fallback | TEST PASS: denial keeps local data/pending changes and explicit denied status; actual owner's new Rules permit writes, so forcing own-account denial in browser NOT RUN |

Final artifacts: artifacts/preference-sync-live-final/browser-result.json, chat-account-synced.png, scene-raza-synced.png. Earlier attempts exposed harness timing/stale-expectation issues (immediate server read before acknowledgement, Aisha expectation after deliberately choosing Raza); bounded server acknowledgement checks and the correct saved choice are used in final run. A status mount notification timeout led to the useSyncExternalStore fix. These earlier runs are not being counted as production backend tests.

Limits: browser conversation was empty synthetic data, so session identity continuity was observed but a live Modal reply/navigation-during-SSE regression was NOT RUN in this increment; existing P0 automated suites PASS. No linked Email/Password account or second physical device was tested. Real preference sync is functioning for the tested anonymous Firebase identity and published owner-only policy. This is not an encrypted backup/recovery, media, multi-chat or reward issuance acceptance.

Final checks: 209 Jest tests /34 suites PASS, TypeScript PASS, production build PASS (19/19, PayaHUPYLgqqrRX6UvgKO); git diff --check PASS with existing line-ending notices only. No commit, push, deployment, security rule/config/auth/crypto/session/renderer/backend edits. All earlier uncommitted project/IDE/Android work preserved; one development server remains running.
