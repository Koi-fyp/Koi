# KOI Web gap-only pre-defense audit — 2026-10-18

Accepted baseline: `193b1854a6dadeec44b8f74012d86bfd52c9ad15`, branch `feat/avatar-webview-host`. Read the wiring acceptance, P1 avatar acceptance and jigsaw audit before editing. Tracked worktree initially clean; existing untracked IDE/Android files preserved. This report supersedes no historical browser evidence and makes no deployment claim.

All source references below are relative to `repos/koi-backend/nextjs_app/src`. Inspected all 12 actual `page.tsx` routes, layouts, their active interactive components, preference/progress readers and auth integration. Existing unmounted `components/koi/*` prototypes and `onboarding/AvatarStep.tsx` are not production route controls; do not mistake their no-op buttons for active navigation.

## Confirmed gaps fixed in this batch

| Source | Confirmed checkpoint defect | Narrow correction |
| --- | --- | --- |
| `app/(authenticated)/settings/page.tsx:142,336` | Clear History still enabled despite W1 report; invented 42 KB / 5 MB and 1% storage | Disabled deletion with approved-scope explanation. Browser `navigator.storage.estimate()` through `hooks/useStorageEstimate.ts`; explicitly approximate **origin-wide** usage/quota, includes caches/other accounts, unavailable on denial/unsupported/invalid result. No database scan or per-user storage claim. |
| Same page, `:460,588` | Invented January 2025 release, v1.0.0/production and optimization claims; blanket 24/7 contact availability | Web preview, unpublished release date, actual build-time NODE_ENV runtime mode; implemented feature list; contact hours explicitly unverified. Existing contact numbers and safety behavior untouched. |
| `app/(authenticated)/progress/page.tsx:1160,1191` | Download/Share looked actionable but had no handlers | Disabled, visible Unavailable labels and explanation; existing card and read model unchanged. |
| `components/onboarding/PrivacyStep.tsx:8,129` | Claimed mood-response storage and never storing contact details/sharing conversations | Actual local preference/content description; optional identity linking and readable inference boundary; no unsupported global collection promises. |
| `components/onboarding/AIDisclosureStep.tsx:30` | Required agreement to nonexistent linked Privacy Policy/Terms | Explicit acknowledgement of the actual storage/inference boundary. AI acknowledgement, gating and crisis contacts retained. Formal policy publication remains a decision gate. |
| `app/(authenticated)/settings/privacy/page.tsx:157,192` | Entire local-data card labelled encrypted, including plaintext preferences; cloud labelled anonymous without receipt | Content-encrypted badge; plaintext preference disclosure; cloud status unverified. No fabricated ledger or deletion enabled. |
| `app/(authenticated)/settings/export/page.tsx:336` | Disabled export still advertised scores, themes, crisis outcomes and insights as report contents | Record-availability descriptions; no conclusions, scores or prepared personal report claimed. Existing generation guard remains false. |
| `app/how-it-works/page.tsx:7`, `app/page.tsx:30`, `app/layout.tsx` | Unverified fine-tuning/emotional-analysis/language guarantees and instant/no-account metadata | Describe service expressions, bounded context and saved language preference; anonymous Firebase identity and encrypted history. |
| `components/layout/ModeSelector.tsx:19,59` | Hover-only activation; media options were clickable divs styled as locked | Click/native keyboard activation, expanded/control semantics, Escape; native disabled media buttons, same visual classes/animations. |
| `components/chat/InputBar.tsx` | Textarea lacked an explicit accessible name | Added Message KOI label; send/keyboard/session logic untouched. |

## Every route and active control group

Categories: **local** = actual device/UID state; **static** = legitimate nonpersonal copy/art; **preview** = explicitly segregated sample; **unavailable** = disabled/no delivery claim; **dependency** = unverified service/policy gate. No cloud success inferred from a local write.

