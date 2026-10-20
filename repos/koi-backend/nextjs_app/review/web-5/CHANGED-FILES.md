# WEB-5 exact changed files

Compared against captured pre-WEB-5 SHA-256 hashes, including existing uncommitted WEB-3/4 files. Baseline HEAD: `f2b9c80f3390e7828131e98d943322f6d1694bfb`. The four intentional existing-file edits are listed separately from additions.

| Change | Exact path |
| --- | --- |
| Modified | `.gitignore` |
| Added | `dev/web5-reference/firebase.json` |
| Added | `dev/web5-reference/firestore.indexes.json` |
| Added | `dev/web5-reference/firestore.rules` |
| Added | `dev/web5-reference/platform-deny.patch.rules` |
| Added | `dev/web5-reference/source-manifest.json` |
| Added | `scripts/web5-artifacts.cjs` |
| Added | `scripts/web5-backend-functional.cjs` |
| Added | `scripts/web5-cloud-audit.cjs` |
| Added | `scripts/web5-cloud-env.ps1` |
| Added | `scripts/web5-load-platform.cjs` |
| Added | `scripts/web5-network-guard.cjs` |
| Added | `scripts/web5-provision-core.cjs` |
| Added | `scripts/web5-provision.cjs` |
| Added | `scripts/web5-provision.ps1` |
| Added | `scripts/web5-rules-evidence.cjs` |
| Added | `scripts/web5-rules-security.cjs` |
| Added | `src/__tests__/firebase-admin-coexistence.test.ts` |
| Modified | `src/__tests__/platform/bootstrap.test.ts` |
| Added | `src/__tests__/platform/web5-production.test.ts` |
| Added | `src/__tests__/platform/web5-provision.test.ts` |
| Modified | `src/lib/firebase-admin.ts` |
| Modified | `src/lib/platform/server/admin-config.cjs` |
| Added | `src/lib/platform/server/production-evidence.cjs` |

Reports added: `review/web-5/WEB-5-COMPLETION.md`, `EXISTING-FIREBASE-INTEGRATION.md`, `SECURITY-VERIFICATION.md`, `DEMO-DEPLOYMENT.md`, `CHANGED-FILES.md`. Machine-readable hashes: `changed-files.json`; original checkpoint: `baseline.json`; logs/results: `evidence/`.

All other pre-existing files retain their captured hashes (`evidence/preservation.json`). Original UI/theme, companion/SSE/crisis/avatar implementations and all frozen contracts are untouched. `src/lib/firebase-admin.ts` has only the default-app name lookup correction for coexistence; no request/transport/provider contract change. Existing `.env.local`, parent Firestore rules, WEB-1?4 reports/evidence and unrelated dirty work are preserved.

`dev/web5-reference/` contains local proposed policy/index/config artifacts, not a deployed policy. Its 12 composite indexes omit redundant single-field proposals and preserve supplied existing configurations when merged. Private operator files belong under ignored `.local/koi-web5/` or another private directory. No cloud credential or password is stored in tracked files. Build/emulator logs/caches are local runtime artifacts.
