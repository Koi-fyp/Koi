# ADR-STATE-TOKEN: expiry and versioning for the signed exercise_state token

Status: PROPOSED (batch g0b, H04). No code written. Not agreed with the Web or Flutter owners.
Chat-generated; every number below is a proposal, not sourced, and needs Ahmad's decision.

## 1. Context (what the code does today)

- `koi_policy/state_token.py`: `token = base64url(JSON) + "." + hex HMAC-SHA256(KOI_DIRECTOR_SECRET, base64 part)`.
  Payload is `{**state, "v": 1}`. `verify()` rejects a bad MAC, a malformed token, an undecodable payload and any `v != 1`. [CODE]
- There is no time claim. A valid token is valid forever. [CODE]
- The module docstring already discloses that a client can replay an older valid token. [CODE]
- `director.turn_events()` catches `TokenError` and silently starts from `fresh_state()`; the only signal is a line
  in the `trace` list ("state token rejected (...); started fresh"), which the SSE layer emits only with
  `KOI_DEBUG_TRACE` on. [CODE]
- Every turn re-signs the state (`rev += 1`), so a token never outlives one turn on a well-behaved client. [CODE]
- The payload holds two kinds of state with very different lifetimes [CODE]:
  - `ex`: the running exercise step (minutes).
  - `policy`: offer cooldowns (`GROUNDING_COOLDOWN` 2 h, `CBT_COOLDOWN` 24 h, `CBT_COOLDOWN_AFTER_DECLINES` 72 h),
    `follow_up_due_ts` (24 h after a crisis), `crisis_peak`, `pin_helplines`, `last_crisis_path`, `offer_times`.
- The token is not bound to the user: user A's token is accepted on user B's request. [CODE]

## 2. Problem

1. A stale exercise can resume days later at the step where it stopped.
2. One expiry for the whole token would also wipe `pin_helplines`, `crisis_peak`, `follow_up_due_ts` and the
   cooldowns. Those are the safety and anti-nagging parts, so a blanket reset is the wrong default.
3. Replay inside any lifetime cannot be prevented by a stateless server.

## 3. Decision (proposed)

### 3.1 Claims (additive, optional, server-set)

| claim | meaning | set by |
|---|---|---|
| `iat` | server epoch seconds when signed | `sign()` |
| `ex_exp` | epoch seconds after which `ex` (the running exercise) is dropped; sliding, re-set each turn | `sign()` when `ex` is not null |
| `exp` | epoch seconds after which the whole token is rejected | `sign()` |
| `sub` | `HMAC-SHA256(secret, uid)[:16]`, binds the token to the user | `sign()` given uid |

Proposed values (GUESS, need a decision): `ex_exp = iat + 30 min`; `exp = iat + 7 days`.
7 days is longer than the longest policy horizon (72 h), so whole-token expiry never cuts a live cooldown or
the 24 h crisis follow-up. Only the server clock is used (`time.time()` in chat_core); the client's clock never matters.

### 3.2 Versioning

- Keep `"v": 1` while the new claims are optional. A v1 verifier (rollback) ignores unknown keys:
  `director` does `{**fresh_state(), **st}`, so extra keys are carried and harmless. Rollback therefore
  does not reset anyone's state. [CODE: director.py line 263]
- Bump to `"v": 2` only if a claim becomes mandatory (for example `sub`). At that point a rolled-back
  server would reject every v2 token and reset everyone's policy state, so a v2 bump must ship with a
  "no rollback past this release" note.
- Optional `kid` (key id) for secret rotation: out of scope here; listed so the format leaves room for it.

### 3.3 Expired-token behaviour

| case | behaviour |
|---|---|
| `now > ex_exp`, `now <= exp` | Drop `ex` only, keep `policy`, continue as plain chat. The turn is otherwise normal. |
| `now > exp` | Same as today's rejected token: `fresh_state()`. Nothing safety-relevant can still be live (see 3.1). |
| `sub` mismatch | Reject, `fresh_state()`. |
| no `iat`/`exp` (old v1 token) | Accept; it is re-signed with the new claims on this turn (one-turn migration). |

Silent reset vs additive event: recommend **additive field, no new event**. Add
`"reset": "exercise_expired" | "token_expired" | "token_rejected"` to the existing `state` frame payload and to
`done` (as `exercise_state_reset`, null otherwise). Reasons:
- event names and the `..., state, done` ordering rule stay unchanged;
- clients that ignore unknown keys keep working;
- the client can clear an exercise UI (breathing animation) that would otherwise be left hanging;
- a purely silent reset (today's behaviour) leaves the client showing a step the server has forgotten.
The reply text itself should not change; the reset is a UI signal, not something the companion says.
This is a chat-schema change: per AGENTS.md it needs a golden example validated against the Web and Flutter repos
before it ships.

### 3.4 Replay inside the TTL (limit, disclosed)

A stateless server cannot detect replay of a valid, unexpired token. With this ADR the bounds become:
- the exercise part of a replayed token is usable for at most `ex_exp` (30 min) after it was signed;
- the whole token for at most `exp` (7 days);
- `sub` stops cross-user replay;
- the risk check still runs every turn on the current message, and a HIGH/CRITICAL tier still forces the crisis
  handoff (H02), so replay can never skip a crisis rule.

Residual risk to disclose: replaying a token signed before a crisis drops `pin_helplines`, `crisis_peak` and
`follow_up_due_ts`. Only server-side storage (for example a per-uid `rev` high-water mark or the crisis facts in
Firestore) removes that; it breaks the stateless design and is out of scope for this ADR. Flag for Ahmad.

## 4. Where the change would live

`state_token.py` (claims, verify) and `director.py` (drop `ex` on `ex_exp`, report the reset reason) are protected
files, so implementation needs a batch that permits editing them. chat_core only passes `uid` and `now` and copies
the reset reason into the `state` frame and `done`.

## 5. Tests needed

1. Round trip: `sign()` sets `iat`, `exp`, and `ex_exp` only when `ex` is not null.
2. `now = ex_exp + 1`: `ex` dropped, `policy` (cooldowns, `pin_helplines`, `follow_up_due_ts`) unchanged, reset = `exercise_expired`.
3. `now = exp + 1`: fresh state, reset = `token_expired`.
4. `now = ex_exp - 1`: exercise continues at the same step (boundary).
5. Sliding window: each turn re-signs with a new `ex_exp`.
6. Old v1 token without claims: accepted, re-signed with claims on the same turn.
7. Rollback: a token with the new claims verifies under the current (unchanged) v1 `verify()` and director, state kept.
8. `sub` mismatch (token from uid A on uid B): rejected, reset = `token_rejected`.
9. Tampered `exp` or `ex_exp`: bad signature, rejected.
10. HTTP: expired exercise mid-breathing -> `state` frame has `reset`, `done.exercise_state_reset` matches,
    event order still ends `state, done`, no `ui_action` from the dropped exercise.
11. HTTP: HIGH tier with a replayed old token still emits the crisis handoff.
12. The existing suites stay at their counts (test_director 71, test_policy 44, test_catalogue 34, deploy/modal 86 + g0b).

## 6. Open questions for Ahmad

- TTL values (30 min / 7 days) and whether `ex_exp` slides.
- Whether `sub` binding is mandatory now (forces v2 and blocks rollback) or optional first.
- Whether the additive `reset` field is acceptable to the Web and Flutter owners.
- Whether the pre-crisis replay residual risk is acceptable for the defense build.
