# KOI Speech API v1 — `POST /api/v1/speech` — **PROPOSED, NOT DEPLOYED**

> **PROPOSED, NOT DEPLOYED.** Code exists in `deploy/speech/` (Modal app `koi-speech`) and passes offline
> tests with stubbed Piper / Rhubarb / Firebase only. It has never been built on Modal, never run with the real
> Piper or Linux Rhubarb, and never called by a client. Not agreed with the Web or Flutter owners.
> Source of truth for behaviour: `deploy/speech/speech_core.py`. Earlier design notes:
> `E:\Koi\voice-lab\SPEECH_API_PROPOSAL.md`, `ADR-VOICE-PLACEMENT.md` (option B, separate CPU worker).

## 1. Service

| item | value |
|---|---|
| Modal app | `koi-speech` (separate from `koi-chat-api` and `koi-crisis`), CPU only (`cpu=2`, `memory=2048`), no GPU |
| Scaling | `scaledown_window=300`, `min_containers` = env `KOI_SPEECH_MIN_CONTAINERS` (default `0` ⇒ cold starts happen) |
| Engine | Piper `piper-tts==1.8.0` + `onnxruntime==1.31.0` (Python API, CPU) → WAV → Rhubarb Lip Sync 1.14.0 Linux |
| Voices | Modal Volume `koi-voices`, mounted read-only at `/voices` (`<id>.onnx` + `<id>.onnx.json`) |
| Auth | Firebase ID token, verified as in `deploy/modal/crisis_app.py`; Modal secret `firebase-service-account` |
| Base URL | its own `*.modal.run` URL (different origin from chat); clients need a configurable speech base URL |

## 2. `GET /health` (no token)

```json
{"voices_found": ["aisha_en", "aisha_ur", "raza_en", "raza_ur"], "rhubarb_found": true}
```

Nothing else is reported. A voice is listed only if its model loaded at container start.

## 3. `POST /api/v1/speech`

```
Authorization: Bearer <Firebase ID token>
Content-Type: application/json; charset=utf-8
```

### 3a. Request (exactly these four string fields; any other field → 422 `invalid-request`)

```json
{
  "text": "السلام علیکم، آج آپ کیسے ہیں؟",
  "voice_id": "raza_ur",
  "language": "ur",
  "generation_id": "3f1c2b9e-6c1d-4f5e-9a51-0d6b7f0e2a11"
}
```

| field | rule |
|---|---|
| `text` | non-empty after trimming; at most **450** characters (code points) before trimming; one sentence-sized chunk; plain text |
| `voice_id` | one of the allowlist below; anything else (including `fox` and raw Piper ids) → 422 `voice-not-allowed` |
| `language` | `"ur"` or `"en"`, and must equal the voice's language (else 422 `language-mismatch`); other values → 422 `invalid-request` |
| `generation_id` | a UUID string, client-generated, echoed back; use it to drop stale responses |

Request body larger than 8 KiB → 413 `text-too-long`.

| `voice_id` | Piper model | language | Rhubarb recognizer |
|---|---|---|---|
| `raza_ur` | `ur_PK-fasih-medium` (male) | `ur` | `phonetic` |
| `aisha_ur` | `ur_PK-aegis_female-medium` (female) | `ur` | `phonetic` |
| `raza_en` | `en_US-hfc_male-medium` (male) | `en` | `pocketSphinx` |
| `aisha_en` | `en_US-hfc_female-medium` (female) | `en` | `pocketSphinx` |

**Language guard (server, rejects with 422 `language-mismatch`):**
- `ur` voices: text must contain at least one Urdu/Arabic-script letter and **no** Latin letters (and no letters of any other script).
- `en` voices: text must contain at least one Latin letter and **no** Urdu/Arabic-script characters (letters, digits or punctuation such as `،` `۔`), and no other-script letters.
- Mixed-script text is rejected by both. Digits/punctuation-only text is rejected by both.
- **Roman Urdu cannot be detected** (it is Latin script, so an `en` voice would accept it and read it with English
  pronunciation). The client must keep Roman Urdu replies **text-only** and never send them here.

### 3b. Success — 200 (field order as sent)

```json
{
  "generation_id": "3f1c2b9e-6c1d-4f5e-9a51-0d6b7f0e2a11",
  "voice_id": "raza_ur",
  "audio_format": "wav",
  "sample_rate": 22050,
  "audio_b64": "UklGR...",
  "mouth_cues": [{"start": 0.0, "end": 0.12, "value": "X"}, {"start": 0.12, "end": 0.3, "value": "B"}],
  "duration_s": 1.231,
  "timings_ms": {"synthesis": 0, "cue_extraction": 0, "total": 0}
}
```

