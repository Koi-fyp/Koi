# KOI avatar acceptance — work package B (rendered emotion + lifecycle), 2026-10-18

## Scope and baseline

- Worktree `E:\Koi\web-avatar`, branch `avatar/vrm-emotion`, base commit `8dac2b6` (batch 1 tests on `223e97c`). No existing source file was edited.
- Route under test: display-only `/avatar-host` (`?model=male|female`) only. It bypasses Firebase (`AppAuthBoundary.tsx:19`, `:29-31`) and makes no API calls. No authenticated route, chat, transport, persistence, crisis or exercise code was exercised.
- Runtime: one `next dev` (Next.js 14.2.35) on `http://127.0.0.1:3010`, `NODE_OPTIONS=--max-old-space-size=1024`, `NEXT_TELEMETRY_DISABLED=1`; stopped after the runs (port free, no browser processes left). Development runtime, not a production build.
- Browser: Playwright 1.64.0 bundled Chromium (already installed), headless, `--use-angle=swiftshader --enable-unsafe-swiftshader`, `deviceScaleFactor 1`, `reducedMotion: 'reduce'`. Every request not to `127.0.0.1:3010` (or data/blob/about) was aborted and logged: **0 blocked**. `getUserMedia` was stubbed to count calls: **0**. No `.env*` file was opened by me; Next's own env loading was not inspected.
- Dev-server log: only `/avatar-host` compiled (866 modules, 6.2 s cold) and requested (16 × `GET /avatar-host 200`); no warnings.

## Regression run (before the browser work)

| Command | Result |
|---|---|
| `node scripts/test-avatar-emotion-matrix.cjs` | PASS, 10 checks |
| `node scripts/test-avatar-controller.cjs` | PASS, 7 checks |
| `node scripts/test-avatar-session.cjs` | PASS, 6 checks |
| `node scripts/test-avatar-host.cjs` | PASS, 6 checks |
| `npx jest src/__tests__/companion-scene-emotion.test.tsx src/__tests__/companion-avatar.test.tsx --runInBand` | PASS, 2 suites / 11 tests |
| `npx tsc --noEmit --incremental false` | PASS, exit 0, no output (5 s) |
| `git diff --check` | PASS, exit 0 |

Installed versions: typescript 5.9.3, three 0.180.0, @pixiv/three-vrm 3.5.5, jest 29.7.0, playwright 1.64.0, next 14.2.35. No production build was run (no application source changed).

## Rendered emotion verification (`scripts/verify-avatar-emotion-screens.cjs`)

Method per model (male, then female; never parallel), viewport 640x800:

1. Load `/avatar-host?model=…`, wait for `AvatarController.ready` with the expected `modelUrl`.
2. Temporal-noise mask: four settled neutral frames ~1 s apart; pixels changing between them (RGB delta > 16, dilated 2 px) are excluded from all comparisons. Saved as `<model>-noise-mask.png`.
3. Face crop: union of unmasked pixels that change between neutral and each emotion at 1.0, plus 35% margin. Assert it covers ≤ 50% of the canvas.
4. For each cell: `setEmotion(e, i)`; wait until `getSnapshot().animation.weights` equals `i × 0.65` on the mapped preset and 0 elsewhere (to 1e-9); wait for an open-eye window (`blinkWeight === 0 && nextBlinkIn > 0.8`), two frames, then a clipped screenshot; the capture is retried if a blink started during it.
5. Assertions: `setEmotion` returned true; weights exact; mouth (vowel) weights 0; face crop not blank (luma std ≥ 8); non-neutral at 0.7 and 1.0 changes > max(0.2%, 3 × residual neutral noise) of compared pixels vs neutral; neutral cells and intensity 0 change ≤ max(0.05%, 2 × residual noise).
6. Cells: 5 × {0, 0.3, 0.7, 1.0} (20) + live-value fixtures {sorrow 0.7, joy 0.3, neutral 0.4} (3) + backend-range {0.2, 0.5} for the four emotions (8) = 31 per model. Contact sheet per model.

**Result: PASS on both models, 0 failures, 0 page errors, 0 console errors.** Total 592 s.

