# WEB-5 security and zero-credit verification

## Results

| Verification | Result | Evidence |
| --- | --- | --- |
| Offline regression suite | PASS: **86 suites / 688 tests** | `evidence/jest-results.json`, `evidence/jest.log` |
| Restricted provision/resume/collision/ownership tests | PASS: actual CommunityService with isolated Auth/store test doubles | `evidence/provision-tests.log`; included in full regression suite |
| Existing-project production gates and policy/index preservation | PASS | `src/__tests__/platform/web5-production.test.ts`; full suite |
| Companion/platform Admin coexistence | PASS: isolated mocks, no companion endpoint invocation | `src/__tests__/firebase-admin-coexistence.test.ts`; full suite |
| TypeScript | PASS after narrowing a test union type | `evidence/typecheck-final.log` (empty successful output) |
| Optimized production build | PASS with external networking blocked and telemetry disabled | `evidence/build.log` |
| Full reference policy + additive deny patch | PASS: **740 direct platform denials**, **80 original ownership-policy assertions** | `evidence/rules-security.json` |
| Real Next production HTTP + real Firebase emulators | PASS: **6 scenario groups** | `evidence/backend-functional.json` |
| Frozen contracts 0.5.0 / 0.5.1 / 0.5.2 | PASS: schema/fixture/hash/patient-boundary checks; unchanged wire schemas | Three existing `validate-*contract.cjs` tools, tool output |
| Browser static chunks | PASS: no Admin/provisioning/cursor/bootstrap environment names | Static `rg` scan of `.next/static/chunks` |
| Cloud read-only inspection | BLOCKED: no Admin credential / CLI login; no network requests or cloud writes were made | `evidence/cloud-inspection/audit.json` |
| Final rules/index artifact consistency | PASS: preserved reference source, 12 required composite proposals, no redundant single-field proposals | `evidence/artifacts.json` |
| Existing-work preservation | PASS: every pre-existing file outside four intentional edits retains its captured hash | `evidence/preservation.json` |
| Operator PowerShell syntax / whitespace checks | PASS: AST parse only (no scripts executed), `git diff --check` | Tool output; existing LF/CRLF notices only |

The full Jest run passed after the initial fixture-return issue was fixed. The later test-only TypeScript union narrowing did not change runtime behavior. The real HTTP harness initially counted jobs at an incorrect root field; it was corrected to the existing frozen `job.organization_id` structure and passed. No production schema was changed to satisfy a test.

## Isolation established before execution

Audited `package.json`, Jest configuration/setup, test network call sites, actual platform routes and operational scripts before executing commands. Unit voice/SSE/speech/crisis/renderer tests use existing mocks/fixture responses. No live AI dependency was substituted.

Every WEB-5 test/build and the isolated Next test server ran with:

```powershell
$env:NODE_OPTIONS='--require=C:/Users/PMYLS/Koi/repos/koi-backend/nextjs_app/scripts/web5-network-guard.cjs'
$env:NEXT_TELEMETRY_DISABLED='1'
```

The test-only guard rejects external fetch, HTTP(S), DNS lookup and sockets before connection. A fictional `metered.example.invalid` target was used to verify rejection; no real provider was probed. The guard also rejects local forwarding paths `/api/v1/chat` and `/api/v1/crisis` through real fetch/HTTP. It is inherited by Node subprocesses and is never imported into the application's normal runtime. SDK metadata discovery produced an explicit blocked-network warning during emulator setup; it did not contact a service.

The real integration harness independently asserts its URLs are local platform paths and excludes chat, crisis and AI route families. It uses Auth 5499, Firestore 5480, Next 3207 and a temporary offline emulator namespace. No cloud Firebase project was created. Existing servers/data on WEB-4 ports were left untouched. No browser/live companion smoke suite was executed for WEB-5.

**WEB-5 made zero Modal, AgentRouter or other paid inference/TTS/lip-sync/crisis/GPU requests.** No health ping, warmup, restart, deployment, benchmark or provider configuration/model/weight change was performed. No external AI endpoint was contacted by these tests/builds.

## What the real backend tests prove

- Actual Firebase password and anonymous tokens are validated by Next's revocation-aware Admin identity path. Password-only users without server registration and `users/{uid}` role spoofing do not gain discovery or professional capability.
- Anonymous, General and Patient users cannot read seven professional evaluation/submission/review/analytics surfaces. Another patient cannot read the assignment; another psychologist cannot inspect another organization's submission workspace.
- A forged version field is rejected by the strict frozen schema. Autosave increments confirmed revisions, rejects stale saves and resumes server-confirmed answers.
- Concurrent submissions produce the same acknowledgement, one additional pending job and locked submitted answers. There is no provider dependency or evaluation field in the acknowledgement.
- Recursive patient assignment/detail/notification DTO inspection finds no evaluation/score/review/job fields. Direct Firestore access also denies those namespaces.
- Human message membership, appointment proposal/confirmation, in-app notification reads and professional actual-data analytics work through real backend routes.
- Relationship closure immediately denies further questionnaire/conversation access; disabled Firebase users' still-held tokens are rejected.
- The provisioning ledger covers every seeded document; replay does not overwrite records/passwords; immutable versions, submitted answers, protected evaluations and manual review are created through the existing services.

## Rules boundary

The full tested policy retains every original checked-in rule and adds explicit direct-client denial for 37 platform/internal roots. All five principals (unauthenticated, anonymous and untrusted General/Patient/Psychologist-labeled clients) are denied get, write, collection query and collection-group query: 37 × 5 × 4 = 740. The original owner read/write and foreign-user denial behavior remains intact across five legacy collections: 4 authenticated clients × 5 collections × 4 checks = 80.

Admin SDK bypasses rules; the backend authorization checks above remain mandatory. Explicit deny clauses do not override another matching allow. This candidate result is **not evidence of the currently published source**. Cloud configuration requires a fresh real release snapshot with the identical hash and passing complete-policy tests. No reference-policy result is presented as deployed verification.

## Deliberately skipped / blocked

| Check | Reason |
| --- | --- |
| Live Modal companion/SSE/crisis/health/voice/lip-sync/avatar inference | Explicit zero-credit restriction; preserved by static inspection and existing isolated mocks only |
| AgentRouter or any paid AI worker evaluation | Explicit zero-credit restriction; pending jobs/manual review only |
| WEB-4 companion browser smoke and any unproven live E2E suite | Credit boundary; not required for Firebase preparation |
| Actual cloud provisioning and persistent cloud-login walkthrough | Owner has not authorized cloud writes; private credential/provider/index evidence missing |
| Published rules/IAM/Auth provider/index/authorized-domain/App Check validation | No authenticated read credential or CLI login |
| Cloud deployment and live rollback | No authorization; prepared instructions only |
| Whether deployed paid workers/triggers consume new cloud jobs | No deployed AI-infrastructure inspection was authorized/performed. Confirm from configuration before any future cloud seed/submission; otherwise keep cloud writes blocked. |
| Flutter parity | Source/integration remains outside this Web batch |

No existing UID, chat, data, storage, live rule, deployment or AI infrastructure was changed. Clinical assessments remain strictly psychologist-only. No public registration/migration bypass or public seeder endpoint exists.
