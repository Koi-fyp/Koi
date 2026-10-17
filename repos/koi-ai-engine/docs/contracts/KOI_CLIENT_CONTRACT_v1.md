# KOI client contract v1 — chat (`/api/v1/chat`) + crisis (`/api/v1/crisis`)

**Status: PROPOSED, chat-generated (Ahmad Suleman + Claude, Oct 16 2026). Not canon until logged into the
Project with a tagged addition. Unverified against a live deployment until the smoke test output is attached.**
Audience: Web (Next.js) and Mobile (Flutter) teams. One contract for both.

Sources: `chat_app.py` (Modal/vLLM build, Sep 22-23 + Oct 15 paste), `crisis_app.py` / `koi_crisis_core.py`
(TSD chat, Oct 14 zip), `koi_policy/` director (Oct 15), Blueprint §4.1 / §4.1d / §4.1e, Handoff §2, §16.

---

## 0. The two services

| Service | Modal app | Path | Transport | Purpose |
|---|---|---|---|---|
| Chat | `koi-chat-api` | `POST /api/v1/chat`, `GET /health` | JSON in, **SSE** out | Companion reply + exercise director |
| Crisis (TSD) | `koi-crisis` | `POST /api/v1/crisis`, `GET /health` | multipart in, JSON out | Per-turn risk score + intervention content |

Base URLs come from `modal deploy` (persistent). Never use a `modal serve` URL in a client build: it changes every session.
Both require `Authorization: Bearer <Firebase ID token>`. Identity is taken from the token only.

**Cold start:** 60-190 s after idle. Modal caps one HTTP request at 150 s. Clients: call `GET /health` on app open
and retry a failed first request once. During a demo window the backend owner sets `KOI_MIN_CONTAINERS=1` (costs GPU time).

---

## 1. Chat — request

`POST {CHAT_BASE}/api/v1/chat`, `Content-Type: application/json`

```json
{
  "message": "string, 1..4000 chars",
  "session_history": [ {"role": "user" | "assistant", "content": "string"} ],
  "exercise_state": "string | null",
  "client_event": "none | playback_done | playback_stopped | start_breathing | start_grounding | start_plan | null",
  "risk": {
    "risk_category": "LOW | MODERATE | HIGH | CRITICAL",
    "crisis_score": 0.0,
    "trigger_flags": ["vocal_contradiction"],
    "is_new": true
  },
  "policy_event": "crisis_resolved | null",
  "crisis_path": "reached_out | said_but_did_not | misunderstanding | null"
}
```

- `session_history` is client-authoritative (the server is stateless). Role `"model"` is accepted and treated as
  `"assistant"` for backward compatibility; any other role is a 422. The server drops the OLDEST turns if the
  history does not fit the model's context window.
- `exercise_state`: opaque signed string. Send back exactly what the last `state` event gave you; `null` on a new
  conversation. Never parse or edit it (an edited token is rejected and the exercise resets).
- `client_event`: `start_*` when the user taps an exercise button; `playback_done` / `playback_stopped` when the
  breathing animation finishes / is stopped by the user. Otherwise `"none"` or omit.
- `risk`: the latest `/api/v1/crisis` result the client holds (section 4). Set `is_new: true` only the first time
  you send a given result. Omit or `null` until the first crisis result arrives.
  **Fail-closed:** with no `risk`, the server never starts or offers an exercise (normal chat still works).
