# KOI backend

## What runs where

- `app/` is the local development reference. It uses the base Qwen model from
  the Hugging Face Hub; it does **not** load the LoRA adapter.
- Modal chat is production: the merged LoRA is served through vLLM.
- Modal crisis is the TSD pilot and is an emotion-proxy service, not a
  validated crisis detector.

## Configuration and secrets

Create the Modal secrets by **name**:

- `firebase-service-account`, key `SERVICE_ACCOUNT_JSON`
- `koi-director`, key `KOI_DIRECTOR_SECRET`

The relevant environment flags are `KOI_EXERCISES`, `KOI_MIN_CONTAINERS`,
`KOI_CORS_ORIGINS`, `KOI_DEBUG_TRACE`, `KOI_MAX_CATEGORY`, and
`KOI_RISK_SOURCE`. The crisis deploy also accepts `KOI_FIREBASE_SECRET`,
`KOI_HELPLINE_NAME`, `KOI_HELPLINE_NUMBER`, and `KOI_HELPLINE_VERIFIED`.

## Deploy and smoke checks

```powershell
modal deploy deploy\modal\chat_app.py
modal deploy deploy\modal\crisis_app.py
python deploy\modal\tools\smoke_crisis.py https://<crisis-endpoint>
python deploy\modal\smoke_chat.py https://<chat-endpoint>
```

The first container can take about 60–90 seconds to cold-start. A warm T4 is
approximately $0.59/hour; set `KOI_MIN_CONTAINERS=0` after demos.

The client contract is [`docs/contracts/KOI_CLIENT_CONTRACT_v1.md`](docs/contracts/KOI_CLIENT_CONTRACT_v1.md).

## Honest limits (must be disclosed in the demo)

- The crisis score is an **emotion proxy** from a pilot model, not a validated crisis detector; it cannot read
  self-harm content specifically. Synthetic-pair AUROC ≈ 0.62; video adds nothing measurable.
- Helpline: 1166 is Pakistan's national health helpline ("Sehat Tahaffuz", toll-free); the Humraaz mental-health service is reached
  through it (web sources, Mar 2023 press release and a 2026 listing). Those sources do NOT describe it as a crisis or suicide line and
  document no 24-hour service. Nobody has phoned it: `verified` stays false. Fallback/intervention wording is a placeholder or draft.
- Exercise lines in Urdu / Roman Urdu have had no native-speaker review; no clinician has reviewed any line.
- The companion system prompt is a placeholder; the training-time prompt is not on record.
