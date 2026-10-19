# WEB-2 completion — patient lifecycle and protected review

**Implemented locally on `feat/web-1-professional-publishing`, continuing the accepted
WEB-1 baseline.** A verified psychologist can onboard an existing server-registered
General account, assign an immutable questionnaire, receive its locked submission and
append protected review decisions. The patient sees their assignments, open answers
and submission acknowledgement; no evaluation fields or evaluation progress are
returned through the patient flow.

No commits, pushes, merges, resets, deployments or destructive Git operations were
performed. Existing unrelated changes were preserved. Existing companion, SSE, avatar,
Dexie, global theme/components and live/checked-in Firestore rules were not edited.
The independent care access-invalidation stream is a new platform route.

## Delivered behavior

- **Onboarding:** random/keyed single-use invitation links, hashed lookup, optional UID
  binding, expiry, revocation, rate limits and transactional redemption. General
  application → demo step → owning psychologist acceptance also activates a relationship.
  Neither payment simulation nor client account fields grant patient privileges.
  The server accepts only the currently supported consent revision.
- **Relationships:** server-owned active/closed records scoped to organization,
  psychologist and patient. Concurrent onboarding does not duplicate the active roster.
  Closure revokes subsequent reads, writes and submission replay; the General account
  remains registered and professional history stays protected.
- **Assignments:** one, selected or all active recipients; up to 200 per synchronous
  batch. All-active snapshots the roster once. Each recipient receives an independent
  assignment/attempt pinned to the exact published version. Repeat assignment uses a
  new operation key and starts a new attempt.
- **Patient runner:** all seven agreed question types; bundled image options; EN/UR/
  Roman Urdu custom content; Urdu RTL; progress; debounced backend autosave; reload/
  cross-session resume; restart before submission; explicit conflict reconciliation;
  answer-review screen and final confirmation. Neo components, theme styles, spinners,
  keyboard controls and scoped reduced-motion behavior are reused unchanged.
- **Submission:** authenticated transaction validates current relationship, ownership,
  assignment/version references, confirmed revision and required answers. It locks
  answers and atomically creates one stable submission, queued AI job and empty
  protected evaluation envelope. Concurrent/duplicate submits return the same four-field
  acknowledgement. Provider availability is outside this transaction.
- **Professional review:** scoped submission list and original-answer inspector;
  deterministic-score fields when authorized results exist; truthful pending/failed
  AI states; original interpretation beside editable clinician fields; append-only
  approve/reject/feedback revisions and paginated history. Custom forms have no validated
  deterministic scores, and no provider/scorer output is invented.
- **Evaluation isolation:** strict patient serializers, recursive DTO checks, separate
  protected namespaces, sanitized errors, no-store responses, no protected offline
  persistence and no direct clinical Firestore subscriptions. Patient entry bundles
  exclude the checked protected evaluation/server-secret identifiers. No result-sharing
  control, automated evaluation notification or evaluation field in patient responses
  was introduced.
- **Revocation:** the separate authenticated access stream carries hints only. The care
  screen clears protected memory, cancels requests and refetches authority on changed
  access, UID change or reconnect. It locks on disconnect, hidden/offline state or a
  missed heartbeat. Backend checks remain authoritative for every request.

## Files and shared contracts

The exact batch delta, including modifications to previously untracked WEB-1 files,
is in [changed-files.md](changed-files.md), with SHA-256 inventory in
[changed-files.json](changed-files.json). The starting snapshot is [baseline.json](baseline.json).
Git alone cannot describe this delta because the accepted WEB-1 files remain uncommitted.

Main implementation paths:

| Area | Files / directories |
| --- | --- |
| Authoritative lifecycle transactions | `src/lib/platform/server/lifecycle.ts`, `lifecycle-http.ts` |
| Reused authorization/queries/runtime | `src/lib/platform/server/service.ts`, `store.ts`, `firestore-store.ts`, `runtime.ts`, `http.ts`, `contract.ts` |
| Patient-safe types, answer validation, client invalidation | `src/lib/platform/patient-types.ts`, `answers.ts`, `access-monitor.ts`, `client.ts` |
| Professional-only evaluation types | `src/lib/platform/professional-types.ts` |
| Patient UI | `src/app/patient/`, `src/components/patient/` |
| Roster, assignment, submission and review UI | `src/components/professional/PatientManagement.tsx`, `SubmissionReview.tsx`, integration in `ProfessionalWorkspace.tsx` |
| New HTTP routes | `src/app/api/v1/connection-requests/`, `patient-invitations/`, `patient/`, new professional routes, `me/access-events/` |
| Tests and browser harness | Five new tests in `src/__tests__/platform/`, `test/platform-memory.ts`, `scripts/web2-emulator-functional.cjs` |
| Contract extension | `contracts/v0.5.1/`, `contracts/implementations/WEB-2.md`, README link, `scripts/validate-web2-contract.cjs` |

