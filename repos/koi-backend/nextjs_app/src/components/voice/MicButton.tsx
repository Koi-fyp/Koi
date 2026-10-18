'use client';
import { useCallback, useEffect, useRef, useState, type CSSProperties } from 'react';
import { MicrophoneCapture, MAX_RECORDING_MS, type CaptureSnapshot } from '@/lib/speech/MicrophoneCapture';

export interface VoiceRecorder {
  snapshot: CaptureSnapshot | null;
  recording: boolean;
  busy: boolean;
  start: () => void;
  /** Stops and hands the clip to `onRecorded`. Auto-stop at the time limit also sends. */
  finish: () => void;
  discard: () => void;
}

/** One microphone per mounted control. Recording only ever starts from start(); the clip is passed on and not kept. */
export function useVoiceRecorder(onRecorded: (audio: Blob) => void, createCapture: () => MicrophoneCapture = () => new MicrophoneCapture()): VoiceRecorder {
  const captureRef = useRef<MicrophoneCapture | null>(null);
  const [snapshot, setSnapshot] = useState<CaptureSnapshot | null>(null);
  const sendWhenReady = useRef(false);
  const onRecordedRef = useRef(onRecorded); onRecordedRef.current = onRecorded;
  const factoryRef = useRef(createCapture);
  useEffect(() => {
    const capture = factoryRef.current();
    captureRef.current = capture; setSnapshot(capture.getSnapshot());
    const unsubscribe = capture.subscribe(() => setSnapshot(capture.getSnapshot()));
    return () => { unsubscribe(); capture.dispose(); captureRef.current = null; };
  }, []);
  useEffect(() => {
    const capture = captureRef.current;
    if (!capture || snapshot?.state !== 'ready' || !snapshot.blob || !sendWhenReady.current) return;
    sendWhenReady.current = false;
    const audio = snapshot.blob;
    capture.cancel(); // Drop our reference to the clip; only the send keeps it, for the one request.
    onRecordedRef.current(audio);
  }, [snapshot]);
  const start = useCallback(() => { sendWhenReady.current = true; void captureRef.current?.start(); }, []);
  const finish = useCallback(() => { captureRef.current?.stop(); }, []);
  const discard = useCallback(() => { sendWhenReady.current = false; captureRef.current?.cancel(); }, []);
  const state = snapshot?.state;
  return { snapshot, recording: state === 'recording', busy: state === 'requesting' || state === 'stopping', start, finish, discard };
}

function MicIcon() {
  return <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
    <rect x="9" y="2" width="6" height="12" rx="3" /><path d="M5 10v1a7 7 0 0 0 14 0v-1" /><line x1="12" y1="18" x2="12" y2="22" /></svg>;
}
function StopIcon() {
  return <svg width="18" height="18" viewBox="0 0 24 24" aria-hidden="true"><rect x="6" y="6" width="12" height="12" rx="2" fill="currentColor" /></svg>;
}
const seconds = (ms: number) => `0:${String(Math.min(59, Math.floor(ms / 1000))).padStart(2, '0')}`;

export interface MicButtonProps {
  onRecorded: (audio: Blob) => void;
  /** e.g. a reply is still arriving or history is locked. Recording in progress can always be stopped. */
  disabled?: boolean;
  /** 'call': round control with a label below (companion scene). 'inline': compact button inside a text bar. */
  variant?: 'call' | 'inline';
  className?: string;
  activeClassName?: string;
  createCapture?: () => MicrophoneCapture;
}

/** Tap to talk, tap again to send. The clip goes to the KOI chat API for transcription and is not stored. */
export default function MicButton({ onRecorded, disabled = false, variant = 'call', className, activeClassName, createCapture }: MicButtonProps) {
  const recorder = useVoiceRecorder(onRecorded, createCapture);
  const { snapshot, recording, busy } = recorder;
  const error = snapshot?.state === 'error' ? snapshot.error : null;
  const label = recording ? 'Stop and send voice message' : busy ? 'Preparing microphone' : 'Start voice message';
  const inline: CSSProperties = { width: 40, height: 40, borderRadius: '50%', border: '2px solid #000', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0,
    background: recording ? '#db5056' : '#fff', color: recording ? '#fff' : '#000', cursor: disabled && !recording ? 'not-allowed' : 'pointer', opacity: disabled && !recording ? 0.5 : 1 };
  const button = <button type="button" aria-label={label} aria-pressed={recording} disabled={(disabled && !recording) || busy}
    className={`${className ?? ''} ${recording && activeClassName ? activeClassName : ''}`.trim() || undefined}
    style={variant === 'inline' ? inline : recording ? { background: '#db5056', borderColor: '#ad383e', color: '#fff' } : undefined}
    onClick={() => (recording ? recorder.finish() : recorder.start())}>
    {recording ? <StopIcon /> : <MicIcon />}
  </button>;
  const status = recording ? `Recording ${seconds(snapshot?.durationMs ?? 0)} / ${seconds(MAX_RECORDING_MS)} · tap to send`
    : busy ? (snapshot?.state === 'stopping' ? 'Sending…' : 'Allow microphone access…') : error ?? (variant === 'call' ? 'Tap to talk' : '');
  if (variant === 'inline') {
    return <span style={{ display: 'inline-flex', alignItems: 'center', gap: 6 }}>
      {error && <span role="alert" style={{ fontSize: 12, color: '#a42c38', maxWidth: 220 }}>{error}</span>}
      {recording && <span aria-hidden="true" style={{ fontSize: 12, fontWeight: 700, color: '#db5056' }}>● {seconds(snapshot?.durationMs ?? 0)}</span>}
      {recording && <button type="button" onClick={recorder.discard} aria-label="Discard voice message" style={{ fontSize: 12, textDecoration: 'underline', background: 'none', border: 'none', cursor: 'pointer' }}>Discard</button>}
      {button}
      {!error && <span role="status" className="sr-only">{status}</span>}
    </span>;
  }
  return <>
    {button}
    <span role={error ? 'alert' : 'status'}>{status}</span>
    {recording && <button type="button" onClick={recorder.discard} style={{ fontSize: 11, textDecoration: 'underline', background: 'none', border: 'none', cursor: 'pointer', padding: 0 }}>Discard</button>}
  </>;
}