Values are schema examples, not measured output. `sample_rate` is read from the WAV Piper wrote (not assumed).
`mouth_cues` are Rhubarb's `mouthCues` unchanged (only `start`, `end`, `value` kept), after server validation with
`deploy/speech/cue_validator.py` (copy of `voice-lab/cue_validator.py`): shapes A–H/X, finite, ordered,
non-overlapping, first start ≤ 0.05 s, last end within ±0.05 s of `duration_s`. Cues are never invented or padded.
Every response carries `Cache-Control: no-store`.

### 3c. Errors — body is always `{"error": {"code": "<code>"}}` (no message, input never echoed)

| HTTP | code | when |
|---|---|---|
| 400 | `invalid-request` | body is not JSON or not a JSON object |
| 422 | `invalid-request` | missing/extra fields, non-string field, bad UUID, empty/whitespace text, language not `ur`/`en` |
| 401 | `unauthenticated` | no `Authorization: Bearer`, or the Firebase token fails verification (checked before the body) |
| 413 | `text-too-long` | `text` > 450 chars, or body > 8 KiB |
| 413 | `audio-too-long` | synthesized audio > 40 s (checked before Rhubarb runs) |
| 422 | `voice-not-allowed` | `voice_id` not in the allowlist |
| 422 | `language-mismatch` | `language` ≠ voice language, or the text fails the language guard |
| 429 | `rate-limited` | > 10 requests per 60 s per uid (sliding window); `Retry-After` header in seconds |
| 503 | `speech-unavailable` | voice not loaded, Rhubarb missing, Piper failed, Rhubarb failed or exceeded its 30 s timeout, cue validation failed, any other server error |

Check order: auth → rate limit → body/fields → voice → language field → empty → length → language guard → synthesis.
The rate limit counts every authenticated request, valid or not.

## 4. Client rules (both clients)

1. **Speak only after `done.full_text` is complete** for the chat turn. Never send partial `delta` text.
2. **Urdu-script replies → `ur` voices; English replies → `en` voices.** Pick `raza_*` / `aisha_*` from the avatar.
3. **Roman Urdu and mixed-script replies stay text-only** (no request). The server cannot detect Roman Urdu.
4. **Chunk sentence by sentence**: one request per sentence (≤ 450 chars), played in order; send the next while the
   current one plays if desired. Split overlong sentences at a clause boundary on the client.
5. **Cancel** (abort the fetch, stop playback, discard any late response by `generation_id`) on: user stop,
   new turn, avatar switch, and **crisis handoff**.
6. Treat every error as "no audio for this chunk": show the text, do not retry automatically except after
   `Retry-After` for 429 (503 carries no `Retry-After`).

## 5. Privacy and logging

- Text, audio, tokens and uid are never logged. One log line per request: `voice_id`, char count, outcome code,
  stage timings. Engine errors log only the exception type name.
- No persistence: WAV and cue files live in a per-request `TemporaryDirectory` (`koi-speech-*`) removed on every
  exit (success, 413, 503); stale `koi-speech-*` folders are swept at container start.
- Text goes to no third party: Piper and Rhubarb run inside the `koi-speech` container.

## 6. Known gaps and contradictions (not resolved here)

- **Client caps disagree:** `voiceContract.ts` (per `SPEECH_API_PROPOSAL.md` §1b) requires `0 < duration_seconds <= 30`,
  `voice === 'ur_PK-fasih-medium'`, `language === 'ur'`, `content_type`, `audio_sha256`, field names
  `audio_base64` / `duration_seconds`, and error codes `invalid-input` / `processing-failed` / `busy`. This contract
  uses `audio_b64` / `duration_s`, public voice ids, a 40 s cap, no `audio_sha256`, and the codes in §3c.
  The client parser must change before it can use this endpoint. 40 s of 22.05 kHz 16-bit mono ≈ 1.76 MB, under
  `SpeechPlayback`'s 2 MiB blob cap.
- `voice_id` is chosen by the client; the server does not check it against the user's stored avatar.
- Rate limit is per container, in memory; with several containers a user can exceed 10/min in total.
- Local measurements (Windows): 599 Urdu chars ≈ 41–46 s audio, so text near 450 chars may still hit
  `audio-too-long`; one sentence per request avoids it.
- UNKNOWN until Ahmad deploys: piper-tts 1.8.0 / onnxruntime 1.31.0 on Linux CPython 3.11 (local tests were Windows
  CPython 3.14); the Linux zip's folder layout (`/opt/rhubarb/*/rhubarb` is globbed); Rhubarb Linux `pocketSphinx`
  resources; cold-start time; CPU cost; licences of the three non-Fasih voices; Piper GPL-3.0 server-side use.
- **Rhubarb download checksum is a TODO placeholder** in `speech_app.py`; until it is filled in, the image build
  prints a WARNING and the zip is not verified.
