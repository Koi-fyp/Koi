# avatar_bundle

Builds Fatima's real VRM avatar host (`/avatar-host` on
`feat/avatar-webview-host`, commit `223e97c`) into a static page the app ships
inside the APK: `../assets/avatar_local/` (`index.html`, `avatar.js`,
`avatar.css`, `models/`). The app serves those files from a loopback-only Dart
server (`lib/avatar/local_avatar_server.dart`) when built with
`--dart-define=KOI_AVATAR_URL=local`.

The built output is committed, so normal Flutter builds don't need Node.

## Sources

- `src/components/avatar/*`, `src/lib/speech/mouthCues.ts`: copied unchanged
  from `repos/koi-backend/nextjs_app/src/...` at `223e97c`, plus a two-line
  header. Don't edit them here: change them upstream and re-copy
  (`test/avatar/local_avatar_assets_test.dart` checks they still match).
- `src/main.tsx`: stands in for `app/avatar-host/page.tsx` (reads
  `?model=male|female`, mounts `AvatarWebViewHost`), plus a guarded
  `Object.hasOwn` polyfill for WebViews older than Chromium 93.
- `src/index.html`: stands in for `app/avatar-host/layout.tsx` (viewport) and
  the page metadata; its CSP keeps every request on the local origin.
- `src/base.css`: the root layout's html/body background, height and margin.
- `../assets/avatar_local/models/koi-male.vrm` and `koi-female.vrm`: byte-for-byte
  copies of `nextjs_app/public/models/` at `223e97c` (git blobs `07c30ad8…` and
  `0999b8e3…`; the asset test checks the hashes).

Not copied: `AvatarAnimator.ts` (only the old `AvatarRenderer.tsx` uses it),
Next.js layouts, `AppAuthBoundary`, `globals.css`.

## Build

```
bash build.sh
```

Runs `npm ci` (exact versions in `package.json` / `package-lock.json`: react
18.3.1, three 0.180.0, @pixiv/three-vrm 3.5.5 — the same as the web app —
and esbuild) and bundles to `../assets/avatar_local/`. `node_modules/` stays in
this folder (ignored); npm's cache goes to `D:\DevCache\npm-cache` when that
folder exists.
