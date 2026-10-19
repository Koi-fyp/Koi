# WEB-0.5 — evidence, authentication reconciliation and contract freeze

**2026-10-19 · Local preparation complete; live verification and cross-track sign-off blocked.**
No platform feature implementation began. Existing Neo UI, theme, spinner patterns,
auth, database schema, companion SSE/crisis/avatar code and rules remain unchanged.
No commits, merges, pushes, resets, deployments or destructive operations occurred.

## Evidence and limits

| Question | Evidence obtained | Conclusion / blocker |
| --- | --- | --- |
| Current source | Branch `review/web-product-data-wip`, HEAD `1390f1b3da96270ad47d8edfa06510ed838add77`; second worktree detached at `2923070` | Initial tracked files clean; existing untracked `.idea/` and mobile Android files preserved |
| Active Firebase project | Allowlisted local config: `NEXT_PUBLIC_FIREBASE_PROJECT_ID=koi-companion-fyp`; matching auth domain. Development anonymous flag enabled locally | **Local target verified; live web build/Auth issuer/backend project binding not verified** |
| Published Firestore rules | Checked-in owner-wide rules and separate proposed rules differ from current nested message path. No `.firebaserc`; `firebase.json` configures functions/emulators, not rules or hosting | No Firebase management credential/CLI available in inspected environment; published release/ruleset **blocked**, not inferred from source or old reports |
| Public Firebase Hosting | GET `https://koi-companion-fyp.web.app/__/firebase/init.json` returned 404 in both probe runs | Does not identify a production web deployment, disable Firestore or disprove project existence |
| Configured backend | Local public API base points to `https://ahsulem--koi-chat-api-chatserver-web.us-east.modal.run` | Source config only; not proof of deployed revision, secret project, CORS or readiness |
| Live health/OpenAPI | GET `/health` and `/openapi.json` timed out with 20-second limits, then timed out again outside sandbox | **Live contract/configuration blocked**; no chat POST, inference request, synthetic account creation or private read was performed |
| Current SSE source | Main frontend requires SSE; main AI checkout has older JSON route. Second worktree has Modal `koi-chat-api` SSE implementation | Source confirms divergence, not which revision is deployed; preserve frontend and seek release provenance |
| Hosting configuration | Backend CI deploys functions only; separate `koi-web` CI references Vercel preview | Neither proves current Next.js app hosting or a usable platform deployment target |
| Flutter | `koi-mobile` has no application `lib/*.dart`; its pubspec has a top-level `flutter_lib` path entry outside dependencies. Separate `koi-backend/flutter_lib` has auth services | Service fragments can be audited; active Flutter app, Firebase config, caches and route parity **blocked by missing source** |

Recorded output: [deployment-evidence.json](deployment-evidence.json),
[source-evidence.json](source-evidence.json),
[verification.json](verification.json). Public probe script:
[`scripts/web05-deployment-evidence.py`](../../scripts/web05-deployment-evidence.py).
Only allowlisted public config fields were emitted; no API keys, tokens, passwords,
private keys, Auth users or private documents are in these artifacts.

## Authentication and storage findings

- Default web "anonymous" sign-in mints a UUID/custom token on the server; browser
  exchanges it for a Firebase session. Test mode uses genuine SDK Anonymous Auth.
  Neither establishes a registered General account. Existing `!isAnonymous`, profile
  fields and stored UUIDs must not authorize platform access.
- Web linking uses Admin `updateUser`, while the Flutter service uses SDK
  `linkWithCredential`. Web returns a generated verification link to the caller,
  does not explicitly refresh/reload SDK identity, and does not perform encryption
  migration. Therefore verified inbox possession needs separate server evidence.
- Dexie `users.uid` is nonunique; ownerless legacy messages and global message IDs
  need explicit migration/conflict handling. The active queue is browser-global
  localStorage, not the declared Dexie queue. Already-owned-path replay lacks a
  per-item UID/revision guard; rules are the foreign-write backstop. These are
  source risks; no actual duplicate counts or successful leaks were measured.
- Current history readers and ledger have useful owner checks. Current onboarding
  already has UID-specific flags, correcting the older handoff's global-flag warning.
  Preserve these safeguards; do not reuse the legacy generic queue for platform writes.

Full trace/store table: [auth-and-storage-audit.md](auth-and-storage-audit.md).

## Proposed local freeze

Canonical package: [`contracts/v0.5.0`](../../contracts/README.md), with 96 shared
schemas and 47 proposed operations. Paths are **not implemented or deployed**.
The OpenAPI document references one canonical JSON Schema file; normative semantics
and collection matrix define ownership/transaction rules that schemas cannot enforce.

- Backend-only account registration, clinician verification, organization membership
  and patient relationships. General grants are explicit; clinician/patient rights
  compose only through separately authorized records. No authority in `users/{uid}`.
