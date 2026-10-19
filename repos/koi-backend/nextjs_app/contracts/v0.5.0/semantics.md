# Normative semantics — 0.5.0 local freeze proposal

## Identity and capabilities

1. The application backend verifies Firebase **ID tokens**, issuer/audience against
   an explicitly pinned project, expiry, disabled accounts and revocation. It never
   accepts an Admin custom token as an API bearer token. For privileged mutations,
   require `auth_time` within five minutes; identity changes require reauthentication.
   All new platform responses use `Cache-Control: private, no-store` and
   `Vary: Authorization`; no shared cache or browser service-worker cache.
2. An existing custom-token guest or Firebase Anonymous Auth session is
   **unregistered** until `accounts/{uid}` says otherwise. A custom-auth provider,
   an empty provider list, `!isAnonymous`, email strings, client-written profile
   fields, `koiUuid`, browser flags and custom claims alone grant no capability.
   Signed-out/missing/invalid tokens get 401; a valid unregistered session may call
   capabilities but cannot discover experts, submit patient forms or enter a practice.
3. `accounts/{uid}` is backend-only. Registration verifies a current password-provider
   Firebase identity, recent actual password authentication, explicit terms/consent,
   and a single-use **server email-possession challenge** bound to UID, purpose and
   the current Auth user's email. Store only a challenge hash, expire after 15 minutes,
   rate-limit issuance/redemption and consume transactionally. Creation returns no
   secret or verification link; delivery must use an approved mail adapter. Provider
   absence yields truthful 503 and no claimed delivery. Do not rely only on
   `emailVerified`: the legacy `/api/auth/link-email` returns a verification link to
  its caller and is not proof of inbox control. Public registration is blocked until
   this delivery prerequisite exists. This contract does not modify that legacy route.
4. `purpose=general` explicitly grants `general_access`; `purpose=professional` does
   not. A public purpose choice never grants clinician verification. Restricted seeded
   onboarding may register an existing clinician UID using separately audited identity
   evidence. Registered/suspended/closed are account states, not profession or patient roles.
5. General discovery/account sync requires registered state plus `general_access`.
   Active patients retain these explicitly granted general capabilities. Clinicians
   do not automatically get general companion sync or patient rights. Dual use requires
   explicit general registration and, independently, an active patient relationship.
6. `psychologist_verifications/{uid}` is written only by a restricted seeded CLI/admin
   operation. Transitions: pending -> verified/rejected; verified -> suspended;
   suspended/rejected -> pending for documented reconsideration. Every transition
   increments a revision and appends who/when/evidence to `audit_events`. No public
   verification endpoint or fifth public UI role exists. CLI authority comes from an
   allowlisted service identity/IAM, never a browser-supplied role.
7. Verified status plus registered account permits idempotent organization creation.
   The backend creates the organization and owner membership together; concurrent
   calls resolve a unique `organization_owners/{uid}` record, yielding one organization
   per owner for this MVP. All professional operations recheck account, verification,
   active organization and active owner membership. Names/profile IDs are not authority.
8. Patient access additionally requires the precise active relationship linking the
   current UID, organization and psychologist. No global `patient` account field.
   Closure immediately denies subsequent patient reads/writes and new human messages.
   Clinicians may read retained historical records in their own authorized practice;
   closure does not delete the person's account or grant cross-practice access.

## Scope, serialization and evaluation firewall

- All new platform Firestore reads and writes go through the authenticated application
  backend. No direct client writes, subscriptions or collection-group queries are enabled
  in this freeze. This deliberately avoids depending on unverified deployed rules.
  Production enablement still requires proving the published rules deny new namespaces.
- An ID, organization query parameter, nested reference or cursor is always untrusted.
  Resolve scope from stored records and check every referenced object; verify foreign
  references before transactions. Use 404 for nonexistent or foreign resources and
  403 for a known authenticated capability failure without revealing foreign existence.
- Lists are bounded (default 25, maximum 100) and scoped before query execution.
  Cursors are opaque, signed, expiring and bound to UID, capability revision,
  organization, filter and order. No unscoped scan followed by client filtering.