### Five-expression verification matrix (Δ = % of compared face-crop pixels changed vs neutral)

Rendered weight = intensity × 0.65; exact in every cell on both models (asserted from the live snapshot).

| Emotion → preset | i = 0 | i = 0.3 (w 0.195) | i = 0.7 (w 0.455) | i = 1.0 (w 0.65) |
|---|---|---|---|---|
| neutral (rest) | M 0.00 / F 0.00 | M 0.00 / F 0.00 | M 0.00 / F 0.00 | M 0.00 / F 0.00 |
| joy → happy | M 0.00 / F 0.00 | M 2.38 / F 2.79 | M 4.44 / F 4.66 | M 5.81 / F 6.02 |
| angry → angry | M 0.00 / F 0.00 | M 0.98 / F 1.71 | M 1.89 / F 2.52 | M 2.53 / F 2.66 |
| sorrow → sad | M 0.00 / F 0.00 | M 1.12 / F 1.82 | M 2.03 / F 2.68 | M 2.52 / F 2.95 |
| fun → relaxed | M 0.00 / F 0.00 | M 0.82 / F 1.17 | M 1.33 / F 1.97 | M 1.81 / F 2.32 |

Every non-neutral row increases monotonically with intensity on both models. Intensity 0 and all neutral cells are pixel-identical to neutral in the face crop.

### Live-value fixtures (B2) and backend range (B3)

Values reported from the live backend, replayed locally through `window.AvatarController.setEmotion` (not received from the backend in this run):

| Fixture | Weight | Male Δ | Female Δ |
|---|---|---|---|
| sorrow 0.7 | sad 0.455 | 2.02% | 2.68% |
| joy 0.3 | happy 0.195 | 2.38% | 2.79% |
| neutral 0.4 | all 0 (neutral ignores intensity) | 0.00% | 0.00% |

Backend prompt range 0.2–0.7 (0.3 and 0.7 from the matrix):

| Emotion | i 0.2 (w 0.13) | 0.3 (0.195) | 0.5 (0.325) | 0.7 (0.455) |
|---|---|---|---|---|
| joy | M 1.78 / F 2.31 | M 2.38 / F 2.79 | M 3.49 / F 3.78 | M 4.44 / F 4.66 |
| angry | M 0.74 / F 1.35 | M 0.98 / F 1.71 | M 1.40 / F 2.37 | M 1.89 / F 2.52 |
| sorrow | M 0.84 / F 1.40 | M 1.12 / F 1.82 | M 1.63 / F 2.36 | M 2.03 / F 2.68 |
| fun | M 0.64 / F 0.97 | M 0.82 / F 1.17 | M 1.14 / F 1.61 | M 1.33 / F 1.97 |

**Live non-neutral expression in an authenticated chat: NOT RUN.** No signed-in harness exists in this work package; no Firebase sign-in, chat POST or SSE stream was made. The only historical live evidence remains the P1 report (live neutral only).

### Actual rendering observations per model (from inspected contact sheets)

- **Female (Aisha, `/models/koi-female.vrm`):** fully deterministic under SwiftShader (temporal mask 0% of canvas; neutral-vs-neutral residual 0). Face crop 291x255 centred on the face. Joy is clearly readable from 0.2 (brows, eyes, pink mouth from ~0.5). Angry/sorrow read mainly through brow shape from 0.3; fun (relaxed) is the weakest preset and is subtle below 0.5.
- **Male (Raza, `/models/koi-male.vrm`):** secondary motion on hair strands and hoodie drawstrings keeps changing between frames even with reduced motion, blink gating and settled weights (mask 1.39% of the canvas, bbox x 218–446, y 166–544; see `male-noise-mask.png`). [Inference] This is VRM spring-bone motion (`VRMC_springBone` present in both files); the renderer's reduced-motion path restores only head/chest bones. None of the masked pixels are on the face. After masking: face crop 216x222, residual neutral noise 0. At thumbnail scale, male angry, sorrow and fun at 0.2–0.3 are hard to distinguish from neutral; joy's mouth reads from ~0.5.

### First run (disclosed)

