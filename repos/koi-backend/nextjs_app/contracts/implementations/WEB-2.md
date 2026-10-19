# WEB-2 shared handoff

Baseline: immutable `v0.5.0`; additive package `v0.5.1`. No existing definition or
patient response changed. Cross-track notification/acknowledgement remains pending;
no external messages were sent and no other owner's source was edited.

Implemented existing contract operations:

| Area | Operations |
| --- | --- |
| Invitations | POST professional/patient-invitations; POST professional/patient-invitations/{id}/revoke; POST patient-invitations/{token}/redeem |
| Applications | POST/GET connection-requests; POST connection-requests/{id}/transition; POST connection-requests/{id}/demo-payment |
| Relationships | POST professional/patient-relationships/{id}/close |
| Assignments | POST professional/assignments; GET patient/assignments and patient/assignments/{id} |
| Attempts | PATCH patient/attempts/{id}; POST patient/attempts/{id}/submit |
| Professional reads/reviews | GET professional/submissions/{id}; GET professional/evaluations/{id}; POST professional/reviews; GET professional/evaluations/{id}/reviews |
| Access invalidation | GET me/access-events, independent of companion SSE |

All paths above have prefix `/api/v1/`. Five additive operations:

| Method/path under `/api/v1` | Request / response |
| --- | --- |
| GET professional/patient-relationships?organization_id=… | PatientRelationshipListDTO; professional only |
| GET professional/submissions?organization_id=… | ProfessionalSubmissionListDTO |
| GET professional/submissions/{id}/workspace | SubmissionWorkspaceDTO |
| POST professional/review-decisions | ReviewDecisionRequest → ReviewDecisionDTO |
| GET professional/evaluations/{id}/review-decisions | ReviewDecisionListDTO |

Every mutation needs Idempotency-Key. Lists default to 25, maximum 100, with opaque
signed cursors. Refer to the package semantics for scope, revision and replay rules.

Mobile: consume unchanged patient DTOs, typed option-ID answers, stable pinned asset
references, PATCH revision conflicts, restart-as-empty-autosave, immutable submission
acknowledgement and access invalidation. Do not subscribe directly to clinical
Firestore or retain protected offline content. Bundled assets remain the WEB-1 manifest.
Missing Flutter source prevents parity verification, not backend/web operation.

AI: submission atomically creates an AIJobRecord in queued state and a protected empty
evaluation envelope. No provider adapter, worker lease/complete/fail endpoints, workload
identity, deterministic instrument scorer or provider availability is claimed. Manual
review works against the empty envelope. Existing validated score fields render when
authorized results exist, but custom questionnaires never receive invented scores.
Reviews append separate records; original output is unchanged. Future worker integration
must handle pre-existing envelopes/review heads and preserve all original provider data.

Deployment: all new namespaces require direct-client deny rules verified in the actual
published release. Only the existing emulator deny-all rules were exercised; live rules
remain untouched. Proposed indexes and remaining prerequisites are in
`review/web-2/SETUP.md`. Real-user consent/retention and registration delivery need approval
before production enablement. Platform default remains disabled without explicit config.
