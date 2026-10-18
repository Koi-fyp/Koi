# UI fix report — 2026-10-19

Branch `integrate/web-2026-10-19` (worktree `E:\Koi\web-integrate`). Local commits only; nothing pushed or deployed. Presentation-only changes: no data, storage, sync, crypto, session, auth, crisis, speech or camera logic was changed.

## KOI look used (quoted from `src/app/globals.css`)

- **Primary button** `.neo-btn-primary`: `background: var(--neo-blue)` (`#2D63EB`), `color: #fff`, `box-shadow: 4px 4px 0 0 #000`, with the shared pill: `border-radius: 9999px; border: 2.5px solid #000; font-family: var(--font-display); font-weight: 700; padding: 0.875rem 1.75rem`.
- **Secondary button** `.neo-btn-secondary`: `background: var(--neo-yellow)` (`#FFD100`), `color: #000`, `box-shadow: 4px 4px 0 0 #000`, same pill.
- **Card** (Settings/Progress) `.neo-card`: `background: #fff; border: 2.5px solid #000; border-radius: 1.25rem; box-shadow: var(--shadow-lg)` (`6px 6px 0 0 #000`). Progress inline cards use the same values plus `padding: 1.25rem`, and headings `font-weight: 800; font-size: 1.1rem; letter-spacing: -0.02em`.
- **Page background**: `html, body { background-color: #ffe5d9 }`. The landing page adds `.page-bg` (mesh + checker images over `#ffe5d9`) and `.grain`.
- **Fonts**: `--font-display: 'Bricolage Grotesque', system-ui, sans-serif`; `--font-body: 'DM Sans', system-ui, sans-serif` (body default).

New shared classes, built only from those tokens: `.neo-btn-sm` (compact size, as used before on "Open avatar conversation"), `.koi-action-row` (wrapping button row), a `:focus-visible` ring on `.neo-btn-*`, a chevron for `select.neo-input`, and `.koi-paper` (white card capsule).

## 1. Landing page root cause

**Root cause:** `next.config.js:7` (before the fix: `module.exports = nextConfig;`, no `distDir`). `next dev` and `next build` both wrote to `.next`. Running `npm run build` while the dev server is up empties the dev server's `.next/static`. The dev server then serves `/` as HTML, but every chunk and the stylesheet return 404. The page never hydrates: no styles, and the CTA stays on "Starting…" because `src/app/page.tsx:109` (`isLoading = starting || loading`) keeps the server-rendered `loading=true` state. The FINAL_REPORT phase-5 builds ran with dev processes in use, which matches "does not render since the merge".

**Evidence:**
- A fresh dev server renders `/` at both sizes with 0 console errors, 0 page errors and 0 failed requests.
- The source diffs of `page.tsx`, `layout.tsx`, `providers/*` and `globals.css` against `884a278` and `223e97c` contain only the per-UID onboarding resolve (`page.tsx:69-77`) and the report print block. Neither breaks rendering.
- Reproduction: I ran `npx next build` while the dev server was running. The build itself died with `EPERM … .next/trace`, but had already removed the dev chunks. Reloading `/` then logged:

  ```
  [http 404] /_next/static/css/app/layout.css
  [http 404] /_next/static/chunks/webpack.js
  [http 404] /_next/static/chunks/main-app.js
  [http 404] /_next/static/chunks/app/page.js
  [http 404] /_next/static/chunks/app/layout.js
  ```

  The server log shows the same 404s. Screenshot: `artifacts/ui-fix/1-landing-broken-repro-1280x800-before.png` (unstyled serif text, a grey "Getting ready…" button, stacked colour blocks).

**Fix:** `next.config.js:13-15` gives the development phase its own `distDir: '.next-dev'` (`.gitignore` and `tsconfig.json` include updated). After the fix, `npm run build` ran to completion while the dev server stayed up, and `/` kept rendering.

Regression tests:
- `src/__tests__/landing-render.test.tsx` renders the page signed out and asserts the hero heading and both CTAs.
- The same file asserts that the dev and build phases use separate `distDir`s.

## Commits

| Commit | Item |
|---|---|
| `c0652e3` | ui 1: landing renders again: dev server gets its own distDir |
| `efe53e4` | ui 1b: no landing flash for signed-in visits; /?home=1 and Home entry |
| `bcd69b4` | ui 2: integration controls become KOI neo buttons in tidy rows |
| `0242897` | ui 3: progress cards made homogeneous with the page |
| `255e9ad` | ui 4: report and export preview on a white paper capsule |
| (this file) | ui 7: report |

Items 5 and 6 produced no further source changes, so there is no separate commit for them. Their tests were added inside the item commits, and `scripts/verify-ui-fix.cjs` grew with items 1–4.

## What changed, per item

- **1b.** `/` renders `AuthPendingSpinner` while auth or the onboarding check is unresolved. This is the same "K" tile as the authenticated layout, now shared from `src/components/layout/AuthPendingSpinner.tsx`.
  - Signed-in and onboarded → `router.replace('/chat')`; signed-in but not onboarded → `replace('/onboarding')`; signed-out → landing.
  - `/?home=1` keeps a signed-in user on the landing page. The header shows "Open chat" (`.neo-btn-primary`), and the hero/ready CTAs open chat instead of signing in again.
  - The top bar gains **Home → `/?home=1`**. The logo also now points at `/?home=1`, because no existing test depended on `href='/'`.
  - Side effect: the server-rendered HTML of `/` is now the spinner. Signed-out visitors see the landing page once Firebase reports no user.
