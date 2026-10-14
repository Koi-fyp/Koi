> Historical Increment 6A audit/results. Increment 6B.1 now verifies local Piper/Rhubarb; see [REAL_SPEECH.md](./REAL_SPEECH.md).

# Increment 6A: local playback and VRM mouth proof of concept

## Audit and implementation boundaries

The audit started on feat/web-vrm-avatar with no tracked changes. Unrelated .idea
and koi-mobile/android files were left alone. Existing renderer/controller,
CompanionScene, conversation session and sandbox were inspected before editing.
No dependencies were installed. Firebase, crypto, backend, chat JSON contract,
crisis code, Flutter, microphone and camera code are unchanged.

Actual koi-ai-engine/main.py installs only app/api/routes.py: health/chat.
The chat route/schema still returns reply, companion_state and latency_ms JSON.
Neither app/services nor requirements.txt defines an operational speech service,
Piper/Rhubarb wiring, ASR engine or authenticated speech endpoint. No suitable
local audio/model fixture was found in the checkout. Frontend audio modes are
disabled presentation (ModeSelector and ChangeModeDropdown), not speech systems.
UserRecord has en/ur language and male_human/female_human avatar preferences;
there is no implemented voice preference or persisted speech lifecycle.

Current PATH has no piper, rhubarb or espeak executable. Current Python lacks
piper, whisper, faster_whisper and vosk. This establishes availability in the
inspected environment, not the absence of off-PATH tools elsewhere on the PC.
Windows System.Speech has Microsoft David Desktop and Zira Desktop. Repository
README/setup/configuration/animation documents were inspected. Backend comments
reference Blueprint sections and TRACK_AI_BACKEND_FINAL_v4_13.md, but those full
blueprint documents were not found in this checkout; no speech API is inferred
from the references. Piper/Fasih is a user-supplied planned candidate, not a
verified KOI deployment.

## Rhubarb assessment (upstream documentation; not locally run)

