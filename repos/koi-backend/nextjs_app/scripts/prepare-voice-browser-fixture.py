"""Make a non-sensitive, single-utterance WAV input for Chromium fake-mic tests."""
import json
import wave
from pathlib import Path

root = Path(__file__).resolve().parents[1]
source = root / "dev/avatar-sandbox/.fixtures/piper-urdu.wav"
target = root / "dev/avatar-sandbox/.fixtures/piper-urdu-browser.wav"
with wave.open(str(source), "rb") as audio:
    params = audio.getparams()
    frames = audio.readframes(audio.getnframes())
frame_width = params.nchannels * params.sampwidth
if params.comptype != "NONE" or not frame_width or not frames:
    raise SystemExit("Expected a non-empty uncompressed Piper PCM WAV fixture.")
# A long silence tail keeps Chromium's file-backed device live through the test
# recording instead of looping and repeating the utterance into the transcript.
silence = bytes(params.framerate * frame_width * 10)
with wave.open(str(target), "wb") as output:
    output.setnchannels(params.nchannels)
    output.setsampwidth(params.sampwidth)
    output.setframerate(params.framerate)
    output.writeframes(frames + silence)
print(json.dumps({"fixture": "piper-urdu", "duration_seconds": (len(frames) + len(silence)) / (params.framerate * frame_width), "output": str(target)}))
