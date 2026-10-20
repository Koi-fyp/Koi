# Existing-project examiner setup and deployment

Run from `C:\Users\PMYLS\Koi\repos\koi-backend\nextjs_app`. Cloud target is **only `koi-companion-fyp`**. This preparation has not deployed anything or provisioned cloud accounts. Keep service-account files and private manifests outside tracked files, e.g. under ignored `.local/koi-web5/`.

## 1. Read-only evidence (no cloud data writes)

Use a private existing-project service account with appropriate Firebase Rules read, Auth configuration read and Firestore index read permissions. Do not paste keys into source or browser settings. The workspace currently has no such credential and no Firebase CLI login.

```powershell
node scripts/web5-cloud-audit.cjs C:\private\koi-service-account.json .local/koi-web5/live-before-demo
```

The fixed-target audit reads the published Firestore release/source, index list, Auth email-provider configuration and Firebase project metadata. It never invokes application/AI endpoints or writes Firebase records. `audit.json` explicitly lists failed/missing reads. A missing credential report already exists at `review/web-5/evidence/cloud-inspection/audit.json`.

Review `published.rules` and the actual deployed application environment separately. Do not proceed on an unavailable, truncated or mismatched inspection. Export the complete existing Firestore index/field-override configuration in Firebase CLI format before preparing any index deployment; the raw REST index response is not that format.

## 2. Verify the exact rules source locally

Local test emulators are verification tools only; they are not required for the final examiner demo and do not create a Firebase project. The isolated `demo-koi-web5-local` identifier is an offline emulator namespace, never a cloud project recommendation. WEB-4 processes on ports 3107/5180/5199 were left untouched.

The checked-in reference config uses Auth 5499, Firestore 5480, websocket 9450, hub 5440 and logging 5450. To test a captured live policy, copy `dev/web5-reference/firebase.json` into a new private test directory and set its `firestore.rules` path to that captured source. Use absolute paths or paths relative to the new config. Do not deploy this emulator configuration.

Before any tests, enable the offline guard (Node 22 / Java 21 / already installed Firebase CLI 15.34.0):

```powershell
$env:NODE_OPTIONS='--require=C:/Users/PMYLS/Koi/repos/koi-backend/nextjs_app/scripts/web5-network-guard.cjs'
$env:NEXT_TELEMETRY_DISABLED='1'
```

Run the locally installed/cached Firebase CLI; do not invoke package downloads under this guard. For the reference test:

```powershell
firebase emulators:start --only auth,firestore --project demo-koi-web5-local --config dev/web5-reference/firebase.json
```

In another guarded shell, with no Admin/Google credentials:

```powershell
$env:KOI_PLATFORM_FIREBASE_PROJECT_ID='demo-koi-web5-local'
$env:FIRESTORE_EMULATOR_HOST='127.0.0.1:5480'
$env:FIREBASE_AUTH_EMULATOR_HOST='127.0.0.1:5499'
node scripts/web5-rules-security.cjs CAPTURED_PUBLISHED_RULES_PATH NEW_RULES_TEST_REPORT_PATH
```

The report must pass all roots and preserve original companion ownership rules. Explicit denies do not override overlapping allows. Test failures require review; do not bypass them. Then assemble evidence from the real read-only snapshot and matching exact-source test:

```powershell
node scripts/web5-rules-evidence.cjs .local/koi-web5/live-before-demo/audit.json NEW_RULES_TEST_REPORT_PATH .local/koi-web5/verified-rules.json
```

Reference-policy test results cannot unlock cloud mode when the published hash differs. Evidence expires after 24 hours; refresh it on the demo day. This is a recent release attestation, not continuous monitoring of live rule changes.

## 3. Rules/index deployment, only if required and separately authorized

If published rules already deny all platform collections, preserve them and test them directly. No rules deployment is necessary.

If a patch is needed, first capture/retain the live policy and complete existing index configuration. Generate a NEW local output directory:

```powershell
node scripts/web5-artifacts.cjs CAPTURED_PUBLISHED_RULES_PATH .local/koi-web5/reviewed-patch EXISTING_COMPLETE_CLI_INDEXES_JSON
```

This preserves the original rule text and existing index/field-override entries. Review the diff, test the exact candidate policy and confirm every index is additive. `dev/web5-reference/` is only a checked-in reference, never a replacement for unknown live settings. If any CLI operation proposes deleting existing indexes, stop.

Only after explicit owner authorization, the reviewed candidate can be deployed from its directory:

```powershell
firebase deploy --only firestore:rules,firestore:indexes --project koi-companion-fyp --config .local/koi-web5/reviewed-patch/firebase.json
```

The generated config names only Firestore; it cannot redeploy Functions, hosting or Modal. Wait for required indexes to be READY. Re-run read-only inspection and exact published-source denial checks after an authorized deployment before assembling runtime evidence. No deployment command was executed in WEB-5.

## 4. Configure the local Next server for existing cloud Firebase

Use a clean shell; no emulator variables, demo credentials or offline guard. `NODE_OPTIONS` from isolated tests must not be inherited here: it intentionally blocks cloud Firebase networking. Keep the existing `.env.local` public Firebase values and all companion/provider configuration unchanged.

Set a persistent private cursor signing key (at least 32 characters, securely generated; save it in your approved private secret store). It also protects invitation tokens, so preserve it across restarts. Then:

```powershell
. .\scripts\web5-cloud-env.ps1 -ServiceAccountFile C:\private\koi-service-account.json -RulesEvidenceFile .local/koi-web5/verified-rules.json
npm run build
npm run start -- --hostname 127.0.0.1 --port 3107
```

Use a free port if another local server is running. Restart the process after public build-time variables change. These commands do not require Firebase emulators. Public variables are project/API web app configuration only; private Admin JSON, cursor key and evidence paths remain server-side.

