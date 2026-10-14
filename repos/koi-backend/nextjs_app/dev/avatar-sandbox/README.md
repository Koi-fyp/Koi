# KOI avatar development viewer

From `repos/koi-backend/nextjs_app`, run `npm run dev:avatar` and open
http://127.0.0.1:3001/companion-scene.

This harness uses the canonical package/node_modules and shared
`src/components/avatar/VRMAvatarRenderer.tsx`. There is no second package,
AuthProvider, backend client, private data, camera or microphone integration.
The allowlisted `/models` handler reads the original `public/models/*.vrm`
files; assets are not copied. The original viewer loads the male model; the mock conversation preview can switch between male and female models.

The launcher binds to loopback and refuses a non-development NODE_ENV.
Next configuration rejects production build/start phases; layout and asset
handler also enforce development mode. The production application's src/app
has no sandbox route. Do not deploy this directory or run a development server
as a production service.

Run `npm run typecheck:avatar` for the isolated harness/shared renderer check.
`npm run build` remains the existing production build and may require Firebase
configuration and repairs to existing unrelated source errors.

Browser verification: with the sandbox running, execute
`node scripts/verify-avatar.cjs`. If Playwright's expected browser is unavailable,
set `KOI_AVATAR_BROWSER` to an existing Chromium executable. On this computer:

```powershell
$env:KOI_AVATAR_BROWSER='C:/Users/PMYLS/AppData/Local/ms-playwright/chromium-1243/chrome-win64/chrome.exe'
node scripts/verify-avatar.cjs
```

Screenshots and results are written to `.next/verification` in this harness
(ignored build artifacts). The check covers binary asset delivery, rendering,
resize, SPA cleanup, reload, failure/retry, local-only requests and production
guards. The browser check uses software WebGL; physical-device/GPU performance
and Flutter WebView behavior remain unverified.

Both supplied exports were inspected as GLB 2 containers with VRM 1.0 metadata:
- Male: 15,353,876 bytes.
- Female: 16,070,892 bytes (browser-rendered in Increment 3).
- Presets on both: neutral, happy, angry, sad, relaxed, surprised, aa, ih, ou,
  ee, oh, blink, blinkLeft, blinkRight. No custom expressions declared.
- MToon and spring-bone extensions present; no expression controller added.

## Increment 3 conversation UI

Open http://127.0.0.1:3001/companion-scene for the development-only mock
conversation. The original Increment 2 viewer is preserved at
http://127.0.0.1:3001/avatar-viewer.

The new canonical `src/components/companion` components receive presentation
props and callbacks, without Firebase, backend or media services. The mock
messages and local model/language selector are confined to the development
harness. No messages are sent or saved. Microphone and camera controls are
disabled. Back and End return home and unmount the avatar.

Desktop uses a collapsible side transcript; mobile uses a bounded panel below
the avatar. Subtitles stay below the WebGL canvas, accept text updates and
support English/Urdu with automatic text direction. The conversation screen
caps pixel ratio at 1.5; the original viewer keeps its previous default.

Run `node scripts/verify-companion-ui.cjs` using the browser configuration above.
The UI tests cover desktop/mobile/short viewports, English/Urdu, panel toggles,
keyboard focus and Escape, male/female switching, end/back cleanup, disabled
media controls, no user video, zero media calls and no external/backend requests.
Screenshots/results are under `.next/verification/increment-3`.

The female selector is a sandbox preview, not production selection integration.
No facial animation, speech, lip sync, inference or camera processing is added.
The existing full-application html2pdf.js and unrelated TypeScript failures
remain outside this increment.
