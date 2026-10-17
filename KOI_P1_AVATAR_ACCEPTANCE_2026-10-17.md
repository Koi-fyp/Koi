# KOI P1 — Avatar selection and emotion rendering

## Scope and tested baseline

- Branch: `feat/avatar-webview-host`; HEAD: `40be37e201998c54e5be3f0f9abd6973ec36e616`. Dirty before and after P1. No commit, push, merge, reset, clean or deployment.
- Frontend browser runtime: `http://127.0.0.1:3000`, Next.js 14.2.35 development. Reused the existing server. Browser contexts were isolated and sequential. Server was stopped during production builds, with no duplicate server started.
- Read the P0 browser acceptance, recovery/integration handoffs and jigsaw audit, plus Downloads copies of `KOI_ULTIMATE_MASTER_BLUEPRINT_v4_13.md` and `TRACK_WEB_AVATAR_PATCHED_v4_9.md` (especially Blueprint §3.2 and track Phase 2). Those documents favor male MVP/default and defer female/retire fox. The user's explicit P1 instruction authorizes both existing human models and preservation of fox preferences; no new fox asset, media pipeline or product redesign was added.
- The published branch was not treated as the implementation baseline. Initial dirty diffs already contained the typed preference resolver, both conversation-screen bindings, Aisha/female PNG and VRM paths, fox preservation and P0 session integration. No separately labelled M14 checkpoint was found in the current status report; those existing local avatar changes were preserved and extended, not recreated.
- No backend/API/schema/transport/auth-rule changes. Firebase, crypto, conversation persistence, SSE parser/transport, crisis handling, jigsaw milestone 1, avatar command bridge/controller, native host and existing PNG/VRM assets were preserved. No Flutter changes. No credentials, tokens, environment-file contents, private conversations or browser storage-state exports were inspected or printed.

## Audit and root causes

| Finding in the actual pre-P1 worktree | Resolution / evidence |
| --- | --- |
| Historical Aisha-to-male mapping bug was already corrected locally. | Retained `src/lib/avatar/avatarPreference.ts` as the common typed resolver used by `useAvatarPreference` on both screens. Companion is canonical; avatar-only legacy profiles still resolve. Reads never migrate/overwrite legacy rows. |
| P0 browser report explicitly used the saved fox/text path. It did not prove a human VRM load failure. | Actual authenticated female and male VRMs both loaded HTTP 200 and visibly rendered. No transport fix was needed. |
| Onboarding mounted the companion picker with Koi as its own default, without restoring an existing selection. | Restore UID-scoped resolved selection before mounting the picker. New-profile default is visibly Raza; saved Aisha/fox selections remain selected. Selection cards expose `aria-pressed`; failed preview images have a readable fallback. |
| Local onboarding save succeeded, but notification/navigation waited on Firestore completion. Real P0 observation had stalled at this final cloud step. | Notify after local commit, disable duplicate submission, and show an explicit **Continue with saved companion** link after local success. Existing cloud merge and truthful failure behavior remain. Cloud sync is never falsely marked successful. Late completion cannot redirect an unmounted/different-owner onboarding page. |
| Settings avatar/name dialog only changed React state and displayed success. | Add a transactional, typed UID-scoped `saveAvatarPreference` writer to existing `db.users`; update only companion/avatar fields. Settings restores the same preference and reports device-local persistence honestly. Save failure preserves the previous choice. No profile schema or display-name persistence was added. |
| Scene disabled/unmounted a failed renderer, making its own Retry inaccessible. | Add scene-level Retry avatar plus a selection-review link for absent/fox preferences. Text transcript/composer stay available. Retry loads the selected model without cancelling/replacing the conversation. |
| Standalone renderer retained resources after an error until retry/unmount. | One idempotent release path now aborts model fetch, cancels RAF, disconnects observers/listeners, detaches/disposes controller, disposes model/bitmaps/GPU renderer and loses/removes the context. Late parse results remain disposed. |
| Mobile screenshot clipped Settings/mode controls. | Narrow responsive spacing, mobile wordmark/icon suppression and shorter visible mode label; accessible mode name retained, media still disabled. Links have active-page semantics; navigation/mode touch height is at least 44 px. |

