# Increment 5: JSON chat and avatar integration

## Confirmed source contract

`koi-ai-engine/app/api/routes.py` implements POST /api/v1/chat with
Depends(verify_firebase_token) and response_model=ChatResponse. The checked-in
route returns ordinary JSON from a synchronous generate_reply call. There is
no implemented SSE transport or token streaming. The older /ai auth middleware
is not installed by main.py and is not the /api/v1/chat authorization boundary.

Request:

```json
{"message":"text","session_history":[{"role":"user","content":"text"},{"role":"assistant","content":"reply"}]}
```

Response:

```json
{"reply":"text","companion_state":{"emotion":"joy","intensity":0.7},"latency_ms":150}
```

History roles are user/assistant; legacy model is normalized only at the client
adapter boundary. Backend emotion is currently a free-form string, not a locked
five-label enum. Frontend presentation recognizes neutral/joy/angry/sorrow/fun;
unknown/missing labels become neutral with zero intensity, without changing the
reply or inventing a crisis outcome. Finite numeric intensity is preserved and
clamped to [0,1]; the controller independently caps rendered weights at 0.65.
Latency is completed generation time (excluding initial model loading), NOT TTFT.

Auth failures return HTTP 401 detail JSON. Request validation normally yields
422 detail JSON. Exhausted structured generation yields 502 detail JSON;
other errors may be 500/plain text. The frontend exposes a generic status/error,
never arbitrary response bodies or raw private message/generation logs. Raw
malformed-generation snippets were removed from backend diagnostics only;
route, auth, inference model and success schema were not changed.

HTTP redirects are rejected so private request bodies/credentials are not redirected to another endpoint.

Client timeout is 45 seconds for the HTTP request, with AbortSignal cancellation.
Token lookup, Firebase salt reads and already-issued IndexedDB writes cannot
be forcibly cancelled. Guards stop further work after they settle. Client abort
does NOT cancel the synchronous backend GPU inference; no server-side
request-disconnect handling/cancellation endpoint exists. There is no fabricated
SSE/onDelta path. The narrow ChatAdapter interface can support a verified future
transport independently of the UI/session state.

## Stage A (Firebase-independent, verified locally)

Run npm run dev:avatar and open http://127.0.0.1:3001/mock-chat.
The mock adapter lives under dev/avatar-sandbox, refuses non-development mode,
and accepts only whitelisted scripted sample commands. The input is read-only;
no real mental-health text is sent, no records are saved and no tokens are
created. Responses use the real JSON schema. Failure/slow samples exercise
error/cancellation behavior. Original /companion-scene and /avatar-viewer demos
remain intact.

ConversationSession is the single message/request/companion-state source of
truth for both adapters. It snapshots the latest completed history (last five
messages), cancels superseded requests and ignores late results by generation.
Failed/cancelled requests are visibly distinct and are not inserted as synthetic
AI replies or sent as completed history. React unmount cancels the session;
model switching does not restart the chat. Thinking means waiting, listening
means text input focus, speaking means displaying a text reply only, and idle
means initial/error/cancelled or unfocused input. No audio is played.

If the VRM fails, it unmounts and the text transcript/composer remain usable.
Mock samples never use the authenticated application, Firebase, FastAPI, speech,
media, Flutter or external inference providers.

## Stage B (implemented; live verification blocked)

The existing (authenticated) layout still protects the new production
/companion-scene route. /chat links to it and remains a text UI using the same
useChat/session/service path. No authentication guards or AuthProvider behavior
were bypassed. Production has no mock adapter imports or environment toggle.

conversationService requires the current SDK user/UID, verifies the caller's
linked state, gets the real Firebase ID token and sends Bearer authorization.
Identity is never supplied in JSON. UID/account-state changes abort further
work. Missing API base produces a configuration error, not a same-origin call.
Linked accounts without a session secret remain locked. useChat accepts an
optional linkedSecret for a future approved unlock flow; it does not store or
invent one. The existing returning-linked-account unlock UI is still absent.

Existing PBKDF2/AES-GCM algorithm, salt policy, ciphertext format and Firestore
sync collection paths are unchanged. Explicit AuthState is now supplied to the
existing crypto helper. Empty-session reads no longer generate salt. Concurrent
anonymous first-use lookups share only an active promise to avoid competing
salt creation; resolved secrets/contexts are not retained in that lookup map.
Linked salt failures never fall back to anonymous encryption.

The user record is encrypted/persisted before the AI request, preserving prior
ordering. The assistant reply is encrypted/persisted only on success. Cancellation
does not delete a write already committed before abort; a committed local write
is still queued as the same ciphertext for sync consistency. There is no fake
connectivity reply persisted as assistant output. Crypto/decryption failures are
shown as locked/storage errors; raw ciphertext is not displayed as plaintext.

### Additive metadata compatibility (no destructive migration)

Dexie schema version/indexes remain unchanged. Old encrypted message records
remain readable without rewrite. The legacy emotion enum is retained for older
readers; new assistant records additionally carry optional companion_state
(emotion/intensity) for lossless presentation. Joy projects to legacy happy,
sorrow to sad, fun to calm, and other labels to legacy neutral. Reads prefer
companion_state; older happy/sad records receive a conservative UI-only default
intensity of 0.5, not a claimed backend measurement. Other old labels are neutral.
Confidence/crisis/sentiment fields remain readable when present; new chat records
omit them because the actual chat API does not provide them. In particular,
missing crisis classification is never defaulted to false or zero. The crisis
endpoint/trust boundary is untouched.

### Configuration required for an authenticated run

- Next.js .env.local: existing NEXT_PUBLIC_FIREBASE_* settings and FIREBASE_ADMIN_SDK
  for existing anonymous/link-email API routes.
- NEXT_PUBLIC_KOI_API_BASE: absolute self-hosted FastAPI base URL, e.g.
  http://localhost:8000 (not the full /api/v1/chat path). Rebuild/restart after
  changing public build-time configuration.
- Backend: its existing Firebase Admin configuration, installed Python/runtime
  dependencies and an available self-hosted inference model.
- NEXT_JS_ORIGIN must match the real frontend origin for CORS (default
  http://localhost:3000). The isolated sandbox does not call that endpoint.
- Returning linked accounts require the missing approved session-unlock flow.

No credential files, fake tokens or deployment URLs were created for this work.
Live FastAPI inference, Firebase persistence and authenticated end-to-end behavior
have NOT been verified. The available Python environment lacks FastAPI/Pydantic;
port 8000 was not listening at audit time. Full-app html2pdf.js, crypto buffer,
onboarding and test-typing failures remain outside this increment.

## Verification commands and scope

- npm run typecheck:avatar: strict Firebase-free graph.
- node scripts/test-chat-contract.cjs: pure/in-memory contract, HTTP fixtures,
  history, timeout/cancel, stale results, real mock production guard and the
  real service's unauthenticated rejection. No fabricated Firebase token.
- python scripts/verify_backend_chat_contract.py: AST/source/syntax checks only;
  NOT a running API or model test.
- node scripts/verify-mock-chat.cjs: real browser/VRM + deterministic local mock.
- Existing test-avatar-controller, verify-avatar, verify-companion-ui and
  verify-avatar-animation scripts: avatar and UI regressions.
- Full TypeScript check reports remaining known application errors; historical
  omitted-AuthState caller errors are fixed. No full-app success is claimed.

Browser scripts use existing Playwright Chromium or KOI_AVATAR_BROWSER.
Artifacts are in the ignored sandbox .next/verification/increment-5 directory.
Stage A can proceed independently; Stage B's essential live acceptance remains
blocked until the configuration and unlock prerequisites are supplied.