Runtime environment names:

| Variable | Requirement |
| --- | --- |
| `KOI_PLATFORM_MODE` | `reviewed-production` |
| `KOI_PLATFORM_FIREBASE_PROJECT_ID`, `NEXT_PUBLIC_KOI_PLATFORM_FIREBASE_PROJECT_ID` | `koi-companion-fyp` |
| Existing `NEXT_PUBLIC_FIREBASE_*` | Existing project web app configuration; retained |
| `FIREBASE_ADMIN_SDK` | Private JSON credential for this project, loaded from private file by helper |
| `KOI_PLATFORM_CURSOR_SIGNING_KEY` | Persistent private random value; no emulator default |
| `KOI_PLATFORM_RULESET_SHA256` | Captured published-source hash matching passing exact-source tests |
| `KOI_PLATFORM_RULES_EVIDENCE_PATH` | Fresh private evidence file; renew within 24 hours |

Do not deploy provisioning-password or bootstrap allowlist variables to a publicly hosted application. Public hosting remains optional for a local examiner demonstration. Hosting/IAM/App Check/authorized-domain behavior still requires verification if choosing an actual deployment.

## 5. Fictional accounts — ONLY after explicit cloud-write authorization

Before authorizing any cloud seed or questionnaire submission, independently review existing deployment configuration to confirm that no paid worker/Firestore trigger consumes the new `ai_jobs` records. The Web source makes no provider calls, but an unknown external consumer could react to a queued job. No deployed consumer was inspected or changed in WEB-5. If this cannot be established without contacting out-of-scope AI infrastructure, keep cloud writes blocked; do not probe or disable a Modal service.

Choose a unique run ID. Preview without credentials or writes:

```powershell
node scripts/web5-provision.cjs --run-id examiner_2026
```

Proposed emails for that run (not yet created):

- `koi-exam-psychologist-examiner_2026@example.invalid`
- `koi-exam-general-examiner_2026@example.invalid`
- `koi-exam-patient-examiner_2026@example.invalid`

Use a private operator shell configured as above. Independently identify an existing non-disabled operator Firebase UID and explicitly allowlist the credential's service account:

```powershell
$env:KOI_PLATFORM_BOOTSTRAP_ADMIN_UID='EXISTING_AUTHORIZED_OPERATOR_UID'
$env:KOI_PLATFORM_BOOTSTRAP_SERVICE_ACCOUNT='EXACT_CREDENTIAL_SERVICE_ACCOUNT_EMAIL'
.\scripts\web5-provision.ps1 -RunId examiner_2026 -ManifestFile .local/koi-web5/examiner-2026-manifest.json
```

The wrapper requires typing the exact project and explicit write phrase and securely prompts for three 12–128 character passwords. No default password, temporary shared password or password log exists. The CLI independently enforces confirmation, project, private credential, rules evidence, enabled email/password provider and operator/service allowlist. It calls existing server verification and platform services; no emulator shortcut is accepted by the cloud entry point.

Existing UID/email collisions stop before adoption. The tool never calls `updateUser` to replace a password. Replaying a completed run performs no record writes. Interrupted runs preserve a durable manifest/record ledger and can resume with the same run ID, allowlisted operator and original passwords. If users have already changed the fixture's authority, preserve that state and investigate rather than reset it.

The output manifest contains exact created Auth UIDs, every seeded Firestore record path/hash, ledger paths and scoped rollback instructions; no passwords, bearer tokens or response content. Root metadata is `demo_provision_runs/{runId}`; per-record ownership is `demo_provision_records/{hash}`. To export a fresh read-only manifest after interruption, choose a NEW output:

```powershell
node scripts/web5-provision.cjs --manifest-only --run-id examiner_2026 --output .local/koi-web5/examiner-2026-manifest-later.json
```

## 6. Examiner routes and workflows

Open `http://127.0.0.1:3107/?home=1` → KOI menu → Account sign-in, or `/account`. Use separate browser profiles for psychologist and patient. Platform sign-in preserves the companion's independent identity and history; there is no anonymous migration.

Psychologist `/professional`: dashboard/profile, manual questionnaire editor/publish, Patients/invites/applications/assignments, submissions/manual reviews, human conversations/appointments, notifications and analytics. General `/patient?view=experts#experts`: discover and apply; its seeded application awaits review after simulated payment. Patient `/patient`: one open questionnaire and one submitted acknowledgement; answer/autosave/reload/resume/submit; messages, appointment responses and safe in-app notifications. Use existing [WEB-4 route inventory](../web-4/SCREEN-ROUTES.md).

All data is explicitly fictional; custom forms are not validated instruments. AI jobs stay queued; no provider/worker runs. Manual review works. Do not open or test paid companion/crisis/speech endpoints in WEB-5 verification. Existing companion UI/source is preserved but no live AI smoke test is authorized.

## 7. Rollback and cleanup

No automatic rollback/deletion command is provided or executed. Obtain separate authorization. Disable platform mode/revert only the newly introduced private platform environment to stop platform API access; preserve existing companion config. If rules were deployed, restore the exact captured prior live rules revision through a reviewed rollback, never the repository reference. Do not remove indexes used by other data.

For fictional data cleanup, use the exact manifest and its embedded plan. First close this run's relationship and suspend this run's psychologist through authoritative transitions; disable only its three Auth UIDs. Inventory later GUI-created records within that organization/UID scope (the seed ledger does not automatically track later GUI operations), compare hashes and stop on drift/outside references. Delete only reviewed exact paths, then ledger/manifest, then owned fictional Auth UIDs. Never bulk-delete a collection or remove an existing operator/real user, `users/`, chats, storage, mood/progress/tasks or unrelated data.
