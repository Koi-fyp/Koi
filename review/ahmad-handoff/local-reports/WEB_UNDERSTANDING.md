# KOI Web (nextjs_app): understanding for Ahmad

Generated 2026-10-20 at HEAD `ffc91f9201de4c1b690a7824c7ddbfe060776a91` (branch `handoff/koi-web-1-to-5-2026-10-20`), read-only, by an assistant session. Everything below was checked against source unless tagged [GUESS] or [NOT FOUND]. Paths are relative to APP = `E:\Koi\web-final\repos\koi-backend\nextjs_app` unless they start with a drive letter.

Tags: [FILE path:line] = read in source/doc; [RUN cmd] = command run in this session; [GUESS] = inference, not verified; [NOT FOUND] = looked for, absent.

## 0. EXECUTIVE SUMMARY

**Ten most important facts**
1. **This Next app is the whole platform backend.** It has 47 `/api/v1` handlers in 44 route files. They run through `service.ts` → `lifecycle.ts` → `community.ts` with the Firebase Admin SDK, and every write is in a Firestore transaction [§2]. The companion's chat/speech backend is external (`NEXT_PUBLIC_KOI_API_BASE`) and paid.
2. **Authority comes only from backend records.** That means `accounts`, `psychologist_verifications.state==='verified'`, an active org plus owner membership, and active `patient_relationships`. Capabilities are derived in one transaction [FILE src/lib/platform/server/service.ts:54-87]. Client roles and `users/{uid}` are never trusted.
3. **Patients get only a 4-field acknowledgement.** It is enforced by explicit DTOs plus `additionalProperties:false` schema checks on every response, and by tests [§2.8].
4. **Submit atomically creates the submission, an empty `clinician_evaluations` envelope, a professional notice, and `ai_jobs/job_<sha256("\"submission_…\"")>`** with a nested `job` wrapper [FILE lifecycle.ts:279-288]. Nothing ever updates the job, and Web calls no AI route. All five handoff claims (a)-(e) are VERIFIED [§4].
5. **Typecheck passes. Tests: 86 suites / 688, 687 pass, 1 fails** — the same failure Ahmad saw [§6].
6. **That failure is almost certainly line endings.** Pinned SVGs are LF in Git, CRLF in this checkout, and there is no `.gitattributes`; the test hashes raw bytes [§12]. The contract freeze-hash validators will likely fail the same way.
7. **Cloud mode re-validates rules evidence on every request.** Evidence expires 24 h after the audit, at which point the running server returns 503 [§9].
8. **Cloud provisioning writes ~30 docs and 3 Auth users into the production project, including one `ai_jobs` doc.** An unknown paid consumer of `ai_jobs` is therefore a real risk; the repo has no tool to rule it out [§9 step 5].
9. **Docs vs code.**
   - OpenAPI 0.5.2 still marks the implemented directory/messages/appointments/notifications/analytics operations as `proposed_not_implemented`.
   - The contracts README still describes 0.5.0 as a proposal.
   - The web-2…5 reports are in `APP\review\`, not `E:\Koi\web-final\review` [§1.3].
10. **A phone cannot use the emulator demo.** It is hard-coded to 127.0.0.1. Phone access needs cloud mode plus HTTPS, because `crypto.randomUUID`/`crypto.subtle` are needed for every platform write [§10].

**GO / NO-GO**
- **(A) Local emulator demo — GO.** All platform code paths are local and guarded to `demo-koi-platform-web1` on loopback. You need Java 21, Node 22 and `firebase-tools@15.34.0` (npx download), choose passwords, and avoid `/chat` [§8].
- **(B) Read-only cloud audit of koi-companion-fyp — GO, once Ahmad approves using `E:\Koi\private\koi-service-account.json` for reads.** `web5-cloud-audit.cjs` makes only GETs to four allowlisted Google APIs and writes local files only. Pass the file path explicitly [§9 step 1].
- **(C) Cloud activation with writes — NO-GO.** There is no live-rules evidence and no proof that nothing paid consumes `ai_jobs`, and the owner has not authorized writes. Provisioning itself creates an `ai_jobs` doc [§9].
- **(D) AI integration — NO-GO.** Web and AI disagree on job ownership, ID, shape and states. There are no worker or claim/complete endpoints, no AI-consent storage, and no approved budget [§11].

Untracked/tracked changes at the end of this session: see the end of PROGRESS.md (expected: no tracked changes).

---

## 1. READ ORDER AND DOC SUMMARY

### 1.1 Where the documents actually are

| Requested | Actual location | Note |
| --- | --- | --- |
| `REVIEW\final-handoff\*` | `E:\Koi\web-final\review\final-handoff\` | Found as stated. |
| `REVIEW\web-5\…`, `web-4`, `web-3`, `web-2` | **Not** under `E:\Koi\web-final\review\`. Found at `APP\review\web-5\`, `APP\review\web-4\`, `APP\review\web-3\`, `APP\review\web-2\` | [RUN Glob] The only thing in `E:\Koi\web-final\review` is `final-handoff/`. The handoff itself calls them `WEB/review/web-N/`, so APP\review is the intended home. |
| `contracts\implementations\WEB-*.md` | Only `WEB-1.md` and `WEB-2.md` exist | [NOT FOUND] for WEB-3/4/5 implementation notes. WEB-3 coverage lives in `contracts/v0.5.2/CHANGELOG.md` and `review/web-3/`. |
| v0.5.1 CHANGELOG | `contracts/v0.5.1/CHANGELOG.md` | Found. |

Suggested read order for Ahmad: `AHMAD_START_HERE.md` → `KOI_WEB_1_TO_5_AHMAD_HANDOFF.md` §4–§9 → `review/web-5/DEMO-DEPLOYMENT.md` → `review/web-4/DEMO-LOGIN-GUIDE.md` → `contracts/v0.5.2/semantics.md` → this file §2–§3.

### 1.2 Summaries

- **AHMAD_START_HERE.md** [FILE E:\Koi\web-final\review\final-handoff\AHMAD_START_HERE.md:1-83]: the short version. Take the branch; only use Firebase project `koi-companion-fyp`; no live writes or paid AI calls without approval. Order: read-only audit → verify the published rules in local emulators → prove no paid consumer of `ai_jobs` → configure `reviewed-production` → owner-authorized fictional provisioning → manual UI checklist (§3, 20 items). AI integration comes later and is blocked by an `ai_jobs` collision. Claims 86 suites / 688 tests (line 74).
- **KOI_WEB_1_TO_5_AHMAD_HANDOFF.md** [FILE …\KOI_WEB_1_TO_5_AHMAD_HANDOFF.md:1-316]: the full technical handoff. It covers architecture (§1), batch status (§2), UI routes (§3), the source map (§4), the Firestore collection table (§5), the questionnaire/review lifecycle (§6), community features (§7), the cloud action sequence (§8), the AI-repo comparison and 17-row blocking-difference table (§9), tests (§10), and Appendix A with 47 actual HTTP operations. Its route list matches the code exactly (see §2.2).
- **SHIPMENT-MANIFEST.json**: the packaging record. Baseline `f2b9c80`, 155 `included_changed_files` + 2 metadata files = `expected_changed_file_count: 157`. It also lists excluded local items (`.env.local`, `.local/`, `.local-emulator-data/`, credentials) and activity counters, all 0.
- **SECRET-SCAN.json** (reported only): `passed: true` and `findings: []`. Three "synthetic fixture matches" are listed: `repos/koi-ai-engine/.env.template:12` (private_key rule), plus `src/__tests__/setup.env.ts:1` (google_api_key) and `:11` (private_key). None were newly staged. Values were not opened.
- **web-5/DEMO-DEPLOYMENT.md**: the cloud runbook. §1 audit, §2 local exact-rules test + evidence, §3 optional rules/index deploy, §4 local production Next against cloud, §5 fictional provisioning, §6 routes, §7 rollback (manual only). Details are in §9 below.
- **web-5/EXISTING-FIREBASE-INTEGRATION.md**: what was observed (`.env.local` targets `koi-companion-fyp`; no Admin credential; no CLI login) and what was reused or isolated: named client app, named Admin app, and a `[DEFAULT]`-by-name fix in `firebase-admin.ts`. It describes the "smallest safe activation path" and warns that additive denies cannot override a broad live allow.
- **web-5/SECURITY-VERIFICATION.md**: the claimed WEB-5 results. 86/688 Jest, tsc, build, 740 rules denials + 80 legacy assertions, 6 real-backend scenario groups, cloud inspection BLOCKED. It also lists what was deliberately skipped: live AI, cloud provisioning, IAM/App Check.
- **web-4/SCREEN-ROUTES.md**: 30 GUI routes/sections with access rules (§2.1 below).
- **web-4/DEMO-LOGIN-GUIDE.md**: the local emulator demo. Three fictional accounts (`psychologist@` / `general@` / `patient@koi-demo.example`), operator-chosen passwords, a 3-terminal startup, an 11-step walkthrough, export/import persistence, `-Fresh` mode and verification harnesses.
- **web-4/WEB-4-COMPLETION.md**: covers the seeder, `/account`, capability menus and mobile fixes. 83 suites / 678 tests at that checkpoint.
- **web-3/WEB-3-COMPLETION.md**: covers directory, messages, appointments, notifications, analytics and the roster. 79/668 (+2 route tests) at that checkpoint; 16 browser scenarios; 28 direct-denial checks.
- **web-2/WEB-2-COMPLETION.md**: covers invitations/applications, relationships, assignments, the runner/autosave, atomic submit with queued job and empty evaluation, append-only review, and the access stream. 78/661 at that checkpoint.
- **contracts/README.md**: the freeze discipline: never edit a frozen version, add a new version directory instead. The header line points at 0.5.2, but the body still describes 0.5.0 as "a local contract freeze proposal … not an implemented API" (lines 5-9).
- **contracts/implementations/WEB-1.md, WEB-2.md**: implementation coverage tables for 0.5.0/0.5.1, operational limits (512,000-byte body, 400,000-byte content, list default 25 / max 100, 15-minute cursors, 5-minute fresh auth), and a Mobile/AI note.
- **contracts/v0.5.2/semantics.md**: WEB-3 rules for the directory, messages, appointment state machine, notification materialization (≤200 per page, ≤10,000 sources), professional_notifications, analytics bounds (10,000 rows / 1,000 versions / 200 points), and archives.
- **contracts/v0.5.2/authorization-matrix.md**: backend read/write authority for the 9 WEB-3 collection groups. All direct client access is denied.
- **contracts/v0.5.2/CHANGELOG.md** and **v0.5.1/CHANGELOG.md**: additive packages. Wire DTO literals stay `0.5.0`. 0.5.1 adds the roster, submission list, workspace and review decisions. 0.5.2 adds profile, archive, patient history and submission notifications.
- **contracts/v0.5.2/openapi.json**: `info.version` 0.5.2. 51 path entries, 58 operationIds, 53 carry `x-status`. Includes proposed `/api/v1/ai/*`, `/api/v1/accounts/*` and `/internal/v1/evaluation-jobs/{claim,complete,fail}` [FILE contracts/v0.5.2/openapi.json:5170,5294,5426].
- **contracts/v0.5.2/contracts.schema.json**: the Draft-07 definitions. **The running server validates every request and response against this file** [FILE src/lib/platform/server/contract.ts:3,11-18].
- **contracts/v0.5.2/fixtures.json**: `valid` (line 2) and `invalid` (line 452) fixture arrays. Validated only by `scripts/validate-web3-contract.cjs`, which was not run here.

### 1.3 Contradictions (doc vs doc, doc vs code)

1. **OpenAPI status vs implementation.** `contracts/v0.5.2/openapi.json` marks `listExperts` (line 1076), `getExpert` (1195), `getProfessionalAnalytics` (3234), `createHumanMessage` (3809), `listHumanMessages` (3928), `createAppointment` (4055), `listAppointments` (4174), `transitionAppointment` (4301), `listNotifications` (4428) and `markNotificationRead` (4547) as `"x-status": "proposed_not_implemented"`. On the other side, `contracts/v0.5.2/CHANGELOG.md:5` says "Implemented existing directory, human messaging, appointments, in-app notifications and professional activity analytics operations", and the route files exist (e.g. [FILE src/app/api/v1/experts/route.ts:5], [FILE src/app/api/v1/messages/route.ts:5]). The four new WEB-3 operations (`updateProfessionalProfile` 6169, `getOwnProfessionalProfile` 6205, `listSubmissionNotifications` 6236, `getPatientArchive` 6281, `archivePatient` 6307) have **no** `x-status`. `listPatientSubmissionHistory` (6355) says `web2_implemented` although it was added in WEB-3 ([FILE review/web-3/CHANGED-FILES.md] lists its route). **A mobile or AI developer reading OpenAPI status will be misled.**
2. **contracts/README.md is stale.** "This is a **local contract freeze proposal**, version **0.5.0** … It is not an implemented API" [FILE contracts/README.md:6-8] vs line 3 "WEB-3 additive package: 0.5.2" and 47 implemented handlers.
3. **Test totals.** Docs say "Latest credible Web checkpoint: **86 suites / 688 tests**" [FILE AHMAD_START_HERE.md:74] and "PASS: **86 suites / 688 tests**" [FILE review/web-5/SECURITY-VERIFICATION.md:7]. This checkout gives `Tests: 1 failed, 687 passed, 688 total` [RUN npm test -- --runInBand]; see §6 and §12.
4. **Firebase CLI provenance.** DEMO-LOGIN-GUIDE says "Firebase CLI 15.34.0 through npx" [FILE review/web-4/DEMO-LOGIN-GUIDE.md:3], and the script runs `npx --yes --package firebase-tools@15.34.0 firebase emulators:start …` [FILE scripts/start-demo-emulators.ps1:9,17]. DEMO-DEPLOYMENT says "already installed Firebase CLI 15.34.0 … Run the locally installed/cached Firebase CLI; do not invoke package downloads under this guard" and uses bare `firebase emulators:start …` [FILE review/web-5/DEMO-DEPLOYMENT.md:23,30,33].
5. **Paths in docs are the previous owner's machine.** "Run from `C:\Users\PMYLS\Koi\repos\koi-backend\nextjs_app`" [FILE review/web-5/DEMO-DEPLOYMENT.md:3], [FILE review/web-4/DEMO-LOGIN-GUIDE.md:3,22]. `NODE_OPTIONS='--require=C:/Users/PMYLS/…/web5-network-guard.cjs'` [FILE review/web-5/DEMO-DEPLOYMENT.md:26]. Real path: `E:\Koi\web-final\repos\koi-backend\nextjs_app`. Doc credential path `C:\private\koi-service-account.json` [FILE review/web-5/DEMO-DEPLOYMENT.md:10,80] → use **`E:\Koi\private\koi-service-account.json`**.
6. **Branch name.** WEB-2/3/4 completions say `feat/web-1-professional-publishing` [FILE review/web-4/WEB-4-COMPLETION.md:3]. The shipped branch is `handoff/koi-web-1-to-5-2026-10-20`. These are historical branch names, not a functional conflict.
7. **Index proposal vs code.** `review_records` gets an `(organization_id, psychologist_uid)` composite [FILE dev/web5-reference/firestore.indexes.json:205-221] [FILE scripts/web5-artifacts.cjs:15]. But `review_records` documents have no `psychologist_uid` field (written as `{...review, decision}` with `reviewer_uid`) [FILE src/lib/platform/server/lifecycle.ts:345-346], and the list query for reviews always uses `evaluation_id` because routes always pass an id [FILE src/lib/platform/server/lifecycle.ts:369] [FILE src/app/api/v1/professional/evaluations/[id]/reviews/route.ts:5]. [GUESS] The index is unused but harmless.
8. **Notification "read" path writes on GET.** Docs say "Inbox refresh is manual" [FILE contracts/v0.5.2/semantics.md:8]. That is true, but note that `GET /api/v1/notifications` **writes** `notifications` documents on the first page (assignment notices materialization) [FILE src/lib/platform/server/community.ts:195,225-247]. This matters for any "read-only cloud check" by GET: it is not read-only.
9. **Access invalidation outbox.** The handoff says "`access_invalidation_outbox/{receiptId}` … stream independently reauthorizes" [FILE KOI_WEB_1_TO_5_AHMAD_HANDOFF.md:126]. In code, the outbox is only written [FILE src/lib/platform/server/lifecycle.ts:51] and never read (`git grep` finds no reader). The SSE stream instead re-runs `capabilities()` every 2 s [FILE src/app/api/v1/me/access-events/route.ts:22-29]. Consistent with "independently reauthorizes", but the outbox is dead data today.
10. **Export of existing indexes.** DEMO-DEPLOYMENT requires exporting the "complete existing Firestore index/field-override configuration in Firebase CLI format" [FILE review/web-5/DEMO-DEPLOYMENT.md:15]. No repo script does this, and the audit writes the raw REST response [FILE scripts/web5-cloud-audit.cjs:36]. [NOT FOUND] for a command; it needs the Firebase CLI (see §9).

### 1.4 SHIPMENT-MANIFEST.json vs `git ls-files`

- [RUN git show --name-status ffc91f9] lists exactly the 155 manifest paths plus the 2 metadata files (SECRET-SCAN.json, SHIPMENT-MANIFEST.json) = 157, in the same order.
- [RUN git ls-files -s …] Every manifest `index_blob` checked matches the current index blob. That covers all of contracts/v0.5.2, dev/web5-reference, scripts, src/lib/platform/server, review/web-2…5, src/__tests__, src/app (including all 15 api/v1 route files in the manifest), components, contexts, lib. **No mismatches found.** The two final-handoff `.md` blobs live at repo root `review/final-handoff/`; their blob ids were not re-listed, since `git show` already confirms presence.
- Excluded items (`.env.local`, `.local/`, `.local-emulator-data/`) are untracked/ignored. [RUN git status --short] was clean after creating `.local/ahmad/`, which confirms `.local/` is ignored by a higher-level rule. APP `.gitignore` only names `.local/koi-demo/` and `.local/koi-web5/` [FILE .gitignore:11,14].

---

## 2. ARCHITECTURE MAP

### 2.1 Page routes (`src/app/**/page.tsx`, 17 files)

| Route | File | Gate |
| --- | --- | --- |
| `/` (bare redirects into companion; `/?home=1` stays on landing) | `src/app/page.tsx` | Public |
| `/account` | `src/app/account/page.tsx` (+ layout) | Public sign-in through the **named** platform Auth app |
| `/patient` (`?view=experts|care|questionnaires|messages|appointments|notifications`) | `src/app/patient/page.tsx` → `PatientApp` | Client-side; every data call goes to `/api/v1/*`, which re-authorizes |
| `/professional` (`?view=dashboard|questionnaires|patients|submissions|analytics`, `?version=ID`) | `src/app/professional/page.tsx` → `ProfessionalApp` | Same |
| `/onboarding`, `/about`, `/how-it-works`, `/avatar-host` | `src/app/*/page.tsx` | Original companion / public |
| `/chat`, `/companion-scene`, `/history`, `/progress`, `/settings`, `/settings/{privacy,export,import,report}` | `src/app/(authenticated)/**/page.tsx` | Original companion session (default Firebase app) |

Menu links come only from `GET /api/v1/me/capabilities` [FILE src/lib/platform/navigation.ts:4-17]: `expert_directory` → Find an Expert; `active_patient_relationships.length` → My Psychologist / Questionnaires / Messages / Appointments / Notifications; `professional_workspace` → the 5 professional links.

### 2.2 `/api` routes (44 route files, 47 method handlers + 2 companion routes)

Common to every `/api/v1` route:
- Bearer token required; `verifyIdToken(token, true)` (revocation/disabled check) plus `aud`/`iss` pinned to the configured project [FILE src/lib/platform/server/runtime.ts:18-27].
- Non-GET requests need an `Idempotency-Key` (schema `Id`) and a JSON body of at most 512,000 bytes [FILE src/lib/platform/server/http.ts:10-23,34-37].
- Responses are `Cache-Control: private, no-store`.
- "Fresh" means the Firebase `auth_time` is ≤300 s old (−30 s tolerance) [FILE src/lib/platform/server/service.ts:23-26].
- "Owner" means: registered `accounts`, `psychologist_verifications.state==='verified'`, active `organizations` owned by the uid, and an active owner `organization_memberships` document [FILE service.ts:27-37].
- "General" means `accounts.state==='registered' && general_access===true` [FILE lifecycle.ts:26-30].
- "Active patient" means General + `patient_relationships.state==='active'` + the psychologist still passes Owner [FILE lifecycle.ts:40-48].

| Method | URL | Handler → service | Auth / role | Collections read (R) / written (W) |
| --- | --- | --- | --- | --- |
| GET | /api/v1/me/capabilities | http.ts → `capabilities` [service.ts:54-87] | Any valid Firebase token (incl. anonymous) | R accounts, psychologist_verifications, organization_owners, organizations, organization_memberships, patient_relationships (query ≤201) |
| GET | /api/v1/me/access-events | own route [access-events/route.ts:7-38] | registered account; SSE, polls capabilities every 2 s, max 250 s | same as capabilities, repeatedly |
| POST | /api/v1/professional/organizations | `createOrganization` [service.ts:88-112] | fresh; registered+verified | R …; W organization_owners, organizations, organization_memberships, idempotency_records, audit_events |
| POST/GET | /api/v1/professional/questionnaires | `createDraft` [113-125] / `listDrafts` [197-209] | fresh (POST); Owner | W/R questionnaires (+idem/audit) |
| GET/PUT | /api/v1/professional/questionnaires/{id} | `getDraft` / `updateDraft` (CAS) [134-151] | Owner; PUT fresh | R/W questionnaires |
| POST | /api/v1/professional/questionnaires/{id}/publish | `publish` [152-170] | fresh; Owner; revision+sha256 match | W questionnaire_versions |
| GET | /api/v1/professional/questionnaire-versions/{id} | `getVersion` [171-180] | Owner | R questionnaire_versions |
| POST | /api/v1/professional/patient-invitations | `createInvitation` [lifecycle.ts:65-89] | fresh; Owner; 30/h | W platform_rate_limits, patient_invitations, invitation_token_lookup |
| POST | /api/v1/professional/patient-invitations/{id}/revoke | `revokeInvitation` [90-105] | fresh; Owner | W patient_invitations |
| POST | /api/v1/patient-invitations/{token}/redeem | `redeemInvitation` [106-128] | fresh; General; consent `care-consent-v1`; 60/h | R invitation_token_lookup, patient_invitations; W patient_relationships, accounts (revision bump), access_invalidation_outbox, patient_invitations |
| POST | /api/v1/professional/patient-relationships/{id}/close | `closeRelationship` [129-146] | fresh; Owner (own relationship) | W patient_relationships, accounts, access_invalidation_outbox |
| GET | /api/v1/professional/patient-relationships | `list('relationships')` [353-386] | Owner | R patient_relationships |
| POST/GET | /api/v1/connection-requests | `createConnection` [147-175] / `list('connections')` | POST fresh, General, 30/h, profile discoverable+accepting; GET owner→org list, else own | W connection_requests, notifications |
| POST | /api/v1/connection-requests/{id}/transition | `transitionConnection` [176-202] | fresh; applicant (General) or owning psychologist | W connection_requests, notifications, on accept patient_relationships + accounts + outbox |
| POST | /api/v1/connection-requests/{id}/demo-payment | `transitionConnection(…, true)` | fresh; applicant only | W demo_payments, connection_requests, notifications |
| POST | /api/v1/professional/assignments | `assign` [203-231] | fresh; Owner; ≤200 targets | R questionnaire_versions, patient_relationships, accounts; W assignments, attempts |
| GET | /api/v1/patient/assignments | `list('assignments')` | General; each row checked as active patient | R assignments, patient_relationships, attempts, questionnaire_versions |
| GET | /api/v1/patient/assignments/{id} | `patientDetail` [248-257] | active patient owning it | same |
| PATCH | /api/v1/patient/attempts/{id} | `saveAttempt` [258-296] | active patient (**not** fresh) | W attempts, assignments |
| POST | /api/v1/patient/attempts/{id}/submit | `saveAttempt(…, true)` | fresh; active patient | **W submissions, professional_notifications, ai_jobs, clinician_evaluations**, attempts, assignments |
| GET | /api/v1/professional/submissions | `list('submissions')` | Owner | R submissions, assignments |
| GET | /api/v1/professional/submissions/{id} | `getSubmission` [306-308] | Owner (`psychologist_uid` match) | R submissions, assignments |
| GET | /api/v1/professional/submissions/{id}/workspace | `workspace` [326-334] | Owner | R submissions, assignments, clinician_evaluations, questionnaire_versions, **ai_jobs**, review_heads |
| GET | /api/v1/professional/evaluations/{id} | `getEvaluation` [323-325] | Owner | R clinician_evaluations, submissions, assignments, review_heads |
| POST | /api/v1/professional/reviews | `createReview` [335-352] | fresh; Owner | W review_records, review_heads |
| POST | /api/v1/professional/review-decisions | `createReview(…, true)` | fresh; Owner | same, with `decision` approve/reject/feedback |
| GET | /api/v1/professional/evaluations/{id}/reviews, …/review-decisions | `list('reviews'|'decisions')` | Owner | R review_records |
| GET | /api/v1/professional/patient-relationships/{id}/submissions | `patientHistory` [community.ts:21-31] | Owner | R patient_relationships, submissions |
| GET/POST | /api/v1/professional/patient-relationships/{id}/archive | `archive` [32-50] | Owner; POST fresh, closed relationship only | R/W patient_archives |
| GET | /api/v1/professional/submission-notifications | `submissionNotices` [51-59] | Owner | R professional_notifications |
| GET/PUT | /api/v1/professional/profile | `profile` [60-78] | Owner; PUT fresh | R/W psychologist_profiles (adds `directory_scope:'public_profiles'`) |
| GET | /api/v1/experts, /api/v1/experts/{id} | `experts` [79-94] | General; each profile re-checked as Owner | R psychologist_profiles + authority docs |
| GET | /api/v1/professional/analytics | `analytics` [95-117] | Owner; bounded scans | R assignments, submissions |
| POST | /api/v1/messages | `sendMessage` [132-146] | fresh; active participant | W messages, notifications |
| GET | /api/v1/relationships/{id}/messages, …/appointments | `conversation` [183-192] | active participant | R messages / appointments |
| POST | /api/v1/appointments | `appointment` [147-182] | fresh; patient only (psychologist → 403) | W appointments, notifications |
| POST | /api/v1/appointments/{id}/transition | `appointment(…, id)` | fresh; actor-specific state machine | W appointments, notifications |
| GET | /api/v1/notifications | `notifications` [193-216] | registered; per-notice access check | R notifications, connection_requests, relationships; **W notifications (assignment materialization)** |
| POST | /api/v1/notifications/{id}/read | `notifications(…, id)` | registered + access (not fresh) | W notifications.read_at |
| POST | /api/auth/anonymous | companion | **unauthenticated** | Admin: createCustomToken; W `users/{uuid}` [FILE src/app/api/auth/anonymous/route.ts:5-32] |
| POST | /api/auth/link-email | companion | (see file) | W `users/{uid}` merge [FILE src/app/api/auth/link-email/route.ts:30] |

The Appendix A list in the handoff (47 operations) matches these files exactly [RUN Grep export function GET|POST… in src/app/api/v1].

### 2.3 Layers under `src/lib/platform`

- **Shared/client:** `types.ts`, `patient-types.ts` (patient-safe only; `CARE_CONSENT_VERSION='care-consent-v1'`), `professional-types.ts` (evaluation/job/review types; "Import only from professional screens or server"), `community-types.ts`, `content.ts` (content validation), `answers.ts`, `canonical.ts` (RFC 8785-style JSON + browser SHA-256), `illustrations.json` (3 pinned SVG assets), `navigation.ts`, `client.ts` (bearer fetch, relative `/api/v1/` only, idempotency key reuse), `professional-auth.ts` (named Auth app), `access-monitor.ts` (SSE client that locks/clears protected UI).
- **Server (`server/`, all `import 'server-only'`):**
  - `runtime.ts` (token verification, builds `CommunityService`)
  - `admin-config.cjs` (mode gate + named Admin app)
  - `production-evidence.cjs` (rules evidence validation; requires `scripts/web5-artifacts.cjs` at runtime [FILE production-evidence.cjs:2])
  - `contract.ts` (JSON Schema from contracts/v0.5.2, `hash()` = sha256 of canonical JSON)
  - `errors.ts`
  - `store.ts` (transaction interface) and `firestore-store.ts` (Admin `runTransaction`, equality filters + `orderBy(__name__)`)
  - `service.ts` (`PlatformService`: authority, idempotency receipts, audit, cursors, WEB-1 ops), `lifecycle.ts` (`LifecycleService extends PlatformService`: WEB-2), `community.ts` (`CommunityService extends LifecycleService`: WEB-3)
  - HTTP adapters `http.ts`, `lifecycle-http.ts`, `community-http.ts`
- **Mode gate** [FILE src/lib/platform/server/admin-config.cjs:6-28]:
  - `emulator` requires a `demo-*` project plus loopback `FIRESTORE_EMULATOR_HOST`/`FIREBASE_AUTH_EMULATOR_HOST`. Cursor key defaults to a demo constant.
  - `reviewed-production` requires: no emulator vars; `KOI_PLATFORM_RULESET_SHA256` (64 hex); project `koi-companion-fyp`; matching public project ids; no emulator flags; `FIREBASE_ADMIN_SDK` service account of that project; fresh evidence file; cursor key ≥32 characters and not the demo constant.
  - Anything else throws → every platform route returns **503 unavailable** [FILE runtime.ts:14].
  - **`configuration()` runs on every request** (via `getPlatformRuntime` → `getPlatformAdmin`), so evidence older than 24 h makes the running server return 503 mid-demo [FILE admin-config.cjs:21,31] [FILE production-evidence.cjs:5-6].

### 2.4 Two Firebase client apps

- **Companion (default `[DEFAULT]` app)** [FILE src/lib/firebase.ts:41-63]: configured from `NEXT_PUBLIC_FIREBASE_*`. Connects to emulators 127.0.0.1:5199/5180 only when `NEXT_PUBLIC_KOI_COMPANION_DEMO_EMULATOR==='true'`, `NODE_ENV==='development'`, project `demo-koi-platform-web1` and auth URL `http://127.0.0.1:5199` [FILE src/lib/auth/demoEmulatorMode.ts:2-5]. Guest sign-in goes through `/api/auth/anonymous` + custom token, or genuine anonymous auth when `NEXT_PUBLIC_KOI_LOCAL_TEST_ANON` is set (see `src/lib/auth/anonymousSignInMode.ts`).
- **Platform (named `koi-professional-web1`)** [FILE src/lib/platform/professional-auth.ts:8-27]: email/password; project = `NEXT_PUBLIC_KOI_PLATFORM_FIREBASE_PROJECT_ID || NEXT_PUBLIC_FIREBASE_PROJECT_ID`. The emulator is allowed only in development + `demo-*` project + `http://localhost|127.0.0.1`. Signing in or out here does not touch the companion session.
- **Server:** the platform uses named Admin app `koi-platform-server-web1` [FILE admin-config.cjs:32-36]. The companion uses `[DEFAULT]` from `FIREBASE_ADMIN_SDK`, found by name [FILE src/lib/firebase-admin.ts:3-10]. Coexistence is tested in `src/__tests__/firebase-admin-coexistence.test.ts`.

