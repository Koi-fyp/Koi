# Ahmad: start here — KOI WEB-1 to WEB-5

The Web implementation is in `repos/koi-backend/nextjs_app` (`WEB`). Take ownership from branch **`handoff/koi-web-1-to-5-2026-10-20`** in **`Koi-fyp/Koi`**. WEB-1/2 checkpoint and all later Web source/contracts/tests/scripts/reports are preserved. Read the adjacent `KOI_WEB_1_TO_5_AHMAD_HANDOFF.md` for source-verified schemas and the blocking AI mismatch matrix.

**Shipping transfer only:** no rebuild/regression rerun/deployment/activation happened for this handoff. No live Firebase writes or paid AI/Modal calls are authorized. Do not ping health endpoints, start workers, warm services or run live companion/crisis/voice tests.

## 1. Take the branch safely

From the existing repository (keep teammate work in its branch/worktree):

```powershell
git fetch origin handoff/koi-web-1-to-5-2026-10-20
git switch --track origin/handoff/koi-web-1-to-5-2026-10-20
Set-Location repos/koi-backend/nextjs_app
```

If that branch already exists locally, switch to it instead of recreating it. If your worktree is dirty, use a separate clean worktree/checkout rather than reset/stash/overwrite someone else's work. No force-push or merge into main/master is part of the transfer.

Ahmad's AI docs are on **`Koi-fyp/KOI-Psycholov` `master` at `59e90ddba505ea07adbf7f92121ffc3eac0d89db`**. The default `main` ref (`52728363231731fe3f7477167ea176bc3068b571`) does not contain the five requested AI handoff files. Pin the correct ref. Do not transplant this Web tree into that AI repo.

## 2. First priority: existing Firebase and manual demo

Use **only `koi-companion-fyp`**. The public Web config already targets it. Private credentials and authenticated live evidence are missing; cloud demo identities have not been created. Existing production Auth users/chats/data must survive.

Follow `WEB/review/web-5/DEMO-DEPLOYMENT.md` in order:

1. Obtain a private existing-project Admin credential locally. Inspect live rules/source/index/Auth provider/project with the read-only audit tool. Inspect deployed backend/IAM/authorized-domain/App Check state. Never commit credentials.
2. Verify the exact published rules in isolated local tests and assemble matching fresh evidence. A reference policy or arbitrary hash is insufficient. Preserve current rules if already safe; any required additive deployment needs explicit owner approval. Keep unrelated rules/indexes.
3. Establish from configuration that no paid consumer processes new pending jobs. If unproven, keep cloud seed/submission blocked; do not probe or alter AI infrastructure to find out.
4. Configure `reviewed-production` using the private helper/required evidence/cursor key. The final examiner can use a local production Next server with this existing cloud Firebase project; no emulator or new cloud project is needed for the final demo.
5. Obtain explicit owner authorization for cloud writes. Use the restricted operator workflow with exact project confirmation, existing operator/service allowlist, secure per-role passwords and a unique run ID. Review/store its private exact-path manifest. Never reuse or overwrite real accounts.
6. Run the manual UI checklist below. Keep AI disconnected. The empty protected envelope/queued job and a manual review are truthful working states.

The proposed `examiner_2026` emails are `koi-exam-psychologist-examiner_2026@example.invalid`, `koi-exam-general-examiner_2026@example.invalid`, `koi-exam-patient-examiner_2026@example.invalid`. They are **planned, not cloud-provisioned**, and have no default passwords.

## 3. Complete working UI demo checklist

Use separate browser profiles for psychologist, General user and patient. Base URL is the chosen local Next origin (documented example `http://127.0.0.1:3107`). Care login is `/account`; companion identity/history stays separate. Do not send live companion/crisis/voice requests as part of this checklist.

