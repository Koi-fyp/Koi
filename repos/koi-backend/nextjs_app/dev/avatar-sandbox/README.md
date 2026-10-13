# KOI avatar development viewer

From `repos/koi-backend/nextjs_app`, run `npm run dev:avatar` and open
http://127.0.0.1:3001/companion-scene.

This harness uses the canonical package/node_modules and shared
`src/components/avatar/VRMAvatarRenderer.tsx`. There is no second package,
AuthProvider, backend client, private data, camera or microphone integration.
The allowlisted `/models` handler reads the original `public/models/*.vrm`
files; assets are not copied. Only the male model is loaded by the viewer.

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
- Female: 16,070,892 bytes (not browser-rendered in this increment).
- Presets on both: neutral, happy, angry, sad, relaxed, surprised, aa, ih, ou,
  ee, oh, blink, blinkLeft, blinkRight. No custom expressions declared.
- MToon and spring-bone extensions present; no expression controller added.
