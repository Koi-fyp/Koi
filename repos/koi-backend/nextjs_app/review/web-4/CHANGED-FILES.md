# WEB-4 changed files

Compared with the captured pre-WEB-4 file hashes in `baseline.json`, not just Git HEAD. This distinguishes this batch from the existing uncommitted WEB-3 work. Baseline HEAD: `f2b9c80f3390e7828131e98d943322f6d1694bfb`. No commit was created.

| Change | Exact path |
| --- | --- |
| Modified | `.gitignore` |
| Added | `scripts/demo-env.ps1` |
| Added | `scripts/koi-demo-guard.cjs` |
| Added | `scripts/koi-demo-preflight.cjs` |
| Added | `scripts/seed-koi-demo.cjs` |
| Added | `scripts/start-demo-emulators.ps1` |
| Added | `scripts/web4-companion-smoke.cjs` |
| Added | `scripts/web4-demo-functional.cjs` |
| Added | `scripts/web4-persistence-check.cjs` |
| Added | `scripts/web4-regression-functional.cjs` |
| Modified | `src/__tests__/auth.test.tsx` |
| Added | `src/__tests__/platform/demo-companion-mode.test.ts` |
| Added | `src/__tests__/platform/demo-guard.test.ts` |
| Added | `src/__tests__/platform/navigation.test.tsx` |
| Added | `src/app/account/layout.tsx` |
| Added | `src/app/account/page.tsx` |
| Modified | `src/app/page.tsx` |
| Modified | `src/app/patient/layout.tsx` |
| Modified | `src/app/professional/layout.tsx` |
| Modified | `src/components/layout/BottomNav.tsx` |
| Modified | `src/components/patient/PatientWorkspace.tsx` |
| Added | `src/components/platform/AccountApp.tsx` |
| Added | `src/components/platform/PlatformNavigation.tsx` |
| Modified | `src/components/professional/PatientManagement.tsx` |
| Modified | `src/components/professional/PracticeOverview.tsx` |
| Modified | `src/components/professional/ProfessionalWorkspace.tsx` |
| Modified | `src/contexts/AuthContext.tsx` |
| Added | `src/lib/auth/demoEmulatorMode.ts` |
| Modified | `src/lib/firebase.ts` |
| Added | `src/lib/platform/navigation.ts` |

New reports: `review/web-4/WEB-4-COMPLETION.md`, `review/web-4/DEMO-LOGIN-GUIDE.md`, `review/web-4/SCREEN-ROUTES.md`, `review/web-4/CHANGED-FILES.md`, `review/web-4/TEST-EVIDENCE.md`. Baseline and test logs/JSON/screenshots are under `review/web-4/`; consult TEST-EVIDENCE for their paths and status.

The existing contracts, backend services, companion SSE transport, avatar renderer, crisis handling and Firestore rule files have no WEB-4 edits. AuthContext has one guarded local-emulator exception; the original default custom-token flow is unchanged. Existing WEB-2 evidence edits, WEB-3 work, `.local-emulator-data/` and unrelated parent/mobile changes were preserved.

Ignored local artifacts: `.local/koi-demo/export/` (Auth/Firestore snapshot) and `.local/koi-demo/persistence-check.json` (verification fingerprints). These are not source deliverables and must not be published. Dev/build caches and emulator logs are runtime artifacts.