- [ ] Landing `/?home=1` shows the original Neo UI and KOI account menu. Anonymous navigation exposes no expert directory or care/clinical workspace; direct unauthorized routes deny access.
- [ ] Sign in through `/account` as the verified fictional psychologist; menu shows Professional Dashboard/Questionnaires/Patients/Submissions/Analytics from server capabilities.
- [ ] Open `/professional`; inspect the fictional organization/profile. Verification is seeded server-side, never self-approved in the UI.
- [ ] Create a manual questionnaire, include text plus a bundled picture option, optionally add Urdu RTL, save and reload the draft.
- [ ] Publish saved revision, open the immutable version/bookmark, edit the draft and verify the old published version is unchanged.
- [ ] General user opens `/patient?view=experts#experts`, finds the accepting verified professional, inspects profile and application state. Simulated payment collects no card data and alone grants no patient rights.
- [ ] Psychologist accepts the pending fictional application, or issues an expiring identity-bound invitation for the General account to redeem after consent. Confirm authoritative active relationship/roster change.
- [ ] Assign one published version to one/selected/all active patients. Confirm independent assignments and repeat-assignment support.
- [ ] Patient signs in separately; care menu shows My Psychologist/Questionnaires/Messages/Appointments/Notifications, never clinical evaluation pages.
- [ ] Open `/patient?view=questionnaires#questionnaires`; answer text and picture items, wait for save, reload and resume confirmed answers.
- [ ] Restart before submission if demonstrating it, re-answer, review answers, confirm final submission. Expect acknowledgement only, with no score/interpretation/review/job progress.
- [ ] Repeated submit/reload yields the same acknowledgement and locked answers. Use existing security evidence for race cases unless a new scoped recheck is justified.
- [ ] Psychologist opens submissions, raw answers and protected review workspace. AI remains pending; no fabricated score or interpretation. Append manual approve/reject/feedback and inspect separate review history.
- [ ] Send a human thread message; patient refreshes/reads/replies; verify timestamps and loaded unread indicators. This is separate from companion chat.
- [ ] Patient requests appointment; psychologist proposes time; patient confirms. Demonstrate cancellation if desired. Reschedule means cancel/new request; no double-booking guarantee.
- [ ] Refresh in-app notices; mark loaded notices read. No sensitive evaluation payload or external push appears.
- [ ] Open professional Analytics and individual history; confirm actual fictional assignment/submission counts and version-specific date filters. No invented improvement metric; empty states work.
- [ ] Patient/General direct professional evaluation/submission/review/analytics requests deny access; cross-patient/practice IDs do not disclose records. Do not use an AI endpoint to test this.
- [ ] Close a disposable fictional relationship; open patient content locks and subsequent protected reads/writes fail. General account/companion identity is not deleted. Preserve a separate active fixture for the main demo.
- [ ] Logout/login as another account clears old care data/menu; mobile layout and Urdu RTL remain usable.
- [ ] Original companion/SSE/avatar/crisis compatibility is supported by preserved source and existing offline/mock evidence. Live inference/health/voice checks remain skipped under the zero-credit rule.

Full route inventory: `WEB/review/web-4/SCREEN-ROUTES.md`. Most runner/review/patient-detail selections live inside their workspace rather than separate URLs.

## 4. Optional AI integration — later, after contracts and budget approval

Do not start the API/worker or hit `/health`. First reconcile the adjacent technical matrix. The most urgent collision is `ai_jobs`: Web atomically creates a nested protected job under a hashed job ID; AI master documents a flat job under submission ID created by its start route. Role/member/relationship/version/answer/consent/result/review paths also differ. Web 0.5.2 and AI draft 0.4 are independent contracts, not a completed integration.

Keep the manual slice working while defining one authoritative enqueue/claim/completion path, explicit AI consent, server-only adapter, result/review projections, versioned fixtures, provider budget and revocation/retention controls. Do not allow direct patient AI calls or weaken Web's backend-only clinical policy to apply an AI listener sketch. AI's report still documents an emulator-only Firestore refusal and recommends another project; the current owner's existing-project-only decision overrides that recommendation.

## 5. Flutter parity and release

Locate the actual Flutter source/owner and agree capabilities, relationship schema, immutable version/asset mapping, answer revisions, acknowledgement, messages/appointments/notices and cache clearing. No Flutter parity is claimed. Do not silently change the frozen Web contracts; publish an acknowledged version if reconciliation needs changes.

Latest credible Web checkpoint: **86 suites / 688 tests**, TypeScript/build passed, 740 direct platform rule denials + 80 original ownership assertions, six real local backend scenario groups. Reports are in `WEB/review/web-5/`; older UI/browser/persistence evidence is in WEB-1–4. No unnecessary reruns were done for transfer.

Release only after actual cloud configuration/evidence, manual GUI checklist, access isolation/revocation, optional AI budgets/contracts, localization/accessibility, retention/consent, proxy/logging behavior and rollback have owner sign-off. No deployment, live-data migration, account deletion or new Firebase project is authorized by this handoff.

## 6. Rollback / included and excluded files

Use WEB-5's private run/record ledger and exact manifest after authorized provisioning. It covers seed-created records, not all later GUI actions: inventory later scoped changes and stop on hash drift/outside references. Cleanup requires separate authorization; never bulk-delete or remove original users/chats/storage. For configuration rollback, disable only the platform and preserve the companion; restore captured live rules only if a separately authorized patch had been deployed.

Included: Web source and its existing WEB-1/2 ancestry, frozen contracts, bundled assets, tests, safe scripts, rules/index proposals, setup guides, reports and sanitized test evidence. Excluded/preserved locally: actual `.env`/service-account/API credentials, `.local` content, Auth exports/emulator snapshots/private manifests, generated caches/logs and unrelated `.idea`/mobile Android work. Staged files were scanned before the handoff commit. Read `SHIPMENT-MANIFEST.json` and `SECRET-SCAN.json` alongside this guide for the exact packaging record.