**Contract disclosures:** frozen 0.5.0 files and all 96 original definitions remain
unchanged. The compatible 0.5.1 package adds six definitions and five professional
operations: roster list, submission list, submission workspace, append review decision,
and list review decisions. Existing patient/questionnaire DTO constants stay 0.5.0.
There are 52 described operations; 31 are implemented across WEB-1/WEB-2 and the rest
remain marked proposed. Review decisions use new endpoints instead of silently adding
fields to existing review DTOs.

Physical internal additions (`invitation_token_lookup`, `platform_rate_limits`,
`review_heads`, `access_invalidation_outbox`) and the empty evaluation envelope are
explicitly documented in the versioned [authorization supplement](../../contracts/v0.5.1/authorization-matrix.md).
The earlier generic `platform_outbox` placeholder remains unused. Demo completion
is recorded on the connection request; no separate financial subsystem is created.
Mobile/AI acknowledgement of the additive package is pending; no cross-track messages
or edits were performed.

## Verification results

| Command / check | Final result |
| --- | --- |
| `npm test -- --runInBand --silent` | **PASS: 78 suites, 661 tests**, including existing companion/SSE/avatar regression coverage |
| WEB-2 unit/route/UI tests within that suite | **PASS: 5 suites, 35 new tests** |
| `npm run build` | **PASS**, Next 14.2.35 production build, TypeScript checks and 22 static-generation entries |
| `node scripts/validate-web05-contract.cjs` | **PASS:** original frozen hashes; 96 schemas, 47 operations, 13 valid / 14 rejected fixtures |
| `node scripts/validate-web2-contract.cjs` | **PASS:** 102 definitions, 52 operations, 17 valid / 18 rejected fixtures, 25 patient-reachable definitions and extension freeze hashes |
| `node scripts/web2-emulator-functional.cjs` | **PASS: 15 real emulator/browser scenarios**, zero browser page errors, zero companion requests, zero provider calls |
| Preserved-source hashes, patient bundle scan, whitespace checks | **PASS**; details in [verification.json](verification.json) |

No final failing checks remain. The browser run found a missing accessible field name
and a disposed-client race during authorization-generation replacement; both were
corrected and retested. A dedicated regression test now verifies old rejected requests
cannot expire the replacement session. Other initial failures were test-harness timing
and a text regex matching “AI” inside “questionnaire.” Early diagnostic screenshots
are retained as diagnostics; the final evidence JSON identifies the successful run.

Final browser evidence: [scenario results](evidence/functional-emulator.json),
[mobile Urdu runner](evidence/patient-urdu-mobile.png),
[patient acknowledgement](evidence/patient-acknowledgement.png),
[professional review](evidence/professional-review.png). The mobile and professional
screens were visually inspected; the 390px runner had no horizontal overflow.

Verified scenarios include invitation redemption/reuse denial, application acceptance
with safe idempotent replay after acceptance, immutable assignment, save/resume/restart,
final confirmation, cross-device save conflict and first-submit race, one job per
submission, provider failure independence, append-only review preservation,
cross-patient/cross-practice denial, direct Firestore get/write/collection/group denial,
open-screen closure invalidation and cross-account logout/login isolation.

## Remaining dependencies and actual simulation boundary

| Item | Status / consequence |
| --- | --- |
| Production Firebase/rules/IAM/App Check/hosting/indexes | Still unverified and undeployed. Local emulators do not establish deployed security or index availability. |
| Real General registration | Approved email-possession delivery remains unavailable. Runtime requires an already server-registered General account; invitations never bypass it. |
| Consent and retention | Local integration version is enforced, but production wording, legal basis, duration and deletion/export processes remain policy prerequisites. |
| Invitation logging/key rotation | Production token-path redaction and secret-rotation policy must be configured and verified. |
| Access-stream hosting | Buffering, timeouts and connection limits need deployment evidence. No disconnected-client instantaneous delivery is claimed. |
| AI worker and deterministic scoring | Not implemented here. Normal jobs remain queued. Approved workload identity, lease endpoints, provider adapter and licensed/versioned instrument scorers belong to the AI/infrastructure integration. Manual review and patient submission already work without them. |
| Flutter | Source/parity testing and additive-contract acknowledgement remain missing; web/backend work does not depend on them. |

Jest uses identity/network/storage doubles where indicated. The functional browser run
uses actual SDKs, HTTP handlers and Firestore transactions against official local
Firebase emulators. Accounts, registration evidence and test patient content are
fictional. One explicitly labelled original-interpretation/provider-failure fixture
is inserted through emulator Admin access solely to test protected review behavior;
it is not provider output. Runtime has no mock result or in-memory persistence fallback.

This batch does not implement public discovery, registration delivery, notifications,
messages, appointments, instrument registry/scoring, or same-practice re-onboarding after
closure. Closing a relationship cannot reopen historical assignments. A future return
to the same practice needs a new relationship-generation contract. A dual clinician/
General account currently gets its professional application-list scope first.

Local web/backend integration is ready for contract-based AI/Mobile work. Production
enablement remains blocked on the listed evidence and policy prerequisites. Reproduction
and proposed indexes are in [SETUP.md](SETUP.md). No deployment or merge is implied.