The first run (540 s) failed 8 male checks: the face crop was calibrated without a noise mask, so hair/drawstring motion inflated it to 483x640 (most of the torso). The ~0.30% background drift then made neutral/intensity-0 cells "differ" from neutral and pushed male angry 0.7 (0.32%) and fun 0.7 (0.21%) below the visible threshold. Female passed every check in that run with the same numbers as the final run. The harness was corrected (temporal-noise mask, crop-size guard); thresholds were not loosened. The final run is the one reported above.

## Lifecycle verification (`scripts/verify-avatar-lifecycle.cjs`, B1)

Instrumentation (init script, no app changes): wrapped `getContext` (per-context `webglcontextlost` listeners), `WEBGL_lose_context.loseContext` (observes `renderer.forceContextLoss()`), `gl.delete*` calls (GPU resource release), canvas `removeEventListener('webglcontextcreationerror')` (only `WebGLRenderer.dispose()` removes it), RAF and ResizeObserver tracking, a `KoiBridge` stub.

Per model: load → reload → resize 640x800 → 360x640 → 1280x800 → client-side switch to the other model and back (`window.next.router.push`, Next dev debug handle; same document, so the renderer effect cleanup — the same `releaseResources` the unmount path calls, `VRMAvatarRenderer.tsx:235-238` — must run) → full navigation to `about:blank` and back.

**Result: PASS on both models, 0 page errors, 0 console errors, 0 unexpected context-loss events, 0 media calls, 0 blocked requests.** 41 s.

| Observation | Male | Female |
|---|---|---|
| Load / reload to ready | 2.7 s / 2.1 s | 1.2 s / 2.1 s |
| Steady state after every step | 1 canvas, 1 live context, 1 pending RAF, 1 ResizeObserver | same |
| Resize drawing buffer (= CSS size at DPR 1) | 640x800 → 360x640 → 1280x800, no new context | same |
| KoiBridge `AVATAR_READY` | once per document, once per new model generation | same |
| Client switch away + back | +1 context each; previous one force-lost and detached; `WebGLRenderer.dispose` observed each time; 88 then 192 cumulative GPU deletions | 104 then 192 |
| Full navigation away and back | fresh document returns to steady state | same |

Cleanup observations:

- `renderer.forceContextLoss()` and `renderer.dispose()` both ran on every model replacement (observed counts +1 per switch), and GPU deletions confirm the previous model's textures/buffers/programs were released.
- Every fresh document creates **two** WebGL contexts; the first is force-lost and detached before the model loads (0 GPU deletions, nothing uploaded yet). [Inference] This is React StrictMode's development double-invoke of effects (Next 14 App Router default; `next.config.js` does not override it). It shows the release path is idempotent and correct; production is expected to create one. The first lifecycle run asserted exactly one context per document and failed on this; the assertion was corrected to "exactly one unreleased context; every extra context forced and detached".
- A drawing-buffer size read immediately after shrinking the viewport can lag one ResizeObserver callback (1280x800 buffer at 640x800 CSS in a pre-switch snapshot); the steady state after the next frame was correct.
- True component unmount on `/avatar-host` is not reachable without leaving the display-only route (any other route mounts the authenticated application and Firebase). The model switch exercises the same cleanup function; the full-page navigation only proves a clean remount.

## Performance and memory

| Measure | Male | Female |
|---|---|---|
| Model load to ready (screens run) | 2.8 s (8.6 s in the first run: cold compile + first model fetch) | 4.6 s |
| Weight settle, wall time | ~0.9–1.6 s (controller fade 0.38–0.60 s at SwiftShader frame rate) | ~1.3–2.4 s |
| Time per cell (settle + blink gate + capture) | mean 5.5 s (3.4–8.7 s); 6 blink retries | mean 8.4 s (5.7–13.7 s); 4 retries |
| Page JS heap (CDP `JSHeapUsedSize`) | 19 MB after load, 18 MB after 31 cells | 34 MB after load, 18 MB after cells |
| Lifecycle JS heap range | 20–46 MB | 20–40 MB |

Dev server node process: 110 MB working set idle → 644 MB working set / 789 MB peak / 754 MB private after all runs. Harness node RSS ~89 MB. GPU/SwiftShader memory and Chromium process memory were not measured. Not a soak test.