### 2.5 How capabilities are derived [FILE src/lib/platform/server/service.ts:54-87]

Everything runs inside one Firestore transaction:
- `registered` = `accounts/{uid}.uid===uid && state==='registered'`.
- `professional` = registered && `psychologist_verifications/{uid}.state==='verified'`. It is then downgraded unless `organization_owners/{uid}` points to an active organization owned by the uid **and** an active owner membership `member_${hash([uid,org])}` exists.
- `general` = registered && `general_access===true`.
- Active relationships are queried only when general (≤201; more than 200 → 403). Each one is kept only if its psychologist still passes Owner.
- Output: `capabilities.{companion_account_sync: general, expert_directory: general, professional_workspace, create_organization: professional && !owner}`, `professional_organization_ids`, `active_patient_relationships[]`, `contract_version:'0.5.0'`.
- Client `users/{uid}`, `isAnonymous` and custom claims are never consulted.

### 2.6 Review flow

1. Submit creates `clinician_evaluations/evaluation_<hash(sid)>` with `validated_scores:[]`, `evidence:[]`, `review_status:'unreviewed'` [FILE lifecycle.ts:283].
2. The professional opens the workspace: submission + pinned version + evaluation + job projection + `review_revision` [lifecycle.ts:326-334].
3. `POST reviews|review-decisions` with `expected_review_revision` (CAS on `review_heads/{evaluationId}`) appends `review_records/review_<hash([eid,revision])>` with `conclusion`, optional `feedback`, `decision` (default `feedback`) and sets the head revision [lifecycle.ts:335-352].
4. The evaluation document is **never modified**. The DTO computes `review_status` from the head [lifecycle.ts:317,324]. Test: "appends approve/reject/feedback revisions without touching original AI output" [FILE src/__tests__/platform/lifecycle.test.ts:170-184].

