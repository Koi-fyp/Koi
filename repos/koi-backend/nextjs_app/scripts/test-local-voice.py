import base64,http.client,io,json,os,subprocess,urllib.error,urllib.request,wave
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];TOOLS=ROOT/'dev/avatar-sandbox/.voice-tools';token=(TOOLS/'service-token').read_text().strip()
def request(operation,body=b'{}',authorized=True,origin='http://127.0.0.1:3001',language='ur'):
 headers={'Origin':origin,'X-Koi-Language':language,'Content-Type':'application/octet-stream'}
 if authorized:headers['Authorization']='Bearer '+token
 try:
  with urllib.request.urlopen(urllib.request.Request('http://127.0.0.1:3002/'+operation,data=body,headers=headers),timeout=90) as response:return response.status,json.load(response)
 except urllib.error.HTTPError as error:return error.code,json.load(error)
assert request('health',authorized=False)[0]==403
assert request('health',origin='https://unapproved.invalid')[0]==403
assert request('health')[0]==200
# Duplicate start must not rotate a running worker's capability or clean its active files.
owned=TOOLS/'tmp/koi-voice-active-check';owned.mkdir(exist_ok=True);marker=owned/'non-sensitive-marker';marker.write_text('test')
assert owned.resolve().is_relative_to((TOOLS/'tmp').resolve())
child=subprocess.run([str(TOOLS/'venv/Scripts/python.exe'),str(ROOT/'dev/avatar-sandbox/voice_service.py')],env={**os.environ,'KOI_VOICE_DEVELOPMENT':'1'},capture_output=True,timeout=15)
assert child.returncode!=0 and (TOOLS/'service-token').read_text().strip()==token and marker.exists()
marker.unlink();owned.rmdir()
production=subprocess.run([str(TOOLS/'venv/Scripts/python.exe'),str(ROOT/'dev/avatar-sandbox/voice_service.py')],env={**os.environ,'KOI_VOICE_DEVELOPMENT':'1','NODE_ENV':'production'},capture_output=True,timeout=15);assert production.returncode!=0
assert request('transcribe',b'not-audio')[0]==422
assert request('transcribe',b'')[0]==422
buffer=io.BytesIO()
with wave.open(buffer,'wb') as audio:audio.setnchannels(1);audio.setsampwidth(2);audio.setframerate(16000);audio.writeframes(bytes(31*16000*2))
assert request('transcribe',buffer.getvalue())[0]==422
silence=io.BytesIO()
with wave.open(silence,'wb') as audio:audio.setnchannels(1);audio.setsampwidth(2);audio.setframerate(16000);audio.writeframes(bytes(16000*2))
status,empty=request('transcribe',silence.getvalue());assert status==200 and empty['text']=='' and empty['input']['level_rms']==0
connection=http.client.HTTPConnection('127.0.0.1',3002);connection.putrequest('POST','/transcribe');connection.putheader('Origin','http://127.0.0.1:3001');connection.putheader('Authorization','Bearer '+token);connection.putheader('Content-Length',str(2*1024*1024+1));connection.endheaders();assert connection.getresponse().status==413;connection.close()
status,transcript=request('transcribe',(ROOT/'dev/avatar-sandbox/.fixtures/piper-urdu.wav').read_bytes());assert status==200 and transcript['text'];assert transcript['input']['normalized_sample_rate']==16000
text=json.loads((ROOT/'dev/avatar-sandbox/.fixtures/piper-urdu.json').read_text())['transcript'];status,speech=request('synthesize',json.dumps({'text':text,'language':'ur'}).encode());assert status==200
assert speech['mouth_cues'] and base64.b64decode(speech['audio_base64']).startswith(b'RIFF')
assert not list((TOOLS/'tmp').glob('koi-voice-*'))
report={'passed':True,'scope':'Real local worker + non-sensitive fixture; no physical microphone or Firebase','transcription':transcript,'silence':{'text':empty['text'],'level_rms':empty['input']['level_rms'],'duration_seconds':empty['input']['duration_seconds']},'ttsTimings':speech['timings_ms'],'checks':['capability/origin rejection','empty/invalid/oversized/overduration audio rejection','silent audio metrics and no fabricated transcript','real PCM decode/resampling and ASR','real persistent Piper/Rhubarb and temporary-file cleanup']}
(TOOLS/'service-verification.json').write_text(json.dumps(report,ensure_ascii=True,indent=2));print(json.dumps(report,ensure_ascii=True,indent=2))
