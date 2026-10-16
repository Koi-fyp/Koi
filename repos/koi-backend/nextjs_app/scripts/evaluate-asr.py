import argparse,json,os,re,subprocess,sys,threading,time,unicodedata
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];TOOLS=ROOT/'dev/avatar-sandbox/.voice-tools';FIXTURES=ROOT/'dev/avatar-sandbox/.fixtures'
def normalize(text):
 text=unicodedata.normalize('NFC',text).lower()
 # No Urdu/Roman transliteration or script conversion. Strip Unicode punctuation, collapse spaces.
 return ' '.join(''.join(c for c in text if not unicodedata.category(c).startswith('P')).split())
def distance(a,b):
 row=list(range(len(b)+1))
 for i,x in enumerate(a,1):
  next_row=[i]
  for j,y in enumerate(b,1): next_row.append(min(next_row[-1]+1,row[j]+1,row[j-1]+(x!=y)))
  row=next_row
 return row[-1]
def worker(name):
 import psutil
 from faster_whisper import WhisperModel
 process=psutil.Process();peak=[process.memory_info().rss];done=threading.Event()
 def monitor():
  while not done.wait(.01): peak[0]=max(peak[0],process.memory_info().rss)
 thread=threading.Thread(target=monitor,daemon=True);thread.start()
 began=time.perf_counter();model=WhisperModel(str(TOOLS/name),device='cpu',compute_type='int8',cpu_threads=2,num_workers=1,local_files_only=True);load=time.perf_counter()-began
 rows=[]
 for sample in ['piper-urdu','piper-english','piper-mixed']:
  metadata=json.loads((FIXTURES/(sample+'.json')).read_text());reference=metadata['transcript'];language='en' if sample=='piper-english' else 'ur'
  began=time.perf_counter();segments,info=model.transcribe(str(FIXTURES/(sample+'.wav')),language=language,beam_size=3,condition_on_previous_text=False,vad_filter=False,word_timestamps=False);text=''.join(segment.text for segment in segments).strip();elapsed=time.perf_counter()-began
  ref,hyp=normalize(reference),normalize(text);words=ref.split();characters=ref.replace(' ','')
  rows.append({'sample':sample,'reference':reference,'text':text,'languageRequested':language,'languageReported':info.language,'inferenceSeconds':elapsed,'audioDurationSeconds':metadata['durationSeconds'],'wer':distance(words,hyp.split())/len(words),'cer':distance(characters,hyp.replace(' ',''))/len(characters)})
 done.set();thread.join();peak[0]=max(peak[0],process.memory_info().rss)
 return {'model':name,'runtime':'faster-whisper 1.2.1 / CTranslate2 CPU int8','modelLoadSeconds':load,'modelBytes':sum(p.stat().st_size for p in (TOOLS/name).rglob('*') if p.is_file()),'peakProcessRssBytes':peak[0],'samples':rows}
def main():
 parser=argparse.ArgumentParser();parser.add_argument('--worker',choices=['tiny','base']);args=parser.parse_args()
 if args.worker: print(json.dumps(worker(args.worker),ensure_ascii=True));return
 results=[]
 for name in ['tiny','base']:
  child=subprocess.run([sys.executable,'-X','utf8',__file__,'--worker',name],capture_output=True,text=True,encoding='utf-8',env={**os.environ,'HF_HUB_OFFLINE':'1'},timeout=300,check=True);results.append(json.loads(child.stdout))
 report={'normalization':'NFC, lowercase, strip Unicode punctuation, collapse whitespace; CER excludes spaces. No transliteration or Urdu letter folding. References are intended synthetic TTS input, not human-verified audible transcripts. Tiny dataset confounds TTS and ASR; not general accuracy.','datasetProvenance':'Existing non-sensitive Piper evaluation speech, no private recordings','results':results}
 (TOOLS/'asr-evaluation.json').write_text(json.dumps(report,ensure_ascii=True,indent=2),encoding='utf-8');print(json.dumps(report,ensure_ascii=True,indent=2))
if __name__=='__main__':main()
