# KOI WEB-1 through WEB-5: technical ownership handoff to Ahmad

Handoff branch: `handoff/koi-web-1-to-5-2026-10-20` in [Koi-fyp/Koi](https://github.com/Koi-fyp/Koi). Web application: `repos/koi-backend/nextjs_app` (called `WEB` below). WEB-1/2 were already checkpointed in `f2b9c80f3390e7828131e98d943322f6d1694bfb`; this handoff preserves those ancestors and packages the subsequent WEB-3/4/5 changes. Read `AHMAD_START_HERE.md` first for the short execution order.

**Ownership transfer only. No feature development, rebuild, test-suite rerun, Firebase activation, deployment, provider request or data migration was performed during this handoff.** Existing credible reports are referenced. Cloud shipping and cross-repository AI integration remain unfinished. No secret, account export, private provisioning manifest or emulator snapshot is intentionally included.

## 1. Vision and architecture

KOI 2.0 combines a private existing AI companion with a separately authorized human-care platform. Anonymous users keep the original companion. Registered General users can discover/apply to professionals. An active server-owned relationship adds patient capabilities without replacing account identity. Verified psychologists manage their own organization, patients, forms, submissions and confidential clinical reviews.

The patient experience ends at submission acknowledgement. Scores, interpretations, reviewed conclusions, evaluation status and longitudinal evaluation data are psychologist-only, even after review. There is no patient result page or visibility toggle.

```text
Original companion UI -> existing default Firebase Auth / Dexie / original sync
                     -> original companion/crisis/SSE/avatar/speech integrations
                        [PRESERVED; no paid-service access authorized]

Account / professional / patient Neo UI
  -> named Firebase client Auth (same project, separate persisted identity)
  -> authenticated Next /api/v1 platform routes
  -> current backend account + verification + membership + relationship authority
  -> named server Firebase Admin app -> Firestore transactions
       drafts -> immutable versions -> assignments -> attempts -> submitted records
       protected clinician_evaluations + review_records + queued ai_jobs

Ahmad's separate AI repo -> NOT CONNECTED to these Web records/jobs
Flutter client          -> NOT VERIFIED against these contracts
```

Framework/dependencies are existing Next 14.2.35, React 18, Firebase JS 10, Firebase Admin 12, TypeScript, Dexie and Neo components. `package-lock.json` is the dependency baseline; no dependency reinstall/rebuild was performed for handoff. The production build and dev server use separate output directories (`.next`, `.next-dev`). Do not run two dev servers against the same output directory.

### Original companion versus platform

The companion's default client app and AuthContext retain existing Firebase persistence, encrypted local stores, onboarding, avatar preference, history, crisis handling and streaming behavior. The normal anonymous entry uses `/api/auth/anonymous` and `signInWithCustomToken`; a custom-token guest is not necessarily Firebase `isAnonymous=true`. The existing explicit development-only test flag instead uses genuine Firebase Anonymous Auth. Neither flag/provider alone grants General or clinician access.

The platform uses named client app `koi-professional-web1` and named Admin app `koi-platform-server-web1`. Signing in/out through `/account` does not import, merge, overwrite or sign out the independent companion identity. General platform registration is not evidence that companion history has been linked/synchronized to that account. Anonymous migration remains unimplemented and unapproved.

WEB-5 changes the companion Admin helper only to find `[DEFAULT]` by name: a previously initialized named platform app must not cause `admin.app()` to assume a default app already exists. Isolated mocks cover both initialization orders. No companion/SSE/crisis/provider URL or API contract was changed.

## 2. Delivered batches and their actual status

| Batch | Implemented and locally verified | Remaining boundary |
| --- | --- | --- |
| WEB-1 | Restricted pending/verified/rejected/suspended professional verification; account/organization/owner membership; verified workspace; manual form editor; seven types; localized custom content; bundled pictures; draft CAS; immutable publish and later inspection; scoped reauthentication | No AI authoring, licensed instrument seed, cloud activation or public registration |
| WEB-2 | Invitations and applications; server relationship activation/closure; individual/selected/all-active assignment snapshots; patient runner, autosave, resume, restart, review/confirmation; atomic idempotent submit; queued protected job/envelope; professional raw answers/manual review and review history; access monitor | No worker execution or automatic score; dedicated AI-provider consent and retention policy unresolved |
| WEB-3 | Verified/discoverable directory and application switch; simulated payment record; roster/search/filter/details/archive; human conversations; appointments; safe in-app notices; professional authoritative counts/version-grouped activity and patient history | Search/counts are scoped/loaded or explicitly bounded; no external push/calendar/payment gateway or booking guarantee |
| WEB-4 | Persistent fictional emulator identities/seeder; export/import and fresh mode; unified server-capability menu and `/account`; role-aware workspace section links; real local UI demonstrations; mobile/reduced-motion fixes | Account credentials/snapshots are local, excluded from handoff; cross-platform sync/migration not implemented |
| WEB-5 | Existing `koi-companion-fyp` production preparation; stronger configuration/rules evidence gates; additive deny/index proposals; read-only audit; restricted cloud provisioning tools; exact-path ledger/manifest and rollback guidance; offline security/backend verification | No cloud user/data writes, published-rule proof, rules/index/hosting deployment or cloud GUI verification; paid consumers/AI integration unverified |

Reports: `WEB/review/web-{1,2,3,4,5}/`. Completion and setup documents are retained, including their historical limitations. Earlier statements that a feature was future work are superseded by later batch reports; none imply live deployment.

## 3. UI routes and capabilities

Neo components/tokens, spinner conventions, focus/error/empty/loading states, responsive layouts and Urdu RTL are reused. Menu links come from authenticated `/api/v1/me/capabilities`, not client role claims. Menus are advisory; every protected backend request rechecks authority. Direct links cannot grant access.

| Screen | Route / entry |
| --- | --- |
| Landing / account | `/?home=1`, `/account`; bare `/` retains original post-auth redirect |
| Original companion | `/onboarding`, `/chat`, `/companion-scene`, `/avatar-host`, `/history`, `/progress`, `/settings`, `/settings/privacy`, `/settings/export`, `/settings/import`, `/settings/report`, `/about`, `/how-it-works` |
| Expert directory/profile/application | `/patient?view=experts#experts`; registered General/Patient only |
| Care home/invite/application state | `/patient` |
| My Psychologist / messages / appointments | `/patient?view=care#care`, `?view=messages#care`, `?view=appointments#care`; active relationship |
| Patient forms | `/patient?view=questionnaires#questionnaires`; runner/confirmation/ack are selected in the workspace |
| Patient notifications | `/patient?view=notifications#notifications`; General application notices also exist in the underlying inbox |
| Professional organization/dashboard | `/professional`, `/professional?view=dashboard#practice-dashboard` |
| Manual editor / immutable preview | `/professional?view=questionnaires#professional-questionnaires`, `/professional?version=VERSION_ID` |
| Roster/invites/applications/assign | `/professional?view=patients#patients` |
| Submissions/review | `/professional?view=submissions#submissions` -> Inspect submission |
| Professional analytics | `/professional?view=analytics#practice-analytics` |
| Patient history / human thread | Professional roster -> Patient details / Open conversation (selection in memory) |

Full existing inventory: `WEB/review/web-4/SCREEN-ROUTES.md`. Query/hash links scroll existing workspace sections rather than introducing duplicate applications. Do not promise standalone URLs for in-memory selected patient/attempt/review state.

Anonymous gets original KOI and account sign-in only. General gets discovery/applications. Active relationships add care/forms/messages/appointments. A verified clinician gets practice navigation but is not automatically a patient or General user. The owner account remains a General user after relationship closure if its explicit General grant exists. No public self-verification UI exists.

## 4. Backend and authorization source map

| Concern | Source under WEB |
| --- | --- |
| Identity verification/config | `src/lib/platform/server/runtime.ts`, `admin-config.cjs`, `production-evidence.cjs` |
| Account/professional/org authority, drafts/publish | `src/lib/platform/server/service.ts` |
| Invitations/applications/relationships/assignments/attempts/submission/review | `src/lib/platform/server/lifecycle.ts` |
| Directory/profile/conversations/appointments/notifications/analytics | `src/lib/platform/server/community.ts` |
| HTTP boundary | `http.ts`, `lifecycle-http.ts`, `community-http.ts`; actual handlers in `src/app/api/v1/` |
| Firestore transactions/pagination | `firestore-store.ts`, `store.ts` |
| Schema/content/answers | `contract.ts`, `src/lib/platform/content.ts`, `answers.ts`, `canonical.ts`, shared type files |
| Client identity/API lifecycle | `professional-auth.ts`, `client.ts`, patient access-monitor components/hooks |
| Restricted professional approval | `scripts/platform-verify-psychologist.cjs` |

Bearer tokens are verified with revocation/disabled checks, issuer/audience/project/UID checks. Backend service methods independently require current registered account, verified psychologist, active organization and owner membership, or an active patient relationship. Owner-writable `users/{uid}`, `!isAnonymous`, display names and client organization IDs are never authority.

Mutation requests use strict schemas, bounded bodies, stable `Idempotency-Key`, current scope and optimistic revisions. Privileged writes require recent authentication (five minutes, with limited clock tolerance); UI reauthentication preserves unsaved edits. Scope checks precede idempotency replay. Lists are bounded and cursors are signed and actor/scope/revision-bound. Responses are explicit DTOs with private/no-store headers, not raw document spreads.

## 5. Actual Firestore records (source-verified, not a claim of cloud existence)

Names below are literal reads/writes in the Web service/CLI source. All platform records are backend-only under the proposed/tested policy. Fields are the important persisted shape; see schemas/source for optional fields and exact DTO allowlists. Times are server-generated ISO strings. Foreign keys are opaque stable IDs, not authorization by themselves.

| Collection / key | Actual persisted fields / purpose |
| --- | --- |
| `accounts/{uid}` | `uid,state,general_access,registration_method,registration_evidence_id,registered_at,authorization_revision`; separate authoritative registration |
| `psychologist_verifications/{uid}` | `uid,state,revision,changed_at,changed_by,audit_id`; state pending/verified/rejected/suspended |
| `organization_owners/{uid}` | `uid,organization_id`; MVP one-owner practice lock |
| `organizations/{id}` | `id,owner_uid,name,state,created_at` |
| `organization_memberships/{memberHash}` | `id,organization_id,uid,kind=owner,state,revision,created_at`; deterministic member ID from UID/org |
| `psychologist_profiles/{uid}` | `id,organization_id,display_name,bio,discoverable,accepting_new_patients,revision,directory_scope`; derived public projection only after live authority checks |
| `patient_relationships/{relationshipHash}` | `id,organization_id,patient_uid,psychologist_uid,state,consent_version,activated_at,closed_at?,revision` |
| `connection_requests/{id}` | public connection fields plus `consent_version`; requested/awaiting_demo_payment/pending_psychologist_review/accepted/rejected/withdrawn and demo payment state/revision/timestamps |
| `patient_invitations/{id}` | org/psychologist/intended UID, nonce, token hash, state, expiry, revision, redeemed UID; never stores bearer token |
| `invitation_token_lookup/{tokenHash}` | invitation/org lookup, internal only |
| `questionnaires/{id}` | draft `id,organization_id,psychologist_uid,revision,content,created_at,updated_at` |
| `questionnaire_versions/{id}` | **flat collection**, `id,questionnaire_id,organization_id,psychologist_uid,source_revision,content,content_sha256,published_at,schema_version=0.5.0` |
| `assignments/{id}` | org/relationship/patient/psychologist/version/attempt refs, state, creation/due time and idempotency key; independent record per recipient/repeat |
| `attempts/{id}` | assignment/patient/org/relationship/version refs, status, answers, revision, server update time and submitted time/submission ref after lock; **no evaluation fields** |
| `submissions/{id}` | `id,organization_id,relationship_id,assignment_id,attempt_id,patient_uid,questionnaire_version_id,answers,submitted_at,psychologist_uid`; immutable |
| `clinician_evaluations/{id}` | org/submission/version refs, `validated_scores[]`, optional interpretation, evidence `{question_id,answer_index}[]`, review status, creation time, optional provider hash; empty envelope on submit |
| `ai_jobs/{jobHash}` | **wrapper** `{job:{id,organization_id,kind=evaluate,state,created_at,updated_at,...},submission_id,attempt_count,idempotency_key,revision}`; queued, no worker supplied |
| `review_records/{id}` | org/evaluation/reviewer refs, revision, conclusion, optional feedback, creation time and decision; append-only separate from original interpretation |
| `review_heads/{evaluationId}` | org/evaluation/revision serialization metadata |
| `messages/{id}` | `id,relationship_id,sender_uid,body,created_at,organization_id`; immutable sender/time |
| `appointments/{id}` | relationship/org refs, state, optional start/end, revision, update time |
| `notifications/{id}` | safe event ID/kind/reference/recipient, org and optional relationship, created/read time; no assessment/job-result payload |
| `professional_notifications/{id}` | event/submission/org/recipient refs and creation time; strictly professional submission feed |
| `demo_payments/{id}` | connection/org/applicant refs, `state=demo_completed`, creation time; no financial credentials |
| `patient_archives/{relationshipId}` | relationship/org refs, archive flag and revision; closed relationship metadata only |
| `platform_rate_limits/{hash}` | UID/operation/hour bucket/count; invitation/application/redemption throttling |
| `access_invalidation_outbox/{receiptId}` | UID/org/authorization revision/time hint; stream independently reauthorizes |
| `idempotency_records/{id}` | actor/operation/resource/request hash/sanitized response/scope/time; restricted verification receipts have their own audited shape |
| `audit_events/{id}` | actor/org or target/service identity/operation/evidence refs/time; no generic patient-readable audit API |
| `demo_seed_manifests/web4_v1` | emulator-only deterministic fixture refs; actual local file/data snapshot excluded |
| `demo_provision_runs/{runId}` | restricted cloud seed run project/operator/service/fictional status/identities/refs and progress |
| `demo_provision_records/{hash}` | run/project/exact record path/content hash/ownership; ledger of every seeded record, never browser-readable |

`registration_challenges`, `instrument_templates`, `ai_results`, `platform_outbox`, `migration_manifests` appear in proposed contracts/deny reserves but have no delivered public feature/service writer in this slice. Dedicated `consents`, `scoring_configs`, `equivalence_rules` and the AI repo's result collections are not Web implementations. Do not provision them just because a contract/sketch names them.

Original companion namespaces include `users`, legacy `conversations`, nested current conversation paths, `mood_entries`, `wellness_progress`, `tasks` and local Dexie stores. They are not clinical platform records. The checked-in rules/current nested conversation path variance predates this handoff; live policy remains unverified here.

## 6. Questionnaire lifecycle and confidential review

Manual content is `kind=custom_questionnaire`, `origin=manual`, `validation_status=not_validated`, localized title/prompts/options with `en`, `ur`, `ur-Latn`. Seven types: single_choice, multi_choice, yes_no, likert, short_text, image_single_choice, image_multi_choice. Numeric is not enabled. Images must match `src/lib/platform/illustrations.json` asset ID/version/hash and bundled SVGs; arbitrary URLs and paid Storage are not used. Urdu is RTL. Roman Urdu custom text is not a validated translation.

Draft saves compare revision; publish compares the saved revision/content hash and creates one immutable snapshot. Editing a draft cannot mutate assigned/published versions. Bulk targets resolve the authorized active roster at assignment time and create independent assignments. Repeat actions use distinct idempotency keys/attempts. No rolling auto-enrollment occurs.

The patient runner uses server autosave with revisions, resume from confirmed answers, restart before submission and final answer review/confirmation. Two devices cannot overwrite newer revisions. Submission locks answers and atomically creates immutable submission, protected empty evaluation, one pending job and a professional submission notice. Duplicate/racing submits return the same acknowledgement with no duplicate job.

Patient acknowledgement fields are only `attempt_id,assignment_id,submitted_at,status=submitted`. Patient DTOs/notifications never include evaluation progress, scores, interpretation, feedback or review data. Protected content/listeners/caches are cleared/locked on UID/authority/relationship change or access-monitor interruption. Current web runner is not an offline questionnaire client.

Clinicians can inspect submitted raw answers and protected envelope/job state and append approve/reject/feedback reviews. The original interpretation is not overwritten by a review. In ordinary delivered manual forms, `validated_scores` remains empty and AI jobs remain queued. Synthetic AI/provider-failure fixtures exist only in tests. There is no delivered deterministic instrument-scoring runtime/registry seed and no automatic AI result adapter. Historical screenshots/tests do not prove live model output.

## 7. Community features and limits

Directory reads require explicit General capability, recheck verified active practice ownership, distinguish discoverability from accepting new patients, and support loaded-page search/pagination. Payment is a demo record only; acceptance plus consent/onboarding activates relationship, not payment alone. Invitations expire, bind intended identity when supplied, are revocable/single-use and store only hashes plus server token reconstruction metadata. Closure revokes patient permissions and retains scoped professional history; it never deletes the KOI account. Closed relationships do not reopen through replay.

Human messages are in separate relationship threads, never companion AI chat. They have server sender/time, paging and loaded unread indicators. No assessment data is automatically copied into messages; human-authored prose is not semantically censored. No emergency response guarantee is claimed.

Appointments: patient requested -> psychologist proposed -> patient confirmed -> psychologist completed after end. Rejection/cancellation follow actor-specific transitions; expected revisions resolve races. Rescheduling is cancel plus new request. No external calendar or double-booking guarantee.

In-app notifications use deterministic server event IDs and safe references for assignment/message/application/appointment changes. Professional submission notices are a separate collection/route. Assignment notice delivery is request-driven and bounded, not an always-on worker. External push is deferred.

Professional analytics count authoritative assignments/submissions grouped by exact questionnaire version, with UTC daily/date-filtered data and bounded complete scans. Enrollment counts assignments, including repeats, not unique people. No invented improvement score or patient evaluation trend screen exists. Roster counts/search and unread counts describe loaded data where labeled. Limits return unavailable instead of silently incomplete totals.

## 8. Firebase cloud preparation: exact remaining actions

Cloud target is **only `koi-companion-fyp`**. The existing public web config points there. The WEB-5 inspection found no Admin JSON credential in the app environment and no authenticated Firebase CLI session. No cloud user/rule/index/hosting change or real-cloud examiner walkthrough was completed.

`reviewed-production` requires matching private Admin credential/project, persistent cursor secret, no emulator shortcuts/demo signing key and a fresh private live-release evidence file. The file must match `KOI_PLATFORM_RULESET_SHA256`, all tested platform roots and the actual captured release/ruleset. Evidence expires after 24 hours; it is an attestation, not continuous live-rules monitoring. A hash alone is no longer sufficient.

Owner action sequence (commands are already documented in `WEB/review/web-5/DEMO-DEPLOYMENT.md`):

1. Obtain an existing-project private credential locally with appropriate read/runtime permissions; never commit or send it through chat. Run `scripts/web5-cloud-audit.cjs` for read-only release/source/index/Auth-provider/project inspection. Inspect the actual deployed backend/authorized domains/IAM/App Check separately.
2. Confirm email/password Auth is enabled and required composite indexes are ready; export the complete existing index/field-override config before considering a merge. An emulator does not prove production index readiness.
3. Test the **exact published source** using `web5-rules-security.cjs` against local emulators. Assemble matching evidence with `web5-rules-evidence.cjs`. Existing reference tests cannot attest an unknown live release.
4. If live policy already denies platform namespaces, preserve it: no rules deployment needed. Otherwise prepare an additive candidate from the captured live source, preserve all unrelated rules/indexes, obtain separate owner approval, test/deploy only that reviewed patch, re-capture/retest the resulting published release. Explicit denies cannot override a broad matching allow.
5. Before **any cloud seed or submit**, independently establish from deployment configuration that no paid external consumer reacts to the new `ai_jobs` collection. Do not probe/start/disable AI infrastructure to find out. If unknown, keep cloud writes blocked.
6. Use a clean private shell and `scripts/web5-cloud-env.ps1`, preserving existing public/companion settings. Keep Admin JSON, cursor key and evidence server-side. No emulator is required for the final demo; local production Next with cloud Firebase is sufficient.
7. Obtain explicit owner authorization for cloud provisioning. `web5-provision.ps1` requires typing project and write phrase and prompts for three passwords. `web5-provision.cjs` repeats project/mode/evidence/provider/operator/service checks and refuses collisions. It uses existing verification and services; no emulator bypass or public seeder endpoint exists.
8. Use a unique run ID. For `examiner_2026`, planned emails are `koi-exam-psychologist-examiner_2026@example.invalid`, `koi-exam-general-examiner_2026@example.invalid`, `koi-exam-patient-examiner_2026@example.invalid`; **not created in cloud**. Passwords are operator supplied, no defaults. Complete the manual UI checklist before optional AI/Flutter integration.

Runtime names: `KOI_PLATFORM_MODE`, `KOI_PLATFORM_FIREBASE_PROJECT_ID`, `NEXT_PUBLIC_KOI_PLATFORM_FIREBASE_PROJECT_ID`, existing `NEXT_PUBLIC_FIREBASE_*`, private `FIREBASE_ADMIN_SDK`, `KOI_PLATFORM_CURSOR_SIGNING_KEY`, `KOI_PLATFORM_RULESET_SHA256`, `KOI_PLATFORM_RULES_EVIDENCE_PATH`. Bootstrap allowlist/password/write-confirmation variables belong only in the restricted operator shell, not public hosting.

The provisioning ledger records exact seeded paths/hashes, identities, partial progress and references. Run replay does not replace passwords/records; interrupted runs resume under the same operator and run ID. Private manifest export supports inspection; no actual private manifests/exports are shipped. Later GUI-created records are not automatically added to the seed ledger: inventory that organization's/UIDs' later records before cleanup.

Rollback is **planned, not executed**: disable only platform configuration while preserving companion settings; restore the exact prior live rules if an authorized deployment happened; retain unrelated indexes. For demo cleanup, separately authorize closure/suspension/disable of the exact fictional identities, inventory/hash-check all scoped records and outside references, then remove only reviewed exact paths/ledger/manifest/owned Auth UIDs. Never bulk-delete a collection or delete the operator, real users, chats or storage. See WEB-5 deployment document for the full sequence.

## 9. Ahmad AI repository comparison (read-only, pinned)

Requested AI source: [KOI-Psycholov master](https://github.com/Koi-fyp/KOI-Psycholov/tree/59e90ddba505ea07adbf7f92121ffc3eac0d89db), commit `59e90ddba505ea07adbf7f92121ffc3eac0d89db`. Read without checking out/running/installing AI code. Compared:

- [WEB_HANDOFF.md](https://github.com/Koi-fyp/KOI-Psycholov/blob/59e90ddba505ea07adbf7f92121ffc3eac0d89db/contracts/WEB_HANDOFF.md)
- [JOB_CONTRACT.md](https://github.com/Koi-fyp/KOI-Psycholov/blob/59e90ddba505ea07adbf7f92121ffc3eac0d89db/contracts/JOB_CONTRACT.md)
- [CONSUMED_CONTRACTS.md](https://github.com/Koi-fyp/KOI-Psycholov/blob/59e90ddba505ea07adbf7f92121ffc3eac0d89db/contracts/CONSUMED_CONTRACTS.md)
- [PRODUCED_COLLECTIONS.md](https://github.com/Koi-fyp/KOI-Psycholov/blob/59e90ddba505ea07adbf7f92121ffc3eac0d89db/contracts/PRODUCED_COLLECTIONS.md)
- [INTEGRATION_READINESS.md](https://github.com/Koi-fyp/KOI-Psycholov/blob/59e90ddba505ea07adbf7f92121ffc3eac0d89db/reports/INTEGRATION_READINESS.md)

Also inspected exported Submission/PublishedQuestionnaire schemas. GitHub default HEAD is `main` at `52728363231731fe3f7477167ea176bc3068b571`; **all five requested documents are absent on that ref**. Do not assume default `main` contains the AI handoff. No branch in either repository was merged or overwritten.

AI docs describe `ai-contracts-draft-0.4` (with additive changes over 0.3 and an earlier critic-field rename). Web package is `0.5.2`, while some unchanged wire DTO/version literals remain `0.5.0` by design. These versions are independent; matching the word "contract" does not make them interoperable. AI historical claims that Web entities do not exist were from its earlier snapshot and are superseded by the actual Web implementation here. Its report's earlier recommendation for another Firebase project conflicts with the current owner's explicit `koi-companion-fyp`-only decision.

### Blocking differences — do not connect the worker directly

| Area | Actual Web | AI master's documented assumption | Required owner decision / adapter |
| --- | --- | --- | --- |
| Verification | `accounts` + `psychologist_verifications.state=verified` and current account state | `psychologists/{uid}` with `verified/revoked/verified_at` | Read Web authority through agreed adapter/API; do not create a client-approved parallel role store |
| Organization membership | `organization_owners`, `organizations`, `organization_memberships`; `organization_id`, `kind=owner`, active state | `org_members/{org_id}_{uid}` with `org_id,role,active` | Map path/ID/fields and current owner/state; MVP one owner, not inferred multiorg scope |
| Relationship | `patient_relationships`, `state=active`, organization/patient/psychologist IDs | `relationships`, `active` boolean and `org_id` | Map, preserve closure/revocation checks before every provider action |
| Consent | `consent_version` for care onboarding; no dedicated external-provider consent collection | `consents` with `ai_interpretation` scope, grant/withdrawal | Separate AI consent contract/storage/withdrawal semantics are unresolved; fail closed, do not infer from care consent |
| Published version | Flat `questionnaire_versions/{opaqueVersionId}`, immutable content/locales/source revision/hash | Nested `questionnaires/{qid}/versions/{integer}`, published status/body/scoring config | Explicit version registry/adapter; do not rename/move live Web records |
| Submission | `id`, `organization_id`, opaque `questionnaire_version_id`, attempt/assignment/relationship refs; language in pinned content | `submission_id`, `org_id`, `questionnaire_id`, integer `questionnaire_version`, standalone language | Derive all scope/version fields from server-owned refs and agree stable mapping |
| Answers/evidence | `{question_id,type,value}`; evidence `{question_id,answer_index}` | stable `answer_id`, `option_ids`, value/text; evidence cites answer IDs | Define stable answer-ID mapping and preserve original immutable answers; never silently mutate submissions |
| Authoring content | Localized dictionaries, seven types, `short_text`, `ur-Latn`, version/hash-pinned assets; manual-only publish path | Single language (`roman_ur`), `free_text`/numeric among eight types, provenance/sources/warnings and AI version metadata | New reviewed schema version + conversion/provenance plan; no numeric support or AI-origin insertion is delivered |
| Job creation authority | Patient submit server transaction creates exactly one pending job/envelope and acknowledgement atomically | AI psychologist start route creates/re-runs job after submission; explicitly moved ownership away from Web | Choose one authoritative queue/bridge and update versioned contracts. Do not let both create independent jobs |
| Job ID/shape | `ai_jobs/{jobHash}` where `sid="submission_"+hash(attemptId)`, `jid="job_"+hash(submissionId)`; nested `job`, `attempt_count`, revision | `ai_jobs/{submission_id}`; flat `job_id,org_id,state,stage,run,attempts,lease...` | Actual collision/incompatibility despite shared collection name; do not scan/process all Web jobs with the AI worker |
| Job states/reasons | queued/claimed/completed/failed; `failure_code` has four delivered codes | queued/processing/needs_review/approved/rejected/failed plus stages; includes provider_auth_failed/repair_no_progress | Define explicit state/reason mapping; do not coerce `needs_review` into a valid Web state or drop failure meaning |
| Results | `clinician_evaluations`, empty envelope initially | `ai_scores`, `ai_interpretations`, `ai_evidence_checks`, `ai_comparisons` | Choose protected result namespace/projection and versioned completion write contract |
| Review | Append-only `review_records` + `review_heads`; preserves original interpretation, not job approval transitions | Web changes AI job/interpretation review status and writes `ai_feedback` using AI validator | Reconcile approve/reject semantics and preserve original/revised versions and audit; not implemented across repos |
| Rules/read transport | All direct clinical Firestore reads/writes denied, including psychologists; backend explicit DTOs | Proposed psychologist Firestore gets/lists/listeners for `ai_*` using `org_id` | Current Web firewall remains authoritative; choose server proxy/DTO, do not apply AI sketch blindly |
| Worker privilege boundary | No delivered worker; shared contract favors protected leased service operations | Direct Admin/ADC reads of Web data, writes allowed `ai_*` collections | IAM cannot be assumed collection isolation; review dedicated identity/service API and no companion access |
| Scoring/instruments | No seeded fixed instruments/custom score implementation; custom analytics not_applicable | English WHO-5/DASS registry/scorer, Urdu WHO-5 disabled; custom scoring configs | Wording/licensing/scoring and immutable instrument-schema review required before Web enablement |
| Comparisons | Version-specific completion activity; no cross-version equivalence/scored trend service | `equivalence_rules`, automatic comparisons and `ai_comparisons`; default extra model calls | Leave disconnected; explicit budget/trigger/consent/retention decision and professional-only adapter required |
| Assets | Three approved bundled SVG references with version/hash and accessibility/locale mapping | Own manifest absent per docs; visual_description and unpinned asset references | Map only approved IDs; preserve asset hashes and licensing/accessibility metadata |
| Cloud readiness | Reviewed-production gate for `koi-companion-fyp`, still missing authenticated evidence/credentials | AI report says Firestore adapter/worker refuses non-demo/non-emulator configuration | No cloud compatibility claim; Ahmad must review AI guard/IAM separately, without touching live AI infrastructure during this handoff |

Source-of-truth Web job example (structural, not real IDs/secrets):

```json
{"job":{"id":"job_<hash>","organization_id":"org_<hash>","kind":"evaluate","state":"queued","created_at":"<server ISO>","updated_at":"<server ISO>"},"submission_id":"submission_<hash>","attempt_count":0,"idempotency_key":"submission_<hash>","revision":1}
```

AI's published five routes (generate/revise/critique/start/job status) are not mounted as a Web-to-AI integration here. Do not assume a matching path in two documents means a proxy exists. Patient clients must never invoke AI start/status/results. The platform's manual form, submit and review path works without that integration.

The AI docs report its own model/provider tests and gates; none were re-executed or independently verified here. Its readiness file is explicitly documentation-only and marks many paths assumed. Its direct-listener rules sketch and alternate-project recommendation are **not** accepted Web/cloud changes. Ahmad should pin both repositories, answer W1-W18 using this table, publish acknowledged versioned adapters/fixtures and only then consider an authorized, budgeted AI integration. Do not start its API/worker or call even `/health` during this transfer.

## 10. Tests, local operation and known limits

Credible recorded results (not rerun for handoff):

| Report | Result / scope |
| --- | --- |
| WEB-1 completion | 73 suites / 626 tests; 18 real emulator/browser checks; manual publish/CAS/auth isolation |
| WEB-2 completion | 78 suites / 661 tests; 15 real emulator/browser checks; lifecycle/races/revocation/review |
| WEB-3 completion | 79 suites / 668 at full checkpoint, later 2 route tests; 16 browser scenarios and 28 direct-denial checks |
| WEB-4 evidence | 83 suites / 678 at full checkpoint; later targeted Auth/navigation checks; seven browser groups, persistence export/import and mobile companion smoke at that earlier authorized local checkpoint |
| WEB-5 evidence | 86 suites / 688; TypeScript/build/contract validators; 740 platform + 80 legacy policy assertions; six real backend scenario groups; paid networking blocked |

Counts are historical checkpoints, not additive totals. WEB-5 is the latest full-suite baseline. Its real emulator tests are not live Firebase/IAM/index evidence. Diagnostic/failure artifacts are historical, not final acceptance. Some earlier tests inject clearly fictional AI result/failure fixtures; no production fallback/output is implied. Build/test logs ignored by Git may remain local; retained JSON/reports supply the checkpoint evidence. No rebuild or suite rerun occurred for handoff.

Emulator reproduction (optional development only): follow `WEB/review/web-4/DEMO-LOGIN-GUIDE.md`, `scripts/start-demo-emulators.ps1`, `demo-env.ps1`, `seed-koi-demo.cjs`. WEB-4 pins Auth 5199, Firestore 5180, Next 3107 and an offline demo namespace. Set your own passwords; local snapshots/Auth hashes are not shipped. The three documented emulator emails are `psychologist@koi-demo.example`, `general@koi-demo.example`, `patient@koi-demo.example`. Seeder reruns preserve domain edits; `-Fresh` starts a non-deleting disposable session without overwriting saved snapshots.

WEB-5 separate reference-policy config uses Auth 5499/Firestore 5480/Next 3207, avoiding existing WEB-4 processes. Its local namespace is not another Firebase cloud project. Test network isolation is via `scripts/web5-network-guard.cjs` in `NODE_OPTIONS`, telemetry off, and local-only platform paths. Never run a suite whose paid-service isolation is unproven. Do not run the old companion smoke script under the current no-paid-traffic handoff instructions.

Known limitations: public registration/email delivery absent; no anonymous migration; no Flutter parity; no AI worker completion integration; no validated instrument seed/scoring in Web; no external push/payment/calendar/double-booking guarantee; scoped bounded analytics; loaded search/counts; no offline questionnaire client; patient record retention/AI consent/cursor-key rotation/ingress invite-token log redaction and deployment streaming limits still need owner review. Old reference rules versus nested current companion sync remain a live-evidence question, not an invitation to change original behavior.

## 11. Explicit next-owner actions and release gates

1. The origin repository is public (GitHub metadata verified); Ahmad can read the handoff. Write/admin permissions for Ahmad are not asserted or changed; repository administrators should grant them if needed. Ahmad checks out the handoff branch without disturbing teammate branches; compare against `master` in AI repo, not default `main` for the referenced contracts.
2. Preserve existing Firebase `koi-companion-fyp`; complete read-only authenticated audit and exact rules evidence. Keep original users/chats/companion services intact. Do not create another project or reuse emulator credentials in cloud.
3. Obtain owner approval for any live rule/index/provisioning write, first rule out paid queue consumers, then prove the manual clinician/patient UI path using fictional records and protected reviews.
4. Reconcile AI job creation/IDs/states, authority paths, consent, versions, answers, review/results/rules and provider budget before any adapter/worker activation. Do not migrate or duplicate collections ad hoc.
5. Hand the signed-off contracts/assets/conflict/ack/relationship schemas to Mobile; locate and verify the actual Flutter source and supported direct-write policy (current platform uses backend-only writes).
6. Confirm retention, consent, deployment IAM/rules/indexes/stream proxy behavior/access revocation/log redaction, accessibility/RTL, account-cache separation, rollback and owner sign-off before release.

Ahmad's AI repository remains separate. No Web project was transplanted into it. No teammate branch, live service or existing data was altered. Git push verification and the final commit are recorded separately in the shipping summary/remote ref; this document does not claim an integration was deployed.

## Appendix A. Actual platform HTTP handlers

Generated by reading the existing `src/app/api/v1/**/route.ts` exports during handoff; no route was invoked. These 47 operations are distinct from unimplemented proposals in OpenAPI (including optional AI/registration operations). All use the existing authenticated platform boundary; access-events is the platform invalidation stream, not companion SSE.

| Method | Actual URL |
| --- | --- |
| POST | `/api/v1/appointments` |
| POST | `/api/v1/appointments/{id}/transition` |
| GET | `/api/v1/connection-requests` |
| POST | `/api/v1/connection-requests` |
| POST | `/api/v1/connection-requests/{id}/demo-payment` |
| POST | `/api/v1/connection-requests/{id}/transition` |
| GET | `/api/v1/experts` |
| GET | `/api/v1/experts/{id}` |
| GET | `/api/v1/me/access-events` |
| GET | `/api/v1/me/capabilities` |
| POST | `/api/v1/messages` |
| GET | `/api/v1/notifications` |
| POST | `/api/v1/notifications/{id}/read` |
| POST | `/api/v1/patient-invitations/{token}/redeem` |
| GET | `/api/v1/patient/assignments` |
| GET | `/api/v1/patient/assignments/{id}` |
| PATCH | `/api/v1/patient/attempts/{id}` |
| POST | `/api/v1/patient/attempts/{id}/submit` |
| GET | `/api/v1/professional/analytics` |
| POST | `/api/v1/professional/assignments` |
| GET | `/api/v1/professional/evaluations/{id}` |
| GET | `/api/v1/professional/evaluations/{id}/review-decisions` |
| GET | `/api/v1/professional/evaluations/{id}/reviews` |
| POST | `/api/v1/professional/organizations` |
| POST | `/api/v1/professional/patient-invitations` |
| POST | `/api/v1/professional/patient-invitations/{id}/revoke` |
| GET | `/api/v1/professional/patient-relationships` |
| GET | `/api/v1/professional/patient-relationships/{id}/archive` |
| POST | `/api/v1/professional/patient-relationships/{id}/archive` |
| POST | `/api/v1/professional/patient-relationships/{id}/close` |
| GET | `/api/v1/professional/patient-relationships/{id}/submissions` |
| GET | `/api/v1/professional/profile` |
| PUT | `/api/v1/professional/profile` |
| GET | `/api/v1/professional/questionnaire-versions/{id}` |
| GET | `/api/v1/professional/questionnaires` |
| POST | `/api/v1/professional/questionnaires` |
| GET | `/api/v1/professional/questionnaires/{id}` |
| PUT | `/api/v1/professional/questionnaires/{id}` |
| POST | `/api/v1/professional/questionnaires/{id}/publish` |
| POST | `/api/v1/professional/review-decisions` |
| POST | `/api/v1/professional/reviews` |
| GET | `/api/v1/professional/submission-notifications` |
| GET | `/api/v1/professional/submissions` |
| GET | `/api/v1/professional/submissions/{id}` |
| GET | `/api/v1/professional/submissions/{id}/workspace` |
| GET | `/api/v1/relationships/{id}/appointments` |
| GET | `/api/v1/relationships/{id}/messages` |