- Explicit patient serializers build allowlisted fields. Never spread a Firestore
  document. Assignments and attempts contain no evaluation fields. Submitted detail
  returns `PatientSubmittedAssignmentDTO`: assignment plus the four-field acknowledgement;
  it exposes no submitted answer view. Pre-submit detail includes original answers and
  questionnaire items only. The separate submitted-original-response feature is disabled.
- `clinician_evaluations`, `review_records`, `ai_jobs` and AI result records are
  professional/backend only, including status, trends and feedback. A psychologist with
  patient capabilities must pass professional scope checks to access another patient's
  professional records; merely being a patient never grants evaluation access.
- Notifications have four fixed kinds and typed ID references only. No arbitrary
  title/body/data/provider strings, evaluation events or AI progress notifications.
  Human message bodies are user-authored: prohibit automated evaluation insertion and
  result-sharing tools. Schemas cannot prevent a person manually typing clinical text;
  the application must not claim to enforce the semantic content of arbitrary messages.
- Existing companion records never enter the professional API or AI evaluation worker.
  Patient responses may contain free text; never inspect arbitrary answer strings for
  words such as "score" as a substitute for structural access control.
  The canonical package and fixtures stay outside browser bundles; future client
  generation must use separate patient/professional entry points and must never ship
  clinician example data or server/provider configuration to patient clients.
- Backend Admin SDK access bypasses Firestore rules. Middleware/serializers and service
  identity controls are mandatory; rules alone do not protect Admin API responses.

## Questionnaire/version contract

- Drafts use integer revisions. Create/update validate all locales, unique question and
  option IDs, question order, required flags, option cardinalities and selection bounds.
  The questions array is canonical order; every declared locale must cover titles,
  prompts, labels and asset accessibility labels. `ur` renders RTL; `en`/`ur-Latn` LTR.
- Choice answers use stable **option IDs**, including likert; yes/no is boolean, short
  text is a bounded string, multi-choice is a unique option-ID array. No numeric type.
  Autosave may omit required answers but cannot contain unknown question/option IDs,
  mismatched types, duplicate question answers or out-of-range selections.
- Manual and AI-drafted custom forms always say `not_validated`. Structural checks
  always run; Critic is an explicit clinician action. No AI output auto-publishes.
  `UpdateQuestionnaireRequest` can edit only custom content; instrument-derived drafts
  are created from the protected registry and their wording/scoring metadata are immutable.
- Fixed-instrument snapshots can only be built server-side from a permission-checked
  registry record. An uploaded/custom object cannot declare itself an instrument.
  English/official Urdu evidence must be checked per exact version; Roman Urdu custom
  forms never become validated instrument translations. This freeze approves no seed.
- Image options refer to exact approved asset ID/version/SHA-256. Paths come only from
  the bundled manifest, are relative to the app asset root, and cannot traverse paths
  or be supplied by a form author. Hash/source/license review precedes manifest inclusion.
  No storage bucket, paid service or arbitrary URL is required.
- A content hash is SHA-256 over UTF-8 RFC 8785 canonical JSON content (no timestamps or
  draft revision). Publish rereads the draft within the transaction, compares revision
  and content hash, validates structural/registry/asset constraints, and creates one
  immutable version for `(organization_id, questionnaire_id, source_revision)`.
  Repeated publish of that revision returns the same snapshot, even with a fresh key.
  No update/delete endpoint for published versions. Draft edits only affect later versions.

## Idempotency, autosave and submission

- Every mutation takes `Idempotency-Key`. Store the actor UID, operation, resource,
  canonical request hash and exact sanitized acknowledgement. Same key/different payload
  yields 409; same key/same payload returns the acknowledgement **after reauthorization**.
  A removed relationship cannot replay an old key to regain access. Use deterministic
  resource identity for publish, assignment and submission beyond key-level deduplication.
- Assignment resolves only active relationships owned by the practice. `all_active`
  snapshots the roster once; retry uses that snapshot, never a newly expanded roster.
  Maximum 200 relationships per synchronous batch; larger requests fail 422 before
  writes. One independent assignment/attempt pair per relationship; include relationship
  ID, organization and pinned version. All references must belong to the same practice.
