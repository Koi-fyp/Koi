# AI-assisted questionnaire drafting: README

## Env
`KOI_AI_BASE` (server only, never NEXT_PUBLIC_). Example: `http://localhost:8100`. Unset or malformed (not http/https) -> the route answers 503 `ai_unavailable` and the panel shows "not configured" with a build-manually fallback. The AI service must accept the caller's Firebase ID token (the Web server forwards the Authorization header unchanged).

## New files
- `src/app/api/v1/professional/questionnaire-drafts/ai/route.ts`: POST only. Proposed contract 0.5.3.
- `src/app/api/v1/professional/questionnaires/[id]/confirm-review/route.ts`: server-side "I reviewed this draft". Proposed 0.5.3.
- `src/lib/platform/ai/route-kit.ts`: standalone POST wrapper with the same conventions as `platformRoute` (so `http.ts` is untouched).
- `src/lib/platform/ai/questionnaire-draft.ts`: request validation, upstream call (60 s, no retry), error mapping, response validation.
- `src/components/professional/AiDraftPanel.tsx`: panel, error states, review banner.
- Tests: `src/__tests__/platform/ai-draft-routes.test.ts` (36), `ai-draft-panel.test.tsx` (6).

## Edited existing files (with reasons)
- `contract.ts`: new `checkDraftContent` (both origins). `checkManualContent` is unchanged in effect and calls it, then requires origin `manual`. Reason: save must accept `ai_drafted`, publish must not.
- `service.ts`: `createDraft`/`updateDraft` use `checkDraftContent`. `updateDraft` rejects an origin change (422), so the browser cannot flip `ai_drafted` -> `manual` by saving. New `authorizeAiDraft` (fresh sign-in + verified psychologist) and `confirmAiDraftReview` (revision-checked flip, idempotent receipt, `audit_events` row, revision +1).
- `types.ts`: `origin: 'manual' | 'ai_drafted'`.
- `ProfessionalWorkspace.tsx`: mounts the panel and banner, load/confirm handlers, publish button disabled for `ai_drafted`, heading text.
- `http.ts`, `errors.ts`, the shared error table, and all existing tests: NOT edited. No existing assertion changed.

## Flow and the demo
Psychologist -> "Draft with AI" (topic, audience, language, count) -> content loads as an unsaved draft with the banner and provenance -> edit -> Save draft (origin stays `ai_drafted`; publish is blocked in the UI and by the server) -> tick "I reviewed this draft" (needs a saved, unmodified draft) -> server flips to `manual`, revision +1, audited -> Publish. Patients see nothing new.

## Not tested (no live run)
- Real AI service, real Firebase token verification, real Firestore, a browser, real latency/timeouts beyond the mocked 60 s abort.
- Visual styling/layout of the panel (jsdom only).
- The upstream error body shape for 422 (I read `code`, `error.code` or `detail.code`), the exact shape of `provenance.sources` (strings or objects with title/name/id/url are accepted) and whether the AI service really returns `web_content` with `origin: ai_drafted`: all [GUESS] from the brief.
- Provenance is shown only in the session that generated the draft; it is not stored with the draft.