[Rhubarb documentation](https://github.com/DanielSWolf/rhubarb-lip-sync/blob/master/README.adoc)
provides Windows/macOS/Linux binaries, WAV/Ogg Vorbis input and JSON output with
mouthCues start/end seconds and A-H/X categories. pocketSphinx is for English;
phonetic is the non-English alternative with lower recognition accuracy. No
Urdu/code-switching quality claim is made. Example future command (NOT executed):

    rhubarb -r pocketSphinx -f json -o sample-cues.json speech-sample.wav

For non-English evaluation, use -r phonetic. A future backend can run the CLI in
a bounded subprocess after synthesis, validate its JSON and return audio/cues
separately. It needs timeout/concurrency limits and private temporary-file
cleanup. This is a proposal, not an installed endpoint.
[Rhubarb license](https://github.com/DanielSWolf/rhubarb-lip-sync/blob/master/LICENSE.md)
is MIT with bundled dependency notices; retain those notices when distributing
binaries. Generated cue output belongs to its creator under upstream terms.

## Piper assessment (available upstream; not installed or generated here)

The [voice index](https://huggingface.co/rhasspy/piper-voices/blob/main/voices.json)
lists ur_PK-fasih-medium.onnx (63,532,015 bytes) and its .onnx.json configuration
(3,146 bytes). Neither is present locally; upstream entries were checked, not
downloaded or binary-validated. The
[Fasih model card](https://huggingface.co/rhasspy/piper-voices/blob/main/ur/ur_PK/fasih/medium/MODEL_CARD)
describes a male Urdu voice, eSpeak Urdu phonemization, 22050 Hz audio and an MIT
voice license. Mixed Urdu/English quality may vary; English-only and Roman Urdu
need evaluation, not assumed pronunciation support.

[Current Piper CLI](https://github.com/OHF-Voice/piper1-gpl/blob/main/docs/CLI.md)
supports local text-to-WAV synthesis with piper-tts and a downloaded model.
[Package source](https://github.com/OHF-Voice/piper1-gpl/blob/main/setup.py)
requires Python >=3.9 and ONNX Runtime, with bundled eSpeak-ng resources. Windows
build support is documented in the
[releases](https://github.com/OHF-Voice/piper1-gpl/releases); local/backend platform
compatibility still requires an installation and smoke test. PCM WAV is usable
by this playback module and Rhubarb. Future enablement requires pinned runtime,
voice/config checksums, retained licenses, language tests and a private synthesis
worker. The current engine is GPL-3.0-or-later; the
[older engine](https://github.com/rhasspy/piper/blob/master/LICENSE.md) was MIT.
Engine/voice/bundled dependency terms must be tracked separately for the chosen
distribution. No engine or voice is bundled by this increment.

## STT assessment

No working or selected self-hosted ASR implementation was found. Therefore
languages, input format and authentication for a real speech endpoint are not
yet defined. Increment 6B must select/evaluate a self-hosted model for Urdu,
English and code-switching; pin its runtime/model/license; define decoding and
resampling for the browser's actual capture format; and use the existing verified
Firebase identity boundary. Any PCM/sample-rate/API choices remain proposals.
No microphone permission, recording or fake transcription was implemented.

## Reproducible local fixture

Run from the canonical Next.js directory:

    powershell -NoProfile -File scripts/create-speech-fixture.ps1
    npm run dev:avatar

Open http://127.0.0.1:3001/speech-lab. Play requires an explicit click. Windows
David and Python are required only to regenerate the local test fixture; no
online service is used. Original non-sensitive wording:
Ah. Ee. Oh. Ooh. Hello. I am Koi.

create-speech-fixture.ps1 synthesizes separate segments with Windows System.Speech;
assemble-speech-fixture.py measures their WAV durations, inserts silence and
writes matching representative cue categories. Inner timing is authored and
approximate, not phoneme detection, text-derived actual timing or Rhubarb output.
The manifest records transcript, provenance, cue disclaimer, duration and SHA256.
Current sample: mono 16-bit PCM 22050 Hz, 8.272018 seconds, 364840 bytes.

Generated audio/JSON/segments stay in ignored dev/avatar-sandbox/.fixtures and
are served only by the dev harness's allowlisted speech-fixture route. No voice
binaries are redistributed and no generated audio is committed. Windows voice
output redistribution rights were not assessed; this is locally generated test
material, not a production asset/license grant. There is no duplicate VRM asset.

## Reusable architecture and mouth mapping

SpeechPlayback owns one HTMLAudioElement and typed state, events, play/pause/
resume (play while paused), stop, seek, cancellation-by-stop and disposal. A
request generation protects against stale play promises. It uses same-origin
HTTP(S) sources only; a future remote speech source requires an approved origin
and privacy policy. No object URLs are created. Dispose removes listeners,
clears src, unloads media and prevents stale playback. No playback RAF/timer exists.

SpeechTimeline.getFrame reads currentTime, paused/ended/seeking and playback
state directly. VRMMouthController reads it inside the existing avatar update,
before vrm.update. A 40ms media-time smoothstep envelope fades each cue in/out
with maximum weight 0.7. At most one vowel is active; gaps/closed/invalid values
are silent. Seeking recomputes from absolute media time without accumulated drift.
Pause/stop/end/error clear controlled weights on the next existing avatar frame.
Emotional/blink weights and expression overrides are never globally reset.
A speaking conversation state alone does not activate mouth animation.

| Rhubarb | VRM | Approximation |
|---|---|---|
| A, X | all vowels zero | closed/rest; underlying emotion remains |
| B | ih | teeth/consonants, not exact |
| C | ee | mid-open vowel |
| D | aa | open vowel |
| E | oh | rounded vowel |
| F | ou | puckered vowel |
| G | ih | cannot represent teeth/lip contact exactly |
| H | ee | cannot represent tongue placement exactly |
| unknown | X | safe closed/rest fallback |

Finite, ordered, non-overlapping cue times are required; malformed timelines
are rejected. Both real models have nonbinary mouth/emotion presets with
overrideMouth=none and overrideBlink=none. Metadata is not rewritten: other
models may suppress mouth weights through Three-VRM overrides. The sandbox
stops playback before character switches, Back/End and avatar failure; unmount
disposes the player. Future parents must retain that ownership behavior.

The existing chat session remains the conversation source of truth. Audio/cues
can later be supplied separately by a speech adapter without modifying chat JSON.
No new production speech route, fake TTS response or debug production UI exists.

## Verification and limits

Commands: npm run typecheck:avatar; node scripts/test-speech.cjs;
node scripts/verify-speech.cjs; node scripts/test-avatar-controller.cjs;
node scripts/test-chat-contract.cjs; existing verify-avatar, verify-companion-ui,
verify-avatar-animation and verify-mock-chat browser scripts; git diff --check.
Browser scripts use the existing Chromium via KOI_AVATAR_BROWSER.

The speech browser test checks real decoded media playback after click,
pause/resume/stop/end/backward seek/rapid restart/load failure, emotion coexistence,
blink, both models, desktop/mobile, switching and cleanup. It compares actual
applied weights to cues at the media time consumed by the avatar frame. Artifacts
include samples.json, results.json and screenshots in the ignored
.next/verification/increment-6a directory. Headless Chromium mutes speaker output;
physical audible playback, phone hardware and human phoneme alignment have not
been verified. Timing differences measure media-clock/frame sampling only.

Real local media playback and fixture-timeline synchronization are verified.
Actual Rhubarb extraction, Piper synthesis, Urdu quality, STT and authenticated
end-to-end speech are NOT verified. Full-app known html2pdf.js/crypto buffer/
onboarding/Jest typing errors remain outside scope. Ahmad's Firebase/backend
configuration and linked-secret unlock work still block Increment 5 live tests;
future authenticated speech additionally requires real synthesis/ASR services,
contracts and evaluation. None is a prerequisite for this local proof of concept.
