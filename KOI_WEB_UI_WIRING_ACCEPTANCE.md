# KOI Web wiring acceptance — 2026-10-17

Branch `feat/avatar-webview-host`, HEAD `40be37e201998c54e5be3f0f9abd6973ec36e616`, dirty baseline. This is an incremental working-tree execution log, not a deployment. API/auth/crypto/transport are frozen. See the route audit and dependency record for source paths and deferred controls.

## W1 — honest copy and no-op safety

PASS: removed invented landing usage count, trial/history counts and guaranteed availability/no-storage assertions from public routes; corrected privacy trust boundary and removed fabricated successful activity; disabled Clear History/Delete Account; disabled synthetic PDF generation and removed its invented data. Existing UI styles/layout declarations retained.

Changed: public landing/about/how-it-works; Settings clear-history row and reusable SettingsRow disabled state; privacy screen; export data/availability; new `web-honesty.test.tsx`. No protected service/auth/transport changes.

Tests: 5 focused rendered honesty tests PASS; TypeScript PASS; full Jest **12 suites / 66 tests PASS**, including P0/jigsaw/UID fixtures; diff check PASS. Next.js **14.2.35 production build PASS**, 18/18 static-generation entries. Build identity recorded in batch inventory below.

Browser: before-state public desktop PNG/DOM snapshots captured under `artifacts/web-wiring/w0-*`. Anonymous Firebase sign-up/lookup HTTP 200; no Modal requests. Before-state authenticated screenshots were captured too early during loading (empty DOM), so they are **NOT VALID layout comparisons**. No authenticated before/after parity claim is made from those files. Browser closed before heavy checks; existing single dev server stopped for build.

Policy: deletion scope remains blocked; no deletion/retention implemented. No activity ledger or telemetry collection added. PDF remains unavailable until W4 validation.

W1 production build ID: `tmlt7sn3fT0OaBRycO7P6`.

## W2 — UID-scoped local preferences

PASS: one adapter over the existing `db.users`, common hook/resolver, additive optional local companion nickname (not a schema version), language, enabled/time preferences. Onboarding restores prior preferences; settings save errors retain old values. Both PNG/VRM consumers use canonical representation and optional display name. No second database, API, scheduler, permission prompt or new cloud path. Cloud synchronization is not claimed.

Focused Jest: **6 suites / 33 tests PASS** (avatar/onboarding/settings/profile); TypeScript and diff check PASS. W2 build result follows. Browser verification is consolidated in W5; no live backend result is inferred from fixtures. New files: `lib/preferences/userPreferences.ts`, `hooks/useUserPreferences.ts`, `__tests__/user-preferences.test.tsx`. Modified existing avatar adapter/hook, Settings/picker, onboarding/language/notification components, chat/scene display name bindings, and regression test selectors for newly distinct status messages/remounts. All original visual style declarations retained.


## Gap-only pre-defense — 2026-10-18

Accepted baseline **193b1854a6dadeec44b8f74012d86bfd52c9ad15**, branch **feat/avatar-webview-host**, plus current uncommitted changes. Earlier SHA/build/dirty-tree statements above are historical. Existing W1/W2, jigsaw and P1 were not repeated. W2's previously uncaptured build ID was `C4CsmbJsF6X42fXc7Fhn-`. See `KOI_WEB_PRE_DEFENSE_GAP_AUDIT_2026-10-18.md` for all 12 routes, active controls, source references, confirmed fixes and remaining gates.

