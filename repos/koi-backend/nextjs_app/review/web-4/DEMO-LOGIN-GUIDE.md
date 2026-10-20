# Persistent fictional KOI demo

Run from `C:\Users\PMYLS\Koi\repos\koi-backend\nextjs_app`. Requirements: Node 22, Java 21, Firebase CLI 15.34.0 through npx, and installed dependencies. Chrome is needed only for automated browser verification.

## Accounts

| Account | Email | Initial authority |
| --- | --- | --- |
| Verified psychologist | `psychologist@koi-demo.example` | Restricted CLI verification, active organization owner |
| General User | `general@koi-demo.example` | Registered General account, application awaiting psychologist review; no patient rights until accepted |
| Active Patient | `patient@koi-demo.example` | Registered account plus server-owned active relationship |

There is no published/default password. Set your own password using the prompt below. The seeder reads `KOI_DEMO_PASSWORD`, or separate `KOI_DEMO_PSYCHOLOGIST_PASSWORD`, `KOI_DEMO_GENERAL_PASSWORD` and `KOI_DEMO_PATIENT_PASSWORD` overrides (12–128 characters). It never prints passwords. Re-running with new password values updates only these deterministic fictional Auth identities, preserving domain records and operator edits. Browser automated tests may assign ephemeral passwords; rerun the seeder with your chosen values before your own demonstration.

The restricted operator `koi_demo_web4_operator` has no public email/password and is not a fourth application role. It exists only for audited local verification.

## Exact startup

Terminal 1, clean PowerShell:

```powershell
Set-Location C:\Users\PMYLS\Koi\repos\koi-backend\nextjs_app
.\scripts\start-demo-emulators.ps1
```

This uses the unchanged deny-all emulator rules and exact demo project. It imports `.local/koi-demo/export` if present and exports there on graceful Ctrl+C. Exports contain Auth password hashes: the directory is ignored by Git; do not publish or share it.

Terminal 2:

```powershell
Set-Location C:\Users\PMYLS\Koi\repos\koi-backend\nextjs_app
. .\scripts\demo-env.ps1
npm run dev -- --hostname 127.0.0.1 --port 3107
```

Terminal 3, after both services are ready:

```powershell
Set-Location C:\Users\PMYLS\Koi\repos\koi-backend\nextjs_app
. .\scripts\demo-env.ps1
$demoPassword = Read-Host 'Choose a fictional demo password (12–128 characters)' -AsSecureString
$env:KOI_DEMO_PASSWORD = [System.Net.NetworkCredential]::new('', $demoPassword).Password
node scripts/seed-koi-demo.cjs
Remove-Item Env:\KOI_DEMO_PASSWORD
$demoPassword.Dispose()
```

The command prints fictional IDs/emails, never credentials or invitation tokens. No `.env.local` is edited. The helper refuses conflicting platform configuration/credential environment values. The seeder additionally checks exact hosts and project before loading Admin SDK or writing anything.

Open **http://127.0.0.1:3107/?home=1** → **KOI menu** → **Account sign-in**. Direct login: **http://127.0.0.1:3107/account**. Use separate browser profiles or separate private windows for psychologist and patient. Tabs in the same browser profile share the platform account.

The original companion uses its own anonymous Firebase identity, even when a care account is signed in. The helper explicitly connects that original identity to local Auth/Firestore in development and enables the existing local anonymous test path. No linking, local-history migration, cross-account merge or clinician access to companion content is implemented. Companion model/SSE replies still depend on the existing backend; this demo does not substitute a model or fabricate replies.

## Repeatable manual walkthrough

1. Sign in as the psychologist. Open **Professional Dashboard**. The practice and profile are clearly labelled fictional.
2. Open **Professional Questionnaires**. Create a manual form, save, publish and inspect its immutable version. The seeded text/picture form is also available.
3. Open **Patients**. Accept the General User's pending application, or create an invitation for an existing registered account. Demo payment completion is already recorded for the seeded application; it granted no patient rights.
4. Select an active patient or all active patients; assign the published version. Repeated assignments create separate attempts.
5. In another browser profile, sign in as the Patient. Open **Questionnaires**. The seed leaves one open questionnaire and one acknowledgement ready to inspect.
6. Open the assignment, answer, wait for **All answers saved**, reload, reopen and verify the answers persist. Review before submitting and confirm. Only acknowledgement appears.
7. Return to the psychologist, refresh submissions, inspect raw answers and manually review. The seeded review is explicitly fictional. AI jobs stay queued, custom scores absent.
8. Open a patient conversation and send a human message. The patient refreshes the conversation, reads and replies.
9. The patient requests an appointment; the psychologist proposes times; the patient refreshes and confirms. Cancellation followed by a new request is the current rescheduling flow.
10. Refresh notifications and mark loaded notices read. Open Analytics for actual fictional assignment/submission counts grouped by exact version, with UTC date filters.
11. Try `/professional` while logged in as the Patient: practice access is denied. The automated evidence also exercises direct evaluation/workspace/analytics HTTP requests and expects 403.

Care/professional headers contain the same capability-driven menu. Navigation is advisory and refreshes authority; all protected APIs independently reauthorize. Patient content retains its existing access-change monitor.

## Persistence and safe reset

Normally stop emulators with Ctrl+C and wait for export completion. Restart using the same Terminal 1 command; Auth identities, password hashes, professional records and submissions are imported together. Start Next with the same helper. Browser Auth persistence is separate from server export: after an import or account change, sign out/in if needed.

For an explicit checkpoint while emulators run:

```powershell
. .\scripts\demo-env.ps1
node scripts/koi-demo-preflight.cjs
npx --yes --package firebase-tools@15.34.0 firebase emulators:export .local/koi-demo/manual-checkpoint --project demo-koi-platform-web1 --config dev/platform-emulator/firebase.json
```

Use a new destination for each checkpoint. Do not use `--force` to overwrite a snapshot you want to keep.

For a disposable clean demonstration, first stop the running emulator pair, then:

```powershell
.\scripts\start-demo-emulators.ps1 -Fresh
```

This starts empty emulators without importing **or overwriting** the saved snapshot. Run the seeder again. No files or live records are deleted. After stopping the disposable run, the ordinary startup command restores your earlier snapshot. Never run two emulator pairs on the same ports.

Seeding preserves existing domain work: it does not reopen closed relationships, replace submitted answers, overwrite published versions, erase reviews or restore rejected applications. Use the disposable fresh mode when you need the original scenario again.

## Verification

With emulators and Next running and the helper loaded:

```powershell
node scripts/web4-demo-functional.cjs
node scripts/web4-regression-functional.cjs 1
node scripts/web4-regression-functional.cjs 2
node scripts/web4-regression-functional.cjs 3
```

These are real local Auth/Firestore/Next/Chrome journeys. The main WEB-4 harness checks deterministic seeding, navigation and the manual workflow. Earlier harness evidence goes into WEB-4 subfolders without overwriting prior reports. WEB-2's historical fixture receives the now-required discoverable profile through the real owner endpoint. Old harnesses contain explicitly labelled AI-failure test fixtures; they do not contact a provider.

Public registration/mail delivery, clinical instrument scoring, the AI worker/provider, Flutter integration and production deployment validation remain separate dependencies. Payments are simulated; notifications are in-app/request-driven; no push, calendar integration or double-booking guarantee is claimed.