| Route / source | Values, controls, source of truth and error state |
| --- | --- |
| `/` — `app/page.tsx:30,97` | Static art/features/FAQ; anchor/navigation links; FAQ accordion; Get Started uses existing Firebase sign-in with loading/error. Recent context/encrypted local restore are accepted P0 behavior. Language is a preference, not verified translation. |
| `/about` — `app/about/page.tsx:328,386,445` | Static project/team attribution and journey descriptions, no personal usage metrics. Biography buttons already disabled, preserved. Attribution is repository copy, not independently verified employment/research history. Links and reveal animations retained. |
| `/how-it-works` — `app/how-it-works/page.tsx:7,242` | Static feature explanation; service-dependent replies, bounded context and companion expressions. Start button calls existing sign-in; links/reveals retained. No clinical effectiveness or model-training verification claimed. |
| `/onboarding` — `app/onboarding/page.tsx:62,97` | Welcome auto-advance/tap; privacy continue; canonical companion picker; two acknowledgement controls; language picker; reminder enabled/time; local-save continuation. Existing UID preference restoration and storage/cloud errors preserved. Local completion is not a cloud receipt; no push or scheduler. Welcome keyboard activation and comprehensive picker/dialog keyboard semantics remain accessibility follow-up. |
| `/chat` — `app/(authenticated)/chat/page.tsx:54,77` | Real shared P0 messages/timestamps/pending/error, not scripted conversations. Send/Enter/Shift-Enter, composer focus action, scene link; UID-scoped PNG and readable missing/fox/image-error fallback. Offline banner and blocked input preserved. Empty hero is static copy. |
| `/companion-scene` — `app/(authenticated)/companion-scene/page.tsx:22,33` | Same P0 session and canonical VRM resolver. Back preserves request; End cancels current request and navigates, does not delete history. Transcript toggle, composer Send/Cancel, retry/selection links; mic/camera disabled. Existing exercise request/pause/resume/stop and crisis choices consume validated service state. Their counters are actual playback state, not awards. No safety or transport changes. |
| `/progress` — `app/(authenticated)/progress/page.tsx:170,728,743` | Actual UID-scoped encrypted completed-exchange metadata and recorded piece/source/milestone totals through existing `readProgress`/liveQuery. Loading/error/retry retained. Puzzle expansion, illustrative piece tooltips, milestone details, mood bars, heatmap and emotional colors explicitly **preview**, not recorded personal outcomes. Download/Share now unavailable. No new awards, mood inference or streaks. |
| `/settings` — `app/(authenticated)/settings/page.tsx` | Avatar/name modal save/cancel, language toggle, local check-in enabled/time and due preference use existing `db.users` adapter with UID guards/save errors. No cloud/scheduler receipt. Clear History disabled. Privacy/export/import links work. Origin storage estimate is not personal data. Version/features/contact accordions are static information. |
| `/settings/privacy` — `app/(authenticated)/settings/privacy/page.tsx:157,192,258,336` | Back link; CSE/readable-inference trust boundary; plaintext preferences; cloud unverified. Recent Activity honestly empty (no ledger). Delete Account already disabled. Encryption wording describes content at rest, not zero knowledge/E2EE. |
| `/settings/export` — `app/(authenticated)/settings/export/page.tsx:7,14,336,358` | Back works; report card shows unavailable sources; Generate disabled and handler guard remains false. No invented PDF or completion/download claimed. Future generator code remains unreachable, must not be enabled without consent/escaping/owner/decryption validation. |
| `/settings/import` — `app/(authenticated)/settings/import/page.tsx:57,180` | Back works; future import capabilities are Coming Soon; Notify Me disabled. No file upload/parser, ownership checks or dedup falsely enabled. |
| `/avatar-host` — `app/avatar-host/page.tsx:11` | Presentation-only native WebView contract, allowlisted male/female models, separate from UID conversation preferences. Existing loading/retry/error and host commands preserved. Not an authenticated conversation route; male default here is not fox-profile substitution. |

Shared navigation: `components/layout/BottomNav.tsx` routes Chat/Progress/Settings and active-page semantics; home follows existing authenticated landing redirect. Mode picker now supports keyboard/touch and keeps audio/video disabled. Authenticated layout preserves the single ConversationProvider. `contexts/AuthContext.tsx:158,188` implements account linking/sign-out, but **no active page currently exposes these controls**. Do not claim end-user account management or cross-device recovery is complete. Existing `/api/auth/anonymous` and `/api/auth/link-email` routes inspected only; frozen and unchanged.

## Validation and evidence boundaries

- Focused changed-area tests: 4 suites / 25 tests PASS before mode coverage; final full Jest **15 suites / 84 tests PASS**.
- TypeScript `--noEmit --incremental false` PASS; final source also passed production build type validation.
- Production build PASS, Next.js 14.2.35, 18/18 generation entries, build ID **`qL3Ohyli4LcLkK20FLzVz`**. Built at accepted SHA plus this uncommitted diff, before starting one browser development server. Not deployed.
- P0 recovery script PASS: real local AES-GCM/PBKDF2, Dexie reopen/reconciliation/UID isolation; **synthetic auth/fetch**. Avatar session script PASS: deterministic metadata/controller transitions; **not rendered/live Modal evidence**.
- `git diff --check` PASS. Protected conversation/transport, auth contexts, encryption/database, jigsaw read model, avatar renderer/host and Flutter sources match the checkpoint. No dependencies installed, commits or backend edits.
- Browser evidence and final remaining gates are recorded in the appended acceptance entry. Historical P0 six authenticated Modal 200/SSE requests and P1 rendered emotion fixtures remain historical; this batch does not relabel them as fresh results.

## Remaining gates, not silently implemented

1. Deletion/account purge and retention scope; formal Privacy Policy/Terms approval/publication. Controls stay disabled; no data deleted.
2. Consented UID-scoped export implementation and import owner/integrity/dedup/crypto validation. Do not enable the dormant PDF generator.
3. Locked reward rules, activity completion ledger and cloud authority; no new jigsaw awards. Actual check-in/mood/task writers do not exist in this audited route set; samples remain explicit previews.
4. Reachable account linking/logout UI, approved verification-email delivery and real linked-account/cross-device acceptance. Existing auth stays frozen. Global legacy onboarding-complete localStorage flag is not UID-scoped; current preference/session stores are. Do not use that flag as proof of another user's onboarding or cloud state.
5. Contact numbers/hours have not been independently revalidated in this audit; no new helpline or availability promise added. Crisis content, risk classification and policy unchanged.
6. Fresh live non-neutral Modal emotions, real completed-reply-to-progress browser update, linked-account/offline/denied storage browser matrix, long WebGL soak/native device coverage. Local fixtures do not close these gates.
7. Remaining keyboard details: welcome div, preview milestone controls and avatar dialog focus behavior need a dedicated accessibility pass. Preview interactions are not treatment or user progress facts.
