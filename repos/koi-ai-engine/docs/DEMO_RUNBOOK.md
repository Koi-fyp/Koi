# KOI one-endpoint demo runbook

## What the live smoke proved (17 Oct 2026)

Evidence: `agent_tasks/reports/live/SUMMARY.txt` (deploy run) and
`agent_tasks/reports/live2/SUMMARY.txt` (smoke-only run). Deployed code is the
P3.10 build (image fix `3aa1231`); the P3.4b, P3.11 and P3.2b commits are
**not deployed yet**.

| Claim | Live status | Evidence |
| --- | --- | --- |
| Chat app deployed, `/health` answers | proven | `live/SUMMARY.txt`: chat deploy rc=0, chat ready rc=0 |
| Chat rejects missing/invalid auth | proven | `live2/chat_auth_check` rc=0 |
| English text chat streams `latency, companion_state, risk, delta, state, done` | proven | `live2/smoke_chat.txt` rc=0 |
| No debug/trace leak on the trace-OFF deploy | proven | `live2/trace_check.txt`: "trace contract passed: 3 turns" |
| English emotions (7 prompts) in the 5-value enum, `companion_state` before text | proven | `live2/emotion_probe.txt` (en rows) |
| Crisis app deployed, `/health` ok (ASR on, heads loaded, uncalibrated) | proven | `live2/crisis_ready.txt`, `smoke_crisis.txt` |
| Crisis rejects missing/invalid auth | proven | `live2/crisis_auth_check` rc=0 |
| Crisis text scoring: LOW / HIGH, HIGH → fallback content, 1166 `verified: false`, empty request → 422 | proven | `live2/smoke_crisis.txt` |
| Server-side risk inside chat | **not working in the deployed build**: every chat turn shows `risk {"status": "unavailable"}` | `live2/smoke_chat.txt`; cause fixed in P3.2b (wrong Modal lookup, stub `score`), not deployed |
| Urdu / Roman Urdu chat | **unreliable**: Roman Urdu leaked JSON into the reply; Urdu script produced no `companion_state`/`delta`; Roman Urdu prompts were answered in English | `live2/emotion_probe.txt` rc=1 |
| Multipart (audio, video), `transcript` event, server risk → exercise/handoff | **not live-smoked** | local tests only (`deploy/modal/test_chat_v11.py`) |

P3.11 (language robustness) has local tests that pass (see
`agent_tasks/reports/HANDOFF_FOR_REDEPLOY.md`), but Urdu and Roman Urdu stay
**unreliable for the demo** until the redeploy is smoke-tested. Chat
`chat_ready` in `live2` returned rc=-1073741510 (the probe was interrupted);
the other chat steps in the same run passed.

## T-30 warm-up

1. Check `GET /health` on both deployed apps (`deploy/modal/chat_core.py`,
   `deploy/modal/crisis_app.py`).
2. For the demo window, deploy both apps with `KOI_MIN_CONTAINERS=1`; this
   keeps one T4 warm per app (approximately $0.59/hour per warm T4 in the
   project estimate). Return both values to `0` after the demo. Source:
   `agent_tasks/MASTER_NIGHT.md` and the `min_containers` settings in the two
   Modal apps.
3. After a cold start, risk can be `unavailable`; with `unavailable` risk no
   exercise starts (fail-closed, `deploy/modal/chat_core.py`). In the current
   deployed build risk is always `unavailable` (see table).

## Six-step demo in one chat

1. Text message (English): streamed companion state and deltas. **Live-proven.**
2. Text plus video: same chat stream. Not live-smoked.
3. Audio: `transcript` event before the assistant response. Not live-smoked.
4. Breathing exercise: `ui_action`/`exercise_state`. Not live-smoked; cannot
   start in the deployed build because chat risk is always `unavailable`.
5. Distress mid-exercise: exercise stops. Not live-smoked.
6. HIGH risk: non-dismissible Flow 4 handoff. Not live-smoked through chat; the
   crisis service alone returned HIGH + fallback content in `smoke_crisis.txt`.

Event names and ordering: `docs/contracts/KOI_CLIENT_CONTRACT_v1.md` (incl.
"v1.1 ADDITIONS") and `deploy/modal/chat_core.py`.

## Say / do not say

* Say that emotion is a proxy signal, uncalibrated, and not a probability.
  The pilot AUROC is approximately 0.62; Roman Urdu is blind. Source:
  `agent_tasks/reports/P2_REPORT.md`.
* Say that HIGH content is either a fixed fallback or flagged RAG content.
  The 1166 number is unverified (`verified: false` in the live smoke output).
* Say that fixed exercise lines have not received clinical review; LLM
  acknowledgements fall back when rejected. Source:
  `agent_tasks/reports/live/05_smoke_chat.txt`.
* Say that CBT is a hand-off stub, not a clinical treatment module.
* Do not demo Urdu or Roman Urdu as working until a post-redeploy smoke shows it.
* Do not describe the encryption design with claims beyond the checked-in
  client contract. Do not promise CORS restriction: the current default is
  `KOI_CORS_ORIGINS=*` in `deploy/modal/chat_app.py`.

## Cold/down fallback

If either health check fails, stop the demo, show the connection fallback, do
not start an exercise, and do not imply that a risk score was completed.
Keep the user's local transcript visible where available and retry only after
health returns 200. If crisis scoring is unavailable, use the existing
fallback helpline styling and label the result as unavailable/fallback.