### 2.7 Notification payloads

- `notifications/{id}`: stored `{id, event_id, recipient_uid, relationship_id?, organization_id, kind, reference:{one id}, created_at, read_at?}`.
  - Kinds: `new_message`, `appointment_change` (relationship-scoped, id `notice_${hash([event, recipient])}`) [FILE community.ts:127-131]; `assignment` (id `notice_${hash(['assignment', assignmentId, uid])}`) [community.ts:236-239]; `application_state` (id `notice_${hash([requestId, revision])}`, no relationship_id) [lifecycle.ts:171,197].
  - DTO strips to `{id, event_id, kind, reference:{message_id|appointment_id|assignment_id|connection_request_id}, created_at, read_at?}` [FILE community.ts:15-18].
- `professional_notifications/notice_<sid>`: `{id, event_id: sid, submission_id, organization_id, recipient_uid, created_at}` [lifecycle.ts:287]. DTO `{id, event_id, submission_id, created_at}` [community.ts:57]; Owner only.
- No score, interpretation, job state or answers appear in any notification.

### 2.8 How patient responses stay free of scores, interpretations and evaluation status

Code:
1. Patient types have no evaluation fields [FILE src/lib/platform/patient-types.ts:1-13]. Evaluation/job/review types live in `professional-types.ts`.
2. Every response passes `this.output(schema, dto)` = `checkSchema` against contracts/v0.5.2 with `additionalProperties:false` [FILE service.ts:52] [FILE contract.ts:11-18]. For example, `PatientSubmitAckDTO` allows only `attempt_id, assignment_id, submitted_at, status:'submitted'` [FILE contracts/v0.5.2/contracts.schema.json:1551-1574].
3. Explicit field picking: `assignmentDTO` [lifecycle.ts:232-235], `patientDetail` in-progress/submitted shapes [248-257], `ack()` [236]. Submit returns only `ack` [289].
4. All professional reads go through `scopedSubmission`/`scopedEvaluation`, which call `authority()` (verified Owner) first [lifecycle.ts:297-316].
5. Notification DTOs carry reference ids only [community.ts:15-18]. Submission notices are in a separate Owner-only collection and route [community.ts:51-59].
6. Direct Firestore client access is denied: emulator deny-all `dev/platform-emulator/firestore.rules`; candidate patch `dev/web5-reference/platform-deny.patch.rules` (37 roots incl. `ai_jobs`, `clinician_evaluations`, `review_records`).

Tests:
- [FILE src/__tests__/platform/lifecycle.test.ts:118-127] ack has exactly 4 keys; one job.
- [lifecycle.test.ts:135-146] patient/other patient/guest get 403 on submission, evaluation, workspace and review; other psychologist gets 404.
- [lifecycle.test.ts:147-157] nested `evaluation`/`interpretation` injected into stored records never appears in patient responses; contaminated version → 422.
- [FILE src/__tests__/platform/lifecycle-routes.test.ts:30-45,53] real handlers end to end; SSE carries hints only.
- [FILE src/__tests__/platform/community.test.ts:87] notification isolation.
- [FILE src/__tests__/platform/patient-runner.test.tsx:13] UI returns only the acknowledgement.
- Scripts (not run here): [FILE scripts/validate-web05-contract.cjs:55-65] no patient-reachable schema reaches evaluation/job/review definitions or fields. [FILE scripts/web5-backend-functional.cjs:58-59] recursive DTO scan over real HTTP.

---

## 3. COLLECTIONS

All platform writes happen inside `store.transaction` → Admin `db.runTransaction` [FILE src/lib/platform/server/firestore-store.ts:8]. Exceptions are noted in the table. Queries are equality filters plus `orderBy(__name__)`, limit ≤201 [firestore-store.ts:15-22].

