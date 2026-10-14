# Increment 6B.1: real local Piper and Rhubarb pipeline

## Confirmed audit

Started on feat/web-vrm-avatar with a clean Git working tree. Read the 6A speech
architecture, playback/cue/mouth modules and tests, sandbox route/UI, FastAPI
routes/services/requirements and available repository documentation. FastAPI
still provides health/chat only; no speech service is deployed. No newer full
blueprint/specification files were found; referenced Blueprint and TRACK files
were not available and are not claimed to have been read.

Piper/Rhubarb were initially unavailable. The actual developer runtime is
Windows x64, CPython 3.14.2. No Firebase, crypto, chat JSON, LLM/crisis, Flutter,
renderer/controller or microphone/camera changes were made.

## Reproduce (Windows x64 / Python 3.14)

From repos/koi-backend/nextjs_app:

    python scripts/setup-speech-tools.py
    python scripts/generate-piper-samples.py
    npm run dev:avatar

Open http://127.0.0.1:3001/speech-lab and select a Piper sample, then click Play.
The 6A baseline remains the default. If its ignored fixture needs regeneration:

    powershell -NoProfile -File scripts/create-speech-fixture.ps1

setup-speech-tools.py creates an isolated ignored .speech-tools/venv, installs
only binary wheels from official PyPI with a complete version/hash lock, and
checks model/config/card/archive hashes. Nothing is installed globally. The
lock targets tested Windows/Python 3.14 wheels; it is not a Linux deployment lock.
Piper 1.8.0, ONNX Runtime 1.31.0 and the remaining versions/hashes are recorded in
scripts/speech-requirements.lock.txt. The selected engine has a Windows abi3 wheel
and ran successfully on this machine.