- New platform collections deny all direct Web/Flutter SDK access. Backend transactions
  own draft revisions, publish, assignment, autosave, submit, reviews and transitions.
- Patient serializers expose no evaluations/jobs/reviews/trends. Submitted detail is
  assignment + the four-field acknowledgement; submitted answer-view is disabled.
- AI browser operations require verified practice scope; worker uses a separate
  allowlisted service-identity lease API, without companion data or general DB credentials.
- Registration needs a hashed, expiring server-delivered inbox challenge because the
  legacy verification-link response cannot prove email possession. No mail was sent.
- Versioned questions, image references, EN/UR/Roman Urdu custom content, instrument
  provenance, typed answers, notifications and app state machines are defined. No
  fixed instrument, scoring algorithm, image manifest asset or real gateway is approved.

This is a **local freeze proposal**, not Web/Flutter/AI owner sign-off. Hashes record
the exact review snapshot. No external handoff message was sent. A later change must
use a new version, updated fixtures and an authorized cross-track handoff.

## Remaining blockers and required evidence

| Blocker class | Needed evidence / decision | What it blocks |
| --- | --- | --- |
| Deployment | Read-only Firebase Rules release name, ruleset source/hash and timestamp for `koi-companion-fyp/(default)`; App Check state; confirmation of project-bound issuer/audience | Enabling any new production collection/data; cannot substitute repository rules |
| Deployment | Actual production web URL/build revision, deployed public project/backend settings; Modal release/source SHA and sanitized server project ID/CORS/feature flags | Live configuration/SSE acceptance and a platform hosting plan |
| Deployment | Reachable health/OpenAPI and owner-approved synthetic authenticated SSE trace from the exact deployment | Current deployed stream events, voice/risk support and token verification behavior |
| Missing Flutter source | Current app `lib/`, Firebase initialization/config project ID, dependency layout and owner-designated branch | Cross-platform authentication/cache parity, generated clients and Mobile sign-off; **does not block isolated web manual publish work** |
| Product/infrastructure | Approved registration mail adapter and verified inbox challenge flow | Public General registration/discovery; first slice may use restricted seeded clinician onboarding |
| Policy | Professional record retention duration/legal basis/export/deletion/expiry and restricted verification administrator | Real-patient onboarding/history retention and production approval; synthetic manual publish can proceed independently |
| Integration | Web/Mobile/AI owner acknowledgement of this exact contract version; verified instrument wording/licensing/scoring fixtures for later work | Cross-track freeze acceptance and fixed-instrument/AI integration, not manual questionnaire creation |

## Recommended first implementation slice — not started

**Seeded verified psychologist → organization → manual questionnaire creation → publish.**

1. Implement a restricted seed/verification operation for an existing synthetic clinician
   UID, server-only account/verification records and append-only audit evidence. No
   self-verification UI. Keep production guest auth and linking untouched.
2. Add new platform authorization middleware and an isolated professional layout using
   existing Neo components. Recheck current verification/membership on every operation;
   show existing-style loading, empty/error/expired-session states with reduced-motion support.
3. Create organization + unique owner membership transactionally and idempotently.
4. Build the manual custom form editor against 0.5.0 types; support revision conflicts,
   structural checks and explicit `not_validated` labeling.
5. Publish one immutable version with confirmed revision/content hash; retries return
   the existing version. Demonstrate old versions survive later draft edits unchanged.

Acceptance: unregistered/general/unverified/suspended identities denied; clinician A
cannot touch B's practice; concurrent edits conflict; invalid schemas/assets/locales
cannot publish; duplicate publish produces one immutable version. Use synthetic data
and an isolated test environment until deployment/security evidence is verified.
No invitations, patient runner, account import, scoring, AI provider or live deployment
belongs in this first slice. No first-slice handlers/components were created in WEB-0.5.

## Validation executed

- `node scripts/validate-web05-contract.cjs`: Draft-07 schema compilation, 13 valid
  fixtures accepted, 14 invalid fixtures rejected, reference/operation metadata checks,
  patient-schema reachability and frozen file hashes. No runtime security is proven.
- Existing Jest baseline: **6 suites / 36 tests passed** for auth, Firebase initialization,
  sync queue, onboarding, user preferences and message sync payloads.
- [25 future integration acceptance cases](../../contracts/v0.5.0/acceptance-cases.json)
  are explicitly **NOT RUN**. No live rules/emulator authorization, patient transaction,
  provider, Flutter or browser regression acceptance is claimed. No application build
  was needed for these documentation/schema-only changes.

Official references used for the proposed security design:
[ID tokens](https://firebase.google.com/docs/auth/admin/verify-id-tokens),
[Anonymous Auth credential linking](https://firebase.google.com/docs/auth/web/anonymous-auth),
[revocation](https://firebase.google.com/docs/auth/admin/manage-sessions),
[published rules releases](https://firebase.google.com/docs/reference/rules/rest/v1/projects.releases).
