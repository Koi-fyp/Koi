# WEB-3 collection authorization

All direct client Firestore reads/writes of platform records are denied by the local emulator policy. Published/live rules remain unverified and unchanged. The existing production deployment gate still applies; backend Admin SDK bypasses rules and explicitly authorizes each operation.

| Collection | Backend read authority | Backend write authority |
| --- | --- | --- |
| psychologist_profiles | Registered General directory projection after live verification; verified owner full own profile | Verified active organization owner; revision and idempotency |
| messages | Active patient or verified owner of that active relationship | Same participants; server assigns sender/time; immutable |
| appointments | Active relationship participants | Patient create; actor-specific server state machine and revision |
| notifications | Registered recipient plus current referenced relationship/application authorization | Server event generation; recipient read acknowledgement only |
| professional_notifications | Verified active owner within organization | Server submission transaction only |
| demo_payments | No public collection read endpoint | Server simulated-payment transition; no financial fields |
| patient_archives | Verified owner of referenced organization/relationship | Same owner; closed relationship only for archival |
| assignments, submissions | Existing authorities; analytics/history only verified scoped owner | Existing WEB-2 paths unchanged |
| clinician_evaluations, review_records, ai_jobs | Existing strictly professional/backend policy | Existing protected policy; no new patient access |

Query filters always include recipient, organization, relationship or a fixed directory scope. Pagination is signed and actor-bound. No collection-group query or generic document serialization is exposed. Scope checks precede receipt replay and writes. This matrix supplements the frozen base matrices.