| Collection / id | Fields written | Writer (file:line) | Readers |
| --- | --- | --- | --- |
| `accounts/{uid}` | `uid, state, general_access, registration_method, registration_evidence_id, registered_at, authorization_revision` [types.ts:33-36] | seeders only: `scripts/platform-verify-psychologist.cjs:27-30` (general_access false), `scripts/seed-koi-demo.cjs:22`, `scripts/web5-provision-core.cjs:60`; revision bump `lifecycle.ts:50` | service.ts:28,56; lifecycle.ts:27,138; community.ts:197,231 |
| `psychologist_verifications/{uid}` | `uid, state, revision, changed_at, changed_by, audit_id` | `scripts/platform-verify-psychologist.cjs:31` only | service.ts:29,57 |
| `organization_owners/{uid}` | `uid, organization_id` | service.ts:104 | service.ts:58,94; lifecycle.ts:155,360 |
| `organizations/org_<hash(uid)>` | `id, owner_uid, name, state, created_at` | service.ts:105 | service.ts:32,65,98 |
| `organization_memberships/member_<hash([uid,org])>` | `id, organization_id, uid, kind:'owner', state, revision, created_at` | service.ts:107 | service.ts:33,66 |
| `psychologist_profiles/{uid}` | `id, organization_id, display_name, bio, discoverable, accepting_new_patients, revision, directory_scope` | community.ts:74 | community.ts:67,88,90; lifecycle.ts:159 |
| `patient_relationships/relationship_<hash([org,patient])>` | `id, organization_id, patient_uid, psychologist_uid, state active/closed, consent_version, activated_at, closed_at?, revision` | lifecycle.ts:122,141,195 | many (capabilities, patientRelation, assign, participant) |
| `connection_requests/request_<hash([uid,org])>` | `id, organization_id, applicant_uid, psychologist_uid, state, demo_payment_state, revision, created_at, updated_at, consent_version` | lifecycle.ts:170,196 | lifecycle.ts:163,181; community.ts:219 |
| `patient_invitations/invite_<hash(rid)>` | `id, organization_id, psychologist_uid, intended_uid?, nonce, token_hash, state, expires_at, revision, redeemed_by?` | lifecycle.ts:83,101,123 | lifecycle.ts:74,95,115 |
| `invitation_token_lookup/{sha256(token)}` | `invitation_id, organization_id` | lifecycle.ts:84 | lifecycle.ts:114 |
| `questionnaires/form_<hash>` | `id, organization_id, psychologist_uid, revision, content, created_at, updated_at` | service.ts:121,147 | service.ts:129; firestore-store.ts:24 |
| `questionnaire_versions/version_<hash([org,qid,rev])>` | `id, questionnaire_id, organization_id, psychologist_uid, source_revision, content, content_sha256, published_at, schema_version:'0.5.0'` | service.ts:166 | service.ts:159,175; lifecycle.ts:208,243,330 |
| `assignments/assignment_<hash([rid,relId])>` | `id, organization_id, relationship_id, patient_uid, psychologist_uid, questionnaire_version_id, attempt_id, state, created_at, due_at?, idempotency_key` | lifecycle.ts:226,292 | lifecycle.ts:239,302; community.ts:103,234 |
| `attempts/attempt_<hash(aid)>` | `id, assignment_id, patient_uid, organization_id, relationship_id, version_id, status, answers, revision, server_updated_at, submitted_at?, submission_id?` | lifecycle.ts:226,292 | lifecycle.ts:243,264 |
| `submissions/submission_<hash(attemptId)>` | Submission fields + `psychologist_uid` | lifecycle.ts:286 | lifecycle.ts:299; community.ts:28,103 |
| `clinician_evaluations/evaluation_<hash(sid)>` | `id, organization_id, submission_id, questionnaire_version_id, validated_scores[], evidence[], review_status, created_at` (+ schema allows `interpretation`, `provider_response_sha256`) | lifecycle.ts:288 only | lifecycle.ts:311 |
| `ai_jobs/job_<hash(sid)>` | `{job:{id, organization_id, kind:'evaluate', state:'queued', created_at, updated_at}, submission_id, attempt_count:0, idempotency_key: sid, revision:1}` | lifecycle.ts:288 only | lifecycle.ts:330 |
| `review_records/review_<hash([eid,rev])>` | `id, organization_id, evaluation_id, reviewer_uid, revision, conclusion, feedback?, created_at, decision` | lifecycle.ts:346 | lifecycle.ts:370 (query) |
| `review_heads/{evaluationId}` | `organization_id, evaluation_id, revision` | lifecycle.ts:347 | lifecycle.ts:319 |
| `messages/message_<hash(rid)>` | `id, relationship_id, sender_uid, body, created_at, organization_id` | community.ts:141 | community.ts:188 |
| `appointments/appointment_<hash(rid)>` | `id, relationship_id, state, revision, updated_at, starts_at?, ends_at?, organization_id` | community.ts:177 | community.ts:153,188 |
| `notifications/notice_…` | see §2.7 | lifecycle.ts:171,197; community.ts:130,204,241 (**241 runs in separate per-page transactions on GET**) | community.ts:200,208,236 |
| `professional_notifications/notice_<sid>` | see §2.7 | lifecycle.ts:287 | community.ts:56 |
| `demo_payments/demo_<requestId>` | `id, connection_request_id, organization_id, applicant_uid, state:'demo_completed', created_at` | lifecycle.ts:198 | none |
| `patient_archives/{relationshipId}` | `relationship_id, revision, archived, organization_id` | community.ts:46 | community.ts:40 |
| `platform_rate_limits/{hash([uid,op,hourBucket])}` | `uid, operation, bucket, count` | lifecycle.ts:36 (**its own transaction, before the main one**) | lifecycle.ts:34 |
| `access_invalidation_outbox/{receiptId}` | `uid, organization_id, authorization_revision, created_at` | lifecycle.ts:51 | **none** |
| `idempotency_records/idem_<hash>` | `uid, organization_id, operation, resource, request_hash, response, created_at` (verification receipts: `actor_uid, request_hash, state, revision, created_at`) | service.ts:49; platform-verify-psychologist.cjs:33 | service.ts:43 |
| `audit_events/…` | `actor_uid, organization_id, operation, resource_id, occurred_at` (+ seed variants) | service.ts:50; seed scripts | none |
| `demo_seed_manifests/web4_v1` | fixture marker/summary | seed-koi-demo.cjs:12 (tx), :76 (**non-transactional `set` merge**) | seed-koi-demo.cjs:12 |
| `demo_provision_runs/{runId}`, `demo_provision_records/{hash}` | run manifest / per-record ledger `{run_id, project, path, fictional, created_by_run, content_sha256}` | web5-provision-core.cjs:30,47,97 | web5-provision.cjs:15,17 (non-tx reads) |
| Companion `users/{uid}` | profile/settings/stats | `api/auth/anonymous/route.ts:17` (non-tx), `link-email/route.ts:30`, client `src/lib/onboarding.ts:43`, `src/lib/crypto.ts:288` | companion |
| Companion `users/{uid}/conversations/{cid}/messages/{mid}` | ciphertext message sync | client `src/lib/firestore/messageSync.ts:5,18` | companion |

Reserved but never written by Web: `registration_challenges`, `instrument_templates`, `ai_results`, `platform_outbox`, `migration_manifests` (listed only in deny roots [FILE scripts/web5-artifacts.cjs:4]).

Checked-in companion rules [FILE E:\Koi\web-final\repos\koi-backend\firestore.rules:9-34] cover `users/{uid}` (doc only), legacy `conversations/{uid}/messages/*`, `mood_entries`, `wellness_progress`, `tasks`, then deny-all. **The nested `users/{uid}/conversations/...` path used by `messageSync.ts` is not matched**, so it would be denied by these checked-in rules [GUESS on live behaviour; the live rules are unknown].

Indexes required: 12 composite proposals in [FILE dev/web5-reference/firestore.indexes.json:3-223] (built by `scripts/web5-artifacts.cjs:13-22` from `review/web-2/firestore.indexes.proposed.json` + 5 extras):
- questionnaires(org, psychologist)
- patient_relationships(patient_uid, state); (org, psychologist, state); (org, psychologist)
- connection_requests(org, psychologist)
- submissions(org, psychologist); (org, relationship)
- review_records(org, evaluation); (org, psychologist) ← likely unused, see §1.3 #7
- messages(org, relationship)
- appointments(org, relationship)
- professional_notifications(org, recipient)

Single-field equality queries (assignments by patient_uid/organization_id, submissions by organization_id, notifications by recipient_uid, connection_requests by applicant_uid, psychologist_profiles by directory_scope, and `submissions where assignment_id` in seed-koi-demo.cjs:66) rely on automatic indexes.

---

## 4. VERIFY THE WEB OWNER'S CLAIMS

**(a) Submission transaction creates `ai_jobs` and `clinician_evaluations`: VERIFIED.**
- [FILE src/lib/platform/server/lifecycle.ts:262] `this.store.transaction(async tx => {…})` wraps everything.
- [FILE lifecycle.ts:279] ``const sid = `submission_${hash(t.id)}`, jid = `job_${hash(sid)}`, eid = `evaluation_${hash(sid)}`;``
- `hash = v => sha256hex(canonicalJson(v))` [FILE src/lib/platform/server/contract.ts:19]. For a string, canonicalJson is `JSON.stringify(value)` **including the quotes** [FILE src/lib/platform/canonical.ts:8-16]. Exact derivation:
  - `sid = "submission_" + sha256_hex("\"" + attemptId + "\"")`
  - `jid = "job_" + sha256_hex("\"" + sid + "\"")`
  - `eid = "evaluation_" + sha256_hex("\"" + sid + "\"")`
  - Upstream: `attemptId = "attempt_" + hash(assignmentId)`; `assignmentId = "assignment_" + hash([receiptId, relationshipId])` [lifecycle.ts:223].
- Full wrapper [lifecycle.ts:282,285]:
  ```json
  {"job":{"id":"job_<sha256>","organization_id":"<org id>","kind":"evaluate","state":"queued","created_at":"<ISO>","updated_at":"<ISO>"},
   "submission_id":"submission_<sha256>","attempt_count":0,"idempotency_key":"submission_<sha256>","revision":1}
  ```
  It is validated against `AIJobRecord` [lifecycle.ts:285] [FILE contracts/v0.5.2/contracts.schema.json:1953-1993]. The schema also permits optional `questionnaire_id`, `source_revision`, `lease_owner`, `lease_expires_at`. `job` is `ProfessionalJobDTO`, which allows optional `result_ref` and `failure_code ∈ {provider_unavailable, invalid_output, lease_expired, retry_exhausted}`, `state ∈ {queued, claimed, completed, failed}`, `kind ∈ {generate, revise, critique, evaluate}` [schema:1897-1952].
- Writes at [lifecycle.ts:286-288]: `submissions`, `professional_notifications`, `ai_jobs`, `clinician_evaluations`. Then attempts/assignments at [292].
- Lookup [FILE lifecycle.ts:329-331]: the workspace for submission `id` reads `evaluation_${hash(id)}` and `ai_jobs/job_${hash(id)}`. It requires `j.job.id === job_${hash(id)}`, `kind==='evaluate'`, `j.submission_id===id` and `j.job.organization_id===s.organization_id`. Otherwise 404. **VERIFIED.**

**(b) `psychologist_verifications/{uid}` fields and "verified ⇔ state==='verified'": VERIFIED.**
- Type `VerificationRecord {uid, state: pending|verified|rejected|suspended, revision, changed_at, changed_by, audit_id}` [FILE src/lib/platform/types.ts:38-41].
- Writer `tx.set('psychologist_verifications', uid, { uid, state, revision, changed_at: at, changed_by: actorUid, audit_id: auditId })` [FILE scripts/platform-verify-psychologist.cjs:31].
- Allowed transitions: none→pending; pending→verified|rejected; verified→suspended; rejected|suspended→pending [:22-23].
- Authority checks `verification.state !== 'verified'` → 403 [FILE service.ts:30]; capabilities `verification.state === 'verified'` [service.ts:60]. Being verified also requires a registered `accounts` doc.

