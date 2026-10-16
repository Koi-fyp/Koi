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

## Increment 4 animation controls

Open Preview settings on /companion-scene for development-only emotion,
intensity, conversation-state and Reset controls. Both models reuse the same
controller and renderer. All messages remain scripted mocks.

See `src/components/avatar/ANIMATION.md` for mappings, timing, ownership,
reduced-motion behavior and the opt-in JavaScript ready/not-ready contract.
`node scripts/test-avatar-controller.cjs` runs deterministic source-level tests;
`node scripts/verify-avatar-animation.cjs` exercises the real model files and
writes expression screenshots and lifecycle results to
`.next/verification/increment-4`. Existing viewer/UI test commands still apply.
No backend, voice, lip sync, camera or Flutter integration has been added.

## Increment 5 Stage A mock JSON chat

Open /mock-chat from the sandbox home. Only scripted sample commands are
accepted; responses are development fixtures, never real inference. The same
pure conversation session and wire contract drive the authenticated integration,
without importing Firebase/services into this route. Failure, cancel, rapid
replacement, avatar switching and text-only fallback are available for testing.

See src/lib/conversation/INTEGRATION.md for the reconciled JSON contract,
additive metadata strategy and Stage B configuration/verification blockers.
Run node scripts/test-chat-contract.cjs, python scripts/verify_backend_chat_contract.py
(source-only audit), and node scripts/verify-mock-chat.cjs. Browser artifacts
are under .next/verification/increment-5. No live end-to-end pass is claimed.


## Increment 6A: local speech/lip-sync lab

Generate local test audio with `powershell -NoProfile -File scripts/create-speech-fixture.ps1`,
then run `npm run dev:avatar` and open http://127.0.0.1:3001/speech-lab.
Uses Windows David speech synthesis and explicitly authored approximate cues,
not Piper or Rhubarb extraction. Generated files are ignored under `.fixtures/`.
Play/pause/resume/stop, emotion preview and male/female switching are development-only.
No microphone/camera/backend/Firebase access. Production routes are unchanged.
Run `node scripts/test-speech.cjs` and `node scripts/verify-speech.cjs`.
See [speech architecture](../../src/lib/speech/SPEECH_ARCHITECTURE.md) for provenance,
upstream feasibility sources, lifecycle boundaries and verification limits.


## Increment 6B.1: actual local Piper/Rhubarb samples

On Windows x64 with Python 3.14:

```powershell
python scripts/setup-speech-tools.py
python scripts/generate-piper-samples.py
npm run dev:avatar
```

Open `/speech-lab` and select a Piper sample. The Windows/manual 6A baseline stays
the default. Tools/voices stay ignored under `.speech-tools/`; generated paired
WAV/JSON/raw cues stay under `.fixtures/`. Urdu, English and mixed inputs use the
male Fasih Urdu voice; the latter two are quality-unverified feasibility probes.
Run `python scripts/test-piper-pipeline.py` and `node scripts/verify-piper-speech.cjs`.
See [real speech workflow](../../src/lib/speech/REAL_SPEECH.md) for pinned downloads,
measured timings, licensing, limits and the proposed (not deployed) backend contract.


## Increment 6B.2: local voice-input lab

```powershell
python scripts/setup-voice-tools.py
node scripts/voice-dev.cjs
```

Keep the worker terminal running, start `npm run dev:avatar` separately, and open
http://127.0.0.1:3001/voice-lab. Microphone capture requires consent + Start, and
transcripts require review before submission. ASR/Piper/Rhubarb are real local
processing; chat/emotion are explicitly scripted mocks. Fixture buttons need no
microphone. No recordings are saved. Physical microphone and authenticated voice
conversation have not been verified.

The lab has a **Check local ASR worker** button; the page loading is not proof the
Python worker/model is ready. It also shows permission, device, capture duration,
MIME/size and decoded signal level. After stopping, optionally play the capture
in the browser before transcribing. The Play control does not upload the audio.
Use Refresh microphone list to inspect/select an input for the next capture. The
automated browser test now feeds a non-sensitive Piper fixture through Chromium's
file-backed synthetic microphone and checks that real ASR returns text. This is
not physical microphone verification. On the laptop, grant Chrome microphone
permission, choose the intended input, record a short phrase, play it locally to
confirm the recording contains speech, then transcribe and inspect signal RMS and
the recognized transcript. Report only those diagnostics if asking for help; do
not send private recordings or transcripts.

Use `node scripts/test-microphone.cjs`, `python scripts/test-local-voice.py`, and
`node scripts/verify-voice-lab.cjs`. ASR/TTS benchmark scripts run with the ignored
`.voice-tools/venv/Scripts/python.exe`. See [voice audit/results](../../src/lib/speech/VOICE_INPUT.md)
for exact contracts, normalization, measured timings, privacy boundaries and blockers.
