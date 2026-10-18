# KOI Web WIP staging manifest - approval required

**NOT STAGED. No handoff branch, commit or push has been created.**

Current `feat/web-product-data` / `b384ce2cef44e83e53db7f50182f3ccfaac32187`, dirty work preserved.
Destination after explicit approval: `handoff/web-product-data-2026-10-18` only. No main/Ahmad merge or push.

## Exact proposed files: 100 (24 modified tracked, 76 new)

The list is authoritative for proposed staging operations. Inherited committed files already exist in branch ancestry and are not re-added just to manufacture a diff. SHA-256 pins are in the companion JSON; manifest self-files intentionally have no circular self-hash. No actual index mutation has occurred. The plain text path list is for exact selective staging after approval, not `git add .`.

| # | Exact path | State | Purpose |
|---|---|---|---|
| 1 | `KOI_FIREBASE_PREFERENCE_SYNC_AUDIT_2026-10-18.md` | NEW FILE | handoff/report/function inventory |
| 2 | `KOI_WEB_BASELINE_AND_FILE_OWNERSHIP.md` | TRACKED MODIFIED | handoff/report/function inventory |
| 3 | `KOI_WEB_FINAL_CONFLICT_REPORT_2026-10-18.md` | NEW FILE | handoff/report/function inventory |
| 4 | `KOI_WEB_FINAL_FILE_FUNCTION_INVENTORY_2026-10-18.json` | NEW FILE | handoff/report/function inventory |
| 5 | `KOI_WEB_FINAL_HANDOFF_2026-10-18.md` | NEW FILE | handoff/report/function inventory |
| 6 | `KOI_WEB_IMPLEMENTATION_ACCEPTANCE.md` | TRACKED MODIFIED | handoff/report/function inventory |
| 7 | `KOI_WEB_PRODUCT_ADRS.md` | TRACKED MODIFIED | handoff/report/function inventory |
| 8 | `KOI_WEB_TO_AHMAD_HANDOFF.md` | TRACKED MODIFIED | handoff/report/function inventory |
| 9 | `KOI_WEB_WIP_STAGING_MANIFEST_2026-10-18.json` | NEW FILE | manifest self-file; final contents require review |
| 10 | `KOI_WEB_WIP_STAGING_MANIFEST_2026-10-18.md` | NEW FILE | manifest self-file; final contents require review |
| 11 | `KOI_WEB_WIP_STAGING_PATHS_2026-10-18.txt` | NEW FILE | manifest self-file; final contents require review |
| 12 | `repos/koi-backend/nextjs_app/jest.setup.ts` | TRACKED MODIFIED | test/verification source |
| 13 | `repos/koi-backend/nextjs_app/review/firebase-preferences.rules.cjs` | NEW FILE | unapplied shared-interface/migration/security proposal |
| 14 | `repos/koi-backend/nextjs_app/review/firestore.user-preferences.proposed.rules` | NEW FILE | unapplied shared-interface/migration/security proposal |
| 15 | `repos/koi-backend/nextjs_app/review/handoff-evidence/README.md` | NEW FILE | browser evidence source/summary (review copy, no runtime data) |
| 16 | `repos/koi-backend/nextjs_app/review/handoff-evidence/browser-evidence-summary.json` | NEW FILE | browser evidence source/summary (review copy, no runtime data) |
| 17 | `repos/koi-backend/nextjs_app/review/handoff-evidence/browser-harness-provenance.json` | NEW FILE | browser evidence source/summary (review copy, no runtime data) |
| 18 | `repos/koi-backend/nextjs_app/review/handoff-evidence/browser-harness/firebase-preferences/browser.cjs` | NEW FILE | browser evidence source/summary (review copy, no runtime data) |
| 19 | `repos/koi-backend/nextjs_app/review/handoff-evidence/browser-harness/history-export/browser.cjs` | NEW FILE | browser evidence source/summary (review copy, no runtime data) |
| 20 | `repos/koi-backend/nextjs_app/review/handoff-evidence/browser-harness/increment03/browser.cjs` | NEW FILE | browser evidence source/summary (review copy, no runtime data) |
| 21 | `repos/koi-backend/nextjs_app/review/handoff-evidence/browser-harness/increment03/final-review.cjs` | NEW FILE | browser evidence source/summary (review copy, no runtime data) |
| 22 | `repos/koi-backend/nextjs_app/review/handoff-evidence/browser-harness/increment04-breathing-fixture/browser.cjs` | NEW FILE | browser evidence source/summary (review copy, no runtime data) |
| 23 | `repos/koi-backend/nextjs_app/review/handoff-evidence/browser-harness/increment04-final-smoke/browser.cjs` | NEW FILE | browser evidence source/summary (review copy, no runtime data) |
| 24 | `repos/koi-backend/nextjs_app/review/handoff-evidence/browser-harness/increment04-followup/browser.cjs` | NEW FILE | browser evidence source/summary (review copy, no runtime data) |
| 25 | `repos/koi-backend/nextjs_app/review/handoff-evidence/browser-harness/increment04/browser.cjs` | NEW FILE | browser evidence source/summary (review copy, no runtime data) |
| 26 | `repos/koi-backend/nextjs_app/review/handoff-evidence/browser-harness/pre-defense/browser-check.cjs` | NEW FILE | browser evidence source/summary (review copy, no runtime data) |
| 27 | `repos/koi-backend/nextjs_app/review/handoff-evidence/browser-harness/pre-defense/browser-controls.cjs` | NEW FILE | browser evidence source/summary (review copy, no runtime data) |
| 28 | `repos/koi-backend/nextjs_app/review/handoff-evidence/browser-harness/pre-defense/browser-final.cjs` | NEW FILE | browser evidence source/summary (review copy, no runtime data) |
| 29 | `repos/koi-backend/nextjs_app/review/handoff-evidence/browser-harness/pre-defense/browser-followup.cjs` | NEW FILE | browser evidence source/summary (review copy, no runtime data) |
| 30 | `repos/koi-backend/nextjs_app/review/handoff-evidence/browser-harness/preference-sync-live-final/browser.cjs` | NEW FILE | browser evidence source/summary (review copy, no runtime data) |
| 31 | `repos/koi-backend/nextjs_app/review/handoff-evidence/browser-harness/preference-sync-live/browser.cjs` | NEW FILE | browser evidence source/summary (review copy, no runtime data) |
| 32 | `repos/koi-backend/nextjs_app/review/handoff-evidence/browser-harness/product-accessibility/browser.cjs` | NEW FILE | browser evidence source/summary (review copy, no runtime data) |
| 33 | `repos/koi-backend/nextjs_app/review/handoff-evidence/browser-harness/product-history/browser.cjs` | NEW FILE | browser evidence source/summary (review copy, no runtime data) |
| 34 | `repos/koi-backend/nextjs_app/review/handoff-evidence/browser-harness/product-portability/browser.cjs` | NEW FILE | browser evidence source/summary (review copy, no runtime data) |
| 35 | `repos/koi-backend/nextjs_app/review/handoff-evidence/browser-harness/ux-decisions/browser-no-request.cjs` | NEW FILE | browser evidence source/summary (review copy, no runtime data) |
| 36 | `repos/koi-backend/nextjs_app/review/handoff-evidence/browser-harness/ux-decisions/browser.cjs` | NEW FILE | browser evidence source/summary (review copy, no runtime data) |
| 37 | `repos/koi-backend/nextjs_app/review/handoff-evidence/browser-harness/w1-final/browser.cjs` | NEW FILE | browser evidence source/summary (review copy, no runtime data) |
| 38 | `repos/koi-backend/nextjs_app/review/handoff-evidence/browser-harness/w1-final/final-public-browser.cjs` | NEW FILE | browser evidence source/summary (review copy, no runtime data) |
| 39 | `repos/koi-backend/nextjs_app/review/handoff-evidence/browser-harness/w1-final/fix-browser.cjs` | NEW FILE | browser evidence source/summary (review copy, no runtime data) |
| 40 | `repos/koi-backend/nextjs_app/review/handoff-evidence/current-verification.json` | NEW FILE | browser evidence source/summary (review copy, no runtime data) |
| 41 | `repos/koi-backend/nextjs_app/review/handoff-evidence/security-scan-summary.json` | NEW FILE | browser evidence source/summary (review copy, no runtime data) |
| 42 | `repos/koi-backend/nextjs_app/review/increment04-db-migration.diff` | NEW FILE | unapplied shared-interface/migration/security proposal |
| 43 | `repos/koi-backend/nextjs_app/review/increment04-exercise-callback.diff` | NEW FILE | unapplied shared-interface/migration/security proposal |
| 44 | `repos/koi-backend/nextjs_app/review/new-chat-approval.md` | NEW FILE | unapplied shared-interface/migration/security proposal |
| 45 | `repos/koi-backend/nextjs_app/review/new-chat-consumers.proposed.diff` | NEW FILE | unapplied shared-interface/migration/security proposal |
| 46 | `repos/koi-backend/nextjs_app/review/new-chat-review.md` | NEW FILE | unapplied shared-interface/migration/security proposal |
| 47 | `repos/koi-backend/nextjs_app/review/new-chat-session.proposed.diff` | NEW FILE | unapplied shared-interface/migration/security proposal |
| 48 | `repos/koi-backend/nextjs_app/review/new-chat-source-baseline.json` | NEW FILE | unapplied shared-interface/migration/security proposal |
| 49 | `repos/koi-backend/nextjs_app/review/new-chat-tests.proposed.diff` | NEW FILE | unapplied shared-interface/migration/security proposal |
| 50 | `repos/koi-backend/nextjs_app/review/validate-new-chat-proposal.cjs` | NEW FILE | unapplied shared-interface/migration/security proposal |
| 51 | `repos/koi-backend/nextjs_app/src/__tests__/account-preference-sync-proposal.test.ts` | NEW FILE | test/verification source |
| 52 | `repos/koi-backend/nextjs_app/src/__tests__/activity-ledger.test.ts` | NEW FILE | test/verification source |
| 53 | `repos/koi-backend/nextjs_app/src/__tests__/backup-errors.test.ts` | NEW FILE | test/verification source |
| 54 | `repos/koi-backend/nextjs_app/src/__tests__/breathing-activity.test.tsx` | NEW FILE | test/verification source |
| 55 | `repos/koi-backend/nextjs_app/src/__tests__/checkin-form.test.tsx` | NEW FILE | test/verification source |
| 56 | `repos/koi-backend/nextjs_app/src/__tests__/checkin-service.test.ts` | NEW FILE | test/verification source |
| 57 | `repos/koi-backend/nextjs_app/src/__tests__/ciphertext-export-ui.test.tsx` | NEW FILE | test/verification source |
| 58 | `repos/koi-backend/nextjs_app/src/__tests__/ciphertext-export.test.ts` | NEW FILE | test/verification source |
| 59 | `repos/koi-backend/nextjs_app/src/__tests__/conversation-completion-evidence.test.ts` | NEW FILE | test/verification source |
| 60 | `repos/koi-backend/nextjs_app/src/__tests__/conversation-product-controls.test.tsx` | NEW FILE | test/verification source |
| 61 | `repos/koi-backend/nextjs_app/src/__tests__/history-page.test.tsx` | TRACKED MODIFIED | test/verification source |
| 62 | `repos/koi-backend/nextjs_app/src/__tests__/preference-sync-failure.test.ts` | NEW FILE | test/verification source |
| 63 | `repos/koi-backend/nextjs_app/src/__tests__/preference-sync-integration.test.ts` | NEW FILE | test/verification source |
| 64 | `repos/koi-backend/nextjs_app/src/__tests__/progress.test.tsx` | TRACKED MODIFIED | test/verification source |
| 65 | `repos/koi-backend/nextjs_app/src/__tests__/recorded-board.test.tsx` | TRACKED MODIFIED | test/verification source |
| 66 | `repos/koi-backend/nextjs_app/src/__tests__/reward-preview.test.ts` | NEW FILE | test/verification source |
| 67 | `repos/koi-backend/nextjs_app/src/__tests__/session-transition.test.ts` | NEW FILE | test/verification source |
| 68 | `repos/koi-backend/nextjs_app/src/__tests__/web-honesty.test.tsx` | TRACKED MODIFIED | test/verification source |
| 69 | `repos/koi-backend/nextjs_app/src/app/(authenticated)/chat/page.tsx` | TRACKED MODIFIED | implemented Web source changes |
| 70 | `repos/koi-backend/nextjs_app/src/app/(authenticated)/companion-scene/page.tsx` | TRACKED MODIFIED | implemented Web source changes |
| 71 | `repos/koi-backend/nextjs_app/src/app/(authenticated)/history/page.tsx` | TRACKED MODIFIED | implemented Web source changes |
| 72 | `repos/koi-backend/nextjs_app/src/app/(authenticated)/progress/page.tsx` | TRACKED MODIFIED | implemented Web source changes |
| 73 | `repos/koi-backend/nextjs_app/src/app/(authenticated)/settings/export/page.tsx` | TRACKED MODIFIED | implemented Web source changes |
| 74 | `repos/koi-backend/nextjs_app/src/app/(authenticated)/settings/import/page.tsx` | TRACKED MODIFIED | implemented Web source changes |
| 75 | `repos/koi-backend/nextjs_app/src/app/(authenticated)/settings/page.tsx` | TRACKED MODIFIED | implemented Web source changes |
| 76 | `repos/koi-backend/nextjs_app/src/components/chat/AccountPreferenceStatus.tsx` | NEW FILE | implemented Web source changes |
| 77 | `repos/koi-backend/nextjs_app/src/components/chat/ConversationProductControls.tsx` | NEW FILE | implemented Web source changes |
| 78 | `repos/koi-backend/nextjs_app/src/components/companion/ExerciseDirector.tsx` | TRACKED MODIFIED | implemented Web source changes |
| 79 | `repos/koi-backend/nextjs_app/src/components/data-portability/BackupPreview.tsx` | TRACKED MODIFIED | implemented Web source changes |
| 80 | `repos/koi-backend/nextjs_app/src/components/data-portability/CiphertextExport.tsx` | NEW FILE | implemented Web source changes |
| 81 | `repos/koi-backend/nextjs_app/src/components/progress/ActivityAvailability.tsx` | NEW FILE | implemented Web source changes |
| 82 | `repos/koi-backend/nextjs_app/src/components/progress/BreathingActivityBridge.tsx` | NEW FILE | implemented Web source changes |
| 83 | `repos/koi-backend/nextjs_app/src/components/progress/RecordedBoard.tsx` | TRACKED MODIFIED | implemented Web source changes |
| 84 | `repos/koi-backend/nextjs_app/src/hooks/useActivityData.ts` | NEW FILE | implemented Web source changes |
| 85 | `repos/koi-backend/nextjs_app/src/hooks/useUserPreferences.ts` | TRACKED MODIFIED | implemented Web source changes |
| 86 | `repos/koi-backend/nextjs_app/src/lib/activities/activityLedger.ts` | NEW FILE | implemented Web source changes |
| 87 | `repos/koi-backend/nextjs_app/src/lib/activities/activityTypes.ts` | NEW FILE | implemented Web source changes |
| 88 | `repos/koi-backend/nextjs_app/src/lib/activities/breathingActivity.ts` | NEW FILE | implemented Web source changes |
| 89 | `repos/koi-backend/nextjs_app/src/lib/activities/conversationCompletion.ts` | NEW FILE | implemented Web source changes |
| 90 | `repos/koi-backend/nextjs_app/src/lib/activities/rewardPreview.ts` | NEW FILE | implemented Web source changes |
| 91 | `repos/koi-backend/nextjs_app/src/lib/checkins/checkInService.ts` | NEW FILE | implemented Web source changes |
| 92 | `repos/koi-backend/nextjs_app/src/lib/data-portability/backupDraft.ts` | TRACKED MODIFIED | implemented Web source changes |
| 93 | `repos/koi-backend/nextjs_app/src/lib/data-portability/ciphertextExport.ts` | NEW FILE | implemented Web source changes |
| 94 | `repos/koi-backend/nextjs_app/src/lib/db.ts` | TRACKED MODIFIED | implemented Web source changes |
| 95 | `repos/koi-backend/nextjs_app/src/lib/history/sessionTransition.ts` | NEW FILE | implemented Web source changes |
| 96 | `repos/koi-backend/nextjs_app/src/lib/onboarding.ts` | TRACKED MODIFIED | implemented Web source changes |
| 97 | `repos/koi-backend/nextjs_app/src/lib/preferences/accountPreferenceSync.proposed.ts` | NEW FILE | implemented Web source changes |
| 98 | `repos/koi-backend/nextjs_app/src/lib/preferences/preferenceSync.ts` | NEW FILE | implemented Web source changes |
| 99 | `repos/koi-backend/nextjs_app/src/lib/preferences/syncFailure.ts` | NEW FILE | implemented Web source changes |
| 100 | `repos/koi-backend/nextjs_app/src/lib/preferences/userPreferences.ts` | TRACKED MODIFIED | implemented Web source changes |