**(c) Capabilities derivation in service.ts ~54-83 and the route: VERIFIED.**
- `capabilities()` spans [FILE src/lib/platform/server/service.ts:54-87] (the claim's "54-83" covers the logic; the DTO return ends at 85).
- Route `GET /api/v1/me/capabilities` → `platformRoute(req,'capabilities')` [FILE src/app/api/v1/me/capabilities/route.ts:5] → `service.capabilities(actor)` [FILE http.ts:40]. Details in §2.5.

**(d) "The platform backend is this Next app": VERIFIED for the platform.**
- All `/api/v1` handlers are Next route files calling `src/lib/platform/server/*` with the Admin SDK [FILE runtime.ts:12-29].
- **Caveat:** the *companion chat* backend is **not** this app. Chat goes to `NEXT_PUBLIC_KOI_API_BASE` [FILE src/lib/conversation/conversationService.ts:38,55], and speech to `NEXT_PUBLIC_KOI_SPEECH_BASE` [FILE src/lib/speech/replyVoicePolicy.ts:21].
- No `/api/v1/chat` route exists in this app [RUN Glob src/app/**/route.ts].

**(e) WEB-3 built experts, messages, appointments, notifications: VERIFIED.**
- Routes:
  - `src/app/api/v1/experts/route.ts`, `experts/[id]/route.ts`
  - `messages/route.ts`, `relationships/[id]/messages/route.ts`
  - `appointments/route.ts`, `appointments/[id]/transition/route.ts`, `relationships/[id]/appointments/route.ts`
  - `notifications/route.ts`, `notifications/[id]/read/route.ts`
  - plus `professional/profile`, `professional/analytics`, `professional/submission-notifications`, `professional/patient-relationships/[id]/{archive,submissions}`
- Logic: `src/lib/platform/server/community.ts`, `community-http.ts`, `src/lib/platform/community-types.ts`.
- UI: `src/components/patient/{ExpertDirectory,CareConversation,CareNotifications}.tsx`, `src/components/professional/{PatientHistory,PracticeOverview,SubmissionNotifications}.tsx`.
- Tests: `src/__tests__/platform/community.test.ts`, `community-routes.test.ts`.
- Evidence: listed in [FILE review/web-3/CHANGED-FILES.md:28-55]. All are `A` (added) in [RUN git show --name-status ffc91f9]. Git cannot separate WEB-3 from WEB-4/5 because they were packaged in one commit; the CHANGED-FILES list is the attribution.

---

## 5. SCRIPTS

### 5.1 npm scripts [FILE package.json:5-12]

| Script | Command | Class |
| --- | --- | --- |
| `dev` | `next dev` (distDir `.next-dev` [FILE next.config.js:13-15]) | LOCAL-ONLY server. **Loads `.env.local`**: the companion then talks to whatever `NEXT_PUBLIC_KOI_API_BASE` / `FIREBASE_ADMIN_SDK` point at, and the platform to whatever `KOI_PLATFORM_*` say → effectively UNCLEAR until env is known [GUESS] |
| `build` | `next build` | LOCAL-ONLY, but Next telemetry is on unless `NEXT_TELEMETRY_DISABLED=1`; it also loads `.env*` |
| `start` | `next start` | Same as dev for runtime effects |
| `test` | `jest` | LOCAL-ONLY (jsdom, memory store, mocks) [FILE jest.config.cjs:1-22]. This session ran it without the WEB-5 network guard |
| `dev:avatar` | `node scripts/avatar-dev.cjs` | LOCAL-ONLY (spawns the avatar sandbox on :3001) |
| `typecheck:avatar` | `tsc --project dev/avatar-sandbox/tsconfig.json …` | LOCAL-ONLY |

### 5.2 Files under `scripts\` (classification + evidence)

**Platform / Firebase (most important):**

| File | Purpose | Class | Evidence |
| --- | --- | --- | --- |
| `web5-cloud-audit.cjs` | Read-only audit of `koi-companion-fyp`: published rules + source, indexes, Auth email provider, project | **READS-CLOUD** | GETs only to `firebaserules`/`firestore`/`identitytoolkit`/`firebase.googleapis.com` [:17,23-32]; mints an OAuth token via `cert().getAccessToken()` [:14]. Writes only local files in a NEW dir [:7,28-41]. **Loads `.env*` via `@next/env`** [:45]; with no file argument it falls back to `FIREBASE_ADMIN_SDK` from `.env.local` [:48]. |
| `web5-rules-security.cjs` | Exact-rules test: 37 roots × 5 principals × 4 ops = 740 denials + 80 legacy-owner checks | LOCAL-ONLY (emulator 5480/5499) | guard needs project `demo-koi-web5-local`, those hosts, `NODE_OPTIONS` containing the guard, no Admin creds [:5-7]. It **hashes the file argument but cannot prove the running emulator loaded that same file** [:9,35]. Creates emulator Auth users [:13]. |
| `web5-rules-evidence.cjs` | Combines audit.json + test report → evidence JSON | LOCAL-ONLY | [:4-8]; `verified_at = audit.inspected_at`, so the 24 h clock starts at the audit [:5] |
| `web5-artifacts.cjs` | Builds an additive deny patch + merged rules + indexes + deploy config in a NEW dir | LOCAL-ONLY | [:23-36]. Generated `firebase.json` uses emulator ports 5199/5180 (= WEB-4 ports) [:33] |
| `web5-cloud-env.ps1` | Dot-source: validates credential + evidence files, sets `KOI_PLATFORM_*`, `FIREBASE_ADMIN_SDK` | LOCAL-ONLY (no network) | [:1-19]; runs `admin-config.configuration()` locally [:17] |
| `web5-provision.ps1` | Typed confirmations + 3 password prompts → runs `web5-provision.cjs --apply` | **WRITES-CLOUD, CREATES AUTH USERS** | [:4-14] |
| `web5-provision.cjs` | Plan-only (no args), `--apply`, `--manifest-only` | plan: LOCAL-ONLY; `--apply`: **WRITES-CLOUD**; `--manifest-only`: **READS-CLOUD** | writeGuard [:4-12]; `exportManifest` reads [:13-23]; `--manifest-only` still calls `configuration()`, so it **also needs fresh (<24 h) evidence** [:30-33] |
| `web5-provision-core.cjs` | The seeding itself through real services | **WRITES-CLOUD**: `auth.createUser` ×3 [:51]; accounts, verifications, org, profile, invitation, relationship, questionnaire, version, 2 assignments, **one submission → `ai_jobs` + `clinician_evaluations`** [:87], review, application + demo payment, ledger [:30] | refuses existing UIDs/emails [:43-45], never `updateUser` [:53], blocks companion namespaces [:16] |
| `web5-load-platform.cjs` | Transpiles `src/lib/platform/**/*.ts` in memory for operator tools | LOCAL-ONLY | [:4-16] |
| `web5-network-guard.cjs` | `NODE_OPTIONS` preload that denies non-loopback sockets/DNS/fetch and local `/api/v1/(chat|crisis)` | LOCAL-ONLY (protective). **Do not** load it for real cloud runs | [:3-39] |
| `web5-backend-functional.cjs` | Real Next (3207) + emulators (5480/5499) scenario groups | LOCAL-ONLY | guard reused [:5,8-10]; creates emulator users [:13,34]; writes `review/web-5/evidence/backend-functional.json` (tracked) — refuses if it exists [:8] |
| `platform-verify-psychologist.cjs` | Restricted CLI to set verification state | **WRITES-CLOUD whenever the shell is in `reviewed-production` mode**; no typed confirmation. Writes accounts, psychologist_verifications, audit_events, idempotency_records | [:38-60]; needs `KOI_PLATFORM_BOOTSTRAP_ADMIN_UID` / `_SERVICE_ACCOUNT` [:47-50] |
| `seed-koi-demo.cjs` | WEB-4 fictional emulator seed via real routes on 127.0.0.1:3107 | LOCAL-ONLY (guarded) | `guard()` pins `demo-koi-platform-web1`, 5180/5199, forbids creds [FILE scripts/koi-demo-guard.cjs:7-13]; `auth.updateUser` resets the 3 demo passwords on rerun [:17]; submits → emulator `ai_jobs` [:64] |
| `koi-demo-guard.cjs`, `koi-demo-preflight.cjs` | Guard helpers | LOCAL-ONLY | as above |
| `start-demo-emulators.ps1` | `npx --yes --package firebase-tools@15.34.0 firebase emulators:start --only auth,firestore --project demo-koi-platform-web1 --config dev/platform-emulator/firebase.json` with export/import | LOCAL-ONLY, **but `npx --yes` downloads firebase-tools from the npm registry** and needs Java | [:9-17] |
| `demo-env.ps1` | Sets emulator env + demo `NEXT_PUBLIC_FIREBASE_*` | LOCAL-ONLY | [:1-25] |
| `web1/2/3-emulator-functional.cjs`, `web3-emulator-security.cjs`, `web4-demo-functional.cjs`, `web4-regression-functional.cjs`, `web4-persistence-check.cjs` | Real emulator + Chrome journeys | LOCAL-ONLY (emulator asserts) | e.g. [FILE scripts/web2-emulator-functional.cjs:11-13]. They write evidence into tracked `review/web-N/evidence/` |
| `web4-companion-smoke.cjs` | Anonymous emulator sign-in + onboarding in Chromium | LOCAL-ONLY (aborts `/api/v1/chat` and `modal.run`) [:13-19]. The handoff says not to run it under the no-paid-traffic rule | |
| `validate-web05-contract.cjs`, `validate-web2-contract.cjs`, `validate-web3-contract.cjs` | Schema/fixture/freeze-hash checks | LOCAL-ONLY. **Will likely FAIL on this checkout** because they hash raw CRLF bytes [:98] / [:22] (see §12) [GUESS] | |
| `web05-deployment-evidence.py` | Probes `NEXT_PUBLIC_KOI_API_BASE + "/health"`, `/openapi.json`, `https://<project>.web.app/__/firebase/init.json` | **READS-CLOUD; pings the paid companion backend `/health`** (forbidden by the handoff); reads `.env.local`; overwrites tracked `review/web-0.5/deployment-evidence.json` | [:54-77] |

**Companion / avatar / speech (pre-existing):**

| File(s) | Class | Evidence / note |
| --- | --- | --- |
| `test-*.cjs` (avatar-controller, avatar-emotion-matrix, avatar-host, avatar-session, chat-contract, conversation-recovery, crypto-roundtrip, exercise-director, flow4, microphone, speech, speech-turn, v11-fixture) | LOCAL-ONLY unit harnesses | `example.test`/`.invalid`/localhost URLs only [RUN Grep http in scripts] |
| `verify-avatar*.cjs`, `verify-camera-local.cjs`, `verify-companion-ui.cjs`, `verify-environment.cjs`, `verify-mock-chat.cjs`, `verify-piper-speech.cjs`, `verify-speech.cjs`, `verify-voice-lab.cjs`, `avatar-browser-audit.cjs` | LOCAL-ONLY (Playwright against sandbox :3001/:3010) | |
| `verify-ui-fix.cjs` | **UNCLEAR**: drives the real app at `http://localhost:3000` through `/`, `/chat`, `/companion-scene` [:11,62,481,504]. Only one block aborts Firebase signUp [:91]. On a server configured from `.env.local` it can trigger `/api/auth/anonymous` → cloud `users/` writes [GUESS] | |
| `avatar-dev.cjs`, `voice-dev.cjs` | LOCAL-ONLY dev launchers (spawn) | |
| `setup-speech-tools.py`, `setup-voice-tools.py` | Network downloads (pypi, huggingface, github) — not Firebase, not paid | [:14-47] / [:11-24] |
| `assemble-speech-fixture.py`, `generate-piper-samples.py`, `prepare-voice-browser-fixture.py`, `benchmark-tts-worker.py`, `evaluate-asr.py`, `test-piper-pipeline.py`, `create-speech-fixture.ps1`, `verify_backend_chat_contract.py` | LOCAL-ONLY | header comments [RUN git grep -m 2 scripts] |
| `test-local-voice.py` | LOCAL-ONLY (127.0.0.1:3001/3002) | |
| `fixtures/*.json`, `*.lock.txt` | data | |

**Highlights: anything that can write to Firebase, create Auth users, or call paid services:**
1. `web5-provision.ps1` / `web5-provision.cjs --apply` / `web5-provision-core.cjs`: cloud Auth users plus ~30 Firestore documents, **including one queued `ai_jobs` doc**.
2. `platform-verify-psychologist.cjs`: cloud writes with no typed confirmation if run in a cloud-configured shell.
3. `web05-deployment-evidence.py`: unauthenticated GET to the companion backend `/health`, i.e. a Modal health ping.
4. Running the app itself (`dev`/`start`) with `.env.local`: `/api/auth/anonymous` writes cloud `users/`, and `/chat` sends to the paid companion backend.
5. `verify-ui-fix.cjs`: UNCLEAR, as above.

Everything else creates users only in emulators.

---

## 6. RUN

| Command | Result |
| --- | --- |
| [RUN `npx tsc --noEmit --incremental false`] | **PASS** — exit code 0, no output |
| [RUN `npm test -- --runInBand`] | **Test Suites: 1 failed, 85 passed, 86 total. Tests: 1 failed, 687 passed, 688 total.** Time 51.3 s |

The counts match the claimed 86 suites / 688 tests, but **one test fails**. Single failure:
- File and name: `src/__tests__/platform/service.test.ts`, "pins original bundled asset bytes and canonical JSON semantics".
- At [FILE src/__tests__/platform/service.test.ts:110]: `Expected: "cc6048d1e359dcfabb1f64b0443f21c9a88f2a9b4793cc9bd14bc21ced37bd66"`, `Received: "bcff1f53a004e0b52032ca2074b269966708a5a6052858732f448f7f85d5a4ef"`.
- This is identical to Ahmad's run. Other output consists of pre-existing React `act(...)` warnings (e.g. `how-it-works/page.tsx`).

---

## 7. ENV (names only; `.env*` not opened; `.env.example` and `review/web-1/platform.env.example` **NOT READ**)

| Name | Purpose | Local emulator demo | Reviewed-production cloud |
| --- | --- | --- | --- |
| `KOI_PLATFORM_MODE` | `emulator` / `reviewed-production`; unset → platform 503 [admin-config.cjs:9-23] | `emulator` (demo-env.ps1) | `reviewed-production` (web5-cloud-env.ps1) |
| `KOI_PLATFORM_FIREBASE_PROJECT_ID` | Pinned project | `demo-koi-platform-web1` | `koi-companion-fyp` |
| `NEXT_PUBLIC_KOI_PLATFORM_FIREBASE_PROJECT_ID` | Named client Auth project [professional-auth.ts:10] | demo value | `koi-companion-fyp` |
| `NEXT_PUBLIC_KOI_PLATFORM_AUTH_EMULATOR_URL` | Platform Auth emulator (dev, loopback only) | `http://127.0.0.1:5199` | must be **absent** |
| `FIRESTORE_EMULATOR_HOST`, `FIREBASE_AUTH_EMULATOR_HOST` | Admin SDK emulator redirection | `127.0.0.1:5180` / `127.0.0.1:5199` | must be absent |
| `NEXT_PUBLIC_KOI_COMPANION_DEMO_EMULATOR` | Companion default app → emulator | `true` | must not be `true` |
| `NEXT_PUBLIC_KOI_LOCAL_TEST_ANON` | Dev-only genuine anonymous auth for companion [anonymousSignInMode.ts:6] | `true` | present in `.env.local` per EXISTING-FIREBASE-INTEGRATION.md:16; dev-only |
| `NEXT_PUBLIC_FIREBASE_API_KEY`, `_AUTH_DOMAIN`, `_PROJECT_ID`, `_STORAGE_BUCKET`, `_MESSAGING_SENDER_ID`, `_APP_ID` | Default client app [firebase.ts:6-13] | demo values from demo-env.ps1 | existing `.env.local` values (reported complete, not seen) |
| `FIREBASE_ADMIN_SDK` | Service-account JSON (companion `[DEFAULT]` + platform in cloud) | must be absent from the shell (guard) | from `E:\Koi\private\koi-service-account.json` via web5-cloud-env.ps1 — **missing** |
| `KOI_PLATFORM_CURSOR_SIGNING_KEY` | HMAC for cursors **and invitation tokens**; ≥32 chars, persistent | optional (demo default) | **missing**; must be generated and stored privately |
| `KOI_PLATFORM_RULESET_SHA256` | Hash of published rules | must be absent | from evidence — **missing** |
| `KOI_PLATFORM_RULES_EVIDENCE_PATH` | Evidence file (<24 h) | absent | **missing** |
| `KOI_PLATFORM_BOOTSTRAP_ADMIN_UID`, `KOI_PLATFORM_BOOTSTRAP_SERVICE_ACCOUNT` | Operator allowlist for verification/provisioning | set internally by seeder (`koi_demo_web4_operator`, `emulator-only`) | operator shell only — **missing** (needs an existing, non-disabled Auth UID) |
| `KOI_WEB5_CLOUD_WRITE_AUTHORIZATION`, `KOI_WEB5_{PSYCHOLOGIST,GENERAL,PATIENT}_PASSWORD` | Provisioning gate + passwords | n/a | set transiently by web5-provision.ps1 |
| `KOI_DEMO_PASSWORD`, `KOI_DEMO_{PSYCHOLOGIST,GENERAL,PATIENT}_PASSWORD` | Demo passwords 12-128 chars | **required** for seeding | n/a |
| `NEXT_PUBLIC_KOI_API_BASE` | Companion chat backend (paid) [conversationService.ts:38] | in `.env.local` (unknown value); avoid `/chat` | unchanged |
| `NEXT_PUBLIC_KOI_SPEECH_BASE` | Companion speech | same | same |
| `NEXT_PUBLIC_KOI_V11_FIXTURE_EVENTS` | Dev fixture flag | n/a | n/a |
| `NODE_OPTIONS` (network guard), `NEXT_TELEMETRY_DISABLED` | Isolation for tests/builds | recommended | `NODE_OPTIONS` must **not** include the guard for real cloud runs |
| `GOOGLE_APPLICATION_CREDENTIALS`, `FIREBASE_TOKEN`, `GOOGLE_OAUTH_ACCESS_TOKEN`, `GOOGLE_CREDENTIALS`, `FIREBASE_SERVICE_ACCOUNT`, `GCLOUD_PROJECT`, `GOOGLE_CLOUD_PROJECT`, `FIREBASE_PROJECT_ID`, `FIREBASE_CONFIG` | Forbidden/conflict-checked by demo guard [koi-demo-guard.cjs:9-11] | must be absent | n/a |
| `KOI_AVATAR_*`, `KOI_MOCK_CHAT_URL`, `KOI_BROWSER_TEST_OUTPUT_DIR`, `KOI_WEB1_BROWSER_EXECUTABLE` | Browser-test helpers | optional | n/a |

Missing for the local demo: Java 21, Node 22 (as documented), the Firebase CLI (or npm registry access for `npx`), and passwords. Missing for cloud: the credential, cursor key, fresh evidence, operator UID/allowlist, and owner approvals.

---

## 8. LOCAL DEMO RUNBOOK (emulator, fictional identities)

Source: [FILE review/web-4/DEMO-LOGIN-GUIDE.md:17-66] with paths rewritten. Nothing here was run in this session.

**Prerequisites** (needs Java + Firebase CLI):
- Node 22 and Java 21 [DEMO-LOGIN-GUIDE.md:3].
- `npx` must be able to fetch `firebase-tools@15.34.0` (npm registry) unless it is cached [start-demo-emulators.ps1:9].
- Use a clean PowerShell with no `FIREBASE_ADMIN_SDK`/Google creds in the environment (guard) [demo-env.ps1:2-4].
- Recommended: `$env:NEXT_TELEMETRY_DISABLED='1'`.

**Terminal 1 — emulators** (JAVA + FIREBASE CLI):
```powershell
Set-Location E:\Koi\web-final\repos\koi-backend\nextjs_app
.\scripts\start-demo-emulators.ps1          # or -Fresh for a disposable empty run
```
Auth on 127.0.0.1:5199 and Firestore on 127.0.0.1:5180, deny-all rules [FILE dev/platform-emulator/firebase.json:1-9]. It imports and exports `.local/koi-demo/export` (not shipped, so the first run starts empty).

**Terminal 2 — Next dev server:**
```powershell
Set-Location E:\Koi\web-final\repos\koi-backend\nextjs_app
. .\scripts\demo-env.ps1
npm run dev -- --hostname 127.0.0.1 --port 3107
```
The port must be exactly 3107 because the seeder targets `http://127.0.0.1:3107` [FILE scripts/koi-demo-guard.cjs:12]. ⚠ `next dev` still loads `.env.local`. Shell values override it for the names demo-env sets, but others (e.g. `NEXT_PUBLIC_KOI_API_BASE`, a companion `FIREBASE_ADMIN_SDK`) remain [GUESS]. **Do not open `/chat` or `/companion-scene` or send companion messages**: they call the paid backend (CLOUD).

**Terminal 3 — seed:**
```powershell
Set-Location E:\Koi\web-final\repos\koi-backend\nextjs_app
. .\scripts\demo-env.ps1
$demoPassword = Read-Host 'Choose a fictional demo password (12–128 characters)' -AsSecureString
$env:KOI_DEMO_PASSWORD = [System.Net.NetworkCredential]::new('', $demoPassword).Password
node scripts/seed-koi-demo.cjs
Remove-Item Env:\KOI_DEMO_PASSWORD
$demoPassword.Dispose()
```
This creates or updates `psychologist@koi-demo.example`, `general@koi-demo.example` and `patient@koi-demo.example`, plus operator `koi_demo_web4_operator`. It also creates: verification pending→verified (via a spawned `platform-verify-psychologist.cjs`), an org, a profile, an invitation and redemption, one published text+picture form, 2 assignments (1 open, 1 submitted, with an emulator `ai_jobs` doc), one fictional approve review, and a General application after demo payment [FILE scripts/seed-koi-demo.cjs:7-77].

**Journey** (open `http://127.0.0.1:3107/?home=1` → KOI menu → Account sign-in, or `/account`; separate browser profiles per role):
1. Psychologist → Professional Dashboard (`/professional?view=dashboard#practice-dashboard`).
2. Professional Questionnaires → create a manual form (text + bundled picture), save, **publish**, inspect the immutable version (`/professional?version=VERSION_ID`). Publishing and other writes need sign-in within the last 5 minutes; the UI reauthenticates.
3. Patients (`/professional?view=patients#patients`) → accept the General application, or invite → assign the new version to the active patient.
4. Patient profile → `/patient?view=questionnaires#questionnaires` → answer, wait for "All answers saved", reload, resume, review, submit → acknowledgement only.
5. Psychologist → `/professional?view=submissions#submissions` → Inspect submission → raw answers, job "queued", empty evaluation → append an approve/reject/feedback review → review history.
6. Optional: messages, appointment request/propose/confirm, notifications, analytics, `/professional` as patient → denied.

Steps that cannot run without cloud: none of the platform journey. Companion chat/voice replies need the external provider (cloud, paid) and are out of scope. Browser pages also fetch Google Fonts and CDN images (public internet, not paid) [FILE src/components/providers/AppAuthBoundary.tsx:8] [FILE src/app/globals.css:53].

Optional verification (needs emulators + Next + Chrome): `node scripts/web4-demo-functional.cjs`, `node scripts/web4-regression-functional.cjs 1|2|3` [DEMO-LOGIN-GUIDE.md:96-103]. Not run here.

---

## 9. CLOUD ACTIVATION RUNBOOK (owner of `koi-companion-fyp`) — NOT RUN

Docs' own sequence [FILE review/web-5/DEMO-DEPLOYMENT.md:5-147] [FILE KOI_WEB_1_TO_5_AHMAD_HANDOFF.md:167-176]: audit → exact-source local rules test → evidence → (optional) additive rules/index deploy → paid-consumer check → configure local production Next → authorized provisioning → manual UI → manifest export → (separately authorized) cleanup.

All commands run from `E:\Koi\web-final\repos\koi-backend\nextjs_app`. `.local/koi-web5/` is gitignored [FILE .gitignore:14].

| # | Command | RO / WRITES | Reads / writes | Evidence produced | Rollback | Approval before it |
| --- | --- | --- | --- | --- | --- | --- |
| 0 | `firebase login` (only if steps 1b/4c are needed) | READS-CLOUD (OAuth) | CLI token cache | — | `firebase logout` | Owner: which Google account; CLI installed |
| 1 | `node scripts/web5-cloud-audit.cjs E:\Koi\private\koi-service-account.json .local/koi-web5/live-before-demo` | **READ-ONLY** cloud | OAuth token + GET release, ruleset, indexes (pageSize 100), Auth config, project | `audit.json`, `published.rules`, `release.json`, `published-indexes.json` (dir must not exist) | delete local dir | Owner OK to use the service account for reads; SA needs rules/index/auth-config/project read IAM [GUESS on exact roles]. **Always pass the file path**; otherwise it silently uses `FIREBASE_ADMIN_SDK` from `.env.local` [web5-cloud-audit.cjs:45-48] |
| 1b | Index export in CLI format — **no repo command** [NOT FOUND]; e.g. `firebase firestore:indexes --project koi-companion-fyp` [GUESS] | READ-ONLY | indexes + field overrides | JSON for step 4b | — | NEEDS-APPROVAL (CLI login) |
| 2 | Compare `.local/koi-web5/live-before-demo/published.rules` with the console copy `E:\Koi\private\published_rules_2026-10-20.txt` (manual diff) | LOCAL | — | your note | — | — |
| 3 | Private test dir: copy `dev/web5-reference/firebase.json`, point `firestore.rules` at the **captured `published.rules`** (absolute path). Guarded shell: `$env:NODE_OPTIONS='--require=E:/Koi/web-final/repos/koi-backend/nextjs_app/scripts/web5-network-guard.cjs'; $env:NEXT_TELEMETRY_DISABLED='1'` then `firebase emulators:start --only auth,firestore --project demo-koi-web5-local --config <private>\firebase.json` | LOCAL (JAVA + CLI) | emulator 5480/5499 | — | stop emulator | none |
| 3b | Second guarded shell: `$env:KOI_PLATFORM_FIREBASE_PROJECT_ID='demo-koi-web5-local'; $env:FIRESTORE_EMULATOR_HOST='127.0.0.1:5480'; $env:FIREBASE_AUTH_EMULATOR_HOST='127.0.0.1:5499'` then `node scripts/web5-rules-security.cjs .local/koi-web5/live-before-demo/published.rules .local/koi-web5/live-rules-test.json` | LOCAL | emulator only | test report with `source_sha256` | — | none |
| 4 | `node scripts/web5-rules-evidence.cjs .local/koi-web5/live-before-demo/audit.json .local/koi-web5/live-rules-test.json .local/koi-web5/verified-rules.json` | LOCAL | — | `verified-rules.json` (valid until audit time + 24 h) | delete | none |
| 4b | *Only if 3b fails because live rules allow platform paths:* `node scripts/web5-artifacts.cjs .local/koi-web5/live-before-demo/published.rules .local/koi-web5/reviewed-patch <CLI-indexes.json from 1b>`, review the diff, re-run 3/3b on `reviewed-patch/firestore.rules` | LOCAL | — | patch dir | delete | Owner reviews diff |
| 4c | `firebase deploy --only firestore:rules,firestore:indexes --project koi-companion-fyp --config .local/koi-web5/reviewed-patch/firebase.json` | **WRITES-CLOUD** (rules + indexes) | live rules/indexes | new release; then redo 1-4 into a NEW audit dir | redeploy the captured `published.rules` + exported indexes through a reviewed config; **stop if the CLI proposes deleting indexes** | **Explicit owner approval** of exact diff |
| 5 | Prove no paid consumer of `ai_jobs` (Cloud Functions/Eventarc triggers, Modal or other workers) from **configuration only** — no repo tool [NOT FOUND] | READ-ONLY (console/config review) | — | written note | — | Owner/AI owner sign-off; if unknown, **stop: no cloud submit or provisioning** |
| 6 | Clean shell (no guard, no emulator vars): set `$env:KOI_PLATFORM_CURSOR_SIGNING_KEY` from the private store, then `. .\scripts\web5-cloud-env.ps1 -ServiceAccountFile E:\Koi\private\koi-service-account.json -RulesEvidenceFile .local/koi-web5/verified-rules.json` | LOCAL | env only | "validated locally" line | close the shell | cursor key generated and stored |
| 6b | `npm run build` then `npm run start -- --hostname 127.0.0.1 --port 3107` | build LOCAL; server **WRITES-CLOUD when used** | all platform collections as users act; companion `users/` | — | stop server; unset platform env (companion unaffected) | owner OK to run platform against prod |
| 7 | `node scripts/web5-provision.cjs --run-id examiner_2026` | LOCAL (plan only) | — | planned UIDs/emails | — | none |
| 8 | Same shell as 6, plus `$env:KOI_PLATFORM_BOOTSTRAP_ADMIN_UID='<existing operator UID>'; $env:KOI_PLATFORM_BOOTSTRAP_SERVICE_ACCOUNT='<SA client_email>'` then `.\scripts\web5-provision.ps1 -RunId examiner_2026 -ManifestFile .local/koi-web5/examiner-2026-manifest.json` | **WRITES-CLOUD + creates 3 Auth users** | see §5.2 highlight #1, **includes one `ai_jobs` doc** | manifest (UIDs, paths, hashes, cleanup plan) + `demo_provision_runs/examiner_2026` ledger | no tool; manual per DEMO-DEPLOYMENT §7 (close relationship, suspend psychologist, disable 3 UIDs, delete exact paths) | **Explicit owner cloud-write authorization**; step 5 done; email/password provider enabled (checked from evidence) |
| 9 | Manual UI checklist (AHMAD_START_HERE §3) | WRITES-CLOUD (fictional) | as used | screenshots/notes | as 8 | as 8 |
| 10 | `node scripts/web5-provision.cjs --manifest-only --run-id examiner_2026 --output .local/koi-web5/examiner-2026-manifest-later.json` | READ-ONLY cloud | ledger | later manifest | — | evidence still <24 h old |

Where the docs depart from the code:
- **Evidence expiry kills the running server.** The doc says "Evidence expires after 24 hours; refresh it on the demo day" [DEMO-DEPLOYMENT.md:51]. In code, `configuration()` re-validates evidence on **every request** [FILE runtime.ts:14] [FILE admin-config.cjs:21], and the 24 h clock starts at the audit's `inspected_at` [FILE web5-rules-evidence.cjs:5]. So a server started on fresh evidence goes to 503 mid-session once the audit is 24 h old. `--manifest-only` also needs fresh evidence.
- **The rules test trusts the operator.** It records `sha(fs.readFileSync(source))` [FILE web5-rules-security.cjs:35], but it tests whatever rules the emulator was started with. If the emulator still runs `dev/web5-reference/firestore.rules`, you get a valid-looking attestation for the live hash. The doc instruction to repoint `firebase.json` [DEMO-DEPLOYMENT.md:21] is the only safeguard.
- **Use the API-captured file.** The test must use the API-captured `published.rules`, not the console copy. Evidence requires `rules_tests.source_sha256 === snapshot.rules_sha256` (hash of the API string) [FILE production-evidence.cjs:4]. A console copy with CRLF or other whitespace differences will not match.
- **Provisioning writes `ai_jobs`.** It submits a questionnaire [FILE web5-provision-core.cjs:87], creating a cloud `ai_jobs` doc. That is why step 5 is mandatory before step 8, not just before "any submit".
- **The operator must already exist.** `auth.getUser(actorUid)` must succeed and not be disabled [FILE web5-provision-core.cjs:39]. The doc says "existing non-disabled operator Firebase UID" — consistent, but someone has to pick a real account.
- **`.env.local` is loaded too.** `web5-cloud-audit.cjs` loads `.env*` [:45], and `npm run build/start` load `.env.local`. The docs say "Keep the existing `.env.local` … unchanged" [DEMO-DEPLOYMENT.md:75], which is consistent. `web5-cloud-env.ps1` sets `FIREBASE_ADMIN_SDK` in the shell, which overrides any `.env.local` value for the companion too [GUESS: same project, so it should be harmless].
- **Index export is assumed.** The doc requires a CLI-format index export, but no command or script is provided (§1.3 #10).

---

## 10. PHONE ACCESS

What has to change so a phone can reach the app:

1. **Listening interface.** Every documented command binds loopback: `--hostname 127.0.0.1` [DEMO-LOGIN-GUIDE.md:33] [DEMO-DEPLOYMENT.md:82]. A phone needs `--hostname 0.0.0.0` (or the PC's LAN IP), plus a Windows Firewall inbound rule for the port.
2. **The emulator demo cannot work from a phone without code changes.**
   - Platform Auth only accepts an emulator URL whose hostname is `localhost`/`127.0.0.1` [FILE src/lib/platform/professional-auth.ts:15].
   - The companion demo hard-codes `http://127.0.0.1:5199` and `127.0.0.1:5180` [FILE src/lib/firebase.ts:52-53] [FILE src/lib/auth/demoEmulatorMode.ts:4].
   - The emulators bind 127.0.0.1 [FILE dev/platform-emulator/firebase.json:4-5].
   - On the phone, 127.0.0.1 is the phone itself, so phone access implies **reviewed-production (cloud) mode**, or a code change that needs owner approval.
3. **HTTPS is effectively required.** `crypto.randomUUID()` and `crypto.subtle` exist only in secure contexts (HTTPS or localhost) [GUESS: standard browser behaviour]. The platform client creates every Idempotency-Key with `crypto.randomUUID()` [FILE src/lib/platform/client.ts:26]. Publish hashes with `crypto.subtle` [FILE src/lib/platform/canonical.ts:25-28] [FILE src/components/professional/ProfessionalWorkspace.tsx:120]. Companion encryption uses `crypto.subtle` [FILE src/lib/crypto.ts:100-169]. Over `http://192.168.x.x:3107`, **all platform mutations and publishing would fail**. Options: a TLS reverse proxy with a cert trusted by the phone, a tunnel, or `next dev --experimental-https` [GUESS: flag exists in Next ≥13.5; not verified for 14.2.35 here]. Android native clients also block cleartext HTTP by default (API 28+) [GUESS].
4. **URL / CORS.** The web client only calls relative `/api/v1/...` paths [FILE client.ts:17], so same-origin needs no CORS. There is **no middleware and no CORS headers or OPTIONS handlers** [RUN Glob middleware.ts → none; route files export only GET/POST/PUT/PATCH]. A native Flutter HTTP client is unaffected by CORS; a browser app on another origin would be blocked.
5. **Firebase authorized domains / API key.** Email/password `signInWithEmailAndPassword` does not use OAuth redirects [GUESS: authorized domains matter for OAuth/popup/email-link flows]. However, if the browser API key has HTTP-referrer restrictions in Google Cloud, the new origin (LAN IP / tunnel host) must be allowed. Check in the console (read-only). Add the domain to Firebase Auth authorized domains if any OAuth or hosting flow is used.
6. **Exposure risk.** `/api/auth/anonymous` is unauthenticated and writes `users/{uuid}` in cloud with no rate limit [FILE src/app/api/auth/anonymous/route.ts:5-32]. Exposing the server on a LAN or tunnel exposes it too.

Routes the mobile client is meant to call. Per [FILE contracts/implementations/WEB-2.md:32-36]: "consume unchanged patient DTOs, typed option-ID answers … PATCH revision conflicts … immutable submission acknowledgement and access invalidation. Do not subscribe directly to clinical Firestore":
- `GET /api/v1/me/capabilities`, `GET /api/v1/me/access-events`
- `GET /api/v1/patient/assignments`, `GET /api/v1/patient/assignments/{id}`, `PATCH /api/v1/patient/attempts/{id}`, `POST /api/v1/patient/attempts/{id}/submit`
- `POST /api/v1/patient-invitations/{token}/redeem`, `GET/POST /api/v1/connection-requests`, `POST …/{id}/transition`, `POST …/{id}/demo-payment`
- `GET /api/v1/experts`, `GET /api/v1/experts/{id}`
- `POST /api/v1/messages`, `GET /api/v1/relationships/{id}/messages`, `POST /api/v1/appointments`, `POST /api/v1/appointments/{id}/transition`, `GET /api/v1/relationships/{id}/appointments`
- `GET /api/v1/notifications`, `POST /api/v1/notifications/{id}/read`

Contract version: package **0.5.2** (`contracts/v0.5.2/*`, OpenAPI `info.version` 0.5.2 [FILE contracts/v0.5.2/openapi.json:6]). Wire literals stay **`0.5.0`** (`contract_version` in CapabilitiesDTO [FILE service.ts:81], `schema_version` in versions/questionnaires [FILE lifecycle.ts:254]). No Flutter acknowledgement exists. Do not trust OpenAPI `x-status` (§1.3 #1).

---

## 11. AI BOUNDARY

**Every reference in code:**
- Writer: `ai_jobs` is created once per submission [FILE src/lib/platform/server/lifecycle.ts:279-288].
- Reader: the workspace reads `ai_jobs` [lifecycle.ts:330-332]. The job projection exposed to professionals is `pick(j.job, ['id','organization_id','kind','state','created_at','updated_at','result_ref','failure_code'])` [lifecycle.ts:332].
- Types: `Job` [FILE src/lib/platform/professional-types.ts:6]; schemas `ProfessionalJobDTO`/`AIJobRecord` [FILE contracts/v0.5.2/contracts.schema.json:1897-1993].
- Deny roots include `ai_jobs`, `ai_results` [FILE scripts/web5-artifacts.cjs:4] [FILE dev/web5-reference/firestore.rules:57-58].
- Tests seed failed jobs and an `ai_provider_responses` fixture [FILE src/__tests__/platform/lifecycle.test.ts:137,173-180]. Only the memory store sees these; there is no production writer.
- Contracts propose `/api/v1/ai/questionnaires/{generate,revise,critique}`, `/api/v1/ai/jobs/{id}`, `/api/v1/ai/jobs/{id}/result` and `/internal/v1/evaluation-jobs/{claim,complete,fail}`, all `proposed_not_implemented` [FILE contracts/v0.5.2/openapi.json:3343-3700,4801,5174-5430]. Semantics require an allowlisted workload OIDC identity for internal routes [FILE contracts/v0.5.0/semantics.md:156].

**Job wrapper:** exact shape in §4(a). Lifecycle:
- **Created** by Web (the patient submit transaction).
- **Updated** by nobody: no code transitions `state` or sets `result_ref`/`failure_code`/lease fields [RUN git grep ai_jobs → only lifecycle.ts:285,288,330].
- **Read** by Web (professional workspace) only.

**Does Web call any AI route?** No.
- No `/api/v1/ai` route exists [RUN Glob src/app/**/route.ts].
- The platform makes no outbound HTTP; `firestore-store` and `runtime` use only the Admin SDK.
- The only AI traffic is the pre-existing **companion** chat/speech to `NEXT_PUBLIC_KOI_API_BASE` / `NEXT_PUBLIC_KOI_SPEECH_BASE`. That is a different AI service from the evaluation repo.

**What the AI repo (Koi-fyp/KOI-Psycholov, `ai-contracts-draft-0.4`) would have to read.** That repo is not on this disk and was not read [NOT FOUND]. These are the Web facts it must adapt to:
- **Job:** `ai_jobs/job_<sha256("\"submission_…\"")>` with nested `job` (not flat, not keyed by submission id). The handoff says AI master assumes `ai_jobs/{submission_id}` flat with `job_id, org_id, state, stage, run, attempts, lease…` [FILE KOI_WEB_1_TO_5_AHMAD_HANDOFF.md:211]. Not verified here.
- **Submission:** `submissions/{sid}`: `id, organization_id, relationship_id, assignment_id, attempt_id, patient_uid, questionnaire_version_id, answers[{question_id,type,value}], submitted_at, psychologist_uid`.
- **Version:** flat `questionnaire_versions/{opaque id}` with `content` (localized `en/ur/ur-Latn`, 7 question types, pinned asset `{asset_id,version,sha256}`), `content_sha256`, `schema_version '0.5.0'`.
- **Authority to re-check before any provider call:**
  - `accounts.state`
  - `psychologist_verifications.state==='verified'`
  - `organizations.state==='active'` + `organization_memberships` (kind owner, active)
  - `patient_relationships.state==='active'`
- **Result destination (today):** `clinician_evaluations/evaluation_<hash(sid)>` with `validated_scores[{scale_id,value,instrument_template_id,item_version,scoring_version,implementation_version}]`, optional `interpretation` (≤16,000 chars), `evidence[{question_id,answer_index}]`, `provider_response_sha256` [FILE professional-types.ts:5]. Note that `review_status` is computed from `review_heads`, not stored meaningfully.

**Consent and the patient–psychologist relationship:**
- Collection `patient_relationships/relationship_<hash([org, patientUid])>`.
- Fields `state ∈ {active, closed}`, `consent_version` (only `care-consent-v1` accepted [FILE src/lib/platform/patient-types.ts:3] [FILE lifecycle.ts:109,149]), `activated_at`, `closed_at?`, `revision`, ids [patient-types.ts:5].
- Closed relationships never reopen [lifecycle.ts:59-60].
- `connection_requests.consent_version` stores the consent given at application [lifecycle.ts:169].
- **There is no AI-specific consent collection or field** [NOT FOUND]. `consents` and the `ai_interpretation` scope exist only in the AI docs, per the handoff (§9 table).

**What `clinician_evaluations` holds, who writes and reads it:**
- At submit it holds an empty envelope: `validated_scores:[]`, `evidence:[]`, `review_status:'unreviewed'`, refs and `created_at` [FILE lifecycle.ts:283].
- **Writer:** only the submit transaction [lifecycle.ts:288]. Nothing fills scores or interpretation.
- **Readers:** `getEvaluation`, `workspace`, review list/creation via `scopedEvaluation` (verified Owner, same org, same version) [lifecycle.ts:309-325].
- Patients can never read it (§2.8).
- Reviews never mutate it; they live in `review_records`/`review_heads`.

---

## 12. FAILING TEST ANALYSIS (read-only, nothing edited)

**Same single failure confirmed** [RUN npm test -- --runInBand]: `service.test.ts` "pins original bundled asset bytes and canonical JSON semantics", expected `cc6048d1…bd66`, received `bcff1f53…a4ef`.

**What the test does** [FILE src/__tests__/platform/service.test.ts:110]: for each manifest asset, `sha256(readFileSync(join(cwd,'public',asset.web_path)))` must equal `asset.reference.sha256`. It reads **raw working-tree bytes**. The loop stops at the first failing `expect`, so only the circle is reported; square and triangle are probably affected too [GUESS].

**Manifest entry with the expected hash:** [FILE src/lib/platform/illustrations.json:4-21] `asset_id: "shape_circle"`, `version: 1`, `sha256: "cc6048d1e359dcfabb1f64b0443f21c9a88f2a9b4793cc9bd14bc21ced37bd66"`, `web_path: "/illustrations/web1/circle-v1.svg"` → file `public/illustrations/web1/circle-v1.svg`. It is a single SVG line followed by a newline [FILE public/illustrations/web1/circle-v1.svg:1].

The same expected hash appears in [RUN git grep]:
- `review/web-1/changed-files.json:22` (WEB-1 recorded hash when added)
- `review/web-4/baseline.json:112`
- `review/web-5/baseline.json:163` (the previous owner's working-tree hash snapshots)

**Line endings:**
- [RUN git ls-files --eol public] → `i/lf w/crlf attr/` for `circle-v1.svg`, `square-v1.svg`, `triangle-v1.svg`. The **index has LF; this working tree has CRLF**. Binary assets show `-text`/`none`.
- [RUN git ls-files ":(top,glob)**/.gitattributes"] → **no `.gitattributes` anywhere in the repo**, so nothing marks the SVGs `-text` or `eol=lf`.
- Contracts, rules and scripts are also `i/lf w/crlf` [RUN git ls-files --eol contracts dev/web5-reference ../firestore.rules scripts/*.ps1].
- `git status` is clean, consistent with `core.autocrlf=true` normalizing on add [GUESS: `git config` not allowed, so not read].

**How the docs say pinned hashes were produced:**
- WEB-1 `changed-files.json` records per-file sha256 of the added file [FILE review/web-1/changed-files.json:1-33]. Baselines record captured working-tree hashes [FILE review/web-5/baseline.json:163].
- Reports mention "only existing line-ending conversion warnings" [FILE review/web-3/WEB-3-COMPLETION.md:27] and "existing LF/CRLF conversion notices only" [FILE review/web-4/TEST-EVIDENCE.md:13] [FILE review/web-5/SECURITY-VERIFICATION.md:20]. That is Git's "LF will be replaced by CRLF the next time Git touches it" warning: the author's working files were **LF** on a Windows machine with autocrlf conversion enabled.
- No doc says how the asset hash was computed beyond "pinned/bundled".

**Competing explanations:**
1. **CRLF conversion on checkout (most likely).**
   - Evidence: index LF vs working tree CRLF; no `.gitattributes`; the test hashes raw bytes; the file is one line, so CRLF adds exactly one `\r` byte; the author's own baselines match the expected (LF) hash.
   - The authors' "line-ending conversion" notices show their files had not yet been converted, which is why their run passed.
   - Testable without editing: compute the sha256 of the LF blob (`git show HEAD:repos/koi-backend/nextjs_app/public/illustrations/web1/circle-v1.svg` piped to a hasher). Pipes are not allowed in this session, so this is NEEDS-APPROVAL: run `git show HEAD:… | node -e "…sha256…"` or `certutil -hashfile`.
2. **The asset content changed after pinning.** Against it: [RUN git log -- public/illustrations src/lib/platform/illustrations.json] shows a single commit (`f2b9c80`) for both files, and the working tree is clean. Unlikely.
3. **The manifest hash was computed over different bytes** (e.g. a BOM, or a different file). Against it: three independent records (web-1 changed-files, web-4 and web-5 baselines) all show the same `cc6048…`. Unlikely.
4. **Test environment** (cwd different from APP). Against it: Jest ran from APP (`process.cwd()`), and the file was found (a hash was computed, not ENOENT). Ruled out.

**Consequences if (1) is right** [GUESS]:
- The runtime asset bytes served by Next on Windows checkouts differ from the pinned hash that clients (e.g. Flutter) may verify.
- The `validate-web*-contract.cjs` freeze-hash checks would also fail, since contract files are `w/crlf` and they hash raw bytes [FILE scripts/validate-web3-contract.cjs:22].
- The fix belongs to Ahmad/Web owner, not this session. Options: a `.gitattributes` with `*.svg -text` (or `eol=lf`) for pinned assets and contracts plus re-checkout, or hash normalized content. Any of these changes repo files or git settings, which is out of scope here.

---

## 13. UNKNOWNS AND DECISIONS

**Only Ahmad (or the project owner) can decide:**
1. Whether to use `E:\Koi\private\koi-service-account.json` for the read-only audit (§9 step 1), and which IAM roles that account may hold.
2. Whether the platform may run against production `koi-companion-fyp` at all, given that it shares the Auth user pool and Firestore with the real companion users.
3. Whether any rules or index deployment is acceptable, if live rules do not already deny the 37 platform roots.
4. Who is the "existing authorized operator" UID for provisioning, and whether to create one.
5. Whether cloud fictional provisioning (3 Auth users + ~30 docs + one `ai_jobs` doc) is authorized, and its cleanup policy.
6. How to rule out a paid consumer of `ai_jobs` (who inspects Functions/Eventarc/Modal config, and how).
7. How to fix the CRLF hash failure (`.gitattributes` vs normalized hashing), and when, given the frozen-contract hash discipline.
8. Single owner of AI job creation (Web submit vs AI start route), the ID scheme, the state mapping, and the result namespace (`clinician_evaluations` vs `ai_*`).
9. AI-specific consent: storage, scope, withdrawal semantics, and retention.
10. Phone demo approach: HTTPS method (proxy/tunnel/dev https) and exposure of `/api/auth/anonymous`.
11. Whether to correct the OpenAPI `x-status` values and README (that needs a new contract version under the freeze rules).
12. Cursor-signing-key generation, storage and rotation policy (it also derives invitation tokens [FILE lifecycle.ts:64]).

**Questions for the Web owner:**
1. Was `core.autocrlf=true` on your machine, and were the SVG/contract hashes computed from LF working files? Why no `.gitattributes`?
2. Should `GET /api/v1/notifications` really write (assignment materialization)? Is that acceptable for "read-only" checks and for cost?
3. `access_invalidation_outbox` is written but never read. Is it intended for a future worker, or dead?
4. `review_records (organization_id, psychologist_uid)` index: which query needs it? Records have no `psychologist_uid`.
5. Evidence is re-validated on every request, so the server dies 24 h after the audit. Intended? Should evidence be checked only at startup?
6. `web5-rules-security.cjs` cannot confirm the emulator is running the file it hashes. Should it fetch and compare the loaded rules?
7. Access-events polls `capabilities()` plus `verifyIdToken(…, true)` every 2 s per open tab. Has the Firestore/Auth read cost in cloud been estimated?
8. Rate limits run in a separate transaction before the operation, so failed operations still consume quota. Intended?
9. `NEXT_PUBLIC_KOI_LOCAL_TEST_ANON=true` is in `.env.local`. The code ignores it outside `NODE_ENV==='development'` [FILE src/lib/auth/anonymousSignInMode.ts:9], so under `next start` guests use `/api/auth/anonymous`, which writes cloud `users/`. Is that the intended examiner path?
10. Where is the Flutter source, and has anyone validated it against 0.5.2 patient DTOs?
11. Was `web05-deployment-evidence.py` (a `/health` ping) ever run against the paid backend after the zero-credit rule?
