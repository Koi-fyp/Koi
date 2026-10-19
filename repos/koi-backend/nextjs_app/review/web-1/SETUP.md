# WEB-1 setup and operational boundaries

The feature is disabled unless the server environment explicitly selects an isolated
emulator or reviewed production configuration. There is **no in-memory fallback**
in application routes, no preapproved demo account in the UI and no AI provider call.
The functional test creates synthetic accounts only in the local demo emulators.

## Isolated local reproduction

Prerequisites used in this verification: Node 22, Java 21, Firebase CLI 15.34.0,
Next 14.2.35, and installed Chrome through Playwright. The CLI is invoked through
`npx`; no dependency or lockfile changes were made. Use a separate browser origin
and the `demo-` project. No Firebase login or live project credentials are needed.

Start the emulators from `nextjs_app`:

```powershell
npx --yes --package firebase-tools@15.34.0 firebase emulators:start --only 'auth,firestore' --project demo-koi-platform-web1 --config dev/platform-emulator/firebase.json
```

The **new emulator-only** rules deny all direct Firestore access. They do not replace
or weaken `../firestore.rules` or any published rules. Do not run a deploy command.

In a second PowerShell, configure only this process and start a new dev server:

```powershell
$env:KOI_PLATFORM_MODE='emulator'
$env:KOI_PLATFORM_FIREBASE_PROJECT_ID='demo-koi-platform-web1'
$env:FIRESTORE_EMULATOR_HOST='127.0.0.1:5180'
$env:FIREBASE_AUTH_EMULATOR_HOST='127.0.0.1:5199'
$env:NEXT_PUBLIC_KOI_PLATFORM_FIREBASE_PROJECT_ID='demo-koi-platform-web1'
$env:NEXT_PUBLIC_KOI_PLATFORM_AUTH_EMULATOR_URL='http://127.0.0.1:5199'
npm run dev -- --hostname 127.0.0.1 --port 3107
```

Do not share `.next-dev` with another development server in the same directory.
The existing config already separates development output from the production build.

In a third PowerShell, repeat the four server emulator variables above and run:

```powershell
node scripts/web1-emulator-functional.cjs
```

This script creates fresh, fictional identities with random passwords in memory,
uses the restricted CLI for pending -> verified transitions, opens the real UI, and
records sanitized results/screenshots in `review/web-1/evidence/`. It does not print
credentials or retain passwords. It uses Playwright Chromium if installed, otherwise
the standard Windows Chrome path; override with `KOI_WEB1_BROWSER_EXECUTABLE` if needed.
Stopping the emulators discards this synthetic database unless an operator separately
chooses to export it. No export or live cleanup is performed by the test.

## Restricted verification CLI

There is no public verification route and no self-verification control. An operator
must independently verify the clinician and reference that evidence. The CLI requires
an existing non-disabled password-provider Firebase user. Production also requires an
existing operator UID and an exact allowlisted service-account email matching the
configured credential. The audit records both identities and an evidence reference.

Configure `KOI_PLATFORM_BOOTSTRAP_ADMIN_UID` and
`KOI_PLATFORM_BOOTSTRAP_SERVICE_ACCOUNT` privately. In emulator mode only, the latter
must be `emulator-only`. Then explicitly invoke both transitions:

```powershell
node scripts/platform-verify-psychologist.cjs --uid EXISTING_CLINICIAN_UID --state pending --evidence-id REVIEW_REFERENCE --request-id REQUEST_PENDING
node scripts/platform-verify-psychologist.cjs --uid EXISTING_CLINICIAN_UID --state verified --evidence-id REVIEW_REFERENCE --request-id REQUEST_VERIFIED
```

It creates a server-owned account with `general_access=false`, preserving an existing
registered General grant if present, and increments authority revisions. Transitions
are audited and idempotent; verified -> suspended immediately denies subsequent
professional backend operations. Suspended/rejected -> pending requires another review.
The CLI creates no passwords, organization or patient relationship. `users/{uid}`
is never used as authorization authority.

Open `/professional` and sign in using an existing approved clinician account. The
named professional Firebase Auth instance does not replace/sign out the companion's
default session. Create an organization, then a manual questionnaire. Save a valid
draft before publishing. Later use its published bookmark or select a published draft
revision from the editor. The UI's organization name is not reloaded through an invented
GET endpoint: after refresh it shows “Your practice” and the authoritative organization
ID comes from capabilities. The stored organization name remains unchanged.

Privileged writes require auth within five minutes. The editor checks freshness early
and uses same-account Firebase reauthentication, keeping unsaved edits while the user
confirms their password. This is only a client hint: server enforcement remains
mandatory. Revoked/invalid sessions and removed access clear protected UI state.

## Bundled illustrations

`src/lib/platform/illustrations.json` is the static allowlist. Three original SVGs
(circle, square, triangle) were authored and developer-reviewed as neutral geometric
options for this slice. No third-party images, external URLs, upload/storage service,
validated instrument, clinical meaning or external clinical approval is claimed.
Labels include EN/UR/Roman Urdu. The server validates exact ID/version/SHA-256 and
the tests hash the bundled bytes. A published form pins those references. Preserve
old versions when adding new art. Flutter mappings are reserved paths only; no Flutter
source was changed or assumed available.

## Production enablement remains blocked

`reviewed-production` requires `KOI_PLATFORM_FIREBASE_PROJECT_ID`, a matching
`FIREBASE_ADMIN_SDK` credential, a 32-character-or-longer
`KOI_PLATFORM_CURSOR_SIGNING_KEY`, and `KOI_PLATFORM_RULESET_SHA256`. The hash is an
operator review attestation, **not** automatic inspection or validation of live rules.
Do not enable this mode until the actual published rules release denies every new
platform namespace to client SDKs and deployment/project/IAM evidence is verified.
New namespaces remain backend-only; Admin SDK access bypasses rules.

Review [firestore.indexes.proposed.json](firestore.indexes.proposed.json) for the
organization/owner/document-ID draft list query. It is not wired into deployment and
was not deployed. Emulator success does not prove production indexes, IAM, App Check,
published rules, web hosting, service credentials or the live companion SSE revision.

No changes to live Firebase project/rules, backend deployments, `.env.local`, default
AuthContext, Dexie, synchronization queues, companion routes/SSE, avatar or crisis code
are needed or made by this slice. Public account registration, anonymous migration,
invitations, patients, evaluations, AI and Flutter remain outside WEB-1.

Firebase references: [Auth emulator](https://firebase.google.com/docs/emulator-suite/connect_auth),
[Firestore emulator](https://firebase.google.com/docs/emulator-suite/connect_firestore).
