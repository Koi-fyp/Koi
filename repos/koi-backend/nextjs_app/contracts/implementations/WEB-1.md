# WEB-1 implementation against 0.5.0

The accepted proposal in `../v0.5.0/` remains byte-for-byte unchanged. This file records
implementation coverage; it does not replace or revise the frozen contract.

| Frozen operation | Implemented path | Authorization |
| --- | --- | --- |
| `getCapabilities` | GET `/api/v1/me/capabilities` | Verified Firebase ID token, no registration inferred from provider flag |
| `ensureOrganization` | POST `/api/v1/professional/organizations` | Registered + verified clinician, fresh auth; transaction creates unique owner membership |
| `createQuestionnaire` | POST `/api/v1/professional/questionnaires` | Active owner membership in requested organization |
| `listQuestionnaires` | GET `/api/v1/professional/questionnaires` | Scoped organization/owner query; HMAC cursor bound to identity and authority revisions |
| `getQuestionnaire` | GET `/api/v1/professional/questionnaires/{id}` | Resolve stored ownership and current membership |
| `updateQuestionnaire` | PUT `/api/v1/professional/questionnaires/{id}` | Same + revision CAS + fresh auth |
| `publishQuestionnaire` | POST `/api/v1/professional/questionnaires/{id}/publish` | Same + saved revision/content hash; one immutable version per revision |
| `getQuestionnaireVersion` | GET `/api/v1/professional/questionnaire-versions/{id}` | Current verified practice ownership, explicit version DTO |

All mutations require `Idempotency-Key` and reauthorize before replay. All responses
use private/no-store and explicit schema-checked DTOs. Backend records alone govern
verification, account state, organization and membership. CLI verification is separate
from these HTTP operations. No new patient endpoint, evaluation/job record or direct
Firestore client write is implemented.

The 7 agreed question types work for **manual custom questionnaires**. AI-origin drafts,
instrument registry operations, patient assignment/submission and other proposed
operations are not implemented in WEB-1. No unavailable operation returns fake success.
Operational limits are explicit: 512,000-byte JSON request limit, 400,000-byte canonical
content limit, bounded lists (default 25, maximum 100), 15-minute signed cursors, and
five-minute recent authentication for privileged mutations. There are no wire schema
or DTO-field deviations. Operational configuration, isolated named Auth and the
bundled illustration allowlist add no shared endpoint/schema changes.

Evidence and exact files: `../../review/web-1/WEB-1-COMPLETION.md`.
