import io,json,subprocess,tempfile,time,wave
from pathlib import Path
from piper import PiperVoice
ROOT=Path(__file__).resolve().parents[1];SPEECH=ROOT/'dev/avatar-sandbox/.speech-tools';OUTPUT=ROOT/'dev/avatar-sandbox/.voice-tools'
short=json.loads((ROOT/'dev/avatar-sandbox/.fixtures/piper-urdu.json').read_text())['transcript']
texts={'short':short,'longer':' '.join([short]*6)}
start=time.perf_counter();voice=PiperVoice.load(str(SPEECH/'ur_PK-fasih-medium.onnx'));load=time.perf_counter()-start
results=[]
with tempfile.TemporaryDirectory(prefix='koi-tts-benchmark-') as folder:
 for name,text in texts.items():
  path=Path(folder)/(name+'.wav');cues=Path(folder)/(name+'.json')
  start=time.perf_counter();subprocess.run([str(SPEECH/'venv/Scripts/python.exe'),'-X','utf8','-m','piper','--model',str(SPEECH/'ur_PK-fasih-medium.onnx'),'--output-file',str(path)],input=text.encode(),stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,timeout=90,check=True);cold=time.perf_counter()-start
  for attempt in range(2):
   start=time.perf_counter()
   with wave.open(str(path),'wb') as output:voice.synthesize_wav(text,output)
   warm=time.perf_counter()-start
   with wave.open(str(path)) as output:duration=output.getnframes()/output.getframerate()
   start=time.perf_counter();subprocess.run([str(SPEECH/'Rhubarb-Lip-Sync-1.14.0-Windows/rhubarb.exe'),'-r','phonetic','-f','json','-o',str(cues),str(path)],stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,timeout=90,check=True);extraction=time.perf_counter()-start
   results.append({'case':name,'characters':len(text),'attempt':attempt+1,'freshCliSeconds':cold,'persistentVoiceLoadSeconds':load,'warmSynthesisSeconds':warm,'rhubarbSeconds':extraction,'audioDurationSeconds':duration})
report={'method':'Fresh Python/Piper CLI per text versus one already-loaded PiperVoice object. OS disk cache not reset; not production latency. Neutral synthetic Urdu sentence, repeated six times for longer test.','results':results}
(OUTPUT/'tts-benchmark.json').write_text(json.dumps(report,indent=2),encoding='utf-8');print(json.dumps(report,indent=2))
