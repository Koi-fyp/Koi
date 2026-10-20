# WEB-3 — local implementation and verification

Baseline: `feat/web-1-professional-publishing`, HEAD `f2b9c80` (`checkpoint: KOI WEB-1 and WEB-2 implementation`). Existing WEB-2 evidence edits and unrelated `.idea/` / mobile Android work were preserved. No commit, push, merge, reset, deployment, rules deployment or destructive operation was performed.

Implemented:

- Verified-owner public profile controls, registered-only expert directory, loaded-page search, application acceptance switch enforced transactionally, existing application/demo-payment workflow plus dedicated simulated-payment records.
- Patient roster search/status filters and loaded counts; scoped patient details/history; separate archival metadata for closed relationships. Account identity is unchanged by closure/archive.
- Dedicated relationship-bound human messages with immutable sender/time, paging, retry deduplication and inbox indicators. Neo conversation UI is separate from companion transport.
- Patient appointment requests, professional proposals, patient confirmation, rejection/cancellation and post-end completion. Revision checks resolve races. Rescheduling follows cancel/new-request semantics.
- In-app assignment, message, application and appointment events; separate strictly professional submission updates. Safe reference-only serializers, deterministic event IDs, read acknowledgements and request-driven assignment delivery. No external push.
- Professional actual-data activity by exact questionnaire version, daily submission bars/table, UTC date filters, counts and patient submission history. No fabricated scores or improvement metrics.

Validation:

| Check | Result |
| --- | --- |
| `npm run build` | PASS: optimized build, type/lint checks and page generation |
| `npx tsc --noEmit --incremental false` | PASS |
| `npx jest --runInBand` | PASS: 79 suites / 668 tests at the full-suite checkpoint |
| Subsequent `community-routes.test.ts --runInBand` | PASS: 1 additional suite / 2 tests; total tested coverage 80 suites / 670 tests |
| New community service tests (included in full run) | PASS: 7 tests covering authorization, retries, races, closure, nested-field filtering, discovery, analytics and notification boundaries |
| Frozen 0.5.0 / 0.5.1 validators | PASS; original definitions and frozen artifacts unchanged |
| `validate-web3-contract.cjs` | PASS: 108 definitions, 58 operations, 22 valid / 21 rejected fixtures; patient-boundary traversal |
| Real Firebase emulator + Next + Chrome | PASS: 16 scenarios; 0 page errors, 0 companion requests, 0 provider calls; see evidence JSON |
| `web3-emulator-security.cjs` | PASS: 28 direct read/write/query/collection-group denials across all seven new communication/profile/archive collections; real Firebase anonymous UID directory denial |
| `git diff --check` | PASS; only existing line-ending conversion warnings |

The emulator/browser journey covers WEB-1 publish, invitation/onboarding, assignment, EN/UR picture runner, autosave/restart/resume, duplicate submissions, protected review, application/demo flow, direct Firestore denial, new directory, human messages, appointment concurrency, notification deduplication, actual counts, relationship revocation and account switching. New tests also deny cross-organization/General analytics and professional submission notifications. Existing regression output includes pre-existing React test warnings; no failing tests remain.

During verification, the initial cursor test expected HTTP 400 rather than this contract's 422; that assertion was corrected. A screenshot rerun's literal middle-dot selector was converted by PowerShell to question marks and timed out while the correct dashboard counts were visible; it was replaced with an encoding-independent selector. Historical `failure-*.png` images record that harness failure, not a failed application scenario. Final successful evidence is `functional-emulator.json` and the named screenshots.

Contracts: additive `contracts/v0.5.2` preserves every 0.5.1 definition. New routes cover profile controls, archival, scoped patient history and professional submission notices. Existing application creation now requires discoverable/accepting profile state; its fixture explicitly seeds that prerequisite. No questionnaire/attempt/job schema change. Cross-track acknowledgement remains pending; nothing was sent to another owner. See the versioned semantics and authorization matrix for exact boundaries.

Limits and dependencies:

- Search and roster counters describe loaded pages; inbox unread counts also describe loaded notifications. Refresh is explicit, not push/always-on delivery. Assignment notifications materialize on first inbox page refresh from durable assignments. Professional submission updates are an activity feed without read receipts.
- Rescheduling is two explicit operations, not atomic replacement; calendar conflict/double-booking prevention is not implemented. No external calendars.
- Analytics intentionally fail unavailable above documented scan/series bounds rather than present partial totals. Manual custom forms have `scoring_version=not_applicable`. Evaluation/clinical trend charts remain unavailable without validated scoring data; no substitute metrics are invented.
- Published Firebase project/rules/IAM/App Check, production query indexes, hosting configuration and streaming-proxy behavior are still unverified deployment dependencies. Existing fail-closed deployment gate is unchanged. Local emulator rules remained unchanged.
- Public registration/mail verification, approved migration, production consent/retention decisions, AI worker/provider/scoring integration and Flutter source/cross-track acknowledgement remain dependencies from earlier batches. Manual questionnaires and submission acknowledgement remain provider-independent.
- Test doubles: unit tests use the transactional memory store and mocked identity transport. Functional tests use real Auth/Firestore emulators, Next handlers and Chrome; fictional registered accounts and a labelled AI failure/original-interpretation fixture are seeded. Payments are deliberately simulated. No live AI, messaging service, financial provider or external push is connected.

Neo components, existing theme tokens, `neo-spinner`, reduced-motion rules, companion/SSE/avatar implementation and original rules files are preserved. The screenshot evidence shows the existing professional theme. Exact changed/new paths are listed in `CHANGED-FILES.md`; setup is in `SETUP.md`. Local Web integration is ready for review; production and Flutter integration are not certified.
