# WEB-2 semantics supplement

Inherit 0.5.0 semantics and authorization matrix. No existing wire DTO changes.
The implementation adds only the professional schemas listed in CHANGELOG.md.

- General registration is server-owned. No account is registered by invitation,
  demo payment, provider flags, client profile fields or patient UI. The existing
  password/email-possession registration prerequisite remains blocked. Emulator
  tests seed fictional General records; runtime has no fixture bootstrap.
- Onboarding requires the currently implemented `care-consent-v1`, explicit user
  confirmation, current registered General authority, fresh authentication and an
  active verified owning practice. Unknown consent IDs are rejected. Production
  wording, retention, export/deletion policy and legal review remain prerequisites.
- Invitation creation uses a random 256-bit nonce and HMAC-SHA256 with a domain-
  separated server secret to issue a 256-bit bearer token. Persist token SHA-256,
  nonce, expiry, intended UID and revision; never plaintext token or token-bearing
  acknowledgement in receipts/audit. A same-key retry reconstructs the token after
  authorization. Only the token hash is an authentication lookup. Secret rotation
  needs an operational policy before production. Rate limits: 30 invitation creates,
  30 applications and 60 redemption attempts per authenticated UID per hour.
- Browser invitation links carry the secret in a fragment; the care screen removes
  it from the address bar. The frozen redemption API includes a token path segment,
  so production ingress/access-log redaction is mandatory and remains unverified.
- Active relationship identity is unique per practice/UID. Concurrent invitations
  and application acceptance converge on one relationship. Closed relationships
  cannot reopen in this slice, preventing old assignments from regaining access.
  Re-onboarding the same person into the same practice needs a future relationship
  generation/active-pointer contract. Other practice relationships remain independent.
- Applications target a psychologist UID shared by that practice. Directory/profile
  management is not implemented. Requests must pass requested → awaiting_demo_payment
  → pending_psychologist_review before owning clinician acceptance/rejection. The
  applicant may withdraw. Only the demo action marks demo completion; no payment
  credentials or gateway exists. Connection listing resolves professional owner
  scope first, otherwise applicant scope; dual-account application-list switching
  is not implemented.
- Assignment creation snapshots up to 200 active authorized relationships in one
  transaction. Same-key retry uses the original snapshot and reauthorizes recipients;
  newly closed recipients deny replay. A new key intentionally creates repeat
  assignments. Each assignment has one independent attempt and immutable version ID.
- Patient autosave is bearer-authenticated PATCH with revision CAS; it does not demand
  repeated password entry while typing. Submission and onboarding mutations require
  recent authentication. Restart replaces answers with [] before submission.
- Submission atomically locks answers, creates a stable submission, a queued AIJobRecord
  and an empty protected evaluation envelope. Empty validated_scores/evidence and an
  absent interpretation mean no generated result. Manual custom questionnaires have
  no validated scoring implementation. Provider execution never runs in this transaction.
- Stable IDs use the same canonical JSON SHA-256 utility as WEB-1: submission ID
  `submission_${hash(attempt_id)}`, job `job_${hash(submission_id)}`, evaluation
  `evaluation_${hash(submission_id)}`. A future authorized worker must fill that
  envelope through the agreed lease/complete protocol and preserve original output.
  Worker endpoints/identity/leases are not implemented by this batch.
- `review_records` are create-only revisions with an internal decision field;
  `review_heads` stores the latest revision. Original evaluation/provider content is
  never changed by review. The existing ReviewRecordDTO serializer omits decision;
  the new decision endpoints expose {review, decision}. `review_status` is a read
  projection of the head. Approve/reject/feedback never unlock patient result access.
- The independent `/api/v1/me/access-events` stream emits only the frozen authorization
  hint; 2-second heartbeat, 250-second connection lifetime. It polls authority while
  connected. Closing a relationship increments account authorization revision and
  writes a protected invalidation outbox record. The stream does not require a worker.
  Client disconnect, heartbeat gap over 7 seconds, hidden/offline state, UID change or
  changed authorization generation clears protected memory and cancels requests.
  Reconnect fetches fresh capabilities and saved answers. Unsaved edits may be lost
  on security invalidation; no protected offline persistence is enabled. Production
  streaming/proxy timeout behavior remains a deployment prerequisite.
- Every patient response is allowlisted and recursively schema-validated. Submitted
  detail contains assignment + four-field acknowledgement only. Notifications and
  clinical Firestore subscriptions are not implemented; direct client access to all
  new namespaces remains denied. Patient-visible errors contain no provider text.

The full API is intentionally only partly implemented. `x-status` marks WEB-1/WEB-2
operations in this package; other operations remain proposed. Neither Mobile nor AI
source is modified and this package does not assert their integration sign-off.
