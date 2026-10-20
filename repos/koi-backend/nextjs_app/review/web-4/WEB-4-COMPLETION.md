# WEB-4 completion — local fictional demo

Branch: `feat/web-1-professional-publishing`. Baseline HEAD: `f2b9c80`. Existing WEB-1/2/3 and unrelated work were preserved. No commit, push, merge, reset, deployment, production account change or rules deployment was performed.

## Implemented

- Three deterministic email/password Auth emulator identities, operator-configured passwords, restricted CLI psychologist verification, server-owned General registration fixtures and a fictional organization.
- Idempotent fixture creation through real platform routes: published text/picture questionnaire, active patient relationship, one open assignment, one submitted assignment, protected manual review and a General application awaiting review after simulated payment.
- Exact demo project/loopback host checks and credential refusal before seeder SDK initialization. No production fallback, password logs, reusable invitation passwords or real financial processing.
- Auth/Firestore export/import startup and a non-deleting fresh mode. Existing saved data is imported rather than reseeded on startup. The seeder preserves domain edits and fails on incompatible authoritative identity state.
- `/account` and capability-driven Neo navigation on the landing page, companion header and care/professional workspaces. Server capabilities and active relationships determine links; backend checks remain authoritative. General users cannot use clinical deep links.
- Existing workspace section links, shared spinners, responsive account screen and reduced-motion-safe menu interactions. The companion header uses a compact mobile menu so its existing mode selector remains visible.
- Explicit development-only companion Auth/Firestore emulator configuration. The original custom-token flow remains the default; SSE, crisis handling, avatar renderer and provider selection are unchanged. Companion identity remains separate from the signed-in care account. No anonymous account migration was implemented.

## Launch and explore

See [DEMO-LOGIN-GUIDE.md](DEMO-LOGIN-GUIDE.md) for exact PowerShell commands, secure password setup, export/import and reset instructions. [SCREEN-ROUTES.md](SCREEN-ROUTES.md) lists every GUI route.

| Identity | Fictional local email |
| --- | --- |
| Verified psychologist | `psychologist@koi-demo.example` |
| General User | `general@koi-demo.example` |
| Active Patient | `patient@koi-demo.example` |

No default password is supplied. Set `KOI_DEMO_PASSWORD` or the three role-specific password variables through the guide's secure prompt, then invoke `node scripts/seed-koi-demo.cjs`. Automated browser verification uses ephemeral passwords; rerun the seeder with your chosen values before manual login. This does not reset existing questionnaire work.

Main GUI: `http://127.0.0.1:3107/?home=1`; account login: `/account`; professional workspace: `/professional`; patient/discovery workspace: `/patient`. Use separate browser profiles for simultaneous psychologist and patient sessions.

## Demonstrated

Real Auth/Firestore emulators, real Next routes and Chrome exercised sign-in through the homepage, role-specific menus and denied deep links; manual create/save/publish/assign; patient autosave/reload/resume/submit; acknowledgement without evaluation fields; protected submissions/manual review; human messaging; appointment proposal/response; notifications; actual fictional-data analytics; session reload/logout and mobile layout.

The seed uses real invitation redemption and demo-payment/application transitions. Earlier WEB-2/3 regression harnesses cover application acceptance, relationship revocation, isolation and submission races. Patient direct evaluation, submission-workspace and analytics HTTP requests return 403.

An actual emulator export, stop, restart and import preserved the three Auth password-hash fingerprints, fixture references and ten domain collection counts. The snapshot is ignored under `.local/koi-demo/export/`. It contains fictional data and Auth hashes and must not be shared.

Original anonymous emulator sign-in, onboarding, companion/avatar selection and local-save continuation also work. The deny-all demo rules intentionally reject companion profile cloud sync; the existing UI offers continuation with the locally saved companion. No rule was weakened to make that write succeed.

## Validation and limitations

The full Jest checkpoint passed **83 suites / 678 tests**. The last authentication addition passed **11 targeted tests**, including one new test; navigation changes received targeted checks. WEB-1/2/3 real-emulator/browser batches passed **18 / 15 / 16 checks**. WEB-4 has seven passing browser check groups, actual persistence evidence and a companion/mobile smoke check. TypeScript and optimized production builds passed. See [TEST-EVIDENCE.md](TEST-EVIDENCE.md) for exact commands, evidence and final-state validation.

Contracts remain at **0.5.2**, with earlier frozen versions untouched. No API/DTO schema change, new patient result route or client-writable authorization authority was introduced. General fixture registration is an explicit emulator-only server seed, not a production registration mechanism.

Remaining dependencies:

- Public account registration, production project/rules/credentials/deployment verification and cross-track sign-off remain outside this local demo.
- AI jobs are queued; no AI worker/provider output is invented. Custom questionnaires have no fabricated validated score or interpretation. The seeded clinician review is explicitly fictional and manual.
- Flutter source/integration is still unavailable for parity verification.
- Payments are simulated, notifications are in-app/request-driven, and appointments have no external calendar or double-booking guarantee.
- Live companion replies/voice/provider output were not exercised; existing transport/avatar regression tests passed. Companion cloud profile sync remains denied by the intentionally restrictive demo rules.

Exact WEB-4 changes are listed in [CHANGED-FILES.md](CHANGED-FILES.md), separately from pre-existing WEB-3 changes.
