"""Pair locally generated segments with deliberately approximate, authored cue categories."""
import hashlib
import json
import wave
from pathlib import Path
root = Path(__file__).resolve().parents[1] / 'dev/avatar-sandbox/.fixtures'
shapes = [('D',), ('B',), ('E',), ('F',), ('B', 'C', 'H', 'D', 'A', 'G', 'E', 'F')]
frames = []
cues = []
position = 0
rate = 22050
# Timing uses measured WAV segment boundaries; inner cues are authored approximations,
# NOT Rhubarb extraction, recognized phonemes, or evaluated speech alignment.
for index, values in enumerate(shapes):
    with wave.open(str(root / f'segment-{index}.wav'), 'rb') as audio:
        assert (audio.getnchannels(), audio.getsampwidth(), audio.getframerate()) == (1, 2, rate)
        data = audio.readframes(audio.getnframes())
    silence = bytes(int(rate * 0.2) * 2)
    frames.append(silence)
    cues.append(dict(start=position / rate, end=(position + len(silence) // 2) / rate, value='X'))
    position += len(silence) // 2
    length = len(data) // 2
    for cue_index, value in enumerate(values):
        cues.append(dict(start=(position + length * cue_index / len(values)) / rate,
                         end=(position + length * (cue_index + 1) / len(values)) / rate, value=value))
    position += length
    frames.append(data)
frames.append(bytes(int(rate * 0.3) * 2))
with wave.open(str(root / 'speech-sample.wav'), 'wb') as audio:
    audio.setnchannels(1); audio.setsampwidth(2); audio.setframerate(rate)
    audio.writeframes(b''.join(frames))
manifest = dict(provenance='Local Windows System.Speech / Microsoft David Desktop; original non-sensitive test wording.',
                transcript='Ah. Ee. Oh. Ooh. Hello. I am Koi.',
                cueSource='Manually authored representative cues aligned to measured segment durations. NOT Rhubarb or phoneme extraction.',
                durationSeconds=sum(len(data) // 2 for data in frames) / rate,
                sha256=hashlib.sha256((root / 'speech-sample.wav').read_bytes()).hexdigest(), mouthCues=cues)
(root / 'speech-sample.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
print(json.dumps({key: manifest[key] for key in ['durationSeconds', 'sha256', 'cueSource']}, indent=2))