- Autosave is backend-only `PATCH`, replacing the answer set atomically when
  `expected_revision` equals the stored revision and status is not submitted. Increment
  revision and write server time; stale requests get 409 with sanitized error only.
  Client refetches current detail, preserves unsaved local edits in memory and asks for
  deliberate reconciliation. A retry with the original idempotency key returns its ack.
- Restart before submission is autosave with an empty answer array and the confirmed
  revision. It does not create a new attempt. A repeat questionnaire requires a new assignment.
- Submit takes only the last confirmed revision. In one transaction check current
  account/relationship, pinned version, required answers and full schema; lock the attempt,
  create one stable internal submission ID, and one protected evaluation job/outbox record.
  Increment revision and store server submission time. Stable job ID derives from the
  submission; provider execution is never inside this transaction.
- Duplicate submit of an already submitted attempt returns the **same four-field ack**,
  even with a different key, after scope checks. It cannot reopen or change answers.
  An in-progress stale revision gets 409. Job status/ID, scores and evaluation IDs never
  appear in the patient ack, error, list, document or notification.
- Job/outbox creation does not claim an always-running worker or provider availability.
  A scheduled/manual worker and approved service identity are separate deployment prerequisites.

## Professional/AI boundary

- Application backend owns records/transactions, authorization and DTOs. AI owns the
  provider adapter, deterministic scoring implementation, interpretation/critique and worker.
  Flutter consumes the same DTOs; neither track invents collection ownership.
- `/api/v1/ai/questionnaires/{generate,revise,critique}` and `/api/v1/ai/jobs/*` require
  verified owner scope; there is no patient job endpoint and no `/rewrite` alias here.
  No provider key in a browser bundle and no direct client-to-AgentRouter call.
- Internal `/internal/v1/evaluation-jobs/*` requires an allowlisted workload OIDC identity
  with exact audience; Firebase user tokens are denied. Deploy these behind an internal
  ingress boundary. The AI worker receives only a leased submission and its pinned form,
  never general Firestore Admin credentials or companion data. Deployment identity/URL
  is intentionally not invented by this contract.
- Claim uses a transactional lease with server-chosen expiry and revision. Complete/fail
  must match current lease, job revision and all submission/organization references.
  Expired/stale leases get 409. Retry increments attempt count with capped backoff; after
  exhaustion retain protected failed state. Repeated completion is idempotent.
- Deterministic scores require exact registry/scoring/implementation version, and persist
  independently of interpretation availability. Custom forms have no validated score.
  A missing provider produces truthful unavailable/failed state; no companion-model fallback.
- Preserve original AI/provider response immutably when one exists; no invented response
  for manual/fixed-only work. A completed generated/revised form becomes an unpublished
  draft (CAS against source revision); a conflict preserves output separately for manual
  reconciliation. Critique is read via the professional result endpoint.
- Review writes are append-only, revision-checked records. Corrections never overwrite
  original AI output. Evaluation DTO review status is a projection of authorized review
  history. Analytics counts authoritative submitted attempts and groups by questionnaire
  and scoring version; no synthetic clinical improvement or global mental-health score.

## Invitations, applications and communication

- Invitations use cryptographically random 256-bit base64url secrets. Persist SHA-256
  only; bind UID when known, cap expiry at seven days, rate-limit, permit revoke and
  consume once transactionally. Redemption additionally requires explicit general
  registration (`general_access=true`), not a professional-only account. Redact token
  path segments in access logs. A repeat
  with the same authorized idempotency key returns its ack; a consumed token/new key
  fails. No reusable or temporary passwords. Multiple invitations cannot duplicate an
  active `(organization_id, patient_uid, psychologist_uid)` relationship.
- Requests: requested -> awaiting_demo_payment -> pending_psychologist_review ->
  accepted/rejected, or withdrawn by applicant before final decision. Server controls
  transitions; demo completion is recorded only by the applicant's demo action and may
  advance a waiting request, never create a relationship. Acceptance by the owning
  psychologist additionally requires registered general account, consent and onboarding. Public
  request fields cannot reconfigure transition order. Any future order configuration
  needs a versioned server policy contract. No financial credentials or real gateway.
