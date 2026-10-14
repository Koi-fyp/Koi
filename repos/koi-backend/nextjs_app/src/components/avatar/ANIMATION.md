# KOI avatar animation foundation (Increment 4)

`VRMAvatarController` owns only emotional presets, blink presets, and normalized
head/chest offsets. It has no renderer, timers, media, authentication or backend.
The existing renderer calls controller.update(delta), then vrm.update(delta),
then renders in its one requestAnimationFrame loop. Each loaded model receives
its own controller after orientation, relaxed pose, scale and framing are set.

## Facial expressions

- neutral: zero emotional weights; neutral morph is not forced to 1.
- joy -> happy; angry -> angry; sorrow -> sad; fun -> relaxed.
- Input intensity is clamped to [0,1]; non-finite values become zero.
- Effective expression weight is intensity * 0.65 for restrained expressions.
- Unknown or unavailable emotion presets degrade to resting neutral.
- On a preset change, the old expression fades out over 0.22s, then the new one
  fades in over 0.38s. Same-preset intensity changes use a 0.38s fade.
- Smoothstep interpolation uses elapsed seconds, supports interruptions and
  repeated commands, and never makes opposing emotional presets nonzero together.
- Three-VRM retains ownership of expression overrides; metadata is not rewritten.
- aa/ih/ou/ee/oh are never written, including reset/dispose. Emotion morphs may
  naturally include a smile/mouth shape, but there is no speech or lip sync.

## Blink and posture

A seeded PRNG schedules a blink every 3.2-6.2s. Closing takes 75ms, closed hold
25ms and opening 120ms. Prefer combined blink; fall back to the paired left/right
presets if both exist. Missing expressions/bones degrade safely. Reset rewinds
the seed and opens the eyelids; dispose clears only owned presets.

Breathing offsets the normalized chest by at most 1.5mm. Head offsets are tiny,
relative to captured initial transforms: idle is relaxed, listening adds a small
attentive tilt, thinking a slight reflective orientation, speaking adds gentle
head variation. Positions/quaternions are rebuilt from stable bases each frame;
there is no accumulated transform drift or body gesture system. Reduced motion
restores base posture and suppresses breathing/head motion; blinking and smooth
facial fades remain. Delta is bounded after stalls to avoid sudden motion.

## JavaScript command contract

Global exposure is opt-in via renderer/scene exposeController. Only the sandbox
conversation enables it now. Once mounted, the facade accepts commands before
model readiness and keeps the latest emotion/state across model switches:

```javascript
window.AvatarController?.setEmotion('joy', 0.7);
window.AvatarController?.setConversationState('listening');
window.AvatarController?.reset();
const ready = window.AvatarController?.ready;
const snapshot = window.AvatarController?.getSnapshot();
```

The facade is frozen and exposes no VRM references, update loop or binding API.
Readiness is not-ready -> ready after the first rendered frame. Local DOM events
AVATAR_READY/AVATAR_NOT_READY provide type, modelUrl, generation and lifecycle.
A generation is announced ready once; stale controller identities cannot
announce readiness or detach a newer model. Back/End remove the global and
retained old facade references become disposed no-ops. A duplicate global owner
is rejected instead of overwritten.

Window.KoiBridge.postMessage(string) is declared as an optional future transport;
it is NOT called. A future Flutter adapter can forward the documented ready
payload. No Flutter source, native permissions or Android WebView were tested.

## Verification

From the canonical application:

- npm run typecheck:avatar
- node scripts/test-avatar-controller.cjs
- node scripts/verify-avatar-animation.cjs
- node scripts/verify-avatar.cjs
- node scripts/verify-companion-ui.cjs
- git diff --check

Browser commands require the sandbox (npm run dev:avatar) and the existing
Playwright Chromium installation, or KOI_AVATAR_BROWSER selecting Chromium.
Animation screenshots/results are in the ignored sandbox .next/verification/
increment-4 directory. Source tests use in-memory transpilation and real
Three-VRM expression managers with synthetic bone rigs; browser tests load the
actual supplied male/female files. Software WebGL is not physical-device proof.
Known production build/type failures are outside this increment.
