# Collection authorization matrix — proposed, not deployed

All **new** collections below deny direct Web/Flutter SDK reads, writes, lists and
collection-group queries, including to verified psychologists. Access in this table
means **through the backend and explicit DTOs**. Firebase rules are not filters;
Firestore Admin credentials bypass them, so backend authorization remains mandatory.
`own practice` requires current registered account, verified psychologist, active
organization and active owner membership on each operation.

| Collection | Unregistered/custom guest/anonymous | Registered general | Active patient | Verified psychologist | Authoritative writes |
| --- | --- | --- | --- | --- | --- |
| `accounts` | Own computed capabilities only | Own computed capabilities | Own computed capabilities | Own computed capabilities | Registration service/restricted seed; never profile writes |
| `registration_challenges` | No raw reads | No raw reads | No raw reads | No raw reads | Backend issue/consume/revoke; hash only; no direct client reads |
| `psychologist_verifications` | None | None | None | Own capability projection; no approval evidence | Restricted CLI/admin + audit |
| `organization_owners` | None | None | None | Own organization projection | Backend unique ownership lock |
| `organizations` | None | Public expert projection with discovery grant | Linked practice/public expert projection | Own practice | Verified owner through server transactions |
| `organization_memberships` | None | None | None | Own practice membership projection | Backend creation/revocation only |
| `psychologist_profiles` | None | Allowlisted discoverable expert DTO | Same | Own profile/practice | Backend validated update; verification separate |
| `patient_relationships` | None | None | Own active relationship projection | Own practice; historical access subject to retention | Acceptance/invitation/closure transactions |
| `connection_requests` | None | Own requests | Own requests | Own practice requests | Server actor-specific transition service |
| `demo_payments` | None | Own request status projection | Same | Own practice status projection | Server simulation; no finance fields |
| `patient_invitations` | None | Redemption acknowledgement only | Same | Own practice metadata; creation secret shown once | Server hash/expiry/revoke/transactional redemption |
| `instrument_templates` | None | None | Assigned item projection only | Permission-checked registry | Restricted registry seed/version service |
| `questionnaires` | None | None | None | Own practice draft DTO | Server create/CAS update; no client SDK writes |
| `questionnaire_versions` | None | None | Pinned question-only projection while relationship active | Own practice immutable snapshot | Server publish only, create once |
| `assignments` | None | None | Own active relationship, patient DTO | Own practice | Server create/state transitions |
| `attempts` | None | None | Own pre-submit answers; submitted acknowledgement only | Own practice submitted-answer projection | Server revision-checked autosave and atomic submit only |
| `submissions` | None | None | Acknowledgement only | Own practice raw answers | Submission transaction, immutable |
| `clinician_evaluations` | None | None | **None** | Own practice authorized evaluations | Authorized scoring/evaluation service only |
| `review_records` | None | None | **None** | Own practice review history | Backend verified reviewer append only |
| `ai_jobs`, `ai_results` | None | None | **None** | Own practice job/result DTO | Backend + allowlisted service via leased internal API |
| `messages` | None | None | Active relationship participants | Linked active relationships only | Backend immutable sender/time; no direct SDK writes |
| `appointments` | None | None | Active relationship participants | Linked active relationships only | Backend actor/revision-checked transitions |
| `notifications` | None | Own fixed-reference events | Own currently authorized events | Own fixed-reference events | Backend deduplicated events; read receipt through server |
| `audit_events` | None | None | None | Authorized review-history DTO only, not raw audit | Backend/restricted admin append only |
| `idempotency_records`, `platform_outbox` | None | No raw reads | No raw reads | No raw reads | Backend transactions, least-privilege dispatcher |
| `migration_manifests` (future) | No automatic claim | Own migration receipt only after explicit consent | Same | No patient companion access | Backend import verifier; not implemented in first slice |

AI service identities do not get general Firestore access. The internal leased API
supplies only the job's submission, version and approved scoring metadata. A service
cannot select arbitrary patients or inspect companion data. Service identity trust,
ingress and IAM need deployment verification before worker enablement.

Existing namespaces are **observed source behavior, not a new policy**:

| Existing path | Checked-in rule behavior | Current source variance / action |
| --- | --- | --- |
| `users/{uid}` | Any authenticated same-UID read/write, without field allowlist | Never place registration, verification or membership authority here; preserve companion policy |
| `conversations/{uid}/messages/{id}` | Same-UID reads/writes | Legacy path; current queue repaths owned legacy messages |
| `users/{uid}/conversations/{cid}/messages/{id}` | No matching allow in checked-in rules, so deny | Current client path; review proposal differs; published policy unknown |
| `mood_entries/{uid}/entries/{id}`, `wellness_progress/{uid}`, `tasks/{uid}/items/{id}` | Same-UID reads/writes | Preserve; not reused as clinical data |
| Unmatched paths | Deny in checked-in rules | Must verify **published** deny before new platform production data |

No live or checked-in rules were changed. Full-rule emulator/REST denial tests,
cross-organization forged IDs/cursors/nested-reference tests and patient serializer
tests remain implementation acceptance gates, not results of this matrix.
