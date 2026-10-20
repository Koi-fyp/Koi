# WEB-4 verification evidence

All integration activity used `demo-koi-platform-web1`, Auth `127.0.0.1:5199`, Firestore `127.0.0.1:5180` and Next `127.0.0.1:3107`. No production service or rule deployment was performed. Completed evidence was retained across interruptions; only unfinished checks and checks affected by later fixes continued.

| Command/check | Result | Evidence |
| --- | --- | --- |
| `npx jest --runInBand --json --outputFile=review/web-4/evidence/jest-results.json` | PASS: 83 suites, 678 tests | `evidence/jest-results.json`, `evidence/jest.log` |
| `npx jest src/__tests__/auth.test.tsx src/__tests__/platform/demo-companion-mode.test.ts --runInBand` | PASS: 2 suites, 11 tests after the last guarded Auth change; includes one added test | `evidence/auth-final.log` |
| `npx tsc --noEmit --incremental false` | PASS, exit 0 | `evidence/typecheck-final.log` (empty success output) |
| `npm run build` | PASS: optimized compilation, lint/type checking and route generation | `evidence/build-final.log` |
| Final compact-menu `npm run build` | PASS on the final application source | `evidence/build-navigation-final.log` |
| `npx jest src/__tests__/platform/navigation.test.tsx src/__tests__/environment-pages.test.tsx --runInBand` | PASS: 2 suites, 4 tests after the compact-menu fix | `evidence/navigation-final.log` |
| `git diff --check` | PASS; existing LF/CRLF conversion notices only | Tool output; no whitespace errors |
| `node scripts/web4-regression-functional.cjs 1` | PASS: 18 checks | `evidence/web-1-regression/functional-emulator.json` |
| `node scripts/web4-regression-functional.cjs 2` | PASS: 15 checks | `evidence/web-2-regression/functional-emulator.json` |
| `node scripts/web4-regression-functional.cjs 3` | PASS: 16 checks | `evidence/web-3-regression/functional-emulator.json` |
| `node scripts/web4-demo-functional.cjs` | PASS: seven check groups; zero page errors, companion calls, nonlocal Firebase calls or provider calls | `evidence/functional.json` |
| Actual Firebase CLI export, stop, import, then `node scripts/web4-persistence-check.cjs` | PASS: Auth hashes, fixture IDs and ten collection counts preserved | `evidence/persistence.json` |
| `node scripts/web4-companion-smoke.cjs` after mobile adjustment | PASS: real anonymous sign-in, original onboarding/local save, account entry and visible existing mode selector at 390px; zero live Firebase/provider traffic | `evidence/companion-smoke-final.json`, `evidence/companion-mobile-final.png` |

WEB-1/2/3 harness wrappers change only evidence destinations and the historical WEB-2 fixture's now-required discoverable profile prerequisite, supplied through the real owner route. Existing batch reports/evidence were not overwritten. The emulator rules remain deny-all for direct clients. The earlier WEB-3 report also retains its 28 direct Firestore denial assertions; those are not claimed as a newly repeated WEB-4 run.

Screenshots: `patient-ack.png`, `professional-dashboard.png`, `patient-account-mobile.png` and `companion-mobile-final.png`. They contain fictional local data. Older `failure-*.png`, companion diagnostic/failure screenshots and the initial `companion-mobile.png` remain diagnostic history, not final visual acceptance evidence.

## Failures resolved during this batch

- A nested navigation landmark broke an existing environment-page assertion. The dropdown now uses a group; expanded account navigation remains a landmark.
- Reduced-motion hover translation made a new menu link oscillate beneath the pointer. New menu links disable translation only under reduced motion.
- The Windows npm PowerShell shim mishandled splatted startup arguments. The emulator script now invokes `npx.cmd` and reports nonzero exit codes.
- Companion local test sign-in originally accepted only the historical project. The added exception requires the explicit development demo configuration and an Auth SDK already connected to the exact emulator. The original custom-token path remains covered.
- The companion smoke harness initially used `/?home=1`, which deliberately suppresses redirect after sign-in. It now uses the original bare `/` entry.
- A document-width assertion missed clipping of the existing mobile mode selector. Visual inspection found it; the companion header now uses a compact menu and the final test checks the selector's actual bounds.

## Test boundaries

Browser integration results are not fabricated in-memory data. Seeder idempotency is checked by stable IDs and unchanged collection counts on a repeat invocation. Passwords are never written to reports; export files containing Auth hashes stay ignored.

Patients receive assignment/acknowledgement DTOs only. Direct patient requests to evaluation, professional submission workspace and analytics endpoints were denied. Earlier lifecycle tests cover duplicate/racing submissions, cross-organization and cross-patient denial, revocation, immutable versions and provider-independent acknowledgement.

AI-failure fixtures in older tests are explicitly synthetic. No live AgentRouter call, invented score, push delivery, real payment, Flutter execution or production deployment validation is claimed. Avatar/SSE behavior is covered by existing regression suites; the companion smoke stops before provider requests.