- **2.**
  - `/chat`: New Chat (primary), Complete Conversation, Change companion, Open avatar conversation and Browse saved history (secondary) form one wrapping row. The row scrolls on its own if the completion details are open. "Save completion" is primary, and the details sit in a `neo-card`.
  - `/chat` mobile: `.avatarPanel` gets `min-height: 0`, so it keeps its `clamp(132px, 29svh, 230px)` height. Before, it grew to 407 px and squeezed the message area to 24 px.
  - `/history`: New Chat, Open conversation and Continue current conversation are primary; Back, Refresh, Retry and Read saved conversation are secondary.
  - `/companion-scene`: the product controls moved from the bottom of the scrolling tools panel, where they were out of view, into a new `actions` row under the header. Retry avatar and Review companion selection are secondary.
  - Labels, `disabled` states, the "Please finish the safety check first." message and keyboard behaviour are unchanged.
- **3.**
  - Counts, board, check-in (form and chart) and calendar are now separate `neo-card`s with the page's heading style and 1.25 rem spacing, in that order, followed by the labelled previews.
  - Selects use `.neo-input`; Save check-in is primary; milestone buttons are secondary.
  - Chart series use `--neo-blue`, `--neo-coral` and `--neo-mint`. The calendar ramp runs from `--neo-gray` up through `--neo-blue`.
- **4.**
  - The report (disclaimer and article) and the prepared data-export preview sit in `.koi-paper`, under their controls card.
  - Print CSS forces a white page, flattens the paper and hides nav and `.no-print` controls. The export page's back button and controls are now `.no-print` too.

## Per-assertion results (`node scripts/verify-ui-fix.cjs`, final run on a freshly restarted dev server)

**233/233 PASS.** Raw output: `artifacts/ui-fix/verify-final.txt`.

