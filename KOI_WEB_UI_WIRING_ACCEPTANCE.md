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
