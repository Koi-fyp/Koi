# Presentation-only avatar host

Production route: `/avatar-host`. It renders only the existing local male/female
VRM files through `VRMAvatarRenderer` and the existing `VRMAvatarController`.
Use `/avatar-host?model=male` or `/avatar-host?model=female`; the default and
any unknown model value select the male model. The only model URLs are
`/models/koi-male.vrm` and `/models/koi-female.vrm`. The host has no model
selector, loading/status text, retry UI, chat, or user data. Flutter owns model
selection and its loading/error fallback. If the renderer fails, no ready
message is emitted; Flutter should use its own bounded fallback timeout.

Static fallback images are `public/Male.png` and `public/Female.png`. Each was
captured from `/avatar-host?model=male|female` after the corresponding real VRM
reported ready. Both are 491x525 and use the same solid background (`#FFC224`);
they are renderer screenshots, not illustrations or generated substitutes.

The renderer-only host uses system fonts. The rest of the application retains
its existing Google typography, loaded only on non-host routes. The host does
not apply the global external-image background classes; the browser test checks
that it makes no HTTP requests outside the configured host origin.

The root `AppAuthBoundary` omits `AuthProvider` only at this exact route. All
other routes still render through the same Firebase provider; the authenticated
layout and its guards are unchanged. The host does not load conversation,
Firestore, crisis, microphone, camera, or local voice-worker services. The
development sandbox remains development-only.

## JavaScript contract

When the current VRM controller has loaded and completed its first render,
`window.AvatarController` is available with exactly this public API (no model,
mouth-controller, renderer, or lip-sync internals are exposed):

```ts
setEmotion(emotion: 'neutral' | 'joy' | 'angry' | 'sorrow' | 'fun', intensity: number): boolean
setConversationState(state: 'idle' | 'listening' | 'thinking' | 'speaking'): void
reset(): void
readonly ready: boolean
readonly lifecycle: 'not-ready' | 'ready' | 'disposed'
getSnapshot(): AvatarCommandSnapshot
```

Emotion/intensity normalization remains owned by `AvatarCommandBridge` and the
VRM controller. Commands issued before readiness retain the latest state and
apply when the active model binds. They do not grant access to model objects or
the animation loop.

The host sends exactly `window.KoiBridge?.postMessage("AVATAR_READY")` once per
active model generation, only after that model is ready. A reload starts a new
generation and sends one new ready message. Existing DOM
`AVATAR_READY` and `AVATAR_NOT_READY` events remain unchanged. No native
not-ready/error message is sent; Flutter owns its timeout and fallback. A stale
model generation cannot mark the replacement controller ready.

Flutter should allowlist the trusted HTTPS avatar-host origin and block all
other top-level navigation. For calls into the Web page, use only the fixed
`AvatarController` method names and JSON-encode each argument (for example,
using Dart `jsonEncode`) before invoking the fixed call expression. Never
interpolate untrusted strings as JavaScript source. Reloading the WebView creates
a new page/bridge; Flutter must discard old JavaScript references and wait for
the next `AVATAR_READY` message.

## Not part of this host

The existing browser speech contracts are `SpeechTimeline.getFrame()` and
`SpeechPlayback`; the VRM mouth controller consumes validated Rhubarb cues on
the audio media clock. This host does not load a speech timeline, start audio,
connect to the localhost Python worker, or request microphone/camera access.
Flutter and Ahmad must agree on future audio ownership, media delivery, mouth
cue serialization, interruption, and model-selection messaging before extending
the native bridge. No JavaScript methods for those future operations are
defined here.

## Android verification for Irsa

Use `webview_flutter` on a physical Android device against the deployed HTTPS
origin. Restrict top-level navigation to that exact origin and `/avatar-host`
(allow only `model=male|female`). Wait for one `AVATAR_READY` after each load
before testing the six commands above. Exercise both model URLs, repeated
reloads, portrait/landscape and short viewports, background/foreground and
WebView disposal. Provide Flutter-owned loading/error UI because the host is
intentionally silent while loading and after load failure. Verify no external
navigation or external request, and no Firebase/chat/crisis/audio/video
request or microphone/camera permission. This repository does not contain the
native WebView implementation, and no physical Android verification is
claimed.

## Local verification

From `repos/koi-backend/nextjs_app`, build and start the production app with
`npm run build`, then `npm start -- --hostname 127.0.0.1 --port 3010`. In a
second terminal run `node scripts/verify-avatar-host.cjs` (set
`KOI_AVATAR_BROWSER` to the installed Chrome executable if Playwright cannot
find Chrome). The script loads the default male route, reloads it, loads the
female query route, checks the exact command keys and one ready token per page
generation, tests 320x280 layout, checks for visible controls/status, watches
all external HTTP requests, and rejects chat/media requests. Run
`node scripts/test-avatar-host.cjs` and
`node scripts/test-avatar-controller.cjs` for controller/generation lifecycle
checks. These are browser automation checks, not Android-device verification.