## Exact nonignored files excluded: 26

| Exact path | Reason |
|---|---|
| `.idea/.gitignore` | unrelated IDE metadata |
| `.idea/Koi.iml` | unrelated IDE metadata |
| `.idea/misc.xml` | unrelated IDE metadata |
| `.idea/modules.xml` | unrelated IDE metadata |
| `.idea/vcs.xml` | unrelated IDE metadata |
| `repos/koi-mobile/android/.gradle/8.12/checksums/checksums.lock` | unrelated/generated Flutter Android files |
| `repos/koi-mobile/android/.gradle/8.12/checksums/md5-checksums.bin` | unrelated/generated Flutter Android files |
| `repos/koi-mobile/android/.gradle/8.12/checksums/sha1-checksums.bin` | unrelated/generated Flutter Android files |
| `repos/koi-mobile/android/.gradle/8.12/executionHistory/executionHistory.bin` | unrelated/generated Flutter Android files |
| `repos/koi-mobile/android/.gradle/8.12/executionHistory/executionHistory.lock` | unrelated/generated Flutter Android files |
| `repos/koi-mobile/android/.gradle/8.12/fileChanges/last-build.bin` | unrelated/generated Flutter Android files |
| `repos/koi-mobile/android/.gradle/8.12/fileHashes/fileHashes.bin` | unrelated/generated Flutter Android files |
| `repos/koi-mobile/android/.gradle/8.12/fileHashes/fileHashes.lock` | unrelated/generated Flutter Android files |
| `repos/koi-mobile/android/.gradle/8.12/fileHashes/resourceHashesCache.bin` | unrelated/generated Flutter Android files |
| `repos/koi-mobile/android/.gradle/8.12/gc.properties` | unrelated/generated Flutter Android files |
| `repos/koi-mobile/android/.gradle/buildOutputCleanup/buildOutputCleanup.lock` | unrelated/generated Flutter Android files |
| `repos/koi-mobile/android/.gradle/buildOutputCleanup/cache.properties` | unrelated/generated Flutter Android files |
| `repos/koi-mobile/android/.gradle/buildOutputCleanup/outputFiles.bin` | unrelated/generated Flutter Android files |
| `repos/koi-mobile/android/.gradle/file-system.probe` | unrelated/generated Flutter Android files |
| `repos/koi-mobile/android/.gradle/noVersion/buildLogic.lock` | unrelated/generated Flutter Android files |
| `repos/koi-mobile/android/.gradle/vcs-1/gc.properties` | unrelated/generated Flutter Android files |
| `repos/koi-mobile/android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java` | unrelated/generated Flutter Android files |
| `repos/koi-mobile/android/gradle/wrapper/gradle-wrapper.jar` | unrelated/generated Flutter Android files |
| `repos/koi-mobile/android/gradlew` | unrelated/generated Flutter Android files |
| `repos/koi-mobile/android/gradlew.bat` | unrelated/generated Flutter Android files |
| `repos/koi-mobile/android/local.properties` | unrelated/generated Flutter Android files |

