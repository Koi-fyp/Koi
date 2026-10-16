# KOI Dart reference client

`koi_chat_client.dart` is a pure-Dart reference implementation of contract v1. It
uses `package:http` and injects both base URLs and an async ID-token callback.
The crisis call is multipart, has a 20-second timeout, and fails closed (`null`)
on every error. Chat consumes SSE through `utf8.decoder`, so split UTF-8 code
points are safe.

## Dependency and Flutter wiring

Add `http` (and `test` as a dev dependency for the supplied test) to the mobile
package. The existing `repos\koi-backend\flutter_lib\pubspec.yaml` was not
modified; its dependency list was not treated as a client implementation.
Flutter should provide the Firebase ID-token callback and construct one client
per conversation with deployed, persistent base URLs.

Wire `onCompanionState` directly to
`AvatarController.setEmotion(state.emotion.name, state.intensity)`. The WebView
still makes no network calls; native Flutter owns all calls and sends avatar
commands through the `KoiBridge` JavaScriptChannel. Speak each `onDelta`
sentence through TTS. Execute `start_breathing`/`stop_breathing` and related
`UiAction`s in the breathing animation controller; send `markPlayback(true)`
or `markPlayback(false)` on the next turn. `onHandoff` and high-risk
`onCrisis` open UX Flow 4, stop animation, and render intervention content.
Repeated crisis handoffs are idempotent.

Use exactly this emotion union, without Web aliases:
`neutral | joy | angry | sorrow | fun`.

The supplied test uses a local `HttpServer` and covers split Urdu/emoji SSE,
companion state before text, repeated crisis handoff, resolution, 401 fallback,
and multipart input.
