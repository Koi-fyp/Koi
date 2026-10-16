# KOI one-endpoint demo runbook

## T-30 warm-up

1. Check `GET /health` on both deployed apps. Source: `deploy/modal/chat_core.py`
   and `deploy/modal/crisis_app.py`.
2. For the demo window, deploy both apps with `KOI_MIN_CONTAINERS=1`; this
   keeps one T4 warm per app (approximately $0.59/hour per warm T4 in the
   project estimate). Return both values to `0` after the demo. Source:
   `agent_tasks/MASTER_NIGHT.md` and the `min_containers` settings in the two
   Modal apps.
3. After a cold start, risk can be `unavailable`; do not start an exercise
   until crisis scoring is warm. Source: `agent_tasks/MASTER_NIGHT.md` P3.3.

## Six-step demo in one chat

1. Send a text message and show streamed companion state and deltas.
2. Send text plus video and show the same chat stream.
3. Send audio and show the `transcript` event before the assistant response.
4. Start a breathing exercise and show `ui_action`/`exercise_state`.
5. Send distress mid-exercise and show the exercise stopping.
6. Trigger HIGH risk and show the non-dismissible Flow 4 handoff.

The event names and ordering are defined by
`docs/contracts/KOI_CLIENT_CONTRACT_v1.md` and the server stream in
`deploy/modal/chat_core.py`.

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
* Do not describe the encryption design with claims beyond the checked-in
  client contract. Do not promise CORS restriction: the current default is
  `KOI_CORS_ORIGINS=*` in `deploy/modal/chat_app.py`.

## Cold/down fallback

If either health check fails, stop the demo, show the connection fallback, do
not start an exercise, and do not imply that a risk score was completed.
Keep the user's local transcript visible where available and retry only after
health returns 200. If crisis scoring is unavailable, use the existing
fallback helpline styling and label the result as unavailable/fallback.