## Changed files

- New `scripts/verify-avatar-emotion-screens.cjs` — rendered 5x4 matrix, live-value fixtures, backend-range cells, noise mask, contact sheets.
- New `scripts/verify-avatar-lifecycle.cjs` — load/reload/resize/switch/navigation lifecycle with WebGL disposal instrumentation.
- New `AVATAR_ACCEPTANCE_WORKPACKAGE_B_2026-10-18.md` — this report.
- Artifacts under `artifacts/avatar-emotion/` (gitignored by `nextjs_app/.gitignore:88`, so local only): `contact-sheet-{male,female}.png`, 62 face crops `<model>-<emotion>-<intensity>.png`, `<model>-full-neutral.png`, `<model>-noise-mask.png`, `lifecycle-<model>-<w>x<h>.png`, `emotion-screens-result.json`, `lifecycle-result.json`.

No existing source, public page, settings, progress, onboarding, auth, conversation/session/transport/persistence, crisis or exercise file was changed. No package was installed.

## Remaining blockers

1. Live non-neutral expression in an authenticated chat: NOT RUN (no signed-in harness; would need an approved test identity and a real Modal request).
2. Production-runtime rendering (no StrictMode double mount) and real GPU devices: NOT RUN; all pixels here are SwiftShader in development mode.
3. Native WebView/Flutter host and long-duration soak: NOT RUN.
4. Male spring-bone motion under `prefers-reduced-motion`: hair and drawstrings keep moving. Whether reduced motion should also freeze secondary motion is a product/accessibility decision; no change made.
5. Intensity floor (below): needs a decision before any controller change; the existing controller, session, matrix and host tests pin `intensity × 0.65`.

## Proposal (text only, not implemented): intensity floor

Evidence: the backend's 0.2–0.7 renders at weights 0.13–0.455. At 0.2, male angry/sorrow/fun change only 0.64–0.84% of face pixels and are hard to see at contact-sheet scale; female is 0.97–1.40%. Joy is readable throughout. Only the top of the backend range (0.7) reaches 70% of the 0.65 cap.

Option A (recommended for discussion): for intensity > 0, `weight = 0.65 × (0.35 + 0.65 × intensity)`; intensity 0 and neutral stay at rest.

| intensity | 0.2 | 0.3 | 0.5 | 0.7 | 1.0 |
|---|---|---|---|---|---|
| current weight | 0.130 | 0.195 | 0.325 | 0.455 | 0.650 |
| proposed weight | 0.312 | 0.354 | 0.439 | 0.523 | 0.650 |

The proposed 0.2 weight (0.312) is close to the current 0.5 (0.325), measured here at male angry 1.40%, sorrow 1.63%, fun 1.14%, joy 3.49%: visible but still mild. It would also keep 1.0 unchanged and preserve monotonic ordering.

Option B: per-preset gain (e.g. boost `relaxed`, the weakest preset on both models) instead of, or in addition to, a floor.

Option C: no frontend change; have the backend use more of the 0–1 range.

Before choosing numbers: re-run `verify-avatar-emotion-screens.cjs` with the candidate mapping and inspect the contact sheets on both models; update the tests that pin the linear mapping (`test-avatar-controller.cjs` 0.455/0.52/0.65, `test-avatar-session.cjs` 0.39, `test-avatar-emotion-matrix.cjs` intensity × 0.65); `verify-avatar-host.cjs` only asserts a weight above 0. Emotion values are companion presentation states, not an assessment of the user.

## How to re-run

```
# one dev server only
NODE_OPTIONS=--max-old-space-size=1024 NEXT_TELEMETRY_DISABLED=1 npx next dev -p 3010 -H 127.0.0.1
KOI_AVATAR_HOST_ORIGIN=http://127.0.0.1:3010 node scripts/verify-avatar-emotion-screens.cjs   # ~10 min
KOI_AVATAR_HOST_ORIGIN=http://127.0.0.1:3010 node scripts/verify-avatar-lifecycle.cjs         # ~45 s
```

Run the two scripts one after the other, never in parallel.
