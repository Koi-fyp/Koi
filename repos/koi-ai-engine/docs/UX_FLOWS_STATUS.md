# KOI UX flow status

Status is based on the checked-in backend and the base-client inventory in
`docs/contracts/INTEGRATION_MAP.md`. Flutter UI/wiring is owned by Fatima and
was not touched by this run.

Live backend evidence (17 Oct 2026, `agent_tasks/reports/live/SUMMARY.txt`,
`agent_tasks/reports/live2/SUMMARY.txt`): both apps deployed; English text
chat, auth rejection, trace-OFF stream and the crisis service (text scoring,
HIGH → static fallback) are live-smoked. HIGH-risk content is a static DRAFT
fallback with no clinician review; retrieval is not used in the deployed service
(`agent_tasks/reports/RAG_READINESS.md`). Helpline 1166 is `verified: false`.
CRITICAL is never emitted (`KOI_MAX_CATEGORY=HIGH` default; live `max_category: HIGH`). Server-side risk inside chat returned
`unavailable` on every turn in that build (fixed in P3.2b, not yet deployed).
Urdu and Roman Urdu are **unreliable** live (`live2/emotion_probe.txt`); P3.11
fixes pass local tests only. Multipart audio/video, `transcript` and server
risk → exercise/handoff are **not live-smoked**.

| Flow | Backend support | Web client support | Status | Missing / owner |
| --- | --- | --- | --- | --- |
| 1 onboarding | Existing auth/onboarding routes | Existing onboarding pages | partial | Integration verification / web |
| 2 anonymous session | Firebase auth path; chat/crisis reject bad tokens live | Existing auth context | partial | End-to-end smoke / web |
| 3 text chat | `/api/v1/chat` SSE: English live-smoked; Urdu/Roman Urdu unreliable | Existing hook/transport | partial | Redeploy + smoke for Urdu / web |
| 4 crisis handoff | Crisis service live; HIGH content = static DRAFT fallback (no clinician review), 1166 unverified, CRITICAL never emitted; no retrieval in the deployed service; chat-side risk not live (P3.2b pending deploy) | No production Flow 4 modal consumer | partial | Redeploy + smoke; web |
| 5 emotion/avatar | `companion_state` live (English) and director | Avatar controller and command bridge exist | partial | Connect chat stream to bridge / web |
| 6 audio input | Multipart + ASR: local tests only, not live-smoked | No production chat client | not live-smoked | Web |
| 7 video input | Multipart: local tests only, not live-smoked | No production toggle/path | not live-smoked | Web |
| 8 TTS | Speech assets/voice docs exist | Chat page consumer not wired | partial | Web |
| 9 lip-sync | Rhubarb cue parser and mouth controller exist | Chat playback consumer not wired | partial | Web |
| 10 breathing | Director live (state token in smoke) but cannot start while chat risk is `unavailable` | No production exercise animation consumer | not live-smoked | Redeploy; web |
| 11 grounding/plan | Protected director supports policy events | No production consumer | partial | Web |
| 12 persistence | Local/Firestore helpers exist | Required new user path migration incomplete | partial | Web |
| 13 follow-up | No FCM implementation found | Not built | not built | Web/backend |
| 14 account linking | Auth/linking code exists | Re-encryption return-session flow incomplete | partial | Web |

## CBT

`cbt_module` is a hand-off stub, not a clinical module. A real CBT journey
would need clinically reviewed content, consent and escalation rules,
journey versioning, crisis interruption, localization, accessibility review,
and outcome/safety evaluation. `koi_policy/journeys.json` is protected and was
not changed. Options: keep the hand-off stub; add a separately reviewed
content package; or remove the offer until clinical review is complete.

## Deferred product work

* 24-hour follow-up via FCM is not built.
* Account-linking re-encryption remains post-defense work.
* Firestore rules deployment is not performed here. Ahmad should review,
  deploy in a controlled Firebase project, and run authenticated owner/non-owner
  tests.
* Gate 4-J requires cross-platform crypto mock cases: same salt/payload,
  wrong secret rejection, malformed payload rejection, and account-link
  migration.

Flutter UI and wiring are owned by Fatima, not touched by this run.
