"""Isolated loopback development speech worker. Not a production/Firebase API."""
import logging
logging.disable(logging.CRITICAL)
import base64,hashlib,hmac,io,json,os,secrets,shutil,socket,subprocess,tempfile,threading,time,wave
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];TOOLS=ROOT/'dev/avatar-sandbox/.voice-tools';SPEECH=ROOT/'dev/avatar-sandbox/.speech-tools'
TEMP_ROOT=TOOLS/'tmp'
ORIGIN='http://127.0.0.1:3001';MAX_BYTES=2*1024*1024;MAX_SECONDS=30

def decode_audio(data):
 import av,numpy as np
 if not data or len(data)>MAX_BYTES: raise ValueError('invalid-audio-size')
 parts=[];count=0
 with av.open(io.BytesIO(data),mode='r') as container:
  if len(container.streams.audio)!=1 or len(container.streams.video): raise ValueError('audio-only-required')
  stream=container.streams.audio[0];codec=stream.codec_context.name;format_name=container.format.name
  resampler=av.AudioResampler(format='flt',layout='mono',rate=16000)
  for frame in container.decode(stream):
   for normalized in resampler.resample(frame):
    values=normalized.to_ndarray().reshape(-1);count+=len(values)
    if count>MAX_SECONDS*16000: raise ValueError('audio-too-long')
    parts.append(values)
  for normalized in resampler.resample(None):
   values=normalized.to_ndarray().reshape(-1);count+=len(values)
   if count>MAX_SECONDS*16000: raise ValueError('audio-too-long')
   parts.append(values)
 if not count: raise ValueError('empty-audio')
 samples=np.concatenate(parts).astype(np.float32)
 if not np.isfinite(samples).all(): raise ValueError('invalid-audio')
 rms=float(np.sqrt(np.mean(samples*samples)));peak=float(np.max(np.abs(samples)))
 return samples,{'container':format_name,'codec':codec,'duration_seconds':count/16000,'normalized_sample_rate':16000,'channels':1,'level_rms':round(rms,6),'peak':round(peak,6)}

class VoiceRuntime:
 def __init__(self,model='tiny'):
  from faster_whisper import WhisperModel
  from piper import PiperVoice
  self.name=model;self.asr=WhisperModel(str(TOOLS/model),device='cpu',compute_type='int8',cpu_threads=2,num_workers=1,local_files_only=True)
  self.voice=PiperVoice.load(str(SPEECH/'ur_PK-fasih-medium.onnx'))
  self.revision=json.loads((TOOLS/'models.json').read_text())[model]['revision']
 def transcribe(self,data,language):
  import numpy as np
  start=time.perf_counter()
  try:samples,input_meta=decode_audio(data)
  except Exception:raise ValueError('invalid-audio') from None
  if input_meta['level_rms']<.002: text='';code=language if language!='auto' else None
  else:
   segments,info=self.asr.transcribe(samples,language=None if language=='auto' else language,beam_size=3,condition_on_previous_text=False,vad_filter=False,word_timestamps=False)
   text=''.join(segment.text for segment in segments).strip();code=info.language
  return {'text':text,'language':{'code':code,'source':'detected' if language=='auto' else 'requested'},'processing_ms':round((time.perf_counter()-start)*1000,2),'model':{'name':'whisper-'+self.name,'revision':self.revision,'runtime':'faster-whisper','version':'1.2.1','compute_type':'cpu-int8'},'input':input_meta}
 def synthesize(self,text):
  if not isinstance(text,str) or not text.strip() or len(text)>300: raise ValueError('invalid-text')
  # This development worker has one explicitly selected Urdu voice; no language-routing policy.
  TEMP_ROOT.mkdir(parents=True,exist_ok=True)
  with tempfile.TemporaryDirectory(prefix='koi-voice-',dir=TEMP_ROOT) as folder:
   wav=Path(folder)/'reply.wav';cues=Path(folder)/'cues.json';start=time.perf_counter()
   with wave.open(str(wav),'wb') as output: self.voice.synthesize_wav(text,output)
   synthesis=(time.perf_counter()-start)*1000;start=time.perf_counter()
   with wave.open(str(wav),'rb') as output: duration=output.getnframes()/output.getframerate()
   if duration>30: raise ValueError('speech-too-long')
   subprocess.run([str(SPEECH/'Rhubarb-Lip-Sync-1.14.0-Windows/rhubarb.exe'),'-r','phonetic','-f','json','-o',str(cues),str(wav)],stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,timeout=30,check=True)
   extraction=(time.perf_counter()-start)*1000;data=wav.read_bytes();raw=json.loads(cues.read_text())
   previous=0
   for cue in raw['mouthCues']:
    if cue['start']<previous or cue['end']<=cue['start'] or cue['end']>duration+.05 or cue['value'] not in 'ABCDEFGHX': raise ValueError('invalid-cues')
    previous=cue['end']
   return {'audio_base64':base64.b64encode(data).decode('ascii'),'audio_sha256':hashlib.sha256(data).hexdigest(),'content_type':'audio/wav','voice':'ur_PK-fasih-medium','language':'ur','duration_seconds':duration,'mouth_cues':raw['mouthCues'],'timings_ms':{'synthesis':round(synthesis,2),'cue_extraction':round(extraction,2)}}

