# Increment 6B.2: local microphone, ASR and mock voice conversation

## Audit and scope

Branch feat/web-vrm-avatar. Tracked tree was initially clean; unrelated .idea and
koi-mobile/android files are untouched. Read SPEECH_ARCHITECTURE.md, REAL_SPEECH.md,
playback/cue/mouth controller, conversation session/hooks/service, Firebase guard,
FastAPI routes/auth/inference and dependencies. The backend still exposes health
and authenticated JSON chat, not ASR/TTS endpoints. Its inference is self-hosted
Transformers generation. No existing ASR service/model/dependency was present.
Full Blueprint/TRACK documents referenced by backend comments were not found in
this checkout; their audio/privacy sections are not claimed to have been read.
The user's explicit consent/privacy constraints govern this implementation.

No production Firebase/auth, encryption/salt, LLM/chat contract, crisis, Flutter,
camera or user-video code changed. There are no fake Firebase tokens. All new
routes are in the separate existing development harness, guarded against
production. The shared capture/playback primitives do not start on import/mount.

## Reproduce locally

Use Windows x64 / Python 3.14 and existing 6B.1 speech tools/fixtures:

    python scripts/setup-speech-tools.py
    python scripts/generate-piper-samples.py
    python scripts/setup-voice-tools.py

In separate terminals:

    node scripts/voice-dev.cjs
    npm run dev:avatar

Open http://127.0.0.1:3001/voice-lab (use 127.0.0.1, not localhost).
Check explicit capture/local-processing consent, Start recording, Stop, then
Transcribe recording. Review/correct the editable transcript before Submit to
MOCK chat. Fixture buttons exercise real ASR without microphone access. The
reply text/emotion are deterministic development mocks; Piper and Rhubarb are
real. Both avatar previews use the existing male Fasih Urdu voice. Play reply
provides a user-gesture fallback if the browser blocks delayed autoplay.

Tools, capability, models and reports are ignored under .voice-tools; speech
fixtures remain ignored under .fixtures. No npm dependency was added. The voice
wheel lock is separate from the unchanged 6B.1 speech-tool lock. Runtime versions:
faster-whisper 1.2.1, CTranslate2 4.8.3, PyAV 16.1.0, Piper 1.8.0, Rhubarb 1.14.0.
PyAV 19.0.1 was actually incompatible with faster-whisper's metadata_errors
argument; the tested compatible version is pinned, not silently assumed.

## ASR evaluation, not a final provider selection

Compared official Systran converted multilingual Whisper tiny/base on CPU int8,
two CPU threads, beam size 3, no VAD or previous-text conditioning. Each model
was evaluated in a separate fresh process; transcription timing consumes the
lazy segment generator, so it includes actual inference. Language is explicitly
ur for Urdu/mixed and en for English. No confidence score is invented. Current
service language metadata distinguishes a requested hint from model detection.

