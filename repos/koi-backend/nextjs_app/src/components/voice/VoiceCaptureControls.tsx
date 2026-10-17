'use client';
import { useEffect, useRef, useState } from 'react';
import type { CaptureSnapshot } from '@/lib/speech/MicrophoneCapture';
export interface AudioCaptureResult { blob: Blob; mimeType: string; durationMs: number; ownerUid: string; generationId: number; }
/** UI adapter proposal, fixture-verifiable only until Ahmad's hosted adapter is reviewed. */
export interface VoiceCaptureAdapter {
  record(): Promise<void>; stop(): void; cancel(): void;
  submitDirect(value: AudioCaptureResult, signal: AbortSignal): Promise<void>;
}
export default function VoiceCaptureControls({ ownerUid, companionId, capture, captureOwnerUid, captureCompanionId, adapter, enabled = false, interruptGeneration = 0 }: {
  ownerUid: string; companionId: string; capture: CaptureSnapshot | null; adapter?: VoiceCaptureAdapter;
  enabled?: boolean; interruptGeneration?: number; captureOwnerUid?: string; captureCompanionId?: string;
}) {
  const [busy,setBusy]=useState(false),[error,setError]=useState<string|null>(null);
  const generation=useRef(0),pending=useRef<AbortController|null>(null),submitting=useRef(false);
  const current=useRef({ownerUid,companionId});current.current={ownerUid,companionId};
  const ownedCapture=captureOwnerUid===ownerUid&&captureCompanionId===companionId?capture:null;
  useEffect(()=>{
    generation.current++;setBusy(false);setError(null);submitting.current=false;
    return ()=>{generation.current++;pending.current?.abort();pending.current=null;submitting.current=false;adapter?.cancel();};
  },[ownerUid,companionId,interruptGeneration,enabled,adapter]);
  const available=enabled&&!!adapter&&!!ownerUid;
  const send=async()=>{
    if(!available||!ownedCapture?.blob||submitting.current)return;
    const owner=ownerUid,companion=companionId,lease=generation.current,abort=new AbortController();
    pending.current=abort;submitting.current=true;setBusy(true);setError(null);
    try {await adapter.submitDirect({blob:ownedCapture.blob,mimeType:ownedCapture.mimeType,durationMs:ownedCapture.durationMs,ownerUid:owner,generationId:lease},abort.signal);}
    catch {if(!abort.signal.aborted&&current.current.ownerUid===owner&&current.current.companionId===companion)setError('Recording could not be submitted. Text remains available.');}
    finally {if(generation.current===lease){setBusy(false);submitting.current=false;pending.current=null;}}
  };
  return <section className="neo-card p-5" aria-label="Voice input adapter controls">
    <h2 className="font-bold">Voice input</h2>
    <p role="status">{available?'Development adapter verification only; not hosted audio acceptance.':'Unavailable until hosted audio and the joint adapter pass acceptance.'}</p>
    <p>Permission: {ownedCapture?.permission??'unknown'}. Recording state: {ownedCapture?.state??'idle'}.</p>
    <p>Direct send submits audio once. A transcript may arrive afterwards; this is not editable review-first transcription.</p>
    <div className="flex gap-3 flex-wrap mt-3">
      <button type="button" className="neo-btn-ghost" disabled={!available||busy||ownedCapture?.state==='recording'||ownedCapture?.state==='requesting'}
        onClick={()=>{setError(null);const lease=generation.current;void adapter?.record().catch(()=>{if(generation.current===lease)setError('Microphone unavailable. Text remains available.');});}}>Record</button>
      <button type="button" className="neo-btn-ghost" disabled={!available||ownedCapture?.state!=='recording'} onClick={()=>adapter?.stop()}>Stop recording</button>
      <button type="button" className="neo-btn-ghost" disabled={!available||!ownedCapture?.blob||busy} onClick={()=>void send()}>Submit recording directly</button>
      <button type="button" className="neo-btn-ghost" disabled={!available} onClick={()=>{pending.current?.abort();generation.current++;submitting.current=false;setBusy(false);adapter?.cancel();}}>Discard recording</button>
      <button type="button" className="neo-btn-ghost" disabled title="Requires approved ASR-only adapter">Review-first transcription unavailable</button>
    </div>
    {busy&&<p role="status">Submitting the recording…</p>}{error&&<p role="alert">{error}</p>}
  </section>;
}