During P1 browser testing, an introduced onboarding guard compared two absent UIDs and dereferenced a null choice during auth loading. This was reproduced, corrected (`choice && ...`), and covered by a loading/signed-out regression test. The later clean browser run reported zero page errors. Earlier error-bearing onboarding observations are not presented as successful acceptance.

## Selection and asset evidence

| Preference | PNG | VRM | Result |
| --- | --- | --- | --- |
| Aisha / `female_human` | `/Female.png` | `/models/koi-female.vrm` | PASS, authenticated browser: loaded PNG, real rendered female model, persisted after Chat reload. |
| Raza / `male_human` | `/Male.png` | `/models/koi-male.vrm` | PASS, authenticated browser: onboarding and Settings selection, loaded PNG, real male model and scene reload. |
| Koi / `fox` | Explicit unavailable preview | No human model substituted | PASS, authenticated browser: Settings save, Chat fallback, Koi scene text fallback and reload. No new VRM request for fox. |
| Missing/other-account profile | Selection prompt | Text fallback | PASS, tests and browser: no inherited fox/human selection and no automatic male rendering. |

Both files are existing VRM 1.0 binary glTF models: female 16,070,892 bytes, male 15,353,876 bytes, three meshes each. JSON metadata confirms `happy`, `angry`, `sad`, `relaxed`, `neutral`, blink and vowel presets in both. Asset hashes did not change. No optimization/re-export was attempted.

## Emotion path and visual verification

Existing frozen path remains: validated event → `ConversationSession` companion state → `useChat.currentEmotion/currentIntensity` → scene props → renderer's command bridge → existing controller → `vrm.update`/render. The controller/bridge/parser/session did not need changes.

| KOI emotion | VRM expression | Settled weight |
| --- | --- | --- |
| neutral | Rest; all emotional presets zero | 0 |
| joy | happy | intensity × 0.65 |
| angry | angry | intensity × 0.65 |
| sorrow | sad | intensity × 0.65 |
| fun | relaxed | intensity × 0.65 |

Existing controller clamps intensity to [0,1], treats unsupported/missing metadata as neutral, and smoothly transitions with at most one emotional preset nonzero. Neutral is resting weights rather than forcing a neutral morph. Cancellation/failure clears session presentation; stale events cannot revive a cancelled reply. Reduced-motion behavior and blink ownership remain intact. These are companion presentation states, not an assessment of the user's mental health.

- **Rendered local fixtures:** real female model visibly showed all four non-neutral expressions and neutral; controller weights matched 0.65 at intensity 1, and angry 0.455 at intensity 0.7. Real male model visibly showed joy at 0.455. Screenshots were inspected, not inferred solely from DOM readiness. Synthetic adapter metadata was temporarily supplied only inside the isolated browser test session; no application fixture switch, transport interception or production test controls were added. Existing session/snapshot persistence remained in use. Emotional mouth deformation is not lip-sync; speech source remained inactive and mouth-control weights stayed zero.
- **Deterministic regression fixtures:** new `scripts/test-avatar-session.cjs` verifies metadata before request completion, all mappings/intensity, latest of 100 rapid updates, cancellation plus stale-event rejection, missing metadata, failure and disposal. Existing controller tests additionally cover unsupported presets, clamping, continuous/exclusive transitions, reset, reduced motion and stale model/controller generations.
- **Genuine Modal evidence:** one legitimate Firebase-authenticated chat POST returned **HTTP 200**, `text/event-stream; charset=utf-8`, with `latency`, `companion_state`, `risk`, `delta`, `state`, `done`; stream completed on `/companion-scene`. Male VRM remained ready/visible. Its actual final companion emotion was neutral and all rendered emotion weights were zero. No non-neutral live Modal success is claimed; those expressions are simulated verification only. No endpoint, timeout, redirect, auth or SSE experiments occurred.

## Acceptance matrix