| Acceptance | Result and evidence |
| --- | --- |
| All route/control source audit | PASS; gap matrix in linked report. Unmounted prototypes excluded from active-page findings. |
| Honest storage, release, language and privacy claims | PASS; focused rendered tests and real browser. Measured storage is explicitly approximate origin-wide usage/quota, not a UID balance. No fake 42 KB/5 MB. |
| Unapproved/nonfunctional destructive and export controls | PASS: unavailable; Clear History, Delete Account, PDF generation, import notification and Progress Download/Share disabled. No data deleted or fake report generated. |
| Focused/full tests | PASS; focused 4 suites/25 tests, final Jest **15 suites/84 tests**. Initial outdated disclosure/ambiguous test selectors corrected and rerun. |
| TypeScript/build/diff | PASS; tsc --noEmit --incremental false; Next.js **14.2.35** production build, **18/18** generation entries, build ID **qL3Ohyli4LcLkK20FLzVz**. Final source also passed build type validation; git diff --check clean. Not deployed. |
| P0 and UID isolation | PASS local regression: real AES-GCM/PBKDF2, Dexie reopen/reconciliation with synthetic auth/fetch. Fresh populated-history/live SSE browser replay NOT RUN. Protected P0 sources unchanged. |
| Avatar emotion regression | PASS deterministic session/controller fixture; no rendered/live Modal inference from that test. |
| Genuine Firebase sign-in | PASS browser: isolated Chrome, existing development anonymous configuration; signUp/lookup HTTP 200 and authenticated routes reached. No tokens, UIDs, secrets, private messages or storage state exported. |
| Frontend identity | http://127.0.0.1:3000; one development server, listener PID **10132** during checks. No listener existed before startup; production build finished before server/browser work. Browser results are development runtime, not production-runtime acceptance. |
| All-page responsive smoke | PASS: landing/about/how-it-works desktop and mobile; all seven authenticated pages at 1280x900 and 390x844; onboarding mobile entry and female avatar-host mobile. Expected routes reached, no horizontal document overflow, zero recorded page errors across contexts. |
| Keyboard mode/media controls | PASS browser and component tests: Enter opens, Escape closes; locked Audio button disabled; scene mic/camera disabled. No media permission requests added. |
| Language reload | PASS real authenticated browser/local DB: Settings save and full reload retain English preference. Not a cloud receipt. |
| Aisha selection/rendering/navigation | PASS real browser: Settings save, loaded Female PNG, real VRM renderer ready and screenshot visibly renders female model. Chat -> Progress -> Chat -> Scene -> Chat and refresh retain selection. Empty conversation only; does not verify populated history or active SSE. |
| Progress download/share | PASS browser: both visibly unavailable and disabled. Real counts/recorded totals and segregated previews preserved. |
| Raza/fox/per-user preferences | PASS existing local regression tests; fresh Raza/fox/account-switch browser runs NOT RUN. Historical P1 browser acceptance remains separate. |
| Modal HTTP/SSE/reply-to-progress | NOT RUN; zero chat requests in this run, no fresh Modal HTTP status or SSE observations. Historical P0/P1 evidence is not relabelled. |
| Live exercise/crisis delivery | NOT RUN; no crisis-provoking messages or backend requests. Existing behavior/policy unchanged. |
| Linked-account/cloud/denied/offline browser matrix | NOT RUN; no Firestore receipt or cross-device recovery claim. Existing local storage-failure and UID tests pass. |
| Before/after pixel comparison | NOT RUN; after screenshots/DOM captured; no reliable same-context baseline captures. UI styles/layout retained except full-width native mode buttons; no pixel-parity claim. |

Ignored local evidence is under `artifacts/pre-defense/`: PNG/DOM snapshots, harness scripts and sanitized `browser-result.json`, `browser-controls-result.json`, `browser-final-result.json`. Browsers used only fresh test identities and empty conversations. The screenshot named `aisha-vrm-mobile.png` is actually **1280x900 desktop**, not mobile evidence.

Harness limitations: first run stopped on an exact toast selector. Focused follow-up verified persisted language/selection and completed all 13 control checks, then a host screenshot filename containing Windows-invalid '?' failed. Final bounded browser run used a safe filename and passed the female host render and remaining public/onboarding mobile captures. These harness exits are not application failures or a single uninterrupted all-green run. All browser contexts closed; one development server remains running.

Remaining gates: approved deletion/retention and formal legal text; consented/validated export/import; locked reward rules and durable check-in/task sources; reachable account-link/logout UI and verification-email delivery; fresh completed-reply progress and non-neutral live emotions; existing contact verification; denied/offline/linked-account and keyboard/dialog/native/long-soak coverage. See detailed audit for legacy global onboarding flag caveat. No auth, API/transport, encryption format, crisis policy, backend or Flutter changes. No commit/push/merge/deploy.
