# WEB-2 collection authorization supplement

All direct Firebase client reads/writes/listeners/collection-group queries for new
platform collections are denied, including for psychologists. Backend Admin SDK
transactions implement the table below. Live published policy remains unverified;
only the unchanged local emulator deny-all rules were tested.

| Collection/group | General/patient backend access | Verified owner backend access | Writes |
| --- | --- | --- | --- |
| accounts, psychologist_verifications, organizations, organization_memberships, organization_owners | Computed own capabilities only | Computed own authority / existing WEB-1 organization flow | Existing server registration/seed and organization service; closure/onboarding increment account authority revision |
| patient_invitations | Redeem token with current General registration, consent and intended identity | Create/revoke in own practice | Server hash/expiry/revision/consume transaction |
| invitation_token_lookup (new internal) | None | None | Server hash → invitation lookup only |
| patient_relationships | Own active relationship projection | Own practice roster, including retained closed relationships | Server acceptance/redemption/closure; no client role flags |
| connection_requests | Own application DTO/state transitions | Own practice request DTO/accept/reject | Server state machine; demo state embedded in request, no financial credentials |
| questionnaires, questionnaire_versions | Pinned question-only projection for assigned open attempts | Existing own-practice drafts/immutable versions | Existing WEB-1 author/publish services only |
| assignments, attempts | Own active-relationship assignment, pre-submit answers, acknowledgement | Assignment creation; submitted answers via protected submissions | Server revision CAS, atomic submit, assignment batch |
| submissions | Acknowledgement only | Own practice immutable submitted answers | Atomic submission create only |
| clinician_evaluations | **None, including status** | Authorized own-practice evaluation DTO | Submission creates empty envelope; future authorized AI service supplies results |
| ai_jobs | **None** | Own-practice job projection within submission workspace | Submission creates queued job; worker remains unavailable |
| review_records | **None** | Own-practice append-only review/decision history | Verified owner with revision CAS; no original output mutation |
| review_heads (new internal) | **None** | Revision/status projection only | Backend serialized append bookkeeping |
| platform_rate_limits (new internal) | None | None | Server per-UID/hour invite/application/redemption counters |
| access_invalidation_outbox (new internal) | Authorization-only hint via separate access stream; never raw records | No raw records | Onboarding/closure transaction; stream independently rereads authority |
| idempotency_records, audit_events | Sanitized operation acknowledgements only after reauthorization | Same, within authorized scope | Server-only receipts and append-only audit |
| notifications, messages, appointments, AI results | No new endpoint in this batch | No new endpoint in this batch | No WEB-2 writers or subscriptions |

The four explicitly named internal additions have no client contract or existing
consumer. The frozen `platform_outbox` placeholder is not provisioned or read by this
batch; access invalidation uses the explicit new namespace above. The empty protected
evaluation envelope and separate review head are the only new result-side persistence
behavior; no evaluation field is added to assignment or patient attempt responses.

Existing `users/{uid}`, companion messages, Dexie stores and their rules are untouched.
No default companion identity flag or client-writable profile property grants platform
authority. Every request verifies the Firebase ID token and current stored scope.
