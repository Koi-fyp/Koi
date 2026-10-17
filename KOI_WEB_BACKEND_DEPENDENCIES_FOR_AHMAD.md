# KOI Web integration decisions and backend dependencies

2026-10-17; API freeze applies. This is a request/decision list, not a contract change or authorization to deploy.

| Gate | Required decision/evidence | Current safe frontend behavior |
| --- | --- | --- |
| History/account deletion | Define local messages/snapshots, sync queues, cloud copies, backups, active streams, offline tabs and re-login consequences; authorization, cancellation and receipts. | Controls disabled; no delete success, purge or retention timer. |
| Account linking/unlock | Review existing Admin linking, encryption migration and returning-linked-session unlock as one coordinated flow. Current AuthContext says caller must re-encrypt; no complete account-link UI exists. | Do not expose an unsafe linking action or alter frozen auth/crypto. |
| Cloud preferences/history | Confirm existing users/messages namespace, ownership rules, encrypted payloads, sync receipts and cross-device conflict policy. | Local UID-scoped persistence only; never label an attempt synced. |
| Web reminders/check-ins | Approved trigger/delivery semantics, timezone, completed-check-in writer and encrypted ratings. Blueprint §4.1g specifies in-app due state, not Web Push. | Store preference; no scheduler, push permission or fabricated AI message. |
| Jigsaw awards | Approved eligible activity units, piece rates/caps, dedup identity, milestones and board mapping. Blueprint leaves model open. | Preserve existing read model; no new rewards or inferred mood/streaks. |
| Deployed service evidence | Release SHA/version, supported modalities and redacted SSE fixtures for the existing integration. | Preserve accepted text API; no new endpoint/probe/transport changes. |
| Clinical report inputs | Approved encrypted check-in/safety event sources, consent/provenance and interpretation policy. | No diagnosis, improvement claim, synthetic crisis incident or fabricated resolution. |
| Media/native gates | Separate approval and demonstrated ASR/TTS/video contract, consent and cleanup; real Android Gate 2-J jointly. | Media remains disabled; no Flutter edits. |
| Public support contacts | Reviewed sources, applicability and verified service hours for any static helpline listing. | Do not invent or guarantee service availability. Frozen server-provided crisis UI remains unchanged. |

No requested capability justifies implementing a new endpoint under this freeze. Blocking decisions do not stop independent local UI fixes.
