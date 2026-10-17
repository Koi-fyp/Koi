# KOI P0 real-browser acceptance — 2026-10-17

**Result: PASS for the requested P0 scenarios. No application code changes were necessary.**

## Runtime and preservation

- Frontend: `http://127.0.0.1:3000`, Next.js **14.2.35 development mode**.
- Branch: `feat/avatar-webview-host`.
- SHA: `40be37e201998c54e5be3f0f9abd6973ec36e616`, unchanged.
- Initial worktree: 19 modified tracked files, 14 untracked entries, zero staged entries. These remained unchanged; this acceptance report is the only new repository file from this run. Generated `.next` files changed through normal development compilation.
- No Next server was initially listening. Started exactly one development server; it remains listening on port 3000. Test browsers were closed.
- Used installed Chrome headlessly through Playwright, with two sequential isolated browser contexts. No existing user browser/profile was accessed.
- Used the existing development-only Firebase anonymous sign-in through the application. Real `accounts:signUp` and `accounts:lookup` requests returned **HTTP 200**, and application auth state reported `isAnonymous: true`.
- No environment file, Firebase token, credential, private user conversation, storage-state export or raw SSE payload was read/exported into the report. Only synthetic, non-sensitive test conversations were submitted. Evidence contains counts, roles, event names and fingerprints.

## Browser acceptance evidence

| Check | Result | Observed evidence |
| --- | --- | --- |
| Chat → Progress → Chat | PASS | After two real exchanges, conversation fingerprint `a9db541855a148ef` and all four message-ID fingerprints stayed unchanged across routes. Modal POST count remained two. |
| Chat → Companion Scene → Chat | PASS | Existing scene link and Back to chat control retained the same conversation and four completed message IDs; no additional POST. Scene used the existing fox/text fallback, so this is route/session acceptance, not VRM visual acceptance. |
| Browser refresh with encrypted recovery | PASS | Refreshed both `/companion-scene` and `/chat`. Same authenticated owner, conversation, message IDs, roles and completed statuses recovered. Snapshot and all four stored message contents had the `v1:PBKDF2:` encrypted format; no recovery error. |
| Follow-up with restored context | PASS | The next genuine Modal request contained four prior user/assistant history entries. Its history fingerprint `41665ef84fb1d046` exactly matched the restored completed-history fingerprint. Response HTTP 200/SSE; six completed messages afterward. A later request used the existing five-message history window. No semantic model-memory claim is needed. |
| Navigation during active SSE | PASS | Separate timing test navigated by the existing Progress link on receipt of the real `latency` SSE event, with `doneAlreadyObserved: false` and `streamEnded: false`. On `/progress`, the session remained pending and the stream had received `latency`, `companion_state`, `risk` but not `done`. Later `done` arrived on `/progress`; returning to Chat retained the same two message IDs, both completed. Exactly one POST, one assistant message, no chat request failure. |
| Logout isolation | PASS | Invoked the application's existing AuthContext `signOut` action in-browser because there is no exposed logout button. The application redirected to `/`, with no signed-in user or conversation session. |
| Account-change isolation | PASS | A second genuine anonymous sign-in in the same browser context changed owner fingerprint from `c7a26dfc158a68f4` to `0cbb9bfdd0024af3`. It created a different conversation with zero inherited messages. Its first actual Modal request contained empty history and completed with its own two messages. |

## Actual Modal/SSE observations

- Origin observed from real application traffic: `https://ahsulem--koi-chat-api-chatserver-web.us-east.modal.run`.
- Endpoint: `POST /api/v1/chat`.
- **Six actual requests** across the acceptance scenarios; all returned **HTTP 200**, `text/event-stream; charset=utf-8`.
- Sanitized event sequence observed: `latency`, `companion_state`, `risk`, `delta`, `state`, `done`. Streams completed without observed chat request failures or page runtime errors. No event data, risk content or trace was captured in the report.
- Authenticated application traffic was not mocked, delayed or fulfilled by a fixture. A passive response-clone observer counted SSE event names and triggered a normal DOM navigation click for the timing test.
- Backend deployment version/build label: **UNKNOWN**. Successful requests do not establish a particular contract/deployment version.

## Limits and remaining follow-ups

- No blocking P0 defect was reproduced. No implementation, authentication, crypto, SSE, avatar or Firestore-path changes were made.
- The onboarding final cloud-sync step did not complete during observation; the authenticated `/chat` route was then opened directly. Authentication was not bypassed. Onboarding completion and remote Firestore sync are **NOT RUN/unverified**, separate from the passing local-history checks.
- VRM visuals, return to the original signed-out anonymous identity, linked-account unlock and offline launch were **NOT RUN** in this acceptance run.
- Earlier fixture/Jest results in the recovery handoff are historical and were not substituted for browser evidence or rerun here. No new production build was needed because application code was unchanged; the actual development application compiled and served the tested routes.
- `git diff --check`: PASS. No commit, push, merge, reset, clean or deployment. No P1–P4 work.