| # | Requested acceptance case | Result and scope |
| --- | --- | --- |
| 1 | Select Aisha → female PNG | **PASS**, authenticated onboarding/browser; existing and added tests. |
| 2 | Open scene → female VRM | **PASS**, actual authenticated route, HTTP 200, ready renderer and inspected screenshot. |
| 3 | Switch interfaces without losing chat | **PASS**, browser with synthetic conversations through the existing session: stable conversation/message fingerprints across scene → Chat and refresh; genuine request also completed after navigation to scene with one POST. P0 recovery suite passes. |
| 4 | Reload preserves female | **PASS**, Chat reload retained Aisha and all ten synthetic messages/IDs, encrypted snapshot, no chat POST. |
| 5 | Repeat for Raza | **PASS**, onboarding selection in corrected-code final run; PNG/model visible. Earlier scene reload retained male model, same twelve synthetic messages and restored expression. |
| 6 | Fox preference fallback | **PASS**, real Settings save, no PNG or human VRM substitution, visible Koi text fallback retained after scene reload. |
| 7 | Visible emotion changes | **PASS, simulated**, real rendered models plus local controller/session tests. **PASS, live neutral only**. **NOT RUN**, live non-neutral Modal expression changes. |
| 8 | Text chat and breathing/exercise/crisis regression | **PASS**, one genuine text chat; local exercise/Flow 4/P0 fixtures and full Jest suite. **NOT RUN**, genuine exercise/crisis backend delivery; no crisis-provoking messages were submitted. |
| 9 | Mobile and WebGL/model failure fallback | **PASS**, browser at 390×844 and 320×700, visible models/composer/navigation without horizontal document overflow. Simulated context loss and model HTTP 404 produced text fallback; Retry restored same male model. Physical GPU/device coverage is **NOT RUN**. |
| 10 | Focused tests, TypeScript, build, diff checks | **PASS**; details below. |

Additional browser isolation: real Firebase anonymous sign-up/lookup HTTP 200. After logout, no live session; new anonymous owner fingerprint changed from `ed875185c9070a15` to `d52835998a6eaf9e`, got a new empty conversation and no inherited avatar image. No auth bypass or existing user browser profile was used.

Cleanup instrumentation on the actual authenticated route: one live WebGL context, one ResizeObserver and one pending RAF while rendering; after Back to Chat, **zero live contexts, observers and pending frames**, and zero canvases. Model errors/context loss also removed the canvas and retry produced exactly one canvas. Long-duration memory soak and native WebView behavior remain outside this run.

Browser screenshots/harness are temporary local artifacts (`%TEMP%\koi-p1-*.png`, `%TEMP%\koi-p1-browser.cjs`); they contain only synthetic test content. No private transcript screenshots or credential export.

## Files changed by P1 only

Paths relative to `repos/koi-backend/nextjs_app`; all earlier dirty changes outside this list are pre-existing.

Modified existing local files (including previously untracked avatar files):

- `src/lib/avatar/avatarPreference.ts` — explicit transactional preference writer; existing resolver preserved.
- `src/lib/onboarding.ts` — local-save notification/callback and stale-account completion guard.
- `src/app/onboarding/page.tsx` — saved choice restoration, pending/local/error navigation states and owner/unmount guards.
- `src/components/onboarding/CompanionSelectionStep.tsx` — initial selection, pressed state and image fallback.
- `src/components/onboarding/NotificationStep.tsx` — saving/disabled state.
- `src/app/(authenticated)/settings/page.tsx` — shared preference source and honest persisted save.
- `src/app/(authenticated)/settings/components/AvatarPicker.tsx` — typed async save and pending state.
- `src/app/(authenticated)/companion-scene/page.tsx` — text-safe retry and selection-review link.
- `src/components/companion/CompanionScene.tsx` — notice accepts React content for recovery controls; crisis/exercise logic unchanged.
- `src/components/avatar/VRMAvatarRenderer.tsx` — immediate idempotent error/unmount resource release.
- `src/components/layout/BottomNav.tsx` — mobile fit and link accessibility.
- `src/components/layout/ModeSelector.tsx` — mobile fit/label; availability unchanged.
- `src/__tests__/onboarding.test.tsx` — restored preference, pending sync, duplicate submission and auth-loading coverage.
- `src/__tests__/companion-avatar.test.tsx` — failed model retry and existing emotion prop path.