| Item | Assertion | Result | Detail |
|---|---|---|---|
| 1 | 1280x800 header visible inside viewport | PASS | x=0 w=1280 h=64 |
| 1 | 1280x800 hero heading visible inside viewport | PASS | x=48 w=608 h=259 |
| 1 | 1280x800 primary CTA visible inside viewport | PASS | x=48 w=175 h=56 |
| 1 | 1280x800 footer visible inside viewport | PASS | x=0 w=1280 h=236 |
| 1 | 1280x800 feature cards (4) visible inside viewport | PASS |  |
| 1 | 1280x800 FAQ items (7) visible inside viewport | PASS |  |
| 1 | 1280x800 no horizontal scroll | PASS |  |
| 1 | 1280x800 theme stylesheet applied (CTA is a pill) | PASS |  |
| 1 | 1280x800 no console errors / page errors | PASS |  |
| 1 | 1280x800 CTA click issues the anonymous sign-in request | PASS |  |
| 1 | 1280x800 no errors after CTA click besides the aborted sign-up | PASS |  |
| 1 | 390x844 header visible inside viewport | PASS | x=0 w=390 h=64 |
| 1 | 390x844 hero heading visible inside viewport | PASS | x=24 w=342 h=130 |
| 1 | 390x844 primary CTA visible inside viewport | PASS | x=24 w=175 h=56 |
| 1 | 390x844 footer visible inside viewport | PASS | x=0 w=390 h=360 |
| 1 | 390x844 feature cards (4) visible inside viewport | PASS |  |
| 1 | 390x844 FAQ items (7) visible inside viewport | PASS |  |
| 1 | 390x844 no horizontal scroll | PASS |  |
| 1 | 390x844 theme stylesheet applied (CTA is a pill) | PASS |  |
| 1 | 390x844 no console errors / page errors | PASS |  |
| 1 | 390x844 CTA click issues the anonymous sign-in request | PASS |  |
| 1 | 390x844 no errors after CTA click besides the aborted sign-up | PASS |  |
| 1 | signed-out CTA sign-in ends at /onboarding or /chat (live at state creation 2026-10-18T22:28:57.655Z) | PASS | landed /onboarding |
| 1b | 1280x800 signed-in + onboarded at / lands on /chat | PASS | http://localhost:3000/chat |
| 1b | 1280x800 landing hero never in the DOM for signed-in visit | PASS | {"hero":false,"spinner":true,"spinnerFirst":true} |
| 1b | 1280x800 spinner shown first | PASS |  |
| 1b | 1280x800 Back from /chat returns to the previous page without bouncing | PASS | /about |
| 1b | 1280x800 /?home=1 keeps signed-in user on landing (hero, no redirect) | PASS | http://localhost:3000/?home=1 |
| 1b | 1280x800 "Open chat" button present with primary style | PASS |  |
| 1b | 1280x800 "Get Started" absent for signed-in user | PASS |  |
| 1b | 1280x800 "Open chat" opens /chat | PASS |  |
| 1b | 1280x800 top bar has Home -> /?home=1 | PASS |  |
| 1b | 1280x800 top bar logo does not bounce (href) | PASS |  |
| 1b | 1280x800 no console errors / page errors | PASS |  |
| 1b | 1280x800 signed-in, not onboarded at / goes to /onboarding | PASS | http://localhost:3000/onboarding |
| 1b | 390x844 signed-in + onboarded at / lands on /chat | PASS | http://localhost:3000/chat |
| 1b | 390x844 landing hero never in the DOM for signed-in visit | PASS | {"hero":false,"spinner":true,"spinnerFirst":true} |
| 1b | 390x844 spinner shown first | PASS |  |
| 1b | 390x844 Back from /chat returns to the previous page without bouncing | PASS | /about |
| 1b | 390x844 /?home=1 keeps signed-in user on landing (hero, no redirect) | PASS | http://localhost:3000/?home=1 |
| 1b | 390x844 "Open chat" button present with primary style | PASS |  |
| 1b | 390x844 "Get Started" absent for signed-in user | PASS |  |
| 1b | 390x844 "Open chat" opens /chat | PASS |  |
| 1b | 390x844 top bar has Home -> /?home=1 | PASS |  |
| 1b | 390x844 top bar logo does not bounce (href) | PASS |  |
| 1b | 390x844 no console errors / page errors | PASS |  |
| 1b | 390x844 signed-in, not onboarded at / goes to /onboarding | PASS | http://localhost:3000/onboarding |
| 2 | 1280x800 /chat "New Chat" uses neo button look | PASS | neo-btn-primary bg=rgb(45, 99, 235) shadow=rgb(0, 0, 0) 4px 4px 0px 0px |
| 2 | 1280x800 /chat "New Chat" inside viewport, below nav, not covered | PASS | y=86 nav=82 x=16 w=109 covered=false |
| 2 | 1280x800 /chat "New Chat" visible focus outline when tabbed to | PASS |  |
| 2 | 1280x800 /chat "Complete Conversation" uses neo button look | PASS | neo-btn-secondary bg=rgb(255, 209, 0) shadow=rgb(0, 0, 0) 4px 4px 0px 0px |
| 2 | 1280x800 /chat "Complete Conversation" inside viewport, below nav, not covered | PASS | y=86 nav=82 x=137 w=203 covered=false |
| 2 | 1280x800 /chat "Complete Conversation" visible focus outline when tabbed to | PASS |  |
| 2 | 1280x800 /chat "Change companion" uses neo button look | PASS | neo-btn-secondary bg=rgb(255, 209, 0) shadow=rgb(0, 0, 0) 4px 4px 0px 0px |
| 2 | 1280x800 /chat "Change companion" inside viewport, below nav, not covered | PASS | y=86 nav=82 x=352 w=174 covered=false |
| 2 | 1280x800 /chat "Change companion" visible focus outline when tabbed to | PASS |  |
| 2 | 1280x800 /chat "Open avatar conversation" uses neo button look | PASS | neo-btn-secondary bg=rgb(255, 209, 0) shadow=rgb(0, 0, 0) 4px 4px 0px 0px |
| 2 | 1280x800 /chat "Open avatar conversation" inside viewport, below nav, not covered | PASS | y=86 nav=82 x=538 w=244 covered=false |
| 2 | 1280x800 /chat "Open avatar conversation" visible focus outline when tabbed to | PASS |  |
| 2 | 1280x800 /chat "Browse saved history" uses neo button look | PASS | neo-btn-secondary bg=rgb(255, 209, 0) shadow=rgb(0, 0, 0) 4px 4px 0px 0px |
| 2 | 1280x800 /chat "Browse saved history" inside viewport, below nav, not covered | PASS | y=140 nav=82 x=16 w=190 covered=false |
| 2 | 1280x800 /chat "Browse saved history" visible focus outline when tabbed to | PASS |  |
| 2 | 1280x800 /chat no horizontal scroll | PASS |  |
| 2 | 1280x800 /chat details "Save completion" uses neo button look | PASS | neo-btn-primary bg=rgb(45, 99, 235) shadow=rgb(0, 0, 0) 4px 4px 0px 0px |
| 2 | 1280x800 /chat details "Save completion" inside viewport, below nav, not covered | PASS | y=345 nav=82 x=34 w=156 covered=false |
| 2 | 1280x800 /chat details "Save completion" disabled state exposed (disabled/aria-disabled) | PASS |  |
| 2 | 1280x800 /chat details no horizontal scroll | PASS |  |
| 2 | 1280x800 /history "Back to current chat" uses neo button look | PASS | neo-btn-secondary bg=rgb(255, 209, 0) shadow=rgb(0, 0, 0) 4px 4px 0px 0px |
| 2 | 1280x800 /history "Back to current chat" inside viewport, below nav, not covered | PASS | y=90 nav=82 x=280 w=182 covered=false |
| 2 | 1280x800 /history "Back to current chat" visible focus outline when tabbed to | PASS |  |
| 2 | 1280x800 /history "New Chat" uses neo button look | PASS | neo-btn-primary bg=rgb(45, 99, 235) shadow=rgb(0, 0, 0) 4px 4px 0px 0px |
| 2 | 1280x800 /history "New Chat" inside viewport, below nav, not covered | PASS | y=210 nav=82 x=280 w=136 covered=false |
| 2 | 1280x800 /history "New Chat" visible focus outline when tabbed to | PASS |  |
| 2 | 1280x800 /history "Refresh saved history" uses neo button look | PASS | neo-btn-secondary bg=rgb(255, 209, 0) shadow=rgb(0, 0, 0) 4px 4px 0px 0px |
| 2 | 1280x800 /history "Refresh saved history" inside viewport, below nav, not covered | PASS | y=486 nav=82 x=280 w=192 covered=false |
| 2 | 1280x800 /history "Refresh saved history" visible focus outline when tabbed to | PASS |  |
| 2 | 1280x800 /history "Read saved conversation" uses neo button look | PASS | neo-btn-secondary bg=rgb(255, 209, 0) shadow=rgb(0, 0, 0) 4px 4px 0px 0px |
| 2 | 1280x800 /history "Read saved conversation" inside viewport, below nav, not covered | PASS | y=664 nav=82 x=302 w=214 covered=false |
| 2 | 1280x800 /history "Read saved conversation" disabled state exposed (disabled/aria-disabled) | PASS |  |
| 2 | 1280x800 /history "Continue current conversation" uses neo button look | PASS | neo-btn-primary bg=rgb(45, 99, 235) shadow=rgb(0, 0, 0) 4px 4px 0px 0px |
| 2 | 1280x800 /history "Continue current conversation" inside viewport, below nav, not covered | PASS | y=664 nav=82 x=528 w=252 covered=false |
| 2 | 1280x800 /history "Continue current conversation" visible focus outline when tabbed to | PASS |  |
| 2 | 1280x800 /history no horizontal scroll | PASS |  |
| 2 | 1280x800 /companion-scene "New Chat" uses neo button look | PASS | neo-btn-primary bg=rgb(45, 99, 235) shadow=rgb(0, 0, 0) 4px 4px 0px 0px |
| 2 | 1280x800 /companion-scene "New Chat" inside viewport, below nav, not covered | PASS | y=136 nav=82 x=28 w=109 covered=false |
| 2 | 1280x800 /companion-scene "New Chat" visible focus outline when tabbed to | PASS |  |
| 2 | 1280x800 /companion-scene "Complete Conversation" uses neo button look | PASS | neo-btn-secondary bg=rgb(255, 209, 0) shadow=rgb(0, 0, 0) 4px 4px 0px 0px |
| 2 | 1280x800 /companion-scene "Complete Conversation" inside viewport, below nav, not covered | PASS | y=136 nav=82 x=149 w=203 covered=false |
| 2 | 1280x800 /companion-scene "Complete Conversation" visible focus outline when tabbed to | PASS |  |
| 2 | 1280x800 /companion-scene "Change companion" uses neo button look | PASS | neo-btn-secondary bg=rgb(255, 209, 0) shadow=rgb(0, 0, 0) 4px 4px 0px 0px |
| 2 | 1280x800 /companion-scene "Change companion" inside viewport, below nav, not covered | PASS | y=136 nav=82 x=364 w=174 covered=false |
| 2 | 1280x800 /companion-scene "Change companion" visible focus outline when tabbed to | PASS |  |
| 2 | 1280x800 /companion-scene no horizontal scroll | PASS |  |
| 2 | 1280x800 no console errors / page errors on /chat, /history, /companion-scene | PASS |  |
| 2 | 390x844 /chat "New Chat" uses neo button look | PASS | neo-btn-primary bg=rgb(45, 99, 235) shadow=rgb(0, 0, 0) 4px 4px 0px 0px |
| 2 | 390x844 /chat "New Chat" inside viewport, below nav, not covered | PASS | y=316 nav=74 x=16 w=96 covered=false |
| 2 | 390x844 /chat "New Chat" visible focus outline when tabbed to | PASS |  |
| 2 | 390x844 /chat "Complete Conversation" uses neo button look | PASS | neo-btn-secondary bg=rgb(255, 209, 0) shadow=rgb(0, 0, 0) 4px 4px 0px 0px |
| 2 | 390x844 /chat "Complete Conversation" inside viewport, below nav, not covered | PASS | y=316 nav=74 x=124 w=184 covered=false |
| 2 | 390x844 /chat "Complete Conversation" visible focus outline when tabbed to | PASS |  |
| 2 | 390x844 /chat "Change companion" uses neo button look | PASS | neo-btn-secondary bg=rgb(255, 209, 0) shadow=rgb(0, 0, 0) 4px 4px 0px 0px |
| 2 | 390x844 /chat "Change companion" inside viewport, below nav, not covered | PASS | y=370 nav=74 x=16 w=157 covered=false |
| 2 | 390x844 /chat "Change companion" visible focus outline when tabbed to | PASS |  |
| 2 | 390x844 /chat "Open avatar conversation" uses neo button look | PASS | neo-btn-secondary bg=rgb(255, 209, 0) shadow=rgb(0, 0, 0) 4px 4px 0px 0px |
| 2 | 390x844 /chat "Open avatar conversation" inside viewport, below nav, not covered | PASS | y=424 nav=74 x=16 w=224 covered=false |
| 2 | 390x844 /chat "Open avatar conversation" visible focus outline when tabbed to | PASS |  |
| 2 | 390x844 /chat "Browse saved history" uses neo button look | PASS | neo-btn-secondary bg=rgb(255, 209, 0) shadow=rgb(0, 0, 0) 4px 4px 0px 0px |
| 2 | 390x844 /chat "Browse saved history" inside viewport, below nav, not covered | PASS | y=478 nav=74 x=16 w=172 covered=false |
| 2 | 390x844 /chat "Browse saved history" visible focus outline when tabbed to | PASS |  |
| 2 | 390x844 /chat no horizontal scroll | PASS |  |
| 2 | 390x844 /chat details "Save completion" uses neo button look | PASS | neo-btn-primary bg=rgb(45, 99, 235) shadow=rgb(0, 0, 0) 4px 4px 0px 0px |
| 2 | 390x844 /chat details "Save completion" inside viewport, below nav, not covered | PASS | y=494 nav=74 x=34 w=140 covered=false |
| 2 | 390x844 /chat details "Save completion" disabled state exposed (disabled/aria-disabled) | PASS |  |
| 2 | 390x844 /chat details no horizontal scroll | PASS |  |
| 2 | 390x844 /history "Back to current chat" uses neo button look | PASS | neo-btn-secondary bg=rgb(255, 209, 0) shadow=rgb(0, 0, 0) 4px 4px 0px 0px |
| 2 | 390x844 /history "Back to current chat" inside viewport, below nav, not covered | PASS | y=90 nav=74 x=24 w=164 covered=false |
| 2 | 390x844 /history "Back to current chat" visible focus outline when tabbed to | PASS |  |
| 2 | 390x844 /history "New Chat" uses neo button look | PASS | neo-btn-primary bg=rgb(45, 99, 235) shadow=rgb(0, 0, 0) 4px 4px 0px 0px |
| 2 | 390x844 /history "New Chat" inside viewport, below nav, not covered | PASS | y=210 nav=74 x=24 w=136 covered=false |
| 2 | 390x844 /history "New Chat" visible focus outline when tabbed to | PASS |  |
| 2 | 390x844 /history "Refresh saved history" uses neo button look | PASS | neo-btn-secondary bg=rgb(255, 209, 0) shadow=rgb(0, 0, 0) 4px 4px 0px 0px |
| 2 | 390x844 /history "Refresh saved history" inside viewport, below nav, not covered | PASS | y=498 nav=74 x=24 w=174 covered=false |
| 2 | 390x844 /history "Refresh saved history" visible focus outline when tabbed to | PASS |  |
| 2 | 390x844 /history "Read saved conversation" uses neo button look | PASS | neo-btn-secondary bg=rgb(255, 209, 0) shadow=rgb(0, 0, 0) 4px 4px 0px 0px |
| 2 | 390x844 /history "Read saved conversation" inside viewport, below nav, not covered | PASS | y=702 nav=74 x=46 w=194 covered=false |
| 2 | 390x844 /history "Read saved conversation" disabled state exposed (disabled/aria-disabled) | PASS |  |
| 2 | 390x844 /history "Continue current conversation" uses neo button look | PASS | neo-btn-primary bg=rgb(45, 99, 235) shadow=rgb(0, 0, 0) 4px 4px 0px 0px |
| 2 | 390x844 /history "Continue current conversation" inside viewport, below nav, not covered | PASS | y=750 nav=74 x=46 w=229 covered=false |
| 2 | 390x844 /history "Continue current conversation" visible focus outline when tabbed to | PASS |  |
| 2 | 390x844 /history no horizontal scroll | PASS |  |
| 2 | 390x844 /companion-scene "New Chat" uses neo button look | PASS | neo-btn-primary bg=rgb(45, 99, 235) shadow=rgb(0, 0, 0) 4px 4px 0px 0px |
| 2 | 390x844 /companion-scene "New Chat" inside viewport, below nav, not covered | PASS | y=122 nav=74 x=14 w=96 covered=false |
| 2 | 390x844 /companion-scene "New Chat" visible focus outline when tabbed to | PASS |  |
| 2 | 390x844 /companion-scene "Complete Conversation" uses neo button look | PASS | neo-btn-secondary bg=rgb(255, 209, 0) shadow=rgb(0, 0, 0) 4px 4px 0px 0px |
| 2 | 390x844 /companion-scene "Complete Conversation" inside viewport, below nav, not covered | PASS | y=122 nav=74 x=122 w=184 covered=false |
| 2 | 390x844 /companion-scene "Complete Conversation" visible focus outline when tabbed to | PASS |  |
| 2 | 390x844 /companion-scene "Change companion" uses neo button look | PASS | neo-btn-secondary bg=rgb(255, 209, 0) shadow=rgb(0, 0, 0) 4px 4px 0px 0px |
| 2 | 390x844 /companion-scene "Change companion" inside viewport, below nav, not covered | PASS | y=176 nav=74 x=14 w=157 covered=false |
| 2 | 390x844 /companion-scene "Change companion" visible focus outline when tabbed to | PASS |  |
| 2 | 390x844 /companion-scene no horizontal scroll | PASS |  |
| 2 | 390x844 no console errors / page errors on /chat, /history, /companion-scene | PASS |  |
| 3 | 1280x800 reference Progress card found | PASS | {"radius":"20px","border":"2px solid rgb(0, 0, 0)","shadow":"rgb(0, 0, 0) 6px 6px 0px 0… |
| 3 | 1280x800 counts card radius/border/shadow/background equal existing card | PASS | 20px \| 2px solid rgb(0, 0, 0) \| rgb(0, 0, 0) 6px 6px 0px 0px \| rgb(255, 255, 255) |
| 3 | 1280x800 counts heading style equals existing card heading | PASS | 800 17.6px -0.352px vs 800 17.6px -0.352px |
| 3 | 1280x800 counts font family equals the page's | PASS | "DM Sans", system-ui, sans-serif |
| 3 | 1280x800 counts no element overflows the card | PASS |  |
| 3 | 1280x800 counts card inside viewport width | PASS | 424..856 |
| 3 | 1280x800 recorded board card radius/border/shadow/background equal existing card | PASS | 20px \| 2px solid rgb(0, 0, 0) \| rgb(0, 0, 0) 6px 6px 0px 0px \| rgb(255, 255, 255) |
| 3 | 1280x800 recorded board heading style equals existing card heading | PASS | 800 17.6px -0.352px vs 800 17.6px -0.352px |
| 3 | 1280x800 recorded board font family equals the page's | PASS | "DM Sans", system-ui, sans-serif |
| 3 | 1280x800 recorded board no element overflows the card | PASS |  |
| 3 | 1280x800 recorded board card inside viewport width | PASS | 424..856 |
| 3 | 1280x800 check-in (form + chart) card radius/border/shadow/background equal existing card | PASS | 20px \| 2px solid rgb(0, 0, 0) \| rgb(0, 0, 0) 6px 6px 0px 0px \| rgb(255, 255, 255) |
| 3 | 1280x800 check-in (form + chart) heading style equals existing card heading | PASS | 800 17.6px -0.352px vs 800 17.6px -0.352px |
| 3 | 1280x800 check-in (form + chart) font family equals the page's | PASS | "DM Sans", system-ui, sans-serif |
| 3 | 1280x800 check-in (form + chart) no element overflows the card | PASS |  |
| 3 | 1280x800 check-in (form + chart) card inside viewport width | PASS | 424..856 |
| 3 | 1280x800 activity calendar card radius/border/shadow/background equal existing card | PASS | 20px \| 2px solid rgb(0, 0, 0) \| rgb(0, 0, 0) 6px 6px 0px 0px \| rgb(255, 255, 255) |
| 3 | 1280x800 activity calendar heading style equals existing card heading | PASS | 800 17.6px -0.352px vs 800 17.6px -0.352px |
| 3 | 1280x800 activity calendar font family equals the page's | PASS | "DM Sans", system-ui, sans-serif |
| 3 | 1280x800 activity calendar no element overflows the card | PASS |  |
| 3 | 1280x800 activity calendar card inside viewport width | PASS | 424..856 |
| 3 | 1280x800 order: counts, board, check-in, calendar, previews | PASS | 697 < 1180 < 2253 < 2936 < 3123 |
| 3 | 1280x800 check-in selects use .neo-input | PASS |  |
| 3 | 1280x800 Save check-in uses .neo-btn-primary | PASS |  |
| 3 | 1280x800 chart/calendar colours come from the theme palette (no data drawn yet) | PASS |  |
| 3 | 1280x800 /progress no horizontal scroll | PASS |  |
| 3 | 1280x800 /progress no console errors / page errors | PASS |  |
| 3 | 390x844 reference Progress card found | PASS | {"radius":"20px","border":"2px solid rgb(0, 0, 0)","shadow":"rgb(0, 0, 0) 6px 6px 0px 0… |
| 3 | 390x844 counts card radius/border/shadow/background equal existing card | PASS | 20px \| 2px solid rgb(0, 0, 0) \| rgb(0, 0, 0) 6px 6px 0px 0px \| rgb(255, 255, 255) |
| 3 | 390x844 counts heading style equals existing card heading | PASS | 800 17.6px -0.352px vs 800 17.6px -0.352px |
| 3 | 390x844 counts font family equals the page's | PASS | "DM Sans", system-ui, sans-serif |
| 3 | 390x844 counts no element overflows the card | PASS |  |
| 3 | 390x844 counts card inside viewport width | PASS | 24..366 |
| 3 | 390x844 recorded board card radius/border/shadow/background equal existing card | PASS | 20px \| 2px solid rgb(0, 0, 0) \| rgb(0, 0, 0) 6px 6px 0px 0px \| rgb(255, 255, 255) |
| 3 | 390x844 recorded board heading style equals existing card heading | PASS | 800 17.6px -0.352px vs 800 17.6px -0.352px |
| 3 | 390x844 recorded board font family equals the page's | PASS | "DM Sans", system-ui, sans-serif |
| 3 | 390x844 recorded board no element overflows the card | PASS |  |
| 3 | 390x844 recorded board card inside viewport width | PASS | 24..366 |
| 3 | 390x844 check-in (form + chart) card radius/border/shadow/background equal existing card | PASS | 20px \| 2px solid rgb(0, 0, 0) \| rgb(0, 0, 0) 6px 6px 0px 0px \| rgb(255, 255, 255) |
| 3 | 390x844 check-in (form + chart) heading style equals existing card heading | PASS | 800 17.6px -0.352px vs 800 17.6px -0.352px |
| 3 | 390x844 check-in (form + chart) font family equals the page's | PASS | "DM Sans", system-ui, sans-serif |
| 3 | 390x844 check-in (form + chart) no element overflows the card | PASS |  |
| 3 | 390x844 check-in (form + chart) card inside viewport width | PASS | 24..366 |
| 3 | 390x844 activity calendar card radius/border/shadow/background equal existing card | PASS | 20px \| 2px solid rgb(0, 0, 0) \| rgb(0, 0, 0) 6px 6px 0px 0px \| rgb(255, 255, 255) |
| 3 | 390x844 activity calendar heading style equals existing card heading | PASS | 800 17.6px -0.352px vs 800 17.6px -0.352px |
| 3 | 390x844 activity calendar font family equals the page's | PASS | "DM Sans", system-ui, sans-serif |
| 3 | 390x844 activity calendar no element overflows the card | PASS |  |
| 3 | 390x844 activity calendar card inside viewport width | PASS | 24..366 |
| 3 | 390x844 order: counts, board, check-in, calendar, previews | PASS | 718 < 1221 < 2338 < 3101 < 3308 |
| 3 | 390x844 check-in selects use .neo-input | PASS |  |
| 3 | 390x844 Save check-in uses .neo-btn-primary | PASS |  |
| 3 | 390x844 chart/calendar colours come from the theme palette (no data drawn yet) | PASS |  |
| 3 | 390x844 /progress no horizontal scroll | PASS |  |
| 3 | 390x844 /progress no console errors / page errors | PASS |  |
| 4 | 1280x800 /settings/report paper container carries .koi-paper | PASS |  |
| 4 | 1280x800 /settings/report paper background is white and every text run inside sits on white | PASS | rgb(255, 255, 255) |
| 4 | 1280x800 /settings/report sampled pixels inside the capsule are white | PASS | [[255,255,255],[255,255,255],[255,255,255]] |
| 4 | 1280x800 /settings/report sampled pixel outside the capsule is the page colour | PASS | [255,229,217] vs [255,229,217] |
| 4 | 1280x800 /settings/report print: nav hidden | PASS |  |
| 4 | 1280x800 /settings/report print: controls hidden | PASS |  |
| 4 | 1280x800 /settings/report print: page background white | PASS | rgb(255, 255, 255) [[255,255,255],[255,255,255]] |
| 4 | 1280x800 /settings/report controls card (range, titles, print) sits above the paper | PASS |  |
| 4 | 1280x800 /settings/report no horizontal scroll | PASS |  |
| 4 | 1280x800 /settings/export paper container carries .koi-paper | PASS |  |
| 4 | 1280x800 /settings/export paper background is white and every text run inside sits on white | PASS | rgb(255, 255, 255) |
| 4 | 1280x800 /settings/export sampled pixels inside the capsule are white | PASS | [[255,255,255],[255,255,255],[255,255,255],[255,255,255]] |
| 4 | 1280x800 /settings/export sampled pixel outside the capsule is the page colour | PASS | [255,229,217] vs [255,229,217] |
| 4 | 1280x800 /settings/export print: nav hidden | PASS |  |
| 4 | 1280x800 /settings/export print: controls hidden | PASS |  |
| 4 | 1280x800 /settings/export print: page background white | PASS | rgb(255, 255, 255) [[255,255,255],[255,255,255]] |
| 4 | 1280x800 /settings/export controls card (consent, prepare, download) sits above the preview paper | PASS |  |
| 4 | 1280x800 /settings/export no horizontal scroll | PASS |  |
| 4 | 1280x800 export/report no console errors / page errors | PASS |  |
| 4 | 390x844 /settings/report paper container carries .koi-paper | PASS |  |
| 4 | 390x844 /settings/report paper background is white and every text run inside sits on white | PASS | rgb(255, 255, 255) |
| 4 | 390x844 /settings/report sampled pixels inside the capsule are white | PASS | [[255,255,255],[255,255,255],[255,255,255]] |
| 4 | 390x844 /settings/report sampled pixel outside the capsule is the page colour | PASS | [255,229,217] vs [255,229,217] |
| 4 | 390x844 /settings/report print: nav hidden | PASS |  |
| 4 | 390x844 /settings/report print: controls hidden | PASS |  |
| 4 | 390x844 /settings/report print: page background white | PASS | rgb(255, 255, 255) [[255,255,255],[255,255,255]] |
| 4 | 390x844 /settings/report controls card (range, titles, print) sits above the paper | PASS |  |
| 4 | 390x844 /settings/report no horizontal scroll | PASS |  |
| 4 | 390x844 /settings/export paper container carries .koi-paper | PASS |  |
| 4 | 390x844 /settings/export paper background is white and every text run inside sits on white | PASS | rgb(255, 255, 255) |
| 4 | 390x844 /settings/export sampled pixels inside the capsule are white | PASS | [[255,255,255],[255,255,255],[255,255,255],[255,255,255]] |
| 4 | 390x844 /settings/export sampled pixel outside the capsule is the page colour | PASS | [255,229,217] vs [255,229,217] |
| 4 | 390x844 /settings/export print: nav hidden | PASS |  |
| 4 | 390x844 /settings/export print: controls hidden | PASS |  |
| 4 | 390x844 /settings/export print: page background white | PASS | rgb(255, 255, 255) [[255,255,255],[255,255,255]] |
| 4 | 390x844 /settings/export controls card (consent, prepare, download) sits above the preview paper | PASS |  |
| 4 | 390x844 /settings/export no horizontal scroll | PASS |  |
| 4 | 390x844 export/report no console errors / page errors | PASS |  |

## Tests and build

- `npx jest`: **62 suites, 546 tests, all passed**. The baseline was 537 tests. New: `landing-render` (2 tests), `landing-auth-states` (5) and `progress-theme` (2). Assertions were added to `history-page`, `wellness-report` and `ciphertext-export-ui`. No existing assertion had to change.
- `npx tsc --noEmit --incremental false`: pass.
- `npm run build`: pass, Next 14.2.35, 20/20 static pages, `BUILD_ID loLMPMmVGFbFs0Yyab1eb`. It was built while the dev server was running, which shows the item 1 fix.
- `git diff --check 223e97c HEAD -- . ':!review'` and on the working tree: clean.

## Screenshots (`artifacts/ui-fix/`, git-ignored)

- **Before:** `1-landing-{1280x800,390x844}-before.png`, `1-landing-broken-repro-1280x800-before.png`, `1b-signed-in-root-{…}-before.png`, `2-{chat,history,companion-scene}-{…}-before.png`, `3-progress-{…}-before.png`, `4-settings-{export,report}-{…}-before.png`, `6-{landing,chat,history,companion-scene,progress,settings-export,settings-report}-{…}-before.png`.
- **After:** `1-landing-{…}-after.png`, `1b-{signed-in-root,home1,topbar}-{…}-after.png`, `2-{chat,history,companion-scene}-{…}-after.png`, `2-chat-details-{…}-after.png`, `2-history-state-{…}-after.png`, `3-progress-{…}-after.png`, `3-progress-checkin-card-1280x800-after.png`, `4-settings-{export,report}-{…}-after.png`, `4-settings-export-preview-{…}-after.png`, `4-settings{export,report}-print-{…}.png`, `6-{landing,chat,history,companion-scene,progress,settings-export,settings-report}-{…}-after.png`.

`{…}` means both `1280x800` and `390x844`.

## What the final screenshots show

- `6-landing-1280x800-after`: the full landing page (header, hero with "Start Talking", colour grid, four feature cards, seven FAQ rows, both CTA panels, footer) renders styled, with no overlap.
- `6-landing-390x844-after`: the same sections stack in one column inside the 390 px width, with no horizontal scroll and no clipped text.
- `6-chat-1280x800-after`: five neo pills (blue New Chat, four yellow) form one row plus a wrap, under the nav and clear of it, above the hero and the avatar card.
- `6-chat-390x844-after`: a 230 px avatar card, the pills wrapped in three tidy rows, the status line, then the hero text and the input. Nothing overlaps.
- `6-history-1280x800-after`: yellow Back and Refresh pills and a blue New Chat; the card holds a disabled pale-yellow "Read saved conversation" and a blue "Continue current conversation".
- `6-history-390x844-after`: the same controls stack inside the 390 px column, all on the pink background or the white card, none under the nav.
- `6-companion-scene-1280x800-after`: New Chat, Complete Conversation and Change companion sit as a pill row under "Raza / Avatar conversation", above the avatar stage. The tools panel is unchanged.
- `6-companion-scene-390x844-after`: the pills wrap into two rows under the header; the avatar stage and tools panel follow. The End-session button is partly below the panel's scroll edge, as it was before.
- `6-progress-1280x800-after`: counts tiles, the "Your saved activity" card, the board, the check-in card (full-width selects with chevrons, blue Save, pill range toggles) and the calendar card share one card style, followed by "Design previews".
- `6-progress-390x844-after`: the same card sequence in one column with identical borders and shadows, and no overflow.
- `6-settings-export-1280x800-after`: unchanged cards (export, Wellness Report, yellow backup notice) on the pink page. The prepared-preview paper appears only after "Prepare" (`4-settings-export-preview-1280x800-after`: a white paper under the export card).
- `6-settings-export-390x844-after`: the same cards in one column with the disabled pale-blue Prepare button.
- `6-settings-report-1280x800-after`: the options card (dates, titles checkbox, Print / Save as PDF) sits above a white paper holding the disclaimer box, period, Check-ins and Activities, and the footer note.
- `6-settings-report-390x844-after`: the same at mobile width, with all report text on white.
- `4-settingsreport-print-1280x800`: print view, a plain white page with the title and report only; no nav, buttons or card chrome.

## Not fixed, or verified indirectly

1. **"Open conversation" (history)** renders only for an archived conversation with messages, and the rules allow no chat messages. Its `neo-btn-primary` class is asserted in `src/__tests__/history-page.test.tsx`, not in the browser.
2. **"Please finish the safety check first."** needs an open crisis handoff, which cannot be triggered without chat. The markup is unchanged apart from spacing, and it is covered by existing jest suites.
3. **Chart and calendar colours**: the synthetic account has no check-ins or activity, so the browser check finds nothing drawn. `src/__tests__/progress-theme.test.tsx` renders both with data and asserts theme colours only.
4. **Export preview**: for this account, "Prepare" returns "The encrypted conversation snapshot is not available yet…". The paper shows that status, and the "Prepared … / Download" state is covered by jest.
5. **Dev image optimizer stall**: once, the dev server's `/_next/image` webp encode for `Male.png` at `w=256` hung (curl timed out after 120 s with a webp Accept header), so the 390 px chat avatar stayed blank. Restarting the dev server fixed it (0.2 s), and the final 390 px chat shot shows the avatar. This is environmental, not page code.
6. **Mobile scroll clipping (left as is):**
   - At 390 px, the companion-scene End-session button sits partly below the scrolling tools panel's edge. This was the same before.
   - With "Complete Conversation" details open on mobile chat, the empty-state hero scrolls inside the message log. This is scroll clipping, not overlap.
7. **Anonymous accounts**: three synthetic anonymous accounts were created instead of one. The first onboarding script crashed on a checkbox selector after sign-in; the second produced the BEFORE shots; the third was created by `verify-ui-fix.cjs` and reused for all later runs. Later CTA checks record the sign-up request and abort it. Its saved storage state is `artifacts/ui-fix/.auth-state.json` (git-ignored; it holds that account's auth tokens and can be deleted).
8. **Dev server**: port 3000 was down at the start, so I started one in the background. It restarted itself once when `next.config.js` changed, and I restarted it once for item 5 above. It is stopped at the end of this task. Dev output now lives in `.next-dev/`.