- Experts require general/patient discovery capability; only verified, discoverable,
  nonsuspended profiles of active practices are serialized. `accepting_new_patients`
  is distinct from discoverability. Public profiles contain no verification evidence.
- Human messages are separate from companion chat. Active relationship participants
  only; sender, timestamp and unread event derive on server. No message edit/delete in
  this contract and no emergency-support promise. ID references cannot attach evaluations.
- Appointments: patient requests; psychologist proposes start/end; patient confirms that
  exact proposal revision; psychologist completes only a confirmed appointment after
  its end time. Psychologist may reject requested/proposed; either participant may cancel
  requested/proposed/confirmed. Terminal states cannot reopen. Times must be ordered UTC
  timestamps; later rescheduling needs a new request. No unimplemented double-booking guarantee.
- Notification events are backend generated and deduplicated by event ID + recipient.
  Only unread/read acknowledgement is client-triggered. This is in-app only, no FCM.
  On relationship closure, exclude/redact scoped notifications from subsequent reads.

## UID transitions, invalidation and retention

- The independent proposed `/api/v1/me/access-events` stream carries only an
  `authorization_changed` hint/revision. It does not alter companion SSE, grant
  authorization or carry evaluation/job content. Closure writes an outbox invalidation;
  foreground clients clear protected memory and refetch capabilities on events/reconnect.
  Stream disconnect/expired heartbeat locks protected screens. Every backend request
  rechecks records regardless of events. No claim of instantaneous delivery across a
  disconnected network; persistent protected offline caches are disabled in the MVP.
- On UID change/logout/revocation, cancel in-flight work/listeners, drop protected
  plaintext/memory and partition all retained owned data; never carry selected practice
  or authorization snapshots across accounts. Recheck current UID before and after awaits.
- Existing companion storage is preserved, not automatically imported. Migration uses
  `MigrationManifestRecord`: stable IDs, source owner/session, destination UID, schema,
  hash, status and explicit preserve-both conflict policy. Ownerless rows need explicit
  user-authorized claim; no adoption based on browser/device alone. UID-preserving linking
  still needs encryption migration, verified ownership, retries and server acknowledgement.
  Never remove old ciphertext/keys before verified decryption and acknowledgement.
- Relationship closure immediately revokes future patient operations but retains
  professional history behind current clinician scope. **Production retention duration,
  legal basis, deletion/export process and expiry mechanism remain a policy blocker**;
  this freeze grants no indefinite-retention policy or account deletion behavior.

## UI and operational prerequisites

Reuse `NeoButton`, `NeoCard`, `NeoInput`, theme tokens, typography, hard shadows and
KOI's warm surfaces. Use existing spinner/entrance patterns for loading, pending
authorization, saving and publishing, with accessible status labels, `aria-busy` and
disabled duplicate actions. New animation must honor reduced motion; the current
global reduced-motion rule covers environment transitions, not every spinner.
Existing auth/companion UI and animations are not edited by this package.

Existing environment **names only**: web `NEXT_PUBLIC_FIREBASE_*`,
`NEXT_PUBLIC_KOI_LOCAL_TEST_ANON`, `NEXT_PUBLIC_KOI_API_BASE`; server `FIREBASE_ADMIN_SDK`;
Modal `SERVICE_ACCOUNT_JSON`, `KOI_EXERCISES`, `KOI_CORS_ORIGINS`, `KOI_DEBUG_TRACE`,
`KOI_MIN_CONTAINERS`. Proposed platform configuration names:
`KOI_PLATFORM_FIREBASE_PROJECT_ID`, `KOI_PLATFORM_WORKER_AUDIENCE`,
`KOI_PLATFORM_WORKER_SERVICE_ACCOUNT`, `KOI_PLATFORM_MAIL_ADAPTER` and
`KOI_PLATFORM_CURSOR_SIGNING_KEY`. None is provisioned; all secrets stay server-side.
No actual credential values are included here.