New:

- `src/__tests__/avatar-storage.test.tsx` — real Dexie/fake IndexedDB isolation, reopen, atomic deduplication, non-mutating legacy reads and both mounted consumers.
- `src/__tests__/settings-avatar.test.tsx` — persisted Settings path and storage-failure honesty.
- `scripts/test-avatar-session.cjs` — deterministic session-to-controller regression.
- This root report, `KOI_P1_AVATAR_ACCEPTANCE_2026-10-17.md`.

No new packages. The PNG chat implementation and `useAvatarPreference` hook already worked and were not rewritten. Native `AvatarWebViewHost`, command registration/readiness contract, speech/microphone/video modules and all existing assets are unchanged.

## Tests, build and remaining limits

- PASS: full Jest `node node_modules/jest/bin/jest.js --runInBand`: **11 suites, 61 tests**, including all jigsaw/P0/auth tests. Existing styled-jsx attribute warning remains in preserved chat-avatar test; no new test warning remains.
- PASS: installed TypeScript `--noEmit --incremental false` and `npm run typecheck:avatar`.
- PASS: `scripts/test-avatar-session.cjs`, `test-avatar-controller.cjs`, `test-avatar-host.cjs`, `test-exercise-director.cjs`, `test-flow4.cjs`, `test-conversation-recovery.cjs`. Controller/exercise/crisis results are fixtures; recovery uses real local encryption/Dexie with synthetic auth/fetch.
- PASS: production build on the corrected implementation, Next 14.2.35, all 18 static-generation entries. Final build identity after the last mobile-label adjustment is recorded below.
- PASS: `git diff --check` (pre-existing CRLF normalization warnings only).

Remaining integration limits: remote Firestore onboarding sync/cross-device preference recovery is unverified, and Settings honestly saves on this device only. The existing optional display-name input has no durable profile field; this milestone does not invent one. Live non-neutral emotion events were not available in the single legitimate request. Native device/WebView and long-duration resource soak were not run. These limits do not require changing the frozen API. No voice/video/ASR/TTS/lip-sync feature was enabled or started.

### Final artifact and preservation check

- Final production build **PASS**, Next.js **14.2.35**, `npm run build`, build ID **`o71d9-827kD92RS3jQmHc`**. Includes the final mobile visible-label refinement. Compilation, lint/type validation, **18/18** static-generation entries and trace collection completed. Process-only Node heap limit 1024 MB, telemetry disabled for the command; no browser/dev server running during build. Not deployed or served as a production runtime. The authenticated browser evidence above is from development mode, not this production artifact.
- Tested git SHA remains **`40be37e201998c54e5be3f0f9abd6973ec36e616`**, branch unchanged. Final worktree: **26 modified tracked paths, 23 untracked entries, zero staged changes**. Pre-P1 worktree had 20 modified tracked paths and 19 untracked entries. Counts include preserved unrelated work; they are not all P1 changes.
- Pre-P1 comparison of 151 source/asset hashes identified only the 14 intended existing-file changes listed above; new tests/script/report are additional. A separate final check verified **20 protected P0/auth/storage/conversation/transport files unchanged**. The three previously protected avatar/onboarding presentation files intentionally changed are explicitly listed; session/auth/crypto logic was not altered.
- Genuine observed Modal origin: `https://ahsulem--koi-chat-api-chatserver-web.us-east.modal.run`; backend deployment version remains unknown. One POST only; no transport or health probes.
- Final corrected-code browser run: Firebase sign-in HTTP 200, Raza and fox flows, lifecycle/account isolation, **zero page errors**. Earlier runtime errors were fixed and are disclosed above; selector-ambiguity timeouts in the temporary harness are not counted as application failures or successes.
- Browser closed. Exactly one development server restored and ready at **`http://127.0.0.1:3000`**. Final `git diff --check` passed; no files committed, staged, pushed or deployed. Generated `.next` build state is subsequently used/replaced normally by the restored dev server.
