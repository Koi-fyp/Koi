# Existing Firebase integration — WEB-5

Target and only cloud project: **`koi-companion-fyp`**. No Firebase project was created. Existing WEB-1–4 source, reports, setup guides, authorization tests and frozen 0.5.2 contracts were inspected before preparation. Existing dirty work was captured in `baseline.json` and preserved.

## Observed configuration

| Evidence | Observation |
| --- | --- |
| Sanitized `.env.local` inspection | Public Firebase configuration is complete and project is `koi-companion-fyp`. No values besides project/mode/flag names were printed. |
| Current server configuration | `FIREBASE_ADMIN_SDK`, platform project/mode, rules evidence and cursor key are not configured. No Google application credential environment variable was present. |
| Firebase CLI credential cache | No logged-in user or refresh token. No credential output was printed. |
| `src/lib/firebase.ts` | Original default client Firebase app. WEB-4 emulator connection remains an explicitly opted-in development path; cloud setup does not enable it. |
| `src/lib/platform/professional-auth.ts` | Separate named Firebase client app; email/password login against the same existing project. It preserves the companion's default identity/session. |
| `src/lib/firebase-admin.ts` | Existing companion Admin SDK initialized lazily from server-only JSON credential. One minimal correction now finds the default app by name when a platform named app already exists. No transport/provider behavior changes. |
| Platform runtime | Named Admin SDK, revoked/disabled-token-aware `verifyIdToken(token, true)`, explicit issuer/audience/UID checks, current account/verification/membership/relationship checks on each operation. |
| Existing development sign-in flag | `NEXT_PUBLIC_KOI_LOCAL_TEST_ANON=true` is already present in `.env.local`. The existing development-only client Anonymous Auth behavior is preserved. Production uses the existing custom-token endpoint. No flag was rewritten. |
| Existing companion API | `/api/auth/anonymous` creates a custom-token guest and companion records; `/api/auth/link-email` updates the existing UID. Neither route grants authoritative platform registration. Neither endpoint was invoked against cloud. |
| Hosting/deployment | Backend environment, deployed application revision, published rules, provider enablement, IAM, indexes, authorized domains and App Check enforcement could not be authenticated/verified. No hosting/deployment setting was modified. |

## Reuse and isolation

Reuse existing project, public web app configuration, Firebase email/password provider (after confirming enabled), lazy Admin credential, named platform Auth, Neo UI and all WEB-1–4 backend services. No UID is migrated, linked, repurposed or deleted.

Existing checked-in `../firestore.rules` permits same-UID access at `users/{uid}`, legacy `conversations/{uid}/messages/{id}`, `mood_entries/{uid}/entries/{id}`, `wellness_progress/{uid}` and `tasks/{uid}/items/{id}`, followed by a default deny. These are source observations, not published-policy evidence. In particular, the current nested `users/{uid}/conversations/...` path was already a source/rules variance; WEB-5 does not change that policy or assume it matches live.

Platform accounts, psychologist verification, organization membership and patient relationships are separate backend-owned collections. Client `users/{uid}` fields, Firebase `isAnonymous`, email verification flags and custom profile roles never grant platform access. All clinical reads/writes remain through authenticated Next routes; direct Firestore access is denied even for psychologists. Patients receive assignment/answer-entry/acknowledgement DTOs, never evaluation records, job state, scores or reviews.

The existing Admin helper previously assumed any Admin app meant a default app existed. Platform-first initialization could therefore break a later companion Auth request. The default-name lookup fixes that coexistence case without changing the companion API, credentials format, URL, providers, streaming, avatars or crisis logic. Isolated mocks cover both initialization orders.

## Preparation delivered

- Existing-project-only reviewed-production configuration, rejection of emulator flags/demo signing key, matching private service account and fresh rules evidence. A rules hash alone no longer enables cloud mode.
- Read-only Firebase audit CLI; it requests only fixed Firebase control-plane GET targets and SDK OAuth authentication. With missing credentials it writes a truthful local blocker report without networking.
- Additive backend-only deny patch, reference merged policy and proposed composite indexes in `dev/web5-reference/`. Existing source rules are untouched. The reference is **not deployable evidence of live rules**.
- Restricted local operator workflow, exact typed project confirmation, explicit cloud-write phrase, service/operator allowlist, secure password prompts, existing verified-professional transitions, actual platform service calls and durable exact-path creation ledger. No HTTP seeding/verification endpoint was added.
- No Mobile/AI schema change: 0.5.0/0.5.1/0.5.2 contract validators pass. Operational production prerequisites were strengthened and are documented here; no client payload was silently changed.

## Smallest safe activation path

Supply a private existing-project credential; inspect the live release and provider/index configuration; test that exact published source locally; assemble matched evidence; then configure the local Next server for `reviewed-production`. If live rules already deny every platform namespace, no rules deployment is needed. Provision only after the owner explicitly authorizes the fictional cloud records. A locally hosted Next server can demonstrate cloud-persistent accounts without a web hosting deployment or emulators.

If live rules allow clinical collections through a broad wildcard, additive `allow ...: if false` cannot override that allow. Activation remains blocked until an explicitly authorized, reviewed correction is tested. Never replace the unknown live policy with the checked-in reference.

No Modal, companion/crisis, health, speech, lip-sync, worker or paid AI endpoint was contacted. The AI worker remains pending; manual publishing/submission/review works independently.