[Runtime documentation](https://github.com/SYSTRAN/faster-whisper) describes CPU
int8 and bundled-FFmpeg PyAV decoding. Models came only from official Systran
Hugging Face repositories, pinned and model-bin SHA256 checked:

- tiny: d90ca5fe260221311c53c58e660288d3deb8d356
- base: ebe41f70d5b6dfa9166e2c581c45c9c0cfc57b66

Both runtime/model licenses are documented upstream as MIT; keep their notices
and review bundled CTranslate2/PyAV/FFmpeg terms for a deployment/distribution.
These ignored downloads do not approve a binary redistribution policy.

Developer hardware: Windows, Intel i5-1235U (10 cores/12 logical processors),
8,301,043,712 bytes RAM. Measured model-directory size / peak whole-process RSS:

| Candidate | Model files | Peak process RSS | Load time |
|---|---:|---:|---:|
| tiny | 78,205,610 bytes | 244.4 MiB | 0.250 s |
| base | 147,884,932 bytes | 295.9 MiB | 0.405 s |

This is process memory, not isolated model memory or a production capacity test.
Tiny is the provisional development default for smaller memory and its better
Urdu smoke result; base remains evaluated, and the final ASR provider is OPEN.
Three TTS samples are too small/biased for a production accuracy decision.

References are the intended text in existing non-sensitive Piper manifests, not
human-audited audible ground truth. English/mixed audio used an Urdu TTS voice,
so results confound synthesis quality with recognition. Normalization: NFC,
lowercase, remove Unicode punctuation, collapse spaces; CER excludes spaces.
No Roman/Urdu transliteration, Urdu character folding or diacritic removal.
Script differences and variants such as jumla spelling count as errors.
WER/CER below apply only to these references, not general language accuracy.

| Model | Synthetic fixture | Actual transcription | Inference | WER | CER |
|---|---|---|---:|---:|---:|
| tiny | piper-urdu | یہ ایک سادہ جملا ہے | 1.886 s | 20.0% | 6.7% |
| tiny | piper-english | Hello, just be a simple task sentence. | 0.464 s | 42.9% | 26.7% |
| tiny | piper-mixed | اٹھوائر چاہے | 0.684 s | 100.0% | 73.3% |
| base | piper-urdu | یہ اید سادہ جملا ہے | 0.777 s | 40.0% | 13.3% |
| base | piper-english | Hello, just be a simple task sentence. | 0.748 s | 42.9% | 26.7% |
| base | piper-mixed | آڈ وادر چاہے | 0.748 s | 100.0% | 66.7% |

Re-run with:

    dev/avatar-sandbox/.voice-tools/venv/Scripts/python.exe -X utf8 scripts/evaluate-asr.py

Full references, actual outputs, normalization, versions and measurements are in
.voice-tools/asr-evaluation.json. Decoder/fallback behavior can vary; browser
worker results are recorded separately, not substituted for this evaluation.
Human speakers, regional accents, noise, Roman Urdu, broader datasets and other
ASR architectures remain unevaluated. Mixed recognition is not release-ready.

## Capture, actual formats and lifecycle

MicrophoneCapture.start runs only after consent + button interaction, with
getUserMedia({audio:true,video:false}). It selects a browser-supported audio MIME
and records actual recorder.mimeType. Tested Chrome produced audio/webm;codecs=opus.
PyAV identified matroska/webm with Opus, decoded in memory, then resampled to
float32 mono 16000 Hz for ASR. Fixture PCM WAV at 22050 Hz followed the same real
decode/resample boundary. WebM was not passed directly as pretend WAV/PCM.
Ogg/MP4 capture fallbacks exist but were not browser-verified.

Recording stops automatically at 29.5s (margin within the advertised 30s limit).
Encoded payload is capped at 2 MiB in capture, proxy and service; decoded audio
is independently capped at 30s. Tracks, recorder callbacks/timer and blob chunks
are released on stop/error/cancel/disconnect/unmount. Hidden-page/pagehide cancels
capture. A permission grant arriving after cancellation/disposal is immediately
stopped. Permission denial, absent/ended devices and unsupported formats fail
without sending a chat message. The recording blob is cleared after handoff;
no raw audio enters message history, localStorage, IndexedDB or Firestore.

The voice lab now shows browser permission state, secure-context status, selected
input label/settings, actual MIME, duration and byte count. Refresh microphone
enumeration only after a user click; when available, a selected input can be used
for the next recording. A native audio control can play the captured Blob locally
before upload, without saving it. ASR results show decoded container/codec,
duration, 16 kHz mono normalization, RMS and sample peak. Opus decoding may
produce floating-point sample peaks slightly above 1.0; the client validates a
bounded finite diagnostic value without treating 1.0 as a hard audio ceiling.
The local health button verifies the Python worker has loaded Whisper/Piper; a
successful Next page load alone does not indicate ASR readiness.

## Physical microphone failure report and strengthened check

The developer reported that the physical laptop microphone did not produce a
usable transcript, while the mock TTS playback worked. The original browser test
used Chromium's default synthetic input (which can be silent) and only checked
that the request returned decode metadata. It did not assert signal level or
transcript text, so that test was too weak to support the earlier positive
recording claim. The exact physical-device cause cannot be recovered because the
previous captured audio was deliberately ephemeral and was not retained.

While adding the new diagnostics, a separate real browser/server contract bug was
reproduced and fixed: a file-backed synthetic WebM/Opus recording received HTTP
200 from Whisper with a non-empty transcript and `peak=1.0402`, but the frontend
rejected it as an invalid response because it assumed decoded peak must be at
most 1.0. Lossy Opus floating point decode can exceed that value. The validation
now accepts finite bounded sample diagnostics without clamping their reported
values. The browser test now uses the local known-speech fixture as its fake mic
input and asserts nonzero RMS plus non-empty text. One run captured a 3.48 s,
30,030-byte WebM/Opus sample (48 kHz input track; normalized by PyAV to mono
16 kHz), RMS 0.1422, peak 1.0147, and returned text in 5.20 s. Recognition was
imperfect after the lossy browser recording; direct fixture WAV recognition
returned the expected short Urdu sentence in 2.12 s. These are local synthetic
fixture measurements, not physical microphone results or a general accuracy
claim. Full browser artifacts are in ignored
`.next/verification/increment-6b2/results.json`.

SpeechPlayback accepts validated owned WAV Blob data from this capability-protected
local proxy response and owns/revokes its object URL on clear/replacement/dispose.
Arbitrary remote/blob URL strings remain rejected. Pause/resume retain the active
clip; cancel/stop reply/character switch/End clear it. Existing media-time mouth
updates, one renderer/RAF, expressions and blinking remain unchanged.

## Local service boundary and typed contracts

voice_service.py binds ONLY 127.0.0.1:3002 with explicit development launcher/env,
refuses production mode, validates Host/Origin and a random server-held capability.
The Next development-only voice-api proxy validates actual Host, exact Origin and
an intent header, reads the capability server-side, and never returns it to JS.
Public-network binding, wildcard CORS, result-lookup URLs and production auth
bypasses were not added. This protects against remote/browser-origin access;
trusted local OS processes/users are the development threat boundary, not a
replacement for Firebase identity. Duplicate worker startup cannot take another
worker's port, capability or private temporary files.

Actual DEVELOPMENT operations (not deployed FastAPI endpoints):

- POST /voice-api/transcribe: bounded audio bytes + explicit ur/en/auto hint.
  Returns text, language code/source, processing_ms, model name/revision/runtime/
  version/compute type and decoded input container/codec/duration/normalized format.
- POST /voice-api/synthesize: text <=300 chars and language=ur. One explicit Fasih
  voice; returns hashed base64 PCM WAV, actual Rhubarb cues and separate timings.
- POST /voice-api/health: capability-protected worker readiness metadata.

Typed validation/errors are in voiceContract.ts. No confidence fields, fake
transcription service or external inference request exists. Unsupported input,
size, busy, unavailable/timeout and forbidden access produce safe errors. One
active speech job is allowed; other requests receive 429 rather than unbounded
queued private audio. Client/proxy timeout is 90s; Rhubarb subprocess timeout 30s.

Client cancellation aborts waiting/playback and ignores stale generations. Native
ASR/Piper inference cannot currently be force-cancelled mid-call and may continue
before discarding the disconnected response. There is no production cancellation
endpoint or hard native-inference deadline. Production needs managed worker
cancellation/resource limits agreed with Ahmad.

Raw recordings decode entirely in memory; service logging and third-party Python
logging are disabled. Generated TTS WAV/cues use private per-job TemporaryDirectory
under .voice-tools/tmp and delete on normal success/error after processing. Client
abort may await native completion before cleanup. Forced process death may leave
only that generated media; the next exclusive worker startup removes stale owned
directories after checking resolved workspace bounds. A production supervisor/TTL
janitor is still required. No private transcripts/audio are logged or persisted;
only explicitly non-sensitive evaluation scripts write fixture reports.

## Conversation integration: real versus mocked

All messages/history/emotion use the existing ConversationSession and hook. The
existing isolated mock adapter gained a development-only reviewed-voice option;
its default whitelist and production refusal remain. Voice operation phases are
separate recording/ASR/TTS state, not a second conversation/message store.

Real recorded/fixture audio -> real local ASR -> editable review -> explicit
submission -> MOCK chat JSON response/emotion -> real persistent Piper -> real
Rhubarb -> existing media-clock playback/mouth controller. A new operation stops
obsolete audio; switching/End/unmount cancels capture/requests. Empty/failed ASR
never auto-submits. Chat failures remain visible and text survives TTS failure.
The scripted response is not LLM output, clinical guidance or crisis classification.
Existing backend safety authority is unchanged.

## Measured TTS and playback performance

benchmark-tts-worker.py compares fresh Piper CLI calls to one loaded PiperVoice.
Short test is the 20-character neutral Urdu fixture; longer is six sentences,
125 characters. OS cache was not reset and this is a small length/performance
smoke test, not a scientifically controlled production benchmark.

| Case | Fresh CLI | Loaded first synthesis | Steady loaded synthesis | Rhubarb | Audio duration |
|---|---:|---:|---:|---:|---:|
| Short | 3.299 s | 1.298 s | 0.052 s | 0.647-0.981 s | 1.219-1.358 s |
| Longer | 3.307 s | -- | 0.323-0.364 s | 1.036-1.043 s | 8.150-8.557 s |

Voice load was 2.825s separately. Raw measurements are in
.voice-tools/tts-benchmark.json. In one full browser/software-WebGL run, TTS
request to playback took 9.525s: 4.082s synthesis, 4.917s Rhubarb and 323ms after
prepared bytes to playback. Other browser runs are recorded in their artifacts;
these are measured media-start times, not acoustic speaker latency. The much
slower complete workload needs profiling/thread/resource budgeting, not a claim
that the isolated warm number is end-to-end performance.

Sentence-level prefetch is a possible future optimization given steady synthesis
throughput, but real UI contention/extraction overhead must be profiled. No
sentence queue, streaming endpoint or SSE chat change was implemented. Completed
single-audio-response mode remains the fallback. English voice pairing and
multilingual TTS routing remain OPEN; this worker explicitly synthesizes only
the scripted Urdu reply, not an unapproved automatic English routing policy.

## Verification and remaining blockers

Passed source/unit tests cover consent-only access, actual audio-only constraints,
selected device constraints, empty recording, unsupported recorder format,
stop/cancel/dispose, late grant, missing/disconnected/denied microphones,
duration/byte limits, lossy-codec peaks above 1.0 and owned URL cleanup. Worker
HTTP tests cover capability/origin rejection, empty/invalid/oversized/overduration
media, silent-audio rejection, actual ASR, actual Piper/Rhubarb, and empty
temporary-media directories after success.

The browser test uses a file-backed Chromium synthetic audio input, NOT a physical
microphone. The earlier default fake input was effectively silent, and its prior
assertion checked only that a decode diagnostic appeared; it did not require
non-silent signal or transcript text. The strengthened test feeds the known
non-sensitive Piper Urdu fixture through native MediaRecorder as WebM/Opus, then
asserts a measurable level and a non-empty transcript from the real local ASR.
It also tests native permission grant/denial, ASR unavailable error reporting,
review/correction/explicit mock submission, emotion/mouth updates, pause/resume,
cancellation/late results, switching, desktop/mobile and End cleanup. No webcam
constraints/video preview or external browser requests. This synthetic fixture
test does not establish that the laptop's physical input device is selected or
capturing audible speech.
Results/screenshots are in ignored .next/verification/increment-6b2.

Commands: npm run typecheck:avatar; node scripts/test-microphone.cjs;
node scripts/test-speech.cjs; python scripts/test-local-voice.py;
node scripts/verify-voice-lab.cjs; existing controller/chat and Increment 2-6B.1
browser/pipeline checks; git diff --check. Full-app tsc still has known html2pdf.js,
crypto BufferSource, onboarding and Jest type errors, unchanged by this work.

VERIFIED: synthetic-fixture ASR, file-backed synthetic browser recording with
non-silent signal and a non-empty real-ASR transcript, local real-speech/MOCK-chat
conversation, media/resource cleanup.
NOT VERIFIED: physical microphone, natural Urdu/code-switch accuracy, audible
speaker/subjective lip-sync quality, real LLM conversation, authenticated end-to-end
voice conversation, Linux/FastAPI deployment or Flutter WebView.

Ahmad must confirm final ASR/voice/language policy, authenticated speech contracts,
verified Firebase identity/linked-secret unlock, real JSON chat end-to-end run,
CORS/HTTPS, worker sizing and hard cancellation, licensing/distribution and
private-media TTL/crash cleanup. Existing production AuthProvider/guards and
PBKDF2/AES-GCM architecture are unchanged. Camera processing remains Increment 7;
no camera or Flutter work started.
