# Presentation-only avatar host

Production route: `/avatar-host`. It renders only the existing local male/female
VRM files through `VRMAvatarRenderer` and the existing `VRMAvatarController`.
The optional `model` query accepts only `male` or `female`; every other value
selects the male default. It carries no credentials, messages, or user data.
The visible selector changes between those two fixed local paths.

The root `AppAuthBoundary` omits `AuthProvider` only at this exact route. All
other routes still render through the same Firebase provider; the authenticated
layout and its guards are unchanged. The host does not load conversation,
Firestore, crisis, microphone, camera, or local voice-worker services. The
development sandbox remains development-only.

## JavaScript contract

When the current VRM controller has loaded and completed its first render,
`window.AvatarController` is available with its existing API:

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
ready model generation. Existing DOM `AVATAR_READY` and `AVATAR_NOT_READY`
events remain unchanged. No additional native not-ready payload is sent; Irsa
should approve a message format before one is added. A stale model generation
cannot mark the replacement controller ready.

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
origin. Restrict navigation to that exact origin and this host path. Wait for
`AVATAR_READY` before testing commands. Verify portrait/landscape and short
viewport sizes, both allowlisted model values, repeated model switching,
WebView pause/resume/reload, WebGL context loss, and renderer disposal. Check
that the host makes no chat/crisis/voice requests and asks for no microphone or
camera permission. This repository does not contain the native WebView
implementation, and no physical Android verification is claimed.
