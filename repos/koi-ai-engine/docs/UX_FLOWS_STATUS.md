# KOI UX flow status

Status is based on the checked-in backend and the base-client inventory in
`docs/contracts/INTEGRATION_MAP.md`. Flutter UI/wiring is owned by Fatima and
was not touched by this run.

| Flow | Backend support | Web client support | Status | Missing / owner |
| --- | --- | --- | --- | --- |
| 1 onboarding | Existing auth/onboarding routes | Existing onboarding pages | partial | Integration verification / web |
| 2 anonymous session | Firebase auth path | Existing auth context | partial | End-to-end smoke / web |
| 3 text chat | `/api/v1/chat` JSON SSE | Existing hook/transport | partial | v1.1 risk wiring / web |
| 4 crisis handoff | Crisis service and director handoff | No production Flow 4 modal consumer | partial | Web |
| 5 emotion/avatar | `companion_state` and director | Avatar controller and command bridge exist | partial | Connect chat stream to bridge / web |
| 6 audio input | ASR exists in crisis app | No production chat multipart path | partial | Web |
| 7 video input | Crisis media contract exists | No production toggle/path | partial | Web |
| 8 TTS | Speech assets/voice docs exist | Chat page consumer not wired | partial | Web |
| 9 lip-sync | Rhubarb cue parser and mouth controller exist | Chat playback consumer not wired | partial | Web |
| 10 breathing | Protected director supports exercise state | No production exercise animation consumer | partial | Web |
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