## Ignored/local exclusions and sensitive inherited files

Audited 51,865 currently ignored filenames after build; exact exhaustive local-only list: `artifacts/web-final-handoff/excluded-ignored-files.jsonl`. It is intentionally excluded from publication. Categories:

- 17: ignored local file outside proposed source snapshot.
- 150: local runtime/audit artifacts; reviewed browser source copies and sanitized summaries transferred separately.
- 1: local environment configuration; never stage/read .env.local.
- 1,111: build output/cache.
- 18: generated local media fixtures; not approved for publication.
- 70: downloaded voice models/toolchain/evaluation outputs, not authored Web product code.
- 8,662: platform/Python/tool cache.
- 41,836: dependency installation/cache.

All `.env` / `.env.*`, local auth secrets, service-account files, tokens/cookies/profiles, raw user data, backups, logs, caches, builds and IDE/Android paths are excluded from the proposed commit delta. `.env.local` contents never read. The currently ignored environment filename is documented by the local index; it is not copied.

The following environment files are **already tracked in inherited history**, unchanged and NOT proposed for staging:

- `repos/.env.template`
- `repos/koi-ai-engine/.env.template`
- `repos/koi-backend/functions/.env.example`
- `repos/koi-backend/nextjs_app/.env.local.test`

**Push security gate:** the last file contains service-account-shaped/private-key material not conclusively identified as a safe fixture. Local PEM/DER parsing failed; that does not prove it is harmless. Template and setup-env test files also contain nonparseable placeholder markers. No values were printed. Review/credential disposition is needed before push; excluding a tracked path from staging does not remove it from the branch or its history. No deletion, rotation or history rewrite is authorized/performed.