Official voice revision: c10ece1aade47bb51c153c893d14e5bf8e5b7117.
Model SHA256: 46d590b90fbb41e4d4f2c54ded44874917f8b11b6e0500de2a89e5d3731b5917.
[Official voice files](https://huggingface.co/rhasspy/piper-voices/tree/c10ece1aade47bb51c153c893d14e5bf8e5b7117/ur/ur_PK/fasih/medium)
are downloaded from the pinned revision. Config confirms ur_PK, eSpeak ur,
one speaker and 22050 Hz. Model, config and card were actually downloaded and
validated. The model's trusted SHA256 comes from official Hugging Face LFS
metadata; config/card digests record the fetched pinned files.

Rhubarb reports version 1.14.0. Download:
https://github.com/DanielSWolf/rhubarb-lip-sync/releases/download/v1.14.0/Rhubarb-Lip-Sync-1.14.0-Windows.zip
Archive SHA256: 62fa416a8d5e382a3828ee4bef358ce520d0b4cabdeaea75a7ac266d098d1fe3.
The official release API did not publish an asset digest; this hash pins the
observed official HTTPS download, not an independently signed attestation.
Archive paths are checked before extraction. Licenses/notices remain in the
ignored tools directory, including PIPER_COPYING and the complete Rhubarb release.
No executable, wheel, voice binary or generated sample is added to Git.

## Actual commands, format and measured results

The generator sends fixed, non-sensitive UTF-8 evaluation text to real Piper:

    .speech-tools/venv/Scripts/python.exe -X utf8 -m piper --model ur_PK-fasih-medium.onnx --config ur_PK-fasih-medium.onnx.json --output-file SAMPLE.wav

Actual paths are rooted under the dev sandbox; full commands are recorded in
each local manifest. UTF-8 is explicit to avoid Windows console mojibake.
Actual cue command:

    rhubarb.exe -r phonetic -f json -o SAMPLE.cues.json SAMPLE.wav

English uses -r pocketSphinx; Urdu/mixed use phonetic. No dialog-file hints or
manual timing are inserted. Original raw Rhubarb JSON is retained and its
mouthCues are copied unchanged after finite/order/value/duration validation.
Validation permits 50ms tolerance for rounded Rhubarb duration metadata. Actual
metadata-minus-PCM differences were -0.658ms (Urdu), -6.054ms (English), and
-5.147ms (mixed). There was no conversion, offset shift or time rescaling.

| Sample | Fixed text | WAV duration | Piper CLI elapsed | Rhubarb elapsed | Cues |
|---|---|---:|---:|---:|---:|
| piper-urdu | Simple Urdu-script sentence (see manifest/subtitles) | 1.231 s | 8.958 s | 0.931 s | 10 |
| piper-english | Hello. This is a simple test sentence. | 2.856 s | 3.268 s | 2.462 s | 15 |
| piper-mixed | Urdu sentence containing the English word weather | 1.335 s | 3.794 s | 0.544 s | 10 |

All use ur_PK-fasih-medium, including female avatar previews: no female voice
selection was implemented. All output WAVs are mono 16-bit PCM at 22050 Hz,
nonempty/nonzero and browser-decoded successfully. Timings are observed whole
CLI wall times including process/model initialization; they are not warm-service
or production latency promises. Piper's normal synthesis noise defaults remain;
regeneration may change bytes/timing, with new pairing hashes recorded each time.

Synthesis and automatic cues succeeded for all three inputs. English and mixed
text are feasibility probes through an Urdu voice, NOT confirmed language support.
Pronunciation, subjective mouth-animation quality, Roman Urdu and objective
phoneme accuracy remain unverified. Successful JSON cues do not establish natural
Urdu alignment. The engine output is local, not Windows David or cloud inference.

## Pairing, sandbox and verification

Each ignored manifest records exact transcript, voice/language, format, duration,
processing times, commands, audio SHA256, raw cue SHA256 and real cue provenance.
The generator unpublishes its old manifest before generation and atomically
publishes success only after both stages validate. Failures publish no success
or manual-cue fallback; subprocesses have 180s limits and return safe errors.
Only fixed sample names are served by the dev-only allowlisted fixture route.
Real WAV requests include the manifest hash; a changed/mismatched file returns
409 so stale cues cannot silently accompany regenerated audio.

The existing single SpeechPlayback/VRM animation architecture and approximate
Rhubarb-to-VRM mapping are reused unchanged. Sample switching cancels old loads,
stops audio and disables Play until validation succeeds. Model switching also
stops playback. Labels distinguish actual Rhubarb data from the unchanged 6A
Windows/manual baseline. Production routes contain no speech lab or endpoint.

Run:

    python scripts/test-piper-pipeline.py
    node scripts/test-speech.cjs
    node scripts/verify-piper-speech.cjs
    node scripts/verify-speech.cjs
    npm run typecheck:avatar

Also run existing controller/chat pure tests and verify-avatar,
verify-companion-ui, verify-avatar-animation, verify-mock-chat regressions.
Browser tests use the existing Chromium via KOI_AVATAR_BROWSER. Real-cue browser
artifacts are ignored under .next/verification/increment-6b1 (samples/results JSON
and desktop/mobile screenshots). They validate file pairing, real cue-driven
weights against consumed audio time, both models, all emotions, blinking,
pause/resume/seek/stop/end, rapid commands/switches and cleanup. There is no media
capture or external inference request. Headless Chromium mutes output. Windows SoundPlayer separately accepted the
generated Urdu WAV on the default audio device without an API error (1.925s
whole PlaySync call). That is not a human audibility or pronunciation check;
those and subjective alignment still need a listener.
Full-app known html2pdf.js, crypto buffer, onboarding and Jest type errors remain
outside this increment.

## Licensing and deployment decisions

The pinned [Fasih card](https://huggingface.co/rhasspy/piper-voices/blob/c10ece1aade47bb51c153c893d14e5bf8e5b7117/ur/ur_PK/fasih/medium/MODEL_CARD)
declares MIT for the voice. Retain its notice/card with any approved distribution.
The selected [Piper license](https://github.com/OHF-Voice/piper1-gpl/blob/v1.8.0/COPYING)
is GPL-3.0-or-later: binary/container redistribution needs the applicable license,
notices and corresponding-source obligations. GPL distinguishes network-only
interaction from conveying software copies; a deployment/distribution plan must
identify which is occurring. This work does not relicense KOI or approve bundling
Piper into Next.js/Flutter. Track eSpeak-ng, ONNX Runtime and other bundled notices
separately. [Rhubarb's release license](https://github.com/DanielSWolf/rhubarb-lip-sync/blob/v1.14.0/LICENSE.md)
is MIT with additional dependency notices; preserve the release notices if
redistributing it. Linux/EC2 packaging, resource/concurrency limits and licensing
policy need Ahmad/project approval and a separate platform smoke test.

## Minimal future authenticated contract (PROPOSAL ONLY)

Ahmad must agree endpoint naming, approved voice/language combinations, limits,
authenticated audio delivery, cancellation, retention, worker placement and
license policy. No /api/v1/chat field was added and no production speech endpoint
was implemented. The same self-hosted worker should serve Next.js and Flutter;
clients differ only in authenticated transport/audio presentation.

For a bounded first version, recommend authenticated POST /api/v1/speech with
real Firebase Bearer verification, text, voice=ur_PK-fasih-medium and language=ur-PK.
UID comes only from the verified token. An optional request correlation ID is
not identity. Reject unknown voice/language combinations rather than claiming
English support from these probes. Limit text length/audio duration and per-UID
jobs before scheduling synthesis.

Recommend one completed JSON response for short utterances:

```json
{
  "request_id": "server-generated-id",
  "audio": {
    "encoding": "base64", "content_type": "audio/wav",
    "sample_rate_hz": 22050, "channels": 1, "bits_per_sample": 16,
    "duration_seconds": 1.23, "sha256": "sha256-of-wav", "data": "base64-wav"
  },
  "mouth_cues": [{"start": 0.0, "end": 0.1, "value": "X"}],
  "cue_generator": {"engine": "rhubarb", "recognizer": "phonetic", "version": "1.14.0"},
  "timings_ms": {"synthesis": 0, "cue_extraction": 0}
}
```

Values above are schema examples, not measured/deployed output. Inline base64
adds transfer overhead but avoids public media URLs/token query strings and a
second media authorization endpoint for short bounded clips. Next.js could
validate authenticated bytes and create a short-lived owned Blob URL; Flutter
could consume the same bytes/cues without a second TTS system. Supporting Blob
URLs and their cleanup in SpeechPlayback is future work: current playback remains
same-origin HTTP(S) only. If longer clips require authenticated binary media,
agree an alternative owner-scoped delivery contract explicitly.

Errors: 401 invalid identity, 422 unsupported/invalid input, 429 capacity limits,
503 worker unavailable, 504 timeout, 502 synthesis/extraction failure. Return safe
codes/messages without raw text, tokens or tool stderr. Do not substitute invented
cues. Client AbortSignal stops waiting/playback and discards stale request IDs;
a future worker must separately implement cooperative disconnect cancellation,
kill bounded subprocesses and clean their private temporary files. Current local
CLI interruption/timeout is not a deployed cancellation endpoint.

Privacy proposal: no raw text/audio logs, no Firestore/IndexedDB audio persistence,
no external inference, Cache-Control: no-store, private per-job temporary media
only and cleanup on success/failure/cancel. Return audio inline and retain no
server media after response; clients revoke/drop buffers on stop/switch/unmount.
Existing conversation encryption stays unchanged. The retained local fixtures
are deliberately non-sensitive evaluation material, not this production policy.

Increment 6B.2 can build on the verified local pipeline after these decisions
and human language assessment. Ahmad's real Firebase/FastAPI/model configuration
and returning-linked-secret unlock work still block authenticated chat/speech
acceptance. No microphone/STT, Flutter WebView or camera work has started.