def main():
 if os.environ.get('KOI_VOICE_DEVELOPMENT')!='1' or os.environ.get('NODE_ENV') not in (None,'development'): raise RuntimeError('Explicit development launcher required.')
 os.environ['HF_HUB_OFFLINE']='1';token=secrets.token_hex(32);TOOLS.mkdir(exist_ok=True)
 token_file=TOOLS/'service-token';busy=threading.Semaphore(1)
 class Handler(BaseHTTPRequestHandler):
  def log_message(self,*args): pass # No payload/transcript/request logs.
  def respond(self,status,value):
   payload=json.dumps(value,ensure_ascii=True).encode();self.send_response(status);self.send_header('Content-Type','application/json');self.send_header('Cache-Control','no-store');self.send_header('Content-Length',str(len(payload)));self.end_headers()
   try:self.wfile.write(payload)
   except (BrokenPipeError,ConnectionResetError,ConnectionAbortedError):pass
  def do_POST(self):
   if self.headers.get('Host')!='127.0.0.1:3002' or self.headers.get('Origin')!=ORIGIN or not hmac.compare_digest(self.headers.get('Authorization','').encode('utf-8'),('Bearer '+token).encode('ascii')):self.respond(403,{'error':{'code':'forbidden','message':'Local voice access denied.'}});return
   if self.path not in ['/health','/transcribe','/synthesize']:self.respond(404,{'error':{'code':'not-found','message':'Unknown operation.'}});return
   try:size=int(self.headers.get('Content-Length','-1'))
   except ValueError:size=-1
   if size<0 or size>MAX_BYTES:self.respond(413,{'error':{'code':'size-limit','message':'Audio payload limit exceeded.'}});return
   self.connection.settimeout(10);body=self.rfile.read(size)
   if len(body)!=size:self.respond(400,{'error':{'code':'invalid-body','message':'Incomplete payload.'}});return
   if self.path=='/health':self.respond(200,{'development_only':True,'ready':True,'asr':'whisper-'+runtime.name,'tts':'ur_PK-fasih-medium'});return
   if not busy.acquire(blocking=False):self.respond(429,{'error':{'code':'busy','message':'The local speech worker is busy.'}});return
   try:
    if self.path=='/transcribe':
     language=self.headers.get('X-Koi-Language','auto')
     if language not in ['ur','en','auto']:raise ValueError('invalid-language')
     result=runtime.transcribe(body,language)
    else:
     payload=json.loads(body)
     if payload.get('language')!='ur':raise ValueError('unsupported-voice-language')
     result=runtime.synthesize(payload.get('text'))
    self.respond(200,result)
   except ValueError:self.respond(422,{'error':{'code':'invalid-input','message':'Speech input could not be validated or decoded.'}})
   except Exception:self.respond(503,{'error':{'code':'processing-failed','message':'Local speech processing failed.'}})
   finally:busy.release()
 server=ThreadingHTTPServer(('127.0.0.1',3002),Handler,bind_and_activate=False);server.daemon_threads=True;server.allow_reuse_address=False
 if os.name=='nt':server.socket.setsockopt(socket.SOL_SOCKET,socket.SO_EXCLUSIVEADDRUSE,1)
 try:
  server.server_bind() # Own the port before changing capability or private temporary files.
  TEMP_ROOT.mkdir(parents=True,exist_ok=True)
  for stale in TEMP_ROOT.glob('koi-voice-*'):
   resolved=stale.resolve()
   if resolved.is_relative_to(TEMP_ROOT.resolve()) and stale.is_dir() and not stale.is_symlink():shutil.rmtree(stale)
  runtime=VoiceRuntime();token_file.write_text(token,encoding='ascii');server.server_activate()
  print('Development voice worker ready on 127.0.0.1:3002; payload logging disabled.',flush=True)
  server.serve_forever()
 finally:
  server.server_close()
  if token_file.exists() and token_file.read_text()==token:token_file.unlink()
if __name__=='__main__':main()
