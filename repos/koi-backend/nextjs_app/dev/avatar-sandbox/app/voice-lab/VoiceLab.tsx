'use client';
import { useEffect, useRef, useState, useSyncExternalStore } from 'react';
import { useRouter } from 'next/navigation';
import CompanionScene from '@/components/companion/CompanionScene';
import { MicrophoneCapture } from '@/lib/speech/MicrophoneCapture';
import { SpeechPlayback } from '@/lib/speech/SpeechPlayback';
import { parseTranscription, parseSynthesizedSpeech, VoiceServiceError, type TranscriptionResult } from '@/lib/speech/voiceContract';
import { useConversationSession } from '@/hooks/useConversationSession';
import { createMockChatAdapter } from '../mock-chat/mockChatAdapter';
type Resources = { capture: MicrophoneCapture; player: SpeechPlayback };
declare global { interface Window { __koiVoiceLab?: Resources; __koiVoiceTiming?: { generationToPlaybackMs: number; readyToPlaybackMs: number; synthesisMs: number; extractionMs: number }; } }
async function localVoice(operation: string, body: Blob | string, signal: AbortSignal, language = 'ur') {
 const abort = new AbortController(), cancel = () => abort.abort(); signal.throwIfAborted(); signal.addEventListener('abort',cancel,{once:true}); let timedOut=false; const timer = setTimeout(()=>{timedOut=true;cancel();},90000);
 try { const result = await fetch(`/voice-api/${operation}`, { method:'POST', headers:{ 'Content-Type':typeof body === 'string' ? 'application/json' : body.type, 'X-Koi-Voice-Intent':'1', 'X-Koi-Language':language }, body, signal:abort.signal });
  if (!result.ok) {
   const failure = await result.json().catch(()=>null) as { error?: { code?: string } } | null;
   const code = failure?.error?.code;
   const details: Record<string, { code: 'busy'|'size-limit'|'invalid-input'|'unavailable'|'timeout'|'processing-failed'; message: string }> = {
    busy:{code:'busy',message:'The local speech worker is busy. Try again.'},
    'size-limit':{code:'size-limit',message:'The recording exceeds the 2 MiB limit. Record a shorter sample.'},
    'invalid-input':{code:'invalid-input',message:'The local ASR could not decode this audio format or the recording contains no usable audio.'},
    'processing-failed':{code:'processing-failed',message:'The local ASR worker failed while processing audio. Check that its model loaded, then retry.'},
    unavailable:{code:'unavailable',message:'The local speech worker is unavailable. Start node scripts/voice-dev.cjs and check worker readiness.'},
   };
   const detail = details[code ?? ''] ?? {code:'unavailable' as const,message:`Local speech request failed (${result.status}). Check worker readiness and captured audio.`};
   throw new VoiceServiceError(detail.code,detail.message,result.status);
  }
  return await result.json();
 } catch (error) { if(timedOut)throw new VoiceServiceError('timeout','Local speech processing timed out.');throw error; } finally { clearTimeout(timer); signal.removeEventListener('abort',cancel); }
}
function Session({ capture, player }: Resources) {
 const recording = useSyncExternalStore(capture.subscribe,capture.getSnapshot,capture.getSnapshot), playback = useSyncExternalStore(player.subscribe,player.getSnapshot,player.getSnapshot);
 const [adapter] = useState(() => createMockChatAdapter({reviewedVoice:true})); const chat = useConversationSession(adapter);
 const [consent,setConsent] = useState(false), [review,setReview] = useState(''), [language,setLanguage] = useState('ur'), [phase,setPhase] = useState('idle'), [error,setError] = useState<string|null>(null), [diagnostics,setDiagnostics] = useState<TranscriptionResult|null>(null), [female,setFemale] = useState(false), [ready,setReady] = useState(false), [deviceId,setDeviceId] = useState(''), [worker,setWorker] = useState<'unchecked'|'checking'|'ready'|'error'>('unchecked'), [recordedUrl,setRecordedUrl] = useState('');
 const active = useRef<AbortController|null>(null), version = useRef(0), mounted = useRef(true); const router = useRouter();
 useEffect(()=>{if(!recording.blob){setRecordedUrl('');return;}const url=URL.createObjectURL(recording.blob);setRecordedUrl(url);return()=>URL.revokeObjectURL(url);},[recording.blob]);
 const cancel = () => { version.current++;active.current?.abort();active.current=null;capture.cancel();player.clear();chat.cancel();setPhase('idle'); };
 useEffect(() => { mounted.current=true;return () => { mounted.current=false;version.current++;active.current?.abort();capture.cancel();player.clear();chat.cancel(); }; },[capture,player,chat.session]);
 async function transcribe(blob: Blob, requested = language) {
  cancel();const generation=++version.current, abort=new AbortController();active.current=abort;setPhase('transcribing');setError(null);setReview('');
  try { const result=parseTranscription(await localVoice('transcribe',blob,abort.signal,requested));
   if (abort.signal.aborted||generation!==version.current||!mounted.current)return;
   setDiagnostics(result);setReview(result.text);setPhase(result.text.trim()?'review':'error');if(!result.text.trim())setError(result.input.level_rms < .002 ? 'The recording decoded, but its input level is near silence. Check the selected microphone, record a short sample, and play it locally before transcribing again.' : 'The recording decoded, but ASR found no words. Try the other language setting or record again. Nothing was submitted.');
  }catch(cause){if(!abort.signal.aborted&&generation===version.current){setError(cause instanceof Error?cause.message:'Transcription failed.');setPhase('idle');}}
 }
 async function fixture(sample: string, requested: string) {
  cancel();const generation=++version.current,abort=new AbortController();active.current=abort;setError(null);setPhase('loading fixture');
  try { const result=await fetch(`/speech-fixture/${sample}.wav`,{signal:abort.signal});if(!result.ok)throw new Error('Generate the local Piper fixtures first.');const blob=await result.blob();if(generation===version.current&&!abort.signal.aborted)await transcribe(blob,requested); }
  catch(cause){if(!abort.signal.aborted&&generation===version.current){setError(cause instanceof Error?cause.message:'Fixture failed.');setPhase('idle');}}
 }
 async function submit() {
  const text=review.trim();if(!text||text.length>300)return;cancel();const generation=++version.current,abort=new AbortController();active.current=abort;setError(null);setPhase('mock chat');
  await chat.send(text);
  if(generation!==version.current||abort.signal.aborted||!mounted.current)return;
  const response=chat.session.getSnapshot();if(response.error||!response.subtitle){setPhase('idle');return;}
  setPhase('synthesizing Urdu mock reply');const began=performance.now();
  try { const speech=await parseSynthesizedSpeech(await localVoice('synthesize',JSON.stringify({text:response.subtitle,language:'ur'}),abort.signal));
   if(generation!==version.current||abort.signal.aborted||!mounted.current)return;
   const prepared=performance.now();player.load({audioBlob:speech.audio,mouthCues:speech.cues});setPhase('ready');await player.play();
   if(generation===version.current&&!abort.signal.aborted&&player.getSnapshot().state==='playing')window.__koiVoiceTiming={generationToPlaybackMs:performance.now()-began,readyToPlaybackMs:performance.now()-prepared,synthesisMs:speech.synthesisMs,extractionMs:speech.extractionMs};
  }catch(cause){if(!abort.signal.aborted&&generation===version.current){setError(cause instanceof Error?cause.message:'Speech generation failed. Text remains available.');setPhase('idle');}}
 }
 async function checkWorker(){setWorker('checking');try{const value=await localVoice('health','{}',new AbortController().signal) as {development_only?:boolean;ready?:boolean;asr?:string};if(value.development_only&&value.ready&&value.asr?.startsWith('whisper-'))setWorker('ready');else throw new Error('Unexpected worker readiness response.');}catch{setWorker('error');}}
 const leave=()=>{cancel();setReview('');router.push('/');}; const busy=['transcribing','loading fixture','mock chat','synthesizing Urdu mock reply'].includes(phase);
 return <CompanionScene companionName={female?'Aisha':'Raza'} modelUrl={`/models/koi-${female?'female':'male'}.vrm`} exposeController speechSource={player} onAvatarReady={()=>setReady(true)} onAvatarFailure={()=>{cancel();setReady(false);}}
  emotion={chat.companion.emotion} emotionIntensity={chat.companion.intensity} conversationState={recording.state==='recording'?'listening':busy?'thinking':playback.state==='playing'?'speaking':'idle'}
  subtitle={chat.subtitle||'Review recognized text before submitting. Chat replies are scripted.'} subtitleLanguage={chat.subtitle?'ur':'en'} messages={chat.messages.map(message=>({id:message.id,speaker:message.sender==='user'?'user':'companion',text:message.content}))} onBack={leave} onEnd={leave}
  notice="Development only: real local ASR + Piper/Rhubarb; MOCK chat, not a real LLM or crisis assessment. No recordings are saved."
  transcriptNotice="Reviewed transcript and scripted mock reply only. No Firebase, real LLM or conversation persistence."
  settings={<label>Preview model<select aria-label="Preview model" value={female?'female':'male'} onChange={event=>{cancel();setReady(false);setFemale(event.target.value==='female');}}><option value="male">Male</option><option value="female">Female</option></select></label>}
  composer={<div style={{fontSize:12,maxHeight:'42dvh',overflowY:'auto',padding:4}}>
   <label><input type="checkbox" checked={consent} onChange={event=>{setConsent(event.target.checked);if(!event.target.checked)cancel();}}/> I consent to local microphone capture and processing (30 s / 2 MiB maximum).</label>
   <div style={{display:'flex',gap:6,alignItems:'center',flexWrap:'wrap'}}><button onClick={()=>void checkWorker()} disabled={worker==='checking'}>Check local ASR worker</button><span role="status" data-worker-state={worker}>ASR worker: {worker==='ready'?'ready (Whisper model loaded)':worker==='checking'?'checking':worker==='error'?'unavailable / not ready':'not checked'}</span></div>
   <div style={{display:'flex',gap:6,alignItems:'center',flexWrap:'wrap',marginTop:5}}><button onClick={()=>void capture.refreshInputs()}>Refresh microphone list</button><label>Input<select aria-label="Microphone input" value={deviceId} onChange={event=>setDeviceId(event.target.value)}><option value="">System default microphone</option>{recording.inputs.map((input,index)=><option key={input.deviceId||index} value={input.deviceId}>{input.label}</option>)}</select></label><span>Permission: {recording.permission}; secure context: {String(globalThis.isSecureContext)}</span></div>
   <div style={{display:'flex',flexWrap:'wrap',gap:6,margin:'6px 0'}}>
    <button disabled={!consent||busy||['requesting','recording','stopping'].includes(recording.state)} onClick={()=>{cancel();setReview('');setDiagnostics(null);void capture.start(deviceId||undefined);}}>Start recording</button>
    <button disabled={recording.state!=='recording'} onClick={()=>capture.stop()}>Stop recording</button>
    <button disabled={!recording.blob||busy} onClick={()=>{if(recording.blob)void transcribe(recording.blob);}}>Transcribe recording</button>
    <button onClick={cancel}>Cancel voice operation</button>
    <label>ASR language<select aria-label="ASR language" value={language} onChange={event=>setLanguage(event.target.value)}><option value="ur">Urdu</option><option value="en">English</option><option value="auto">Detect (may be wrong)</option></select></label>
   </div>
   <div style={{display:'flex',flexWrap:'wrap',gap:6}}>{[['Urdu','piper-urdu','ur'],['English','piper-english','en'],['Mixed','piper-mixed','ur']].map(([name,file,lang])=><button key={file} disabled={busy} onClick={()=>void fixture(file,lang)}>Transcribe {name} fixture</button>)}</div>
   <p role="status" style={{margin:'5px 0'}}>Microphone: <span data-capture-state={recording.state}>{recording.state==='ready'?'recorded':recording.state}</span> {recording.mimeType||'format pending'} | {recording.durationMs?`${(recording.durationMs/1000).toFixed(1)} s`:''} | {recording.bytes} bytes | Speech: {phase} | Playback: <span data-voice-playback={playback.state}>{playback.state}</span></p>
   {recording.input&&<p style={{margin:'4px 0'}}>Input: {recording.input.label}; track {recording.input.state}; {recording.input.sampleRate??'unknown'} Hz; {recording.input.channelCount??'unknown'} channel(s).</p>}
   {recording.blob&&recordedUrl&&<div><p>Optional local capture check: play this recording in the browser. It remains on this device and is not uploaded by Play.</p><audio aria-label="Recorded microphone sample" controls preload="metadata" src={recordedUrl}/></div>}
   {diagnostics&&<p style={{margin:'4px 0'}}>ASR: {diagnostics.model.name}, {diagnostics.processing_ms.toFixed(0)} ms; {diagnostics.input.container}/{diagnostics.input.codec}, {diagnostics.input.duration_seconds.toFixed(2)} s, decoded to mono 16 kHz. Input level RMS {diagnostics.input.level_rms.toFixed(4)}, peak {diagnostics.input.peak.toFixed(4)}. Language {diagnostics.language.code??'unknown'} ({diagnostics.language.source}).</p>}
   <label>Review transcript<textarea aria-label="Review transcript" dir="auto" maxLength={300} value={review} onChange={event=>setReview(event.target.value)} style={{display:'block',width:'100%',height:48,boxSizing:'border-box'}}/></label>
   <div style={{display:'flex',gap:6,flexWrap:'wrap'}}><button disabled={!review.trim()||busy||['requesting','recording','stopping'].includes(recording.state)} onClick={()=>void submit()}>Submit reviewed text to MOCK chat</button><button disabled={!ready||phase!=='ready'||!['idle','paused','ended','error'].includes(playback.state)} onClick={()=>void player.play()}>Play reply</button><button disabled={playback.state!=='playing'} onClick={()=>player.pause()}>Pause reply</button><button onClick={()=>player.clear()}>Stop reply</button></div>
   {(error||chat.error||recording.error||playback.error)&&<p role="alert">{error||chat.error||recording.error||playback.error}</p>}
  </div>}/>;
}
export default function VoiceLab(){const[resources,setResources]=useState<Resources|null>(null);useEffect(()=>{const value={capture:new MicrophoneCapture(),player:new SpeechPlayback()};window.__koiVoiceLab=value;setResources(value);return()=>{value.capture.dispose();value.player.dispose();if(window.__koiVoiceLab===value)delete window.__koiVoiceLab;delete window.__koiVoiceTiming;};},[]);return resources?<Session {...resources}/>:<p role="status">Loading development voice lab...</p>;}