- `policy_event` + `crisis_path`: send once, on the first request after the user finishes UX Flow 4, with the path
  they took (Flow 4's three paths). Until this arrives the conversation stays in crisis mode and every turn carries
  `handoff: crisis`. After sending it, drop the held `risk` result and send `risk` again only when a NEWER crisis
  result arrives (otherwise the old HIGH result re-enters crisis immediately).

## 2. Chat — response (SSE)

`Content-Type: text/event-stream`. Frames: `event: <name>\ndata: <json>\n\n`. Order within one response:

| # | event | data | notes |
|---|---|---|---|
| 1 | `latency` | `{"latency_ms": number}` | server time from request (after auth) to first released content |
| 2 | `ui_action` (urgent, 0..1) | `{"name": "stop_breathing" \| "pause_breathing", "args": {}}` | only mid-exercise; act on it immediately |
| 3 | `companion_state` | `{"emotion": "neutral\|joy\|angry\|sorrow\|fun", "intensity": 0..1}` | always BEFORE any text; drive the avatar now |
| 4 | `delta` (1..n) | `{"text": "string"}` | **reply text only, never JSON.** Exercise turns: one whole sentence per delta |
| 5 | `ui_action` (0..n) | `{"name": "...", "args": {...}}` | e.g. `start_breathing` (args below), `save_task`, `save_go_to` |
| 6 | `handoff` (0..1) | `{"to": "crisis", "reason": "string"}` | show the crisis flow (UX Flow 4) **alongside** the reply; never instead of it |
| 7 | `state` (0..1) | `{"exercise_state": "string"}` | store; echo next turn |
| 8 | `done` | `{"full_text": "...", "companion_state": {...}, "exercise_state": "...\|null", "ui_actions": [...], "handoff": {...}\|null, "total_generation_s": number}` | always last |

Errors before the stream starts are normal JSON: `401 {"detail": ...}`, `422 {"detail": ...}`. Check `res.ok` first.

Backward compatibility: a client that only reads `latency` / `delta` / `done` keeps working and now receives reply
text in `delta`, and `companion_state` in `done`. Unknown events must be ignored.

### Emotion strings
Exactly five: `neutral, joy, angry, sorrow, fun` (VRM presets; Blueprint/Handoff §2). Map these directly to the
avatar. The current Web union `happy | sad | anxious | calm | neutral` does NOT match and must be changed.

### `start_breathing` args (example)
```json
{"pattern": "slow_6_per_min", "inhale_s": 4, "exhale_s": 6, "cycles": 6,
 "cue_audio": ["Breathe in", "Breathe out"],
 "minutes_note": "about one minute; 'at your own pace' (user need not match the avatar)"}
```
Client: run the avatar breathing animation with these timings, play/show the cues, then send
`client_event: "playback_done"` (or `"playback_stopped"` if the user stops it) on the next request.
`cue_audio` is already in the conversation language (en / ur / ur-roman).

## 3. Exercise behaviour the client must support
- Exercises are conversation, not forms: the avatar speaks the `delta` sentences (TTS per sentence).
- A text like "can we do a breathing exercise" also starts one; buttons send `client_event`.
- Mid-exercise distress words → server stops the exercise (`stop_breathing` urgent action) and replies normally.
- `handoff: crisis` can arrive in any turn. Stop any animation, show UX Flow 4, keep the reply visible.
  It repeats on every turn until `crisis_resolved` is sent: if Flow 4 is already on screen, do not open it again.

## 4. Crisis (TSD) — client calls it every turn, in parallel

`POST {CRISIS_BASE}/api/v1/crisis`, `multipart/form-data`, Bearer token.
Fields (each optional, at least one usable input): `text` (typed message), `audio` (file, ≤25 MB, first 30 s),
`video` (file, ≤80 MB, first 60 s), `language`, `turn_id` (echoed only).
Do not send typed `text` together with `audio`.

Response (fields always present unless noted):
```json
{"crisis_score": 0.0, "risk_category": "LOW|MODERATE|HIGH|CRITICAL",
 "modalities_used": ["text"|"audio"|"video"], "trigger_flags": [], "confidence": "standard|reduced",
 "confidence_reasons": ["reduced_modality_set", "..."], "components": {"p_text_negative": 0.0, "text_uncertainty": 0.0},
 "text_source": "typed|asr", "transcript": "only when ASR ran", "turn_id": "only if sent",
 "intervention_content": "ONLY at HIGH/CRITICAL: {source: grounded|fallback, language, items[1-3]{text, chunk_id, source_corpus, evidence_role, review_status}, helpline{name, number, verified}}",
 "timing_ms": {"decode": 0, "models": 0, "total": 0}, "model": {"version": "pilot-0.1", "calibrated": false, "notice": "..."}}
```
Bands: <0.40 LOW, 0.40-0.69 MODERATE, 0.70-0.89 HIGH, ≥0.90 CRITICAL (deployment may cap at HIGH: `GET /health` → `max_category`).

Client rules:
1. Fire it for every user turn **in parallel** with `/api/v1/chat`. Never wait for it before showing the reply.
2. HIGH or CRITICAL → show UX Flow 4 with `intervention_content`; render `source: "fallback"` distinctly; stop any breathing animation.
3. `confidence: "reduced"` → show "limited information" (text-only turns are always reduced).
4. Error or timeout → "no score this turn". Never show or assume "safe"/LOW. Keep the previous indicator.
5. Send the latest result as `risk` in the next chat request (`is_new: true` once).
6. Ignore unknown fields.

## 5. Honest limits (must be disclosed in the demo)
- The crisis score is an **emotion proxy** from a pilot model, not a validated crisis detector; it cannot read
  self-harm content specifically. Synthetic-pair AUROC ≈ 0.62; video adds nothing measurable.
- Helpline: 1166 is Pakistan's national health helpline ("Sehat Tahaffuz", toll-free); the Humraaz mental-health service is reached
  through it (web sources, Mar 2023 press release and a 2026 listing). Those sources do NOT describe it as a crisis or suicide line and
  document no 24-hour service. Nobody has phoned it: `verified` stays false. Fallback/intervention wording is a placeholder or draft.
- Exercise lines in Urdu / Roman Urdu have had no native-speaker review; no clinician has reviewed any line.
- The companion system prompt is a placeholder; the training-time prompt is not on record.

## 6. Open items (owner decides; do not hard-code around them)
Firebase secret fix before any deploy · `KOI_MAX_CATEGORY` (recommend `HIGH`) · RAG hook (stub → builtin fallback
until wired) · CBT module (not built: CBT offers fall back to normal chat) · emotion union change in Web/Flutter ·
`session_history` window size (server only trims to fit).

## v1.1 ADDITIONS (additive; nothing above is changed)
Source of truth: `deploy/modal/chat_core.py`, `deploy/modal/stream_extract.py`, tests in `deploy/modal/test_chat_v11.py`.

- Clients call ONLY `POST /api/v1/chat` and `GET /health`. The server scores crisis risk itself every turn;
  clients never call `/api/v1/crisis` (it stays for tools/explicit checks).
- Request may be JSON (as v1) or `multipart/form-data` with `payload` (JSON string: v1 fields + optional
  `language`, `turn_id`; `message` optional with audio), `audio`, `video`. Allowed: text | audio | text+video |
  audio+video; anything else → 422. Limits: audio 25 MB, video 80 MB. Request `risk` is deprecated and ignored
  when the server has its own result.
- New events:
  - `transcript` `{"text", "language"}` (audio turns): before `companion_state`. Append it to `session_history`
    as the user turn.
  - `risk` `{"status": "ok"|"unavailable", "risk_category", "crisis_score", "confidence", "confidence_reasons",
    "modalities_used", "trigger_flags", "intervention_content"?, "model": {"version", "calibrated"}}`: exactly once,
    after `companion_state`, before `done` (may interleave with `delta`). Server waits at most 5 s after the reply
    (budget 5 s from request start), then sends `{"status": "unavailable"}`. Unavailable never means "safe".
  - No usable reply text from the model: the server retries generation once, then sends one fixed fallback
    line as a normal `delta` (DRAFT, English only). There is always at least one `delta`. (An `error` event
    briefly existed in commit `aca640c`; it is no longer sent. Clients still ignore unknown events.)
- Consecutive `delta`s that form separate sentences (exercise turns) carry a leading space, so
  `"".join(deltas) == done.full_text` and reads as normal prose.
- Debug trace (`done.trace`, `state.trace`) appears only when the server sets `KOI_DEBUG_TRACE` to
  1/true/yes/on; "0", "false", empty or unset = off.
- `companion_state` is always sent before any text. If the model output had no valid state, it is
  `{"emotion": "neutral", "intensity": 0.4}`.
- `state` is always sent, immediately before `done`. `exercise_state` is `null` when no exercise is active;
  store only string values (the reference TS/Dart clients already ignore non-strings).
- `done` gains `risk` (same object as the streamed `risk`).
- `delta` never carries JSON-looking text: replies that are themselves JSON are unwrapped (`reply`, tolerant of
  misspelled keys) or dropped.