## Substantive work represented / not represented

- Every current nonignored intentional Web source/test/review/report change is selected. No new implementation file is silently omitted.
- Local commits `49ad948` and `b384ce2` (W1/history/data/accessibility foundations) remain the ancestor baseline of the proposed branch and therefore are transferred without restaging unchanged files.
- 22 originally ignored authored browser scripts are copied verbatim to `review/handoff-evidence/browser-harness/`; source hashes and origin paths included. Historical assertion summaries are sanitized and included.
- Raw runtime screenshots/logs/downloads/profiles/results remain local. Excluded results are not silently treated as new browser PASS; summaries retain evidence class and source hash.
- Local avatar sandbox downloaded speech/ASR tools/models (~1 GB) and generated fixtures remain excluded. They are dependencies/evaluation outputs, not missing authored product implementation. No ignored public Web asset was found. No local avatar asset was altered.
- IDE and Android files above remain untouched, not discarded.

## Current verification / limits

- `npm test -- --runInBand --silent`: **286 tests /39 suites PASS**, 28.334s.
- `npx tsc --noEmit --incremental false`: **PASS**.
- `npm run build`: **PASS**, Next14.2.35, 19/19 entries, BUILD_ID `i4JLGTu9EUai8YYGsixEA`.
- `git diff --check`: PASS on tracked changes; existing CRLF notices are harmless. Separate untracked preflight found two verbatim browser copies with one trailing-space line each and three .diff files with valid space-only context lines. They were preserved; staged whitespace review must not misrepresent this as an entirely warning-free new-file snapshot.
- No new authenticated browser/hosted or combined-Ahmad-branch test run. Historical sanitized evidence is separate.
- Proposed content: high-confidence token/private-key/service-account/credential-URL pattern scan found **zero matches** in the selected changes/evidence. Inherited flagged files are not misrepresented as clean. Pattern scan cannot prove absence of all secrets.

## Approval and later execution boundary

Owner must approve this exact manifest and resolve/acknowledge the inherited credential security gate before branch-only push. On approval, recheck byte hashes/status and actual staged diff/security scan, create the named review branch from this exact current local HEAD, selectively stage only these files, review and commit the approved snapshot, push only that branch, then record its actual SHA in the final handoff. If any file changed, stop and reconcile ownership rather than overwrite it. No commit/push has been attempted.
