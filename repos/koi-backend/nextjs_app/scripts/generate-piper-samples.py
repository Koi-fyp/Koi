"""Offline, non-sensitive evaluation only: actual Piper output -> actual Rhubarb cues."""
import argparse
import hashlib
import json
import math
import struct
import subprocess
import time
import wave
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
TOOLS=ROOT/'dev/avatar-sandbox/.speech-tools'
OUTPUT=ROOT/'dev/avatar-sandbox/.fixtures'
SAMPLES={
 'piper-urdu': ('ur', '\u06cc\u06c1 \u0627\u06cc\u06a9 \u0633\u0627\u062f\u06c1 \u062c\u0645\u0644\u06c1 \u06c1\u06d2\u06d4', 'phonetic'),
 'piper-english': ('en', 'Hello. This is a simple test sentence.', 'pocketSphinx'),
 'piper-mixed': ('ur-en', '\u0622\u062c weather \u0627\u0686\u06be\u0627 \u06c1\u06d2\u06d4', 'phonetic'),
}
def validate_cues(data, duration):
    if not isinstance(data,dict) or not isinstance(data.get('mouthCues'),list) or not data['mouthCues']: raise ValueError('Missing actual Rhubarb cues')
    previous=0
    for cue in data['mouthCues']:
        if not isinstance(cue,dict): raise ValueError('Invalid cue object')
        start,end,value=cue.get('start'),cue.get('end'),cue.get('value')
        if not all(isinstance(x,(int,float)) and not isinstance(x,bool) and math.isfinite(x) for x in (start,end)): raise ValueError('Non-finite cue time')
        if start<previous or end<=start or start<0 or end>duration+.05 or not isinstance(value,str) or len(value)!=1 or value not in 'ABCDEFGHX': raise ValueError('Invalid real cue')
        previous=end
    metadata=data.get('metadata')
    cue_duration=metadata.get('duration') if isinstance(metadata,dict) else None
    if not isinstance(cue_duration,(int,float)) or isinstance(cue_duration,bool) or not math.isfinite(cue_duration) or abs(cue_duration-duration)>.05: raise ValueError('Cue/audio duration mismatch')
    return data['mouthCues']
def run(command, **kwargs):
    started=time.perf_counter()
    # Never log arbitrary tool stderr with potentially private text. These inputs are fixed synthetic examples.
    subprocess.run(command,check=True,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,timeout=180,**kwargs)
    return time.perf_counter()-started

def main():
    parser=argparse.ArgumentParser(); parser.add_argument('--sample',choices=[*SAMPLES,'all'],default='all'); args=parser.parse_args()
    python=TOOLS/'venv/Scripts/python.exe'; rhubarb=TOOLS/'Rhubarb-Lip-Sync-1.14.0-Windows/rhubarb.exe'
    if not python.exists() or not rhubarb.exists(): raise RuntimeError('Run python scripts/setup-speech-tools.py first.')
    model=TOOLS/'ur_PK-fasih-medium.onnx'; config=TOOLS/'ur_PK-fasih-medium.onnx.json'
    if hashlib.sha256(model.read_bytes()).hexdigest()!='46d590b90fbb41e4d4f2c54ded44874917f8b11b6e0500de2a89e5d3731b5917': raise RuntimeError('Voice checksum mismatch')
    OUTPUT.mkdir(parents=True,exist_ok=True)
    results=[]
    for sample,(language,text,recognizer) in SAMPLES.items():
        if args.sample not in ('all',sample): continue
        wav=OUTPUT/(sample+'.wav'); cue_file=OUTPUT/(sample+'.cues.json'); manifest=OUTPUT/(sample+'.json')
        # Unpublish an old manifest BEFORE generation so a failed regeneration cannot pair new WAV with old cues.
        manifest.write_text(json.dumps({'error':'Generation not completed'}),encoding='utf-8')
        command=[str(python),'-X','utf8','-m','piper','--model',str(model),'--config',str(config),'--output-file',str(wav)]
        try:
            synthesis=run(command,input=text.encode('utf-8'))
            with wave.open(str(wav),'rb') as audio:
                channels,width,rate,frames=audio.getnchannels(),audio.getsampwidth(),audio.getframerate(),audio.getnframes()
                if (channels,width,rate)!=(1,2,22050): raise ValueError('Unexpected Piper PCM WAV format')
                duration=frames/rate; pcm=struct.unpack('<'+'h'*frames,audio.readframes(frames))
                if not duration>0 or max(abs(value) for value in pcm)==0: raise ValueError('Silent/empty synthesis')
            rhubarb_command=[str(rhubarb),'-r',recognizer,'-f','json','-o',str(cue_file),str(wav)]
            extraction=run(rhubarb_command)
            raw=json.loads(cue_file.read_text(encoding='utf-8')); cues=validate_cues(raw,duration)
            result={'id':sample,'kind':'rhubarb','transcript':text,'language':language,'voice':'ur_PK-fasih-medium',
              'provenance':'Actual local Piper 1.8.0 synthesis; Rhubarb 1.14.0 automatic extraction of this exact WAV.',
              'cueSource':'Actual Rhubarb '+recognizer+' extraction; approximate VRM mapping; Urdu alignment quality not evaluated.',
              'audioFilename':sample+'.wav','durationSeconds':duration,'sampleRateHz':rate,'channels':channels,'bitsPerSample':width*8,
              'sha256':hashlib.sha256(wav.read_bytes()).hexdigest(),'cueSha256':hashlib.sha256(cue_file.read_bytes()).hexdigest(),
              'synthesisSeconds':synthesis,'cueExtractionSeconds':extraction,'recognizer':recognizer,'mouthCues':cues,
              'synthesisCommand':command,'rhubarbCommand':rhubarb_command,'audioConversion':'none',
              'quality':{'pronunciation':'Not human-evaluated','mouthAlignment':'No ground-truth phoneme labels or human evaluation','languageSupport':'Urdu voice; English/mixed inputs are feasibility probes, not a support guarantee'}}
            # Replace manifest atomically after BOTH stages succeed.
            pending=manifest.with_suffix('.pending'); pending.write_text(json.dumps(result,ensure_ascii=True,indent=2),encoding='utf-8'); pending.replace(manifest)
            results.append({key:result[key] for key in ['id','voice','durationSeconds','synthesisSeconds','cueExtractionSeconds','recognizer','sha256']})
        except (subprocess.SubprocessError, ValueError, OSError) as error:
            results.append({'id':sample,'error':type(error).__name__,'verified':False})
            (OUTPUT/'piper-evaluation.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
            raise RuntimeError(f'{sample}: local generation/extraction failed ({type(error).__name__}); no success manifest published.') from None
    (OUTPUT/'piper-evaluation.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
    print(json.dumps(results,indent=2))
if __name__=='__main__': main()
