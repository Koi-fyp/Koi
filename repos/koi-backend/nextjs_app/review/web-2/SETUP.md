# WEB-2 reproduction and integration prerequisites

Continue on `feat/web-1-professional-publishing`. Existing WEB-1 files and reports
are the baseline; no commit, merge, reset, push or deployment is needed to run this.
Node 22, Java 21, Firebase CLI 15.34.0, Next 14.2.35 and local Chrome/Playwright were
used. No package or lockfile changes were made.

Use the WEB-1 emulator instructions in `../web-1/SETUP.md` unchanged: isolated
`demo-koi-platform-web1`, Firestore `127.0.0.1:5180`, Auth `127.0.0.1:5199`, Next
`127.0.0.1:3107`. The existing emulator-only deny-all rules stay unchanged. The actual
checked-in/live companion rules and deployment configuration stay untouched.

In a shell configured with the four server emulator variables from WEB-1:

```powershell
node scripts/web2-emulator-functional.cjs
```

The harness uses real emulated Auth and Firestore, real Next routes and Chrome.
It creates uniquely named fictional identities, runs the restricted clinician
verification CLI, and seeds fictional General registration records only inside the
guarded demo project. No production General registration bypass is provided.
Random test passwords remain in process memory. Screenshots may contain consumed,
fictional local invitation links; they are not production secrets.

Open `/professional`, inspect a published version, then select **Manage patients and
submissions**. Invite a General account or accept its application after the demo
step. Select individual patients or all active patients, and assign the inspected
version. A subsequent successful assignment action creates a repeat attempt.

Open `/patient` in a separate browser profile for the General account. Redeem the
fragment invitation after consent, or apply using the psychologist UID shared by
the practice. Complete the simulated demo step and await clinician acceptance.
Open an assignment, answer text/pictures, wait for autosave, resume after reload,
restart before submission, review the answers, then confirm final submission.
The final screen contains acknowledgement only.

The clinician refreshes submissions, inspects original answers and the protected
evaluation envelope, then appends approve/reject/feedback review revisions. No worker
is connected, so normal jobs remain queued. The harness separately injects explicitly
fictional interpretation/provider-failure fixtures to test protected display and
preservation. Runtime never generates substitute AI results or custom-form scores.

Checks:

```powershell
node scripts/validate-web05-contract.cjs
node scripts/validate-web2-contract.cjs
npm test -- --runInBand --silent
npm run build
```

No additional environment secret is required for this local slice. The existing
server-only cursor secret is domain-separated for invitation token reconstruction;
production key rotation/retention must be defined before enabling real invitations.
The platform remains disabled unless an explicit environment mode is selected.
`review/web-1/platform.env.example` lists configuration names without credentials.

Production dependencies remain unresolved:

| Dependency | Required evidence / action |
| --- | --- |
| Firebase/deployment binding | Prove the active web/backend project, published deny rules, service IAM, App Check policy and actual deployed configuration. An operator rules hash alone is not proof. |
| Indexes | Review `firestore.indexes.proposed.json`; deploy separately only after authorization. The emulator does not prove production composite-index availability. |
| General registration | Approved mail adapter and server-issued email-possession challenges. Existing custom-token guests and `emailVerified` do not bypass registration. |
| Patient policy | Approve consent wording and retention duration/legal basis, deletion/export procedure and expiration process. Current `care-consent-v1` is a local integration policy version. |
| Invitation logging | Redact token path segments at ingress/access logs. Fragment links avoid navigation referrers; the frozen redemption API still has the token in its path. |
| Access invalidation hosting | Verify authenticated streaming, no buffering/caching, token checks, connection limits and proxy timeouts. The stream locks content on interruption and is independent of companion SSE. |
| AI worker/scoring | Approve workload identity/internal ingress, implement leases/retries/completion and provider adapter; verify instrument wording/licensing/scoring before any validated score. Submission already works offline from AI. |
| Flutter | Source and cross-track acknowledgement are required for client parity and asset packaging. Missing Flutter source does not block this web implementation. |

The care UI keeps protected content in memory only. Its access monitor clears the
screen on changed authority, UID changes, hidden/offline state or missed heartbeat.
Reconnect resumes server-confirmed answers; unsaved edits cannot be guaranteed across
an authorization interruption. This is not an offline questionnaire client.

Deferred capabilities: expert directory/profile management, public account registration,
same-practice re-onboarding after closure, switching a dual clinician/General account's
application list scope, notifications, messages, appointments, AI worker/provider and
instrument registry/scorer. No patient result sharing or result visibility control exists.
